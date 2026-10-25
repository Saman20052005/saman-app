package com.example.health_ai_app.cv

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.os.SystemClock
import android.util.Log
import androidx.camera.core.ImageProxy
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicLong

class PoseLandmarkerHelper(
    private val context: Context,
    private val poseLandmarkerListener: LandmarkerListener
) {
    interface LandmarkerListener {
        fun onError(error: String, errorCode: Int = 0)
        fun onResults(resultBundle: ResultBundle)
    }

    data class FrameSubmitMeta(
        val sessionGen: Long,
        val submitRealtimeNs: Long,
        val decoderPtsUs: Long,
        val surfaceTimestampNs: Long,
        val readbackMs: Double,
        val isPtsVerified: Boolean
    )

    data class ResultBundle(
        val results: List<PoseLandmarkerResult>,
        val inferenceTime: Long,
        val inputImageHeight: Int,
        val inputImageWidth: Int,
        val timestamp: Long,
        val sessionGen: Long = 0L,
        val decoderPtsUs: Long = -1L,
        val surfaceTimestampNs: Long = -1L,
        val readbackMs: Double = 0.0,
        val isPtsVerified: Boolean = true
    )

    private var poseLandmarker: PoseLandmarker? = null
    private var lastTimestampMs = Long.MIN_VALUE
    private val submitMetaMap = ConcurrentHashMap<Long, FrameSubmitMeta>()

    val isInitialized: Boolean
        get() = poseLandmarker != null

    init {
        setupPoseLandmarker()
    }

    fun setupPoseLandmarker() {
        if (poseLandmarker != null) return
        try {
            val baseOptionBuilder = BaseOptions.builder()
                .setModelAssetPath("pose_landmarker_lite.task")
                .setDelegate(Delegate.CPU)

            val optionsBuilder = PoseLandmarker.PoseLandmarkerOptions.builder()
                .setBaseOptions(baseOptionBuilder.build())
                .setMinPoseDetectionConfidence(0.5f)
                .setMinTrackingConfidence(0.5f)
                .setMinPosePresenceConfidence(0.5f)
                .setNumPoses(2) // Max 2 poses to detect and gate multiple people
                .setOutputSegmentationMasks(false)
                .setRunningMode(RunningMode.LIVE_STREAM)
                .setResultListener { result: PoseLandmarkerResult, input: MPImage ->
                    val frameTime = result.timestampMs()
                    val nowNs = SystemClock.elapsedRealtimeNanos()
                    WorkoutCvPerfTracker.onCallback(frameTime)
                    val meta = submitMetaMap.remove(frameTime)
                    val inferenceTime = if (meta != null) {
                        ((nowNs - meta.submitRealtimeNs) / 1_000_000L).coerceAtLeast(0L)
                    } else {
                        (SystemClock.uptimeMillis() - frameTime).coerceAtLeast(0L)
                    }
                    poseLandmarkerListener.onResults(
                        ResultBundle(
                            results = listOf(result),
                            inferenceTime = inferenceTime,
                            inputImageHeight = input.height,
                            inputImageWidth = input.width,
                            timestamp = frameTime,
                            sessionGen = meta?.sessionGen ?: -1L,
                            decoderPtsUs = meta?.decoderPtsUs ?: -1L,
                            surfaceTimestampNs = meta?.surfaceTimestampNs ?: -1L,
                            readbackMs = meta?.readbackMs ?: 0.0,
                            isPtsVerified = meta?.isPtsVerified ?: false
                        )
                    )
                }
                .setErrorListener { error ->
                    poseLandmarkerListener.onError(error.message ?: "MediaPipe detection error")
                }

            poseLandmarker = PoseLandmarker.createFromOptions(context, optionsBuilder.build())
        } catch (e: Exception) {
            poseLandmarker = null
            poseLandmarkerListener.onError("PoseLandmarker init failed: ${e.message}")
        }
    }

    fun detectLiveStream(imageProxy: ImageProxy, isFrontCamera: Boolean, sessionGen: Long = 0L) {
        val frameTime = SystemClock.uptimeMillis()
        if (frameTime <= lastTimestampMs) {
            // Strictly monotonic timestamp required by MediaPipe LIVE_STREAM
            imageProxy.close()
            return
        }
        lastTimestampMs = frameTime

        val landmarker = poseLandmarker
        if (landmarker == null) {
            imageProxy.close()
            return
        }

        try {
            // Stage (b): Bitmap conversion
            val tBmp0 = SystemClock.elapsedRealtimeNanos()
            val bitmap = imageProxy.toBitmap()
            val tBmp1 = SystemClock.elapsedRealtimeNanos()
            WorkoutCvPerfTracker.recordBitmapDuration((tBmp1 - tBmp0) / 1_000_000.0)

            val rotationDegrees = imageProxy.imageInfo.rotationDegrees

            // Stage (c): Matrix rotation & transformation
            val tTfm0 = SystemClock.elapsedRealtimeNanos()
            val rotatedBitmap = if (rotationDegrees != 0 || isFrontCamera) {
                val matrix = Matrix().apply {
                    if (rotationDegrees != 0) postRotate(rotationDegrees.toFloat())
                    if (isFrontCamera) postScale(-1f, 1f, bitmap.width.toFloat(), bitmap.height.toFloat())
                }
                Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
            } else {
                bitmap
            }

            val mpImage = BitmapImageBuilder(rotatedBitmap).build()
            val tTfm1 = SystemClock.elapsedRealtimeNanos()
            WorkoutCvPerfTracker.recordTransformDuration((tTfm1 - tTfm0) / 1_000_000.0)

            // Stage (d): Submit MediaPipe async task
            val submitNs = SystemClock.elapsedRealtimeNanos()
            if (submitMetaMap.size > 64) submitMetaMap.clear()
            submitMetaMap[frameTime] = FrameSubmitMeta(
                sessionGen = sessionGen,
                submitRealtimeNs = submitNs,
                decoderPtsUs = frameTime * 1000L,
                surfaceTimestampNs = submitNs,
                readbackMs = 0.0,
                isPtsVerified = true
            )
            WorkoutCvPerfTracker.onSubmit(frameTime)
            landmarker.detectAsync(mpImage, frameTime)
        } catch (e: Exception) {
            poseLandmarkerListener.onError("Inference error: ${e.message}")
        } finally {
            imageProxy.close()
        }
    }

    fun detectVideoFrame(
        bitmap: Bitmap,
        videoPtsMs: Long,
        sessionGen: Long,
        decoderPtsUs: Long,
        surfaceTimestampNs: Long,
        readbackMs: Double,
        isPtsVerified: Boolean
    ): Boolean {
        if (videoPtsMs <= lastTimestampMs) {
            // Strictly monotonic timestamp required by MediaPipe LIVE_STREAM
            return false
        }
        val landmarker = poseLandmarker ?: return false
        lastTimestampMs = videoPtsMs

        return try {
            val tTfm0 = SystemClock.elapsedRealtimeNanos()
            val mpImage = BitmapImageBuilder(bitmap).build()
            val tTfm1 = SystemClock.elapsedRealtimeNanos()
            WorkoutCvPerfTracker.recordTransformDuration((tTfm1 - tTfm0) / 1_000_000.0)

            val submitNs = SystemClock.elapsedRealtimeNanos()
            if (submitMetaMap.size > 64) submitMetaMap.clear()
            submitMetaMap[videoPtsMs] = FrameSubmitMeta(
                sessionGen = sessionGen,
                submitRealtimeNs = submitNs,
                decoderPtsUs = decoderPtsUs,
                surfaceTimestampNs = surfaceTimestampNs,
                readbackMs = readbackMs,
                isPtsVerified = isPtsVerified
            )
            WorkoutCvPerfTracker.onSubmit(videoPtsMs)
            landmarker.detectAsync(mpImage, videoPtsMs)
            true
        } catch (e: Exception) {
            submitMetaMap.remove(videoPtsMs)
            poseLandmarkerListener.onError("Video inference error: ${e.message}")
            false
        }
    }

    fun clearPoseLandmarker() {
        submitMetaMap.clear()
        val landmarker = poseLandmarker ?: return
        poseLandmarker = null
        landmarker.close()
    }

}

