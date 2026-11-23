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
 * Real-time video replay decoder synchronized to presentationTimeUs.
 * Decoupled from MediaPipe inference so video renders smoothly at native FPS.
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

    fun acknowledgeFrame(generation: Long, ptsMs: Long, phase: String): Boolean =
        generation == sessionGen

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
                    if (totalFramesRendered.get() <= 3L) {
                        Log.i(TAG, "[CV_CODEC_RENDER] sessionGen=$sessionGen ptsUs=$ptsUs renderMonotonicNs=$renderNs")
                    }
                }, Handler(Looper.getMainLooper()))
                start()
            }

            val bufferInfo = MediaCodec.BufferInfo()
            var isEos = false
            val playbackStartNs = SystemClock.elapsedRealtimeNanos()
            var firstPtsUs = -1L
            var firstFrameWallClockNs = -1L
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

                // 2. Drain output buffer and render at real-time video PTS speed (30-60 FPS)
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

                    if (bufferInfo.size <= 0) {
                        codec.releaseOutputBuffer(outIndex, false)
                        continue
                    }

                    if (firstPtsUs < 0L) {
                        firstPtsUs = framePtsUs
                        firstFrameWallClockNs = SystemClock.elapsedRealtimeNanos()
                    } else {
                        val mediaElapsedNs = (framePtsUs - firstPtsUs).coerceAtLeast(0L) * 1_000L
                        val targetWallClockNs = firstFrameWallClockNs + mediaElapsedNs
                        val waitNs = targetWallClockNs - SystemClock.elapsedRealtimeNanos()
                        if (waitNs > 1_000_000L) {
                            Thread.sleep(waitNs / 1_000_000L, (waitNs % 1_000_000L).toInt())
                        }
                    }

                    // Register frame PTS in session provenance table BEFORE releasing buffer to Surface
                    latestRenderedPtsUs.set(framePtsUs)
                    listener.onFrameRendered(sessionGen, framePtsUs)

                    // Always release frame with render=true in real-time, decoupled from MediaPipe inference
                    codec.releaseOutputBuffer(outIndex, true)
                    frameCount++
                    totalFramesRendered.set(frameCount)
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
