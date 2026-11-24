package com.example.health_ai_app.cv

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.SurfaceTexture
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.TextureView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.LinkedHashMap
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.abs

class WorkoutCvPlugin(private val activity: Activity) :
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    PoseLandmarkerHelper.LandmarkerListener {

    companion object {
        private const val TAG = "WorkoutCvPlugin"
        const val CAMERA_PERMISSION_CODE = 2001
        private const val METHOD_CHANNEL_NAME = "com.example.health_ai_app/workout_cv/method"
        private const val EVENT_CHANNEL_NAME = "com.example.health_ai_app/workout_cv/events"
        private const val VIEW_TYPE = "workout_camera_view"
        private const val MIN_ML_SUBMIT_INTERVAL_MS = 55L
        private const val MAX_IN_FLIGHT_FRAMES = 2
        private const val CAPTURE_BITMAP_WIDTH = 192
        private const val CAPTURE_BITMAP_HEIGHT = 256
        private const val BENCHMARK_MODEL_NAME = "pose_landmarker_lite.task"
        private const val BENCHMARK_INPUT_WIDTH = 192
        private const val BENCHMARK_INPUT_HEIGHT = 256
        private const val BENCHMARK_DEFAULT_FRAMES = 12
        private const val BENCHMARK_MIN_FRAMES = 5
        private const val BENCHMARK_MAX_FRAMES = 20
        private const val BENCHMARK_MAX_ELAPSED_MS = 2200.0
        private const val BENCHMARK_EARLY_STOP_MIN_FRAMES = 3
        private const val VERBOSE_FRAME_LOGS = false

        fun registerWith(activity: Activity, flutterEngine: FlutterEngine): WorkoutCvPlugin {
            val plugin = WorkoutCvPlugin(activity)

            val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL_NAME)
            methodChannel.setMethodCallHandler(plugin)
            plugin.methodChannel = methodChannel

            val eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL_NAME)
            eventChannel.setStreamHandler(plugin)
            plugin.eventChannel = eventChannel

            flutterEngine.platformViewsController.registry.registerViewFactory(
                VIEW_TYPE,
                WorkoutCameraViewFactory(activity, plugin)
            )

            return plugin
        }
    }

    @Volatile
    var isSessionActive: Boolean = false
        private set

    @Volatile
    var currentSourceMode: String = "camera"
        private set

    @Volatile
    var currentSessionGeneration: Long = 0L
        private set

    var currentClipName: String = ""
        private set

    @Volatile
    private var currentReplayFile: File? = null

    var videoSourceFps: Double = 50.0
        private set

    val inFlightCount = AtomicInteger(0)
    private val bitmapPoolLock = Any()
    private val bitmapPool: Array<Bitmap?> = arrayOfNulls(2)
    private var bitmapPoolIndex = 0
    val lastPoseSubmitRealtimeMs = AtomicLong(0L)
    val latestRenderedPtsUs = AtomicLong(0L)
    private var lastReadbackDurationMs: Double = 0.0

    // Session-scoped bounded lookup table mapping decoder presentationTimeUs -> monotonic release time ns
    private val ptsTableLock = Any()
    private val releasedDecoderPtsUsMap = object : LinkedHashMap<Long, Long>(128, 0.75f, false) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<Long, Long>?): Boolean {
            return size > 120
        }
    }

    // Main-thread synchronized replay state for continuous preview progress & >80ms auto-hide
    private var currentSurfacePtsMs: Long = 0L
    private var isCurrentSurfacePtsVerified: Boolean = false
    private var lastPoseSessionGen: Long = -1L
    private var lastPoseVideoPtsMs: Long = -1L
    private var lastPoseStatus: String = "uninitialized"
    private var lastPosePassedQualityGate: Boolean = false
    private var lastSentSyncValid: Boolean = false
    private var lastPreviewEventSentUptimeMs: Long = 0L
    private var sessionSubmitSampleCount: Long = 0L
    private var sessionResultSampleCount: Long = 0L
    @Volatile
    private var isEosReached: Boolean = false

    var activeCameraView: WorkoutCameraView? = null
        private set

    var poseHelper: PoseLandmarkerHelper? = null
        private set

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var isDisposed = false

    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPermissionResult: MethodChannel.Result? = null
    private val audioManager: AudioManager? =
        activity.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
    private var activeAudioFocusRequest: Any? = null

    fun tryAcquireCameraFrameSlot(): Boolean {
        if (isDisposed || !isSessionActive || currentSourceMode != "camera") return false
        val nowElapsedMs = SystemClock.elapsedRealtime()
        val lastSubmitMs = lastPoseSubmitRealtimeMs.get()
        if (lastSubmitMs > 0L && (nowElapsedMs - lastSubmitMs) < MIN_ML_SUBMIT_INTERVAL_MS) {
            return false
        }
        while (true) {
            val current = inFlightCount.get()
            if (current >= MAX_IN_FLIGHT_FRAMES) {
                return false
            }
            if (inFlightCount.compareAndSet(current, current + 1)) {
                lastPoseSubmitRealtimeMs.set(nowElapsedMs)
                return true
            }
        }
    }

    fun releaseCameraFrameSlot() {
        inFlightCount.updateAndGet { maxOf(0, it - 1) }
    }

    private fun acquireReplayPoolBitmap(): Bitmap {
        synchronized(bitmapPoolLock) {
            val index = bitmapPoolIndex
            bitmapPoolIndex = (bitmapPoolIndex + 1) % bitmapPool.size
            val existing = bitmapPool[index]
            if (existing != null && !existing.isRecycled &&
                existing.width == CAPTURE_BITMAP_WIDTH &&
                existing.height == CAPTURE_BITMAP_HEIGHT
            ) {
                return existing
            }
            val created = Bitmap.createBitmap(
                CAPTURE_BITMAP_WIDTH,
                CAPTURE_BITMAP_HEIGHT,
                Bitmap.Config.ARGB_8888
            )
            bitmapPool[index] = created
            return created
        }
    }

    private fun clearReplayBitmapPool(recycleBitmaps: Boolean) {
        synchronized(bitmapPoolLock) {
            for (i in bitmapPool.indices) {
                val bmp = bitmapPool[i]
                bitmapPool[i] = null
                if (recycleBitmaps && bmp != null && !bmp.isRecycled) {
                    bmp.recycle()
                }
            }
            bitmapPoolIndex = 0
        }
    }

    private fun getDeviceHardwareInfo(): Map<String, Any> {
        val activityManager = activity.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        activityManager?.getMemoryInfo(memInfo)
        val totalRamMb = (memInfo.totalMem / (1024L * 1024L)).toInt()
        val cpuCores = Runtime.getRuntime().availableProcessors()
        val androidSdk = Build.VERSION.SDK_INT
        val deviceModel = Build.MODEL ?: "Unknown"
        val manufacturer = Build.MANUFACTURER ?: "Unknown"
        val socHardware = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (Build.SOC_MODEL ?: "").ifBlank { Build.HARDWARE ?: "Unknown" }
        } else {
            Build.HARDWARE ?: "Unknown"
        }

        return mapOf(
            "totalRamMb" to totalRamMb,
            "cpuCores" to cpuCores,
            "androidSdk" to androidSdk,
            "deviceModel" to deviceModel,
            "manufacturer" to manufacturer,
            "socHardware" to socHardware
        )
    }

    private fun runPoseBenchmark(frameCountArg: Int?, result: MethodChannel.Result) {
        val targetFrames = (frameCountArg ?: BENCHMARK_DEFAULT_FRAMES)
            .coerceIn(BENCHMARK_MIN_FRAMES, BENCHMARK_MAX_FRAMES)
        val appContext = activity.applicationContext

        Thread({
            var benchmarkLandmarker: PoseLandmarker? = null
            var bitmap: Bitmap? = null
            val payload: Map<String, Any?> = try {
                val baseOptions = BaseOptions.builder()
                    .setModelAssetPath(BENCHMARK_MODEL_NAME)
                    .setDelegate(Delegate.CPU)
                    .build()
                val options = PoseLandmarker.PoseLandmarkerOptions.builder()
                    .setBaseOptions(baseOptions)
                    .setMinPoseDetectionConfidence(0.4f)
                    .setMinTrackingConfidence(0.4f)
                    .setMinPosePresenceConfidence(0.4f)
                    .setNumPoses(1)
                    .setOutputSegmentationMasks(false)
                    .setRunningMode(RunningMode.IMAGE)
                    .build()

                benchmarkLandmarker = PoseLandmarker.createFromOptions(appContext, options)

                bitmap = Bitmap.createBitmap(
                    BENCHMARK_INPUT_WIDTH,
                    BENCHMARK_INPUT_HEIGHT,
                    Bitmap.Config.ARGB_8888
                )
                val canvas = Canvas(bitmap)
                canvas.drawColor(Color.rgb(236, 240, 244))
                val shapePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.rgb(64, 82, 108)
                    style = Paint.Style.FILL
                }
                canvas.drawCircle(BENCHMARK_INPUT_WIDTH / 2f, 54f, 20f, shapePaint)
                canvas.drawRect(68f, 80f, 124f, 166f, shapePaint)
                canvas.drawRect(72f, 166f, 92f, 236f, shapePaint)
                canvas.drawRect(100f, 166f, 120f, 236f, shapePaint)

                // 1 warmup frame (excluded from timing)
                benchmarkLandmarker.detect(BitmapImageBuilder(bitmap).build())

                val startNs = SystemClock.elapsedRealtimeNanos()
                var framesRun = 0
                for (i in 0 until targetFrames) {
                    benchmarkLandmarker.detect(BitmapImageBuilder(bitmap).build())
                    framesRun++
                    val elapsedMs = (SystemClock.elapsedRealtimeNanos() - startNs) / 1_000_000.0
                    if (framesRun >= BENCHMARK_EARLY_STOP_MIN_FRAMES && elapsedMs > BENCHMARK_MAX_ELAPSED_MS) {
                        break
                    }
                }
                val totalMs = (SystemClock.elapsedRealtimeNanos() - startNs) / 1_000_000.0
                val avgInferenceMs = if (framesRun > 0) totalMs / framesRun else 0.0
                val measuredFps = if (totalMs > 0.0) (framesRun * 1000.0 / totalMs) else 0.0

                mapOf(
                    "success" to true,
                    "measuredFps" to measuredFps,
                    "avgInferenceMs" to avgInferenceMs,
                    "framesRun" to framesRun,
                    "inputWidth" to BENCHMARK_INPUT_WIDTH,
                    "inputHeight" to BENCHMARK_INPUT_HEIGHT,
                    "delegate" to "CPU",
                    "errorMessage" to null
                )
            } catch (e: Exception) {
                Log.e(TAG, "Pose benchmark failed: ${e.message}", e)
                mapOf(
                    "success" to false,
                    "measuredFps" to 0.0,
                    "avgInferenceMs" to 0.0,
                    "framesRun" to 0,
                    "inputWidth" to BENCHMARK_INPUT_WIDTH,
                    "inputHeight" to BENCHMARK_INPUT_HEIGHT,
                    "delegate" to "CPU",
                    "errorMessage" to (e.message ?: "Pose benchmark failed")
                )
            } finally {
                try {
                    benchmarkLandmarker?.close()
                } catch (closeEx: Exception) {
                    Log.w(TAG, "Error closing benchmark PoseLandmarker: ${closeEx.message}")
                }
                if (bitmap != null && !bitmap.isRecycled) {
                    bitmap.recycle()
                }
            }

            mainHandler.post {
                if (!isDisposed) {
                    result.success(payload)
                }
            }
        }, "WorkoutCvBenchmarkThread").apply {
            isDaemon = true
            start()
        }
    }

    private fun requestAudioFocusInternal(): Boolean {
        val manager = audioManager ?: return false
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val focusRequest = (activeAudioFocusRequest as? AudioFocusRequest) ?: run {
                    val attributes = AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                    AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                        .setAudioAttributes(attributes)
                        .build()
                        .also { activeAudioFocusRequest = it }
                }
                manager.requestAudioFocus(focusRequest) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            } else {
                @Suppress("DEPRECATION")
                val focusResult = manager.requestAudioFocus(
                    null,
                    AudioManager.STREAM_MUSIC,
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
                )
                focusResult == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            }
        } catch (e: Exception) {
            Log.w(TAG, "requestAudioFocus failed: ${e.message}")
            false
        }
    }

    private fun abandonAudioFocusInternal(): Boolean {
        val manager = audioManager ?: return true
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val focusRequest = activeAudioFocusRequest as? AudioFocusRequest
                if (focusRequest != null) {
                    manager.abandonAudioFocusRequest(focusRequest)
                    activeAudioFocusRequest = null
                }
            } else {
                @Suppress("DEPRECATION")
                manager.abandonAudioFocus(null)
            }
            true
        } catch (e: Exception) {
            Log.w(TAG, "abandonAudioFocus failed: ${e.message}")
            true
        }
    }

    fun hasCameraPermission(): Boolean = ContextCompat.checkSelfPermission(
        activity, Manifest.permission.CAMERA
    ) == PackageManager.PERMISSION_GRANTED

    fun attachCameraView(view: WorkoutCameraView) {
        if (activeCameraView !== view) {
            activeCameraView?.stopCamera()
            activeCameraView?.stopVideoDecoder()
            activeCameraView = view
        }
        if (isSessionActive && currentSourceMode == "video_replay") {
            // The platform view is usually created after startVideoReplay already ran; replay the
            // session's resolved file (e.g. an image_picker cache path), not the bundled test clip.
            (currentReplayFile ?: resolveVideoFile(null))?.let {
                view.switchToVideoReplay(it, currentSessionGeneration)
            }
        }
    }

    fun detachCameraView(view: WorkoutCameraView) {
        if (activeCameraView === view) activeCameraView = null
    }

    fun dispose() {
        if (isDisposed) return
        isDisposed = true
        pendingPermissionResult?.success(false)
        pendingPermissionResult = null
        stopCurrentSession()
        abandonAudioFocusInternal()
        clearReplayBitmapPool(recycleBitmaps = true)
        val view = activeCameraView
        activeCameraView = null
        view?.dispose()
        mainHandler.removeCallbacksAndMessages(null)
        eventSink = null
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
    }


    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (isDisposed) {
            result.success(false)
            return
        }
        when (call.method) {
            "checkPermission" -> {
                val granted = ContextCompat.checkSelfPermission(
                    activity,
                    Manifest.permission.CAMERA
                ) == PackageManager.PERMISSION_GRANTED
                result.success(if (granted) "granted" else "denied")
            }
            "requestPermission" -> {
                val granted = ContextCompat.checkSelfPermission(
                    activity,
                    Manifest.permission.CAMERA
                ) == PackageManager.PERMISSION_GRANTED
                if (granted) {
                    result.success(true)
                } else {
                    pendingPermissionResult?.success(false)
                    pendingPermissionResult = result
                    ActivityCompat.requestPermissions(
                        activity,
                        arrayOf(Manifest.permission.CAMERA),
                        CAMERA_PERMISSION_CODE
                    )
                }
            }
            "startSession" -> {
                val exerciseSlug = call.argument<String>("exerciseSlug") ?: "general"
                result.success(startCameraSession(exerciseSlug))
            }
            "startVideoReplay" -> {
                val videoPath = call.argument<String>("videoPath")
                val success = startVideoReplaySession(videoPath)
                result.success(success)
            }
            "switchSource" -> {
                val mode = call.argument<String>("mode") ?: "camera"
                val videoPath = call.argument<String>("videoPath")
                if (mode == "video_replay") {
                    val success = startVideoReplaySession(videoPath)
                    result.success(success)
                } else {
                    result.success(startCameraSession("general"))
                }
            }
            "restartVideoReplay" -> {
                val success = startVideoReplaySession(null)
                result.success(success)
            }
            "stopSession" -> {
                stopCurrentSession()
                result.success(true)
            }
            "acknowledgeReplayFrame" -> {
                val generation = call.argument<Number>("sessionGen")?.toLong()
                val ptsMs = call.argument<Number>("videoPtsMs")?.toLong()
                val phase = call.argument<String>("phase")
                val accepted = isSessionActive && currentSourceMode == "video_replay" &&
                    generation != null && generation == currentSessionGeneration && ptsMs != null && phase != null &&
                    (activeCameraView?.acknowledgeReplayFrame(generation, ptsMs, phase) == true)
                if (accepted) Log.i(TAG, "[CV_FLUTTER_ACK] sessionGen=$generation ptsMs=$ptsMs phase=$phase")
                result.success(accepted)
            }
            "getDeviceHardwareInfo" -> {
                result.success(getDeviceHardwareInfo())
            }
            "runPoseBenchmark" -> {
                val frameCount = call.argument<Number>("frameCount")?.toInt()
                runPoseBenchmark(frameCount, result)
            }
            "requestAudioFocus" -> {
                result.success(requestAudioFocusInternal())
            }
            "abandonAudioFocus" -> {
                result.success(abandonAudioFocusInternal())
            }
            else -> result.notImplemented()
        }
    }

    private fun resetSessionSyncState() {
        synchronized(ptsTableLock) {
            releasedDecoderPtsUsMap.clear()
        }
        lastPoseSubmitRealtimeMs.set(0L)
        latestRenderedPtsUs.set(0L)
        currentSurfacePtsMs = 0L
        isCurrentSurfacePtsVerified = false
        lastPoseSessionGen = -1L
        lastPoseVideoPtsMs = -1L
        lastPoseStatus = "uninitialized"
        lastPosePassedQualityGate = false
        lastSentSyncValid = false
        lastPreviewEventSentUptimeMs = 0L
        sessionSubmitSampleCount = 0L
        sessionResultSampleCount = 0L
        isEosReached = false
    }

    private fun startCameraSession(exerciseSlug: String): Boolean {
        if (!hasCameraPermission()) return false
        currentSessionGeneration++
        val sessionGen = currentSessionGeneration
        isSessionActive = true
        currentSourceMode = "camera"
        currentClipName = ""
        inFlightCount.set(0)
        resetSessionSyncState()

        WorkoutCvPerfTracker.reset()
        poseHelper?.clearPoseLandmarker()
        poseHelper = PoseLandmarkerHelper(activity.applicationContext, this)
        if (poseHelper?.isInitialized != true) {
            isSessionActive = false
            poseHelper?.clearPoseLandmarker()
            poseHelper = null
            activeCameraView?.stopCamera()
            activeCameraView?.stopVideoDecoder()
            return false
        }

        activeCameraView?.switchToCamera()
        Log.i(TAG, "[CV_SYNC_SESSION] Started Camera session gen=$sessionGen slug=$exerciseSlug")
        return true
    }

    private fun resolveVideoFile(path: String?): File? {
        val candidates = mutableListOf<File>()

        if (!path.isNullOrBlank()) {
            candidates.add(File(path))
        }

        // 1. App internal files storage
        candidates.add(File(activity.filesDir, "test_videos/15620300_1080_1920_50fps.mp4"))
        candidates.add(File("/data/data/com.example.health_ai_app/files/test_videos/15620300_1080_1920_50fps.mp4"))

        // 2. App-specific media storage
        candidates.add(File("/sdcard/Android/media/com.example.health_ai_app/test_videos/15620300_1080_1920_50fps.mp4"))

        for (candidate in candidates) {
            if (candidate.exists() && candidate.canRead()) {
                Log.i(TAG, "Resolved video file: ${candidate.absolutePath}")
                return candidate
            }
        }

        Log.w(TAG, "Could not resolve readable video file from candidates: ${candidates.map { it.absolutePath }}")
        return null
    }

    private fun startVideoReplaySession(videoPath: String?): Boolean {
        val file = resolveVideoFile(videoPath ?: currentReplayFile?.absolutePath)
        if (file == null) {
            sendErrorEvent("Video file not found or cannot be read. Checked app internal & media storage.")
            return false
        }

        currentSessionGeneration++
        val sessionGen = currentSessionGeneration
        isSessionActive = true
        currentSourceMode = "video_replay"
        currentClipName = file.name
        currentReplayFile = file
        inFlightCount.set(0)
        resetSessionSyncState()

        WorkoutCvPerfTracker.reset()
        poseHelper?.clearPoseLandmarker()
        poseHelper = PoseLandmarkerHelper(activity.applicationContext, this)
        if (poseHelper?.isInitialized != true) {
            isSessionActive = false
            poseHelper?.clearPoseLandmarker()
            poseHelper = null
            activeCameraView?.stopCamera()
            activeCameraView?.stopVideoDecoder()
            return false
        }

        activeCameraView?.switchToVideoReplay(file, sessionGen)
        Log.i(TAG, "[CV_SYNC_SESSION] Started Video Replay session gen=$sessionGen, file=${file.name}")
        return true
    }

    private fun stopCurrentSession() {
        val endingGen = currentSessionGeneration
        if (isSessionActive && currentSourceMode == "video_replay") {
            WorkoutCvPerfTracker.recordOverlayTransition(
                nowNs = SystemClock.elapsedRealtimeNanos(),
                newState = WorkoutCvPerfTracker.OverlayState.HIDDEN_NO_RESULT,
                isNewRenderedVideoFrame = false,
                liveSkewMs = null
            )
        }
        isSessionActive = false
        currentSessionGeneration++
        inFlightCount.set(0)
        resetSessionSyncState()
        WorkoutCvPerfTracker.dumpSummary(0.0, isFinal = true)
        activeCameraView?.stopVideoDecoder()
        activeCameraView?.stopCamera()
        poseHelper?.clearPoseLandmarker()
        poseHelper = null
        abandonAudioFocusInternal()
        clearReplayBitmapPool(recycleBitmaps = true)
        Log.i(TAG, "[CV_SYNC_SESSION] Stopped session gen=$endingGen -> new idle gen=$currentSessionGeneration")
    }

    fun onTextureFrameUpdated(textureView: TextureView, surfaceTexture: SurfaceTexture) {
        if (!isSessionActive || currentSourceMode != "video_replay" || isEosReached) return
        val sessionGen = currentSessionGeneration

        WorkoutCvPerfTracker.onAnalyzerArrival()
        WorkoutCvPerfTracker.surfaceFramesUpdated.incrementAndGet()

        val surfaceTsBeforeNs = surfaceTexture.timestamp
        if (WorkoutCvPerfTracker.surfaceFramesUpdated.get() <= 3L) {
            Log.i(TAG, "[CV_SURFACE_UPDATE] sessionGen=$sessionGen timestampNs=$surfaceTsBeforeNs")
        }
        val targetPtsUs = surfaceTsBeforeNs / 1000L
        var matchedDecoderPtsUs: Long? = null
        synchronized(ptsTableLock) {
            if (releasedDecoderPtsUsMap.containsKey(targetPtsUs)) {
                matchedDecoderPtsUs = targetPtsUs
            } else {
                for (k in releasedDecoderPtsUsMap.keys) {
                    if (abs(k - targetPtsUs) <= 500L) {
                        matchedDecoderPtsUs = k
                        break
                    }
                }
            }
        }

        val isPtsVerified = (matchedDecoderPtsUs != null)
        if (isPtsVerified) {
            WorkoutCvPerfTracker.ptsVerifiedFrames.incrementAndGet()
        } else {
            WorkoutCvPerfTracker.ptsUnverifiedFrames.incrementAndGet()
        }

        val verifiedPtsMs = if (matchedDecoderPtsUs != null) {
            matchedDecoderPtsUs!! / 1000L
        } else {
            val latestPtsUs = latestRenderedPtsUs.get()
            if (latestPtsUs > 0L) latestPtsUs / 1000L else surfaceTsBeforeNs / 1_000_000L
        }

        currentSurfacePtsMs = verifiedPtsMs
        isCurrentSurfacePtsVerified = true

        val nowNs = SystemClock.elapsedRealtimeNanos()
        val hasResultForSession = (lastPoseSessionGen == sessionGen && lastPoseVideoPtsMs >= 0L)
        val overlayState = when {
            !hasResultForSession -> WorkoutCvPerfTracker.OverlayState.HIDDEN_NO_RESULT
            !lastPosePassedQualityGate -> WorkoutCvPerfTracker.OverlayState.HIDDEN_QUALITY_GATE
            else -> WorkoutCvPerfTracker.OverlayState.VISIBLE
        }

        WorkoutCvPerfTracker.recordOverlayTransition(
            nowNs = nowNs,
            newState = overlayState,
            isNewRenderedVideoFrame = true,
            liveSkewMs = if (hasResultForSession) 0L else null
        )

        // Frame Dropping: Drop frame for MediaPipe if MAX_IN_FLIGHT_FRAMES frames are already in-flight (2-deep pipelining)
        // OR if less than MIN_ML_SUBMIT_INTERVAL_MS (55ms, ~18 FPS cap) has elapsed since the previous MediaPipe submission.
        val nowElapsedMs = SystemClock.elapsedRealtime()
        val lastSubmitMs = lastPoseSubmitRealtimeMs.get()
        if (lastSubmitMs > 0L && (nowElapsedMs - lastSubmitMs) < MIN_ML_SUBMIT_INTERVAL_MS) {
            return
        }
        if (inFlightCount.get() >= MAX_IN_FLIGHT_FRAMES) {
            return
        }
        inFlightCount.incrementAndGet()

        // Measure readback duration separately and read the exact SurfaceTexture timestamp latched by copySurfaceInto.
        // Downscale to 192x256 (preserving 3:4 workout video aspect ratio) into a reusable pooled bitmap (no per-frame allocation).
        val tRead0 = SystemClock.elapsedRealtimeNanos()
        val targetBitmap = acquireReplayPoolBitmap()
        val bitmap = textureView.getBitmap(targetBitmap)
        val surfaceTsAfterNs = surfaceTexture.timestamp
        val tRead1 = SystemClock.elapsedRealtimeNanos()
        val readbackMs = (tRead1 - tRead0) / 1_000_000.0
        lastReadbackDurationMs = readbackMs
        WorkoutCvPerfTracker.recordReadbackDuration(readbackMs)

        // Resolve the post-readback SurfaceTexture timestamp against the session's released decoder PTS table
        val captureTargetPtsUs = surfaceTsAfterNs / 1000L
        var capturedDecoderPtsUs: Long? = null
        synchronized(ptsTableLock) {
            if (releasedDecoderPtsUsMap.containsKey(captureTargetPtsUs)) {
                capturedDecoderPtsUs = captureTargetPtsUs
            } else {
                for (k in releasedDecoderPtsUsMap.keys) {
                    if (abs(k - captureTargetPtsUs) <= 500L) {
                        capturedDecoderPtsUs = k
                        break
                    }
                }
            }
        }

        val finalDecoderPtsUs = capturedDecoderPtsUs ?: matchedDecoderPtsUs ?: latestRenderedPtsUs.get()
        val capturedFramePtsMs = (finalDecoderPtsUs / 1000L).coerceAtLeast(0L)
        currentSurfacePtsMs = capturedFramePtsMs
        isCurrentSurfacePtsVerified = true
        activeCameraView?.onReplayFrameCaptured(sessionGen, finalDecoderPtsUs)

        if (bitmap == null) {
            inFlightCount.updateAndGet { maxOf(0, it - 1) }
            return
        }

        val helper = poseHelper
        if (helper == null || !isSessionActive || sessionGen != currentSessionGeneration) {
            inFlightCount.updateAndGet { maxOf(0, it - 1) }
            return
        }

        val submitted = helper.detectVideoFrame(
            bitmap = bitmap,
            videoPtsMs = capturedFramePtsMs,
            sessionGen = sessionGen,
            decoderPtsUs = finalDecoderPtsUs,
            surfaceTimestampNs = surfaceTsAfterNs,
            readbackMs = readbackMs,
            isPtsVerified = true
        )

        if (!submitted) {
            inFlightCount.updateAndGet { maxOf(0, it - 1) }
            return
        }

        lastPoseSubmitRealtimeMs.set(SystemClock.elapsedRealtime())

        sessionSubmitSampleCount++
        if (VERBOSE_FRAME_LOGS && (sessionSubmitSampleCount <= 15L || sessionSubmitSampleCount % 10L == 0L)) {
            Log.i(
                TAG,
                "[CV_SYNC_SUBMIT] sessionGen=$sessionGen submitIdx=$sessionSubmitSampleCount " +
                    "decoderPtsUs=$finalDecoderPtsUs surfaceTsBeforeNs=$surfaceTsBeforeNs " +
                    "surfaceTsAfterNs=$surfaceTsAfterNs verifiedPtsMs=$capturedFramePtsMs " +
                    "isPtsVerified=true readbackMs=${"%.2f".format(readbackMs)}"
            )
        }
    }

    fun onVideoStarted(sessionGen: Long, durationUs: Long, width: Int, height: Int, fps: Double) {
        if (!isSessionActive || sessionGen != currentSessionGeneration) return
        videoSourceFps = fps
        Log.i(TAG, "Video started (sessionGen=$sessionGen): ${width}x$height @ $fps FPS")
    }

    fun onVideoFrameRendered(sessionGen: Long, presentationTimeUs: Long) {
        if (!isSessionActive || sessionGen != currentSessionGeneration) return
        WorkoutCvPerfTracker.decoderFramesReleased.incrementAndGet()
        synchronized(ptsTableLock) {
            releasedDecoderPtsUsMap[presentationTimeUs] = SystemClock.elapsedRealtimeNanos()
        }
        latestRenderedPtsUs.set(presentationTimeUs)
    }

    fun onVideoFramePreparing(sessionGen: Long, presentationTimeUs: Long) {
        mainHandler.post {
            if (!isSessionActive || currentSourceMode != "video_replay" || sessionGen != currentSessionGeneration) return@post
            lastPoseSessionGen = -1L
            lastSentSyncValid = false
            WorkoutCvPerfTracker.recordOverlayTransition(
                SystemClock.elapsedRealtimeNanos(),
                WorkoutCvPerfTracker.OverlayState.HIDDEN_NO_RESULT, false, null
            )
            eventSink?.success(mapOf(
                "status" to "replayPreparing",
                "sessionGen" to sessionGen,
                "sourceMode" to "video_replay",
                "nextVideoPtsMs" to presentationTimeUs / 1000L
            ))
        }
    }

    fun onVideoEndOfStream(sessionGen: Long, totalFramesRendered: Long, lastPtsUs: Long) {
        val lastPtsMs = lastPtsUs / 1000L
        // Bounded wait for in-flight pose completion before emitting EOS
        Thread({
            val waitStartNs = SystemClock.elapsedRealtimeNanos()
            val maxWaitNs = 500_000_000L // 500ms max wait for final in-flight frame
            while (inFlightCount.get() > 0 && (SystemClock.elapsedRealtimeNanos() - waitStartNs) < maxWaitNs) {
                try {
                    Thread.sleep(10)
                } catch (_: InterruptedException) {
                    break
                }
            }
            mainHandler.post {
                if (!isSessionActive || currentSourceMode != "video_replay" || sessionGen != currentSessionGeneration) {
                    return@post
                }
                isEosReached = true
                WorkoutCvPerfTracker.recordOverlayTransition(
                    nowNs = SystemClock.elapsedRealtimeNanos(),
                    newState = WorkoutCvPerfTracker.OverlayState.HIDDEN_NO_RESULT,
                    isNewRenderedVideoFrame = false,
                    liveSkewMs = null
                )
                WorkoutCvPerfTracker.dumpSummary(0.0, isFinal = true)
                val ov = WorkoutCvPerfTracker.getOverlayVisSummary()
                eventSink?.success(
                    mapOf(
                        "status" to "endOfStream",
                        "sessionGen" to sessionGen,
                        "timestamp" to lastPtsMs,
                        "videoPtsMs" to lastPtsMs,
                        "previewPtsMs" to lastPtsMs,
                        "ptsSkewMs" to 0L,
                        "isPtsVerified" to true,
                        "sourceMode" to "video_replay",
                        "clipName" to currentClipName,
                        "sourceFps" to videoSourceFps,
                        "isEndOfStream" to true,
                        "numPoses" to 0,
                        "landmarks" to emptyList<Map<String, Any>>(),
                        "readbackMs" to lastReadbackDurationMs,
                        "overlayVisiblePct" to ov.visiblePct,
                        "overlayHiddenSkewPct" to ov.hiddenSkewPct,
                        "overlayHiddenNoResultPct" to ov.hiddenNoResultPct,
                        "overlayHiddenGatePct" to ov.hiddenGatePct
                    )
                )
            }
        }, "WorkoutCvEosWorker").apply {
            isDaemon = true
            start()
        }
    }

    fun onVideoDecoderError(sessionGen: Long, error: String) {
        if (!isSessionActive || sessionGen != currentSessionGeneration) return
        Log.e(TAG, "[CV_REPLAY_ERROR] sessionGen=$sessionGen $error")
        mainHandler.post {
            if (!isSessionActive || sessionGen != currentSessionGeneration) return@post
            isEosReached = true // No late result may replace the replay failure.
            activeCameraView?.stopVideoDecoder()
            eventSink?.success(mapOf(
                "status" to "error",
                "sessionGen" to sessionGen,
                "sourceMode" to "video_replay",
                "timestamp" to currentSurfacePtsMs,
                "isPtsVerified" to false,
                "numPoses" to 0,
                "landmarks" to emptyList<Map<String, Any>>(),
                "errorMessage" to error
            ))
        }
    }

    fun handleRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode == CAMERA_PERMISSION_CODE) {
            val isGranted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(isGranted)
            pendingPermissionResult = null
            return true
        }
        return false
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun sendErrorEvent(errorMessage: String) {
        if (isDisposed) return
        mainHandler.post {
            if (isDisposed) return@post
            eventSink?.success(
                mapOf(
                    "status" to "error",
                    "timestamp" to System.currentTimeMillis(),
                    "latencyMs" to 0L,
                    "numPoses" to 0,
                    "landmarks" to emptyList<Map<String, Any>>(),
                    "errorMessage" to errorMessage,
                    "sourceMode" to currentSourceMode,
                    "clipName" to currentClipName
                )
            )
        }
    }

    override fun onError(error: String, errorCode: Int) {
        inFlightCount.updateAndGet { maxOf(0, it - 1) }
        sendErrorEvent(error)
    }

    override fun onResults(resultBundle: PoseLandmarkerHelper.ResultBundle) {
        if (!isSessionActive || resultBundle.sessionGen != currentSessionGeneration) {
            inFlightCount.updateAndGet { maxOf(0, it - 1) }
            WorkoutCvPerfTracker.staleSessionCallbacksDropped.incrementAndGet()
            Log.w(
                TAG,
                "[CV_SYNC_STALE_DROP] Dropped stale callback from sessionGen=${resultBundle.sessionGen} " +
                    "(currentSessionGen=$currentSessionGeneration, isSessionActive=$isSessionActive)"
            )
            return
        }

        // Free pose in-flight flag immediately on completion for active session
        inFlightCount.updateAndGet { maxOf(0, it - 1) }

        val result = resultBundle.results.firstOrNull() ?: return
        val landmarks = result.landmarks()

        val postScheduledNs = SystemClock.elapsedRealtimeNanos()
        mainHandler.post {
            val postExecNs = SystemClock.elapsedRealtimeNanos()
            WorkoutCvPerfTracker.recordDispatchLatency((postExecNs - postScheduledNs) / 1_000_000.0)

            if (!isSessionActive || resultBundle.sessionGen != currentSessionGeneration || isEosReached) {
                WorkoutCvPerfTracker.staleSessionCallbacksDropped.incrementAndGet()
                return@post
            }
            val sink = eventSink ?: return@post

            val tPack0 = SystemClock.elapsedRealtimeNanos()

            val videoPtsMs = resultBundle.timestamp
            val isReplay = (currentSourceMode == "video_replay")
            val isPtsVerified = if (isReplay) {
                resultBundle.isPtsVerified
            } else {
                true
            }
            // Preserve the captured frame's PTS so Dart FSM & skeleton overlay remain valid while video renders at 30-60 FPS
            val currentPreviewPtsMs = videoPtsMs
            val skewMs = 0L

            val statusStr = when {
                landmarks.isEmpty() -> "lost"
                landmarks.size > 1 -> "multiplePeople"
                else -> "detecting"
            }

            val landmarkList = if (statusStr == "detecting") {
                val singlePose = landmarks[0]
                singlePose.mapIndexed { index, lm ->
                    val visibilityVal = if (lm.visibility().isPresent) lm.visibility().get() else 1.0f
                    mapOf(
                        "index" to index,
                        "x" to lm.x(),
                        "y" to lm.y(),
                        "z" to lm.z(),
                        "visibility" to visibilityVal
                    )
                }
            } else {
                emptyList()
            }

            if (isReplay) {
                val passedQualityGate = (statusStr == "detecting")
                lastPoseSessionGen = resultBundle.sessionGen
                lastPoseVideoPtsMs = videoPtsMs
                lastPoseStatus = statusStr
                lastPosePassedQualityGate = passedQualityGate

                val overlayState = when {
                    !passedQualityGate -> WorkoutCvPerfTracker.OverlayState.HIDDEN_QUALITY_GATE
                    isPtsVerified && skewMs <= 80L -> WorkoutCvPerfTracker.OverlayState.VISIBLE
                    else -> WorkoutCvPerfTracker.OverlayState.HIDDEN_SKEW
                }

                WorkoutCvPerfTracker.recordCallbackSkew(skewMs)
                WorkoutCvPerfTracker.recordOverlayTransition(
                    nowNs = postExecNs,
                    newState = overlayState,
                    isNewRenderedVideoFrame = false,
                    liveSkewMs = null
                )

                lastSentSyncValid = (overlayState == WorkoutCvPerfTracker.OverlayState.VISIBLE)
                lastPreviewEventSentUptimeMs = SystemClock.uptimeMillis()

                sessionResultSampleCount++
                if (VERBOSE_FRAME_LOGS && (sessionResultSampleCount <= 15L || sessionResultSampleCount % 10L == 0L)) {
                    Log.i(
                        TAG,
                        "[CV_SYNC_RESULT] sessionGen=${resultBundle.sessionGen} resultIdx=$sessionResultSampleCount " +
                            "decoderPtsUs=${resultBundle.decoderPtsUs} surfaceTsNs=${resultBundle.surfaceTimestampNs} " +
                            "inputPtsMs=$videoPtsMs readbackMs=${"%.2f".format(resultBundle.readbackMs)} " +
                            "asyncMs=${resultBundle.inferenceTime} displayPreviewPtsMs=$currentPreviewPtsMs " +
                            "callbackSkewMs=$skewMs isPtsVerified=$isPtsVerified " +
                            "isSyncValid=$lastSentSyncValid overlayState=$overlayState status=$statusStr"
                    )
                }
            }

            val ov = WorkoutCvPerfTracker.getOverlayVisSummary()

            val eventMap: Map<String, Any> = mapOf(
                "status" to statusStr,
                "sessionGen" to resultBundle.sessionGen,
                "timestamp" to resultBundle.timestamp,
                "latencyMs" to resultBundle.inferenceTime,
                "inputImageWidth" to resultBundle.inputImageWidth,
                "inputImageHeight" to resultBundle.inputImageHeight,
                "numPoses" to landmarks.size,
                "landmarks" to landmarkList,
                "sourceMode" to currentSourceMode,
                "clipName" to currentClipName,
                "videoPtsMs" to videoPtsMs,
                "previewPtsMs" to currentPreviewPtsMs,
                "ptsSkewMs" to skewMs,
                "isPtsVerified" to isPtsVerified,
                "sourceFps" to videoSourceFps,
                "readbackMs" to resultBundle.readbackMs,
                "isEndOfStream" to false,
                "requiresReplayAck" to false,
                "overlayVisiblePct" to ov.visiblePct,
                "overlayHiddenSkewPct" to ov.hiddenSkewPct,
                "overlayHiddenNoResultPct" to ov.hiddenNoResultPct,
                "overlayHiddenGatePct" to ov.hiddenGatePct
            )

            val tPack1 = SystemClock.elapsedRealtimeNanos()
            WorkoutCvPerfTracker.recordPackDuration((tPack1 - tPack0) / 1_000.0)

            val tSink0 = SystemClock.elapsedRealtimeNanos()
            sink.success(eventMap)
            val tSink1 = SystemClock.elapsedRealtimeNanos()
            WorkoutCvPerfTracker.recordSinkDuration((tSink1 - tSink0) / 1_000.0)
        }
    }
}