object WorkoutCvPerfTracker {
    private const val TAG = "CV_PERF"

    enum class OverlayState {
        VISIBLE,
        HIDDEN_SKEW,
        HIDDEN_NO_RESULT,
        HIDDEN_QUALITY_GATE
    }

    data class OverlayVisSummary(
        val visiblePct: Double,
        val hiddenSkewPct: Double,
        val hiddenNoResultPct: Double,
        val hiddenGatePct: Double,
        val totalTimeMs: Double,
        val visibleTimeMs: Double,
        val hiddenSkewTimeMs: Double,
        val hiddenNoResultTimeMs: Double,
        val hiddenGateTimeMs: Double,
        val totalRenderedFrames: Long,
        val visibleFrames: Long,
        val hiddenSkewFrames: Long,
        val hiddenNoResultFrames: Long,
        val hiddenGateFrames: Long
    )

    val analyzerFramesReceived = AtomicLong(0)
    val framesSubmitted = AtomicLong(0)
    val framesCompleted = AtomicLong(0)

    // Provenance & Pairing counters
    val decoderFramesReleased = AtomicLong(0)
    val surfaceFramesUpdated = AtomicLong(0)
    val ptsVerifiedFrames = AtomicLong(0)
    val ptsUnverifiedFrames = AtomicLong(0)
    val captureTsMismatchFrames = AtomicLong(0)
    val staleSessionCallbacksDropped = AtomicLong(0)

