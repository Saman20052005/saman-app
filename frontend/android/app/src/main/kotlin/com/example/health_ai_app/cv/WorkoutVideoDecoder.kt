package com.example.health_ai_app.cv

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.SystemClock
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/**
 * Inference-paced replay. Selected frames stay on the Surface until Flutter has
 * rendered their pose; video PTS is independent of elapsed processing time.
 */
class WorkoutVideoDecoder(
    private val videoFile: File,
    private val surface: Surface,
    private val sessionGen: Long,
    private val listener: VideoDecoderListener
) {

    companion object {
        private const val TAG = "WorkoutVideoDecoder"
        private const val TIMEOUT_US = 10_000L
        private const val SAMPLE_INTERVAL_US = 100_000L
        private const val FRAME_TIMEOUT_MS = 8_000L
        private const val POSE_DISPLAY_MS = 150L
    }

    interface VideoDecoderListener {
        fun onVideoStarted(sessionGen: Long, durationUs: Long, width: Int, height: Int, fps: Double)
        fun onFrameRendered(sessionGen: Long, presentationTimeUs: Long)
        fun onFramePreparing(sessionGen: Long, presentationTimeUs: Long)
        fun onEndOfStream(sessionGen: Long, totalFramesRendered: Long, lastPtsUs: Long)
        fun onError(sessionGen: Long, error: String)
    }

    private val isRunning = AtomicBoolean(false)
    private var workerThread: Thread? = null
    private val frameGate = WorkoutReplayFrameGate(sessionGen)

    fun acknowledgeFrame(generation: Long, ptsMs: Long, phase: String): Boolean =
        frameGate.acknowledge(generation, ptsMs, phase)

    val latestRenderedPtsUs = AtomicLong(0L)
    val totalFramesRendered = AtomicLong(0L)

    fun start() {
        if (isRunning.getAndSet(true)) return

        workerThread = Thread({
            decodeLoop()
        }, "WorkoutVideoDecoderThread").apply {
            isDaemon = true
            start()
        }
    }

    fun stop() {
        isRunning.set(false)
        frameGate.cancel()
        workerThread?.interrupt()
        workerThread = null
    }

    private fun decodeLoop() {
        if (!videoFile.exists() || !videoFile.canRead()) {
            listener.onError(sessionGen, "Cannot read video file at: ${videoFile.absolutePath}")
            isRunning.set(false)
            return
        }

        var extractor: MediaExtractor? = null
        var codec: MediaCodec? = null

        try {
            extractor = MediaExtractor().apply {
                setDataSource(videoFile.absolutePath)
            }

            var videoTrackIndex = -1
            var format: MediaFormat? = null
            var mime = ""

            for (i in 0 until extractor.trackCount) {
                val trackFormat = extractor.getTrackFormat(i)
                val trackMime = trackFormat.getString(MediaFormat.KEY_MIME) ?: ""
                if (trackMime.startsWith("video/")) {
                    videoTrackIndex = i
                    format = trackFormat
                    mime = trackMime
                    break
                }
            }

            if (videoTrackIndex < 0 || format == null) {
                listener.onError(sessionGen, "No video track found in ${videoFile.name}")
                return
            }

            extractor.selectTrack(videoTrackIndex)

            val width = if (format.containsKey(MediaFormat.KEY_WIDTH)) format.getInteger(MediaFormat.KEY_WIDTH) else 1080
            val height = if (format.containsKey(MediaFormat.KEY_HEIGHT)) format.getInteger(MediaFormat.KEY_HEIGHT) else 1920
            val durationUs = if (format.containsKey(MediaFormat.KEY_DURATION)) format.getLong(MediaFormat.KEY_DURATION) else 0L
            val frameRate = if (format.containsKey(MediaFormat.KEY_FRAME_RATE)) format.getInteger(MediaFormat.KEY_FRAME_RATE).toDouble() else 50.0

            Log.i(TAG, "Starting decode (sessionGen=$sessionGen): ${videoFile.name}, ${width}x${height}, duration=${durationUs / 1000}ms, fps=$frameRate")
            listener.onVideoStarted(sessionGen, durationUs, width, height, frameRate)

            codec = MediaCodec.createDecoderByType(mime).apply {
                configure(format, surface, null, 0)
                setOnFrameRenderedListener({ _, ptsUs, renderNs ->
                    Log.i(TAG, "[CV_CODEC_RENDER] sessionGen=$sessionGen ptsUs=$ptsUs renderMonotonicNs=$renderNs")
                }, Handler(Looper.getMainLooper()))
                start()
            }

            val bufferInfo = MediaCodec.BufferInfo()
            var isEos = false
            val playbackStartNs = SystemClock.elapsedRealtimeNanos()
            var nextSamplePtsUs = 1L // Avoid an initial empty Surface timestamp of zero.
            var decodedFrameCount = 0L
            var frameCount = 0L

            while (isRunning.get() && !Thread.currentThread().isInterrupted) {
                // 1. Feed input buffer
                if (!isEos) {
                    val inIndex = codec.dequeueInputBuffer(TIMEOUT_US)
                    if (inIndex >= 0) {
                        val inputBuffer = codec.getInputBuffer(inIndex)
                        if (inputBuffer != null) {
                            val sampleSize = extractor.readSampleData(inputBuffer, 0)
                            if (sampleSize < 0) {
                                codec.queueInputBuffer(inIndex, 0, 0, 0L, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                isEos = true
                            } else {
                                val sampleTime = extractor.sampleTime
                                codec.queueInputBuffer(inIndex, 0, sampleSize, sampleTime, 0)
                                extractor.advance()
                            }
                        }
                    }
                }

                // Decode all frames, presenting at most one sample per 100ms of video PTS.
                val outIndex = codec.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)
                if (outIndex >= 0) {
                    if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        codec.releaseOutputBuffer(outIndex, false)
                        val elapsedMs = (SystemClock.elapsedRealtimeNanos() - playbackStartNs) / 1_000_000L
                        Log.i(TAG, "EOS reached (sessionGen=$sessionGen). Decoded frames: $decodedFrameCount, Presented frames: $frameCount, elapsedMs=$elapsedMs, lastPtsUs=${latestRenderedPtsUs.get()}")
                        listener.onEndOfStream(sessionGen, frameCount, latestRenderedPtsUs.get())
                        break
                    }

                    val framePtsUs = bufferInfo.presentationTimeUs
                    decodedFrameCount++
                    if (framePtsUs < nextSamplePtsUs) {
                        codec.releaseOutputBuffer(outIndex, false)
                        continue
                    }
                    nextSamplePtsUs = framePtsUs + SAMPLE_INTERVAL_US
                    val framePtsMs = framePtsUs / 1000L

                    // Clear the old Flutter overlay BEFORE changing the displayed video frame.
                    frameGate.begin(framePtsMs, "clear")
                    listener.onFramePreparing(sessionGen, framePtsUs)
                    if (!frameGate.await(framePtsMs, "clear", FRAME_TIMEOUT_MS)) {
                        if (isRunning.get()) listener.onError(sessionGen, "Replay timed out waiting for Flutter to clear the previous pose.")
                        break
                    }
                    frameGate.begin(framePtsMs, "pose")

                    // Register frame PTS in session provenance table BEFORE releasing buffer to Surface
                    latestRenderedPtsUs.set(framePtsUs)
                    listener.onFrameRendered(sessionGen, framePtsUs)

                    // Default Surface timestamp is BufferInfo.presentationTimeUs, not a wall-clock deadline.
                    codec.releaseOutputBuffer(outIndex, true)
                    frameCount++
                    totalFramesRendered.set(frameCount)
                    if (!frameGate.await(framePtsMs, "pose", FRAME_TIMEOUT_MS)) {
                        if (isRunning.get()) listener.onError(sessionGen, "Replay timed out waiting for the matching pose to render.")
                        break
                    }
                    // Give the user time to see this exact pair. This is intentional slow replay.
                    Thread.sleep(POSE_DISPLAY_MS)
                }
            }
        } catch (_: InterruptedException) {
            // stop/restart interrupts bounded frame waits and releases the decoder below.
        } catch (e: Exception) {
            if (isRunning.get()) {
                Log.e(TAG, "Decoding error (sessionGen=$sessionGen): ${e.message}", e)
                listener.onError(sessionGen, "Decoder error: ${e.message}")
            }
        } finally {
            isRunning.set(false)
            try {
                codec?.stop()
                codec?.release()
            } catch (_: Exception) {}
            try {
                extractor?.release()
            } catch (_: Exception) {}
        }
    }
}