    @Volatile private var lastAnalyzerArrivalNs = 0L
    @Volatile private var lastSubmitNs = 0L
    @Volatile private var lastCallbackNs = 0L

    // Overlay visibility tracking (synchronized via WorkoutCvPerfTracker)
    @Volatile private var lastOverlayEvalNs = 0L
    @Volatile private var currentOverlayState = OverlayState.HIDDEN_NO_RESULT

    @Volatile private var totalOverlayVisibleNs = 0L
    @Volatile private var totalOverlayHiddenSkewNs = 0L
    @Volatile private var totalOverlayHiddenNoResultNs = 0L
    @Volatile private var totalOverlayHiddenGateNs = 0L

    @Volatile private var totalRenderedVideoFrames = 0L
    @Volatile private var totalVisibleVideoFrames = 0L
    @Volatile private var totalHiddenSkewVideoFrames = 0L
    @Volatile private var totalHiddenNoResultVideoFrames = 0L
    @Volatile private var totalHiddenGateVideoFrames = 0L

    private val pendingSubmits = ConcurrentHashMap<Long, Long>()

    private val analyzerIntervalsMs = CopyOnWriteArrayList<Double>()
    private val bitmapDurationsMs = CopyOnWriteArrayList<Double>()
    private val transformDurationsMs = CopyOnWriteArrayList<Double>()
    private val readbackDurationsMs = CopyOnWriteArrayList<Double>()
    private val asyncLatenciesMs = CopyOnWriteArrayList<Double>()
    private val packDurationsUs = CopyOnWriteArrayList<Double>()
    private val sinkDurationsUs = CopyOnWriteArrayList<Double>()
    private val dispatchLatenciesMs = CopyOnWriteArrayList<Double>()
    private val callbackSkewMsList = CopyOnWriteArrayList<Double>()
    private val liveFrameSkewMsList = CopyOnWriteArrayList<Double>()

    @Volatile private var windowStartNs = SystemClock.elapsedRealtimeNanos()
    @Volatile private var windowAnalyzerCount = 0L
    @Volatile private var windowSubmitCount = 0L
    @Volatile private var windowCallbackCount = 0L

    @Synchronized
    fun reset() {
        analyzerFramesReceived.set(0)
        framesSubmitted.set(0)
        framesCompleted.set(0)
        decoderFramesReleased.set(0)
        surfaceFramesUpdated.set(0)
        ptsVerifiedFrames.set(0)
        ptsUnverifiedFrames.set(0)
        captureTsMismatchFrames.set(0)
        staleSessionCallbacksDropped.set(0)

        lastAnalyzerArrivalNs = 0L
        lastSubmitNs = 0L
        lastCallbackNs = 0L

        lastOverlayEvalNs = 0L
        currentOverlayState = OverlayState.HIDDEN_NO_RESULT
        totalOverlayVisibleNs = 0L
        totalOverlayHiddenSkewNs = 0L
        totalOverlayHiddenNoResultNs = 0L
        totalOverlayHiddenGateNs = 0L

        totalRenderedVideoFrames = 0L
        totalVisibleVideoFrames = 0L
        totalHiddenSkewVideoFrames = 0L
        totalHiddenNoResultVideoFrames = 0L
        totalHiddenGateVideoFrames = 0L

        pendingSubmits.clear()
        clearWindow()
        Log.i(TAG, "WorkoutCvPerfTracker reset for new measurement session.")
    }

    private fun clearWindow() {
        analyzerIntervalsMs.clear()
        bitmapDurationsMs.clear()
        transformDurationsMs.clear()
        readbackDurationsMs.clear()
        asyncLatenciesMs.clear()
        packDurationsUs.clear()
        sinkDurationsUs.clear()
        dispatchLatenciesMs.clear()
        callbackSkewMsList.clear()
        liveFrameSkewMsList.clear()
        windowStartNs = SystemClock.elapsedRealtimeNanos()
        windowAnalyzerCount = 0L
        windowSubmitCount = 0L
        windowCallbackCount = 0L
    }

    @Synchronized
    fun recordOverlayTransition(
        nowNs: Long,
        newState: OverlayState,
        isNewRenderedVideoFrame: Boolean,
        liveSkewMs: Long?
    ) {
        if (lastOverlayEvalNs > 0L && nowNs > lastOverlayEvalNs) {
            val deltaNs = nowNs - lastOverlayEvalNs
            when (currentOverlayState) {
                OverlayState.VISIBLE -> totalOverlayVisibleNs += deltaNs
                OverlayState.HIDDEN_SKEW -> totalOverlayHiddenSkewNs += deltaNs
                OverlayState.HIDDEN_NO_RESULT -> totalOverlayHiddenNoResultNs += deltaNs
                OverlayState.HIDDEN_QUALITY_GATE -> totalOverlayHiddenGateNs += deltaNs
            }
        }
        lastOverlayEvalNs = nowNs
        currentOverlayState = newState

        if (isNewRenderedVideoFrame) {
            totalRenderedVideoFrames++
            when (newState) {
                OverlayState.VISIBLE -> totalVisibleVideoFrames++
                OverlayState.HIDDEN_SKEW -> totalHiddenSkewVideoFrames++
                OverlayState.HIDDEN_NO_RESULT -> totalHiddenNoResultVideoFrames++
                OverlayState.HIDDEN_QUALITY_GATE -> totalHiddenGateVideoFrames++
            }
            if (liveSkewMs != null && liveSkewMs >= 0L && liveFrameSkewMsList.size < 1000) {
                liveFrameSkewMsList.add(liveSkewMs.toDouble())
            }
        }
    }

    @Synchronized
    fun recordCallbackSkew(skewMs: Long) {
        if (callbackSkewMsList.size < 1000) {
            callbackSkewMsList.add(skewMs.toDouble())
        }
    }

    @Synchronized
    fun getOverlayVisSummary(): OverlayVisSummary {
        val totalNs = totalOverlayVisibleNs + totalOverlayHiddenSkewNs + totalOverlayHiddenNoResultNs + totalOverlayHiddenGateNs
        val visTimeMs = totalOverlayVisibleNs / 1_000_000.0
        val skewTimeMs = totalOverlayHiddenSkewNs / 1_000_000.0
        val noResTimeMs = totalOverlayHiddenNoResultNs / 1_000_000.0
        val gateTimeMs = totalOverlayHiddenGateNs / 1_000_000.0
        val totTimeMs = totalNs / 1_000_000.0

        val visPct = if (totalNs > 0L) (totalOverlayVisibleNs * 100.0 / totalNs) else 0.0
        val skewPct = if (totalNs > 0L) (totalOverlayHiddenSkewNs * 100.0 / totalNs) else 0.0
        val noResPct = if (totalNs > 0L) (totalOverlayHiddenNoResultNs * 100.0 / totalNs) else 0.0
        val gatePct = if (totalNs > 0L) (totalOverlayHiddenGateNs * 100.0 / totalNs) else 0.0

        return OverlayVisSummary(
            visiblePct = visPct,
            hiddenSkewPct = skewPct,
            hiddenNoResultPct = noResPct,
            hiddenGatePct = gatePct,
            totalTimeMs = totTimeMs,
            visibleTimeMs = visTimeMs,
            hiddenSkewTimeMs = skewTimeMs,
            hiddenNoResultTimeMs = noResTimeMs,
            hiddenGateTimeMs = gateTimeMs,
            totalRenderedFrames = totalRenderedVideoFrames,
            visibleFrames = totalVisibleVideoFrames,
            hiddenSkewFrames = totalHiddenSkewVideoFrames,
            hiddenNoResultFrames = totalHiddenNoResultVideoFrames,
            hiddenGateFrames = totalHiddenGateVideoFrames
        )
    }

    fun onAnalyzerArrival() {
        val nowNs = SystemClock.elapsedRealtimeNanos()
        val prevNs = lastAnalyzerArrivalNs
        lastAnalyzerArrivalNs = nowNs
        analyzerFramesReceived.incrementAndGet()
        windowAnalyzerCount++
        if (prevNs > 0L) {
            val intervalMs = (nowNs - prevNs) / 1_000_000.0
            if (analyzerIntervalsMs.size < 1000) {
                analyzerIntervalsMs.add(intervalMs)
            }
        }
        checkDumpWindow(nowNs)
    }

    fun recordBitmapDuration(durationMs: Double) {
        if (bitmapDurationsMs.size < 1000) bitmapDurationsMs.add(durationMs)
    }

    fun recordTransformDuration(durationMs: Double) {
        if (transformDurationsMs.size < 1000) transformDurationsMs.add(durationMs)
    }

    fun recordReadbackDuration(durationMs: Double) {
        if (readbackDurationsMs.size < 1000) readbackDurationsMs.add(durationMs)
    }

    fun onSubmit(frameTimeMs: Long) {
        val nowNs = SystemClock.elapsedRealtimeNanos()
        lastSubmitNs = nowNs
        framesSubmitted.incrementAndGet()
        windowSubmitCount++
        pendingSubmits[frameTimeMs] = nowNs
    }

    fun onCallback(frameTimeMs: Long) {
        val nowNs = SystemClock.elapsedRealtimeNanos()
        lastCallbackNs = nowNs
        framesCompleted.incrementAndGet()
        windowCallbackCount++
        val submitNs = pendingSubmits.remove(frameTimeMs)
        if (submitNs != null) {
            val asyncMs = (nowNs - submitNs) / 1_000_000.0
            if (asyncLatenciesMs.size < 1000) asyncLatenciesMs.add(asyncMs)
        }
        checkDumpWindow(nowNs)
    }

    fun recordDispatchLatency(latencyMs: Double) {
        if (dispatchLatenciesMs.size < 1000) dispatchLatenciesMs.add(latencyMs)
    }

    fun recordPackDuration(durationUs: Double) {
        if (packDurationsUs.size < 1000) packDurationsUs.add(durationUs)
    }

    fun recordSinkDuration(durationUs: Double) {
        if (sinkDurationsUs.size < 1000) sinkDurationsUs.add(durationUs)
    }

    @Synchronized
    private fun checkDumpWindow(nowNs: Long) {
        val windowElapsedMs = (nowNs - windowStartNs) / 1_000_000.0
        if (windowElapsedMs >= 5000.0 && (windowAnalyzerCount > 0 || windowSubmitCount > 0)) {
            dumpSummary(windowElapsedMs, isFinal = false)
            clearWindow()
        }
    }

    @Synchronized
    fun dumpSummary(windowElapsedMs: Double, isFinal: Boolean = false) {
        val inFlight = framesSubmitted.get() - framesCompleted.get()
        val elapsed = if (windowElapsedMs > 0.0) windowElapsedMs else ((SystemClock.elapsedRealtimeNanos() - windowStartNs) / 1_000_000.0)
        val windowSec = elapsed / 1000.0
        val analyzerFps = if (windowSec > 0) windowAnalyzerCount / windowSec else 0.0
        val submitFps = if (windowSec > 0) windowSubmitCount / windowSec else 0.0
        val callbackFps = if (windowSec > 0) windowCallbackCount / windowSec else 0.0

        val (intP50, intP95, intMean) = computeStats(analyzerIntervalsMs)
        val (bmpP50, bmpP95, bmpMean) = computeStats(bitmapDurationsMs)
        val (tfmP50, tfmP95, tfmMean) = computeStats(transformDurationsMs)
        val (rbkP50, rbkP95, rbkMean) = computeStats(readbackDurationsMs)
        val (asyP50, asyP95, asyMean) = computeStats(asyncLatenciesMs)
        val (dspP50, dspP95, dspMean) = computeStats(dispatchLatenciesMs)
        val (pckP50, pckP95, pckMean) = computeStats(packDurationsUs)
        val (snkP50, snkP95, snkMean) = computeStats(sinkDurationsUs)
        val (cbSkP50, cbSkP95, cbSkMean) = computeStats(callbackSkewMsList)
        val (lvSkP50, lvSkP95, lvSkMean) = computeStats(liveFrameSkewMsList)

        val ov = getOverlayVisSummary()
        val fTot = ov.totalRenderedFrames.coerceAtLeast(1L).toDouble()
        val fVisPct = ov.visibleFrames * 100.0 / fTot
        val fSkewPct = ov.hiddenSkewFrames * 100.0 / fTot
        val fNoResPct = ov.hiddenNoResultFrames * 100.0 / fTot
        val fGatePct = ov.hiddenGateFrames * 100.0 / fTot

        val header = if (isFinal) "=== FINAL WORKOUT CV PERF REPORT ===" else "=== WORKOUT CV PERF WINDOW SUMMARY ==="
        Log.i(TAG, """
$header
  Window Duration: ${"%.1f".format(elapsed)} ms
  Total Counters: AnalyzerReceived=${analyzerFramesReceived.get()}, Submitted=${framesSubmitted.get()}, Completed=${framesCompleted.get()}, InFlight=$inFlight
  Provenance & Session Isolation:
    - DecoderFramesReleased=${decoderFramesReleased.get()}, SurfaceFramesUpdated=${surfaceFramesUpdated.get()}
    - PtsVerifiedFrames=${ptsVerifiedFrames.get()}, PtsUnverifiedFrames=${ptsUnverifiedFrames.get()}, CaptureTsMismatch=${captureTsMismatchFrames.get()}, StaleSessionDropped=${staleSessionCallbacksDropped.get()}
  Throughput:
    - Stage (a) Analyzer Arrival: samples=${analyzerIntervalsMs.size}, FPS=${"%.2f".format(analyzerFps)}, interval p50=${"%.2f".format(intP50)}ms, p95=${"%.2f".format(intP95)}ms, mean=${"%.2f".format(intMean)}ms
    - Submit Rate: samples=$windowSubmitCount, FPS=${"%.2f".format(submitFps)}
    - Callback Rate: samples=$windowCallbackCount, FPS=${"%.2f".format(callbackFps)}
  Stage Latencies (Clock Domain: SystemClock.elapsedRealtimeNanos monotonic):
    - Stage (b) Bitmap Conversion: samples=${bitmapDurationsMs.size}, p50=${"%.2f".format(bmpP50)}ms, p95=${"%.2f".format(bmpP95)}ms, mean=${"%.2f".format(bmpMean)}ms
    - Stage (c) Matrix & Transform: samples=${transformDurationsMs.size}, p50=${"%.2f".format(tfmP50)}ms, p95=${"%.2f".format(tfmP95)}ms, mean=${"%.2f".format(tfmMean)}ms
    - Readback/Capture: samples=${readbackDurationsMs.size}, p50=${"%.2f".format(rbkP50)}ms, p95=${"%.2f".format(rbkP95)}ms, mean=${"%.2f".format(rbkMean)}ms
    - Stage (d) MP Async Completion (submit->callback): samples=${asyncLatenciesMs.size}, p50=${"%.2f".format(asyP50)}ms, p95=${"%.2f".format(asyP95)}ms, mean=${"%.2f".format(asyMean)}ms
    - Stage (e.1) MainHandler Dispatch: samples=${dispatchLatenciesMs.size}, p50=${"%.2f".format(dspP50)}ms, p95=${"%.2f".format(dspP95)}ms, mean=${"%.2f".format(dspMean)}ms
    - Stage (e.2) Event Packaging: samples=${packDurationsUs.size}, p50=${"%.2f".format(pckP50)}us, p95=${"%.2f".format(pckP95)}us, mean=${"%.2f".format(pckMean)}us
    - Stage (e.3) EventSink Send: samples=${sinkDurationsUs.size}, p50=${"%.2f".format(snkP50)}us, p95=${"%.2f".format(snkP95)}us, mean=${"%.2f".format(snkMean)}us
  PTS Skew (Preview PTS vs Pose PTS, 80ms display hide policy):
    - At Callback Delivery: samples=${callbackSkewMsList.size}, p50=${"%.1f".format(cbSkP50)}ms, p95=${"%.1f".format(cbSkP95)}ms, mean=${"%.1f".format(cbSkMean)}ms
    - Across All Rendered Video Frames: samples=${liveFrameSkewMsList.size}, p50=${"%.1f".format(lvSkP50)}ms, p95=${"%.1f".format(lvSkP95)}ms, mean=${"%.1f".format(lvSkMean)}ms
  Overlay Visibility Breakdown (Cumulative Replay Display Time = ${"%.1f".format(ov.totalTimeMs)}ms, Rendered Video Frames = ${ov.totalRenderedFrames}):
    - VISIBLE (<=80ms & verified): time=${"%.1f".format(ov.visibleTimeMs)}ms (${"%.1f".format(ov.visiblePct)}%), frames=${ov.visibleFrames} (${"%.1f".format(fVisPct)}%)
    - HIDDEN_SKEW (>80ms or unverified): time=${"%.1f".format(ov.hiddenSkewTimeMs)}ms (${"%.1f".format(ov.hiddenSkewPct)}%), frames=${ov.hiddenSkewFrames} (${"%.1f".format(fSkewPct)}%)
    - HIDDEN_NO_RESULT (waiting initial pose): time=${"%.1f".format(ov.hiddenNoResultTimeMs)}ms (${"%.1f".format(ov.hiddenNoResultPct)}%), frames=${ov.hiddenNoResultFrames} (${"%.1f".format(fNoResPct)}%)
    - HIDDEN_QUALITY_GATE (lost/multi-person): time=${"%.1f".format(ov.hiddenGateTimeMs)}ms (${"%.1f".format(ov.hiddenGatePct)}%), frames=${ov.hiddenGateFrames} (${"%.1f".format(fGatePct)}%)
================================================
""".trimIndent())
    }

    private fun computeStats(list: List<Double>): Triple<Double, Double, Double> {
        if (list.isEmpty()) return Triple(0.0, 0.0, 0.0)
        val sorted = list.sorted()
        val mean = sorted.sum() / sorted.size
        val p50 = sorted[((sorted.size - 1) * 0.50).toInt()]
        val p95 = sorted[((sorted.size - 1) * 0.95).toInt()]
        return Triple(p50, p95, mean)
    }
}
