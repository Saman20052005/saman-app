package com.example.health_ai_app.cv

import android.content.Context
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.os.SystemClock
import android.util.Log
import java.io.File
import java.nio.ByteBuffer
import kotlin.math.min
import kotlin.math.roundToInt

class VideoCompressionException(
    val code: String,
    override val message: String,
    cause: Throwable? = null
) : Exception(message, cause)

data class CompressedVideoResult(
    val outputPath: String,
    val sizeBytes: Long,
    val durationSec: Double,
    val width: Int,
    val height: Int,
    val rotationDegrees: Int,
    val usedFastPath: Boolean
) {
    fun toMap(): Map<String, Any> = mapOf(
        "outputPath" to outputPath,
        "sizeBytes" to sizeBytes,
        "durationSec" to durationSec,
        "width" to width,
        "height" to height,
        "rotationDegrees" to rotationDegrees,
        "usedFastPath" to usedFastPath
    )
}

/**
 * Hardware-accelerated video compressor optimized for MediaTek MT6765G (720p/30fps).
 * Prioritizes a zero-transcode fast-path when the input MP4/MOV is already <= 15 MB.
 */
class WorkoutVideoCompressor(private val context: Context) {

    companion object {
        private const val TAG = "WorkoutVideoCompressor"
        const val MAX_FAST_PATH_BYTES = 15L * 1024L * 1024L
        const val TARGET_MAX_SHORT_SIDE = 720
        const val TARGET_FPS = 30
        const val TARGET_BITRATE_BPS = 2_500_000
        const val MIN_BITRATE_BPS = 450_000
        const val DEFAULT_TIMEOUT_MS = 45_000L
        private const val CODEC_TIMEOUT_US = 10_000L
        private const val MIME_AVC = MediaFormat.MIMETYPE_VIDEO_AVC
        private const val I_FRAME_INTERVAL_SEC = 2

        fun computeTargetDimensions(
            sourceWidth: Int,
            sourceHeight: Int,
            maxShortSide: Int = TARGET_MAX_SHORT_SIDE
        ): Pair<Int, Int> {
            val safeW = sourceWidth.coerceAtLeast(16)
            val safeH = sourceHeight.coerceAtLeast(16)
            val shortSide = min(safeW, safeH)
            val scale = if (shortSide > maxShortSide) {
                maxShortSide.toDouble() / shortSide.toDouble()
            } else {
                1.0
            }
            val scaledW = (safeW * scale).roundToInt()
            val scaledH = (safeH * scale).roundToInt()
            // Align down to multiples of 16 for MediaTek OMX / c2.mtk hardware encoder safety
            val alignedW = ((scaledW / 16) * 16).coerceAtLeast(16)
            val alignedH = ((scaledH / 16) * 16).coerceAtLeast(16)
            return Pair(alignedW, alignedH)
        }
    }

    fun compress(
        inputPath: String,
        maxBytes: Long = MAX_FAST_PATH_BYTES,
        timeoutMs: Long = DEFAULT_TIMEOUT_MS
    ): CompressedVideoResult {
        val effectiveMaxBytes = if (maxBytes > 0L) maxBytes else MAX_FAST_PATH_BYTES
        val effectiveTimeoutMs = if (timeoutMs > 0L) timeoutMs else DEFAULT_TIMEOUT_MS

        val inputFile = File(inputPath)
        if (!inputFile.exists() || !inputFile.isFile || !inputFile.canRead()) {
            throw VideoCompressionException(
                "COMPRESSION_FAILED",
                "Input video file does not exist or cannot be read: $inputPath"
            )
        }
        val inputSizeBytes = inputFile.length()
        if (inputSizeBytes <= 0L) {
            throw VideoCompressionException(
                "COMPRESSION_FAILED",
                "Input video file is empty: $inputPath"
            )
        }

        val lowerName = inputFile.name.lowercase()
        val isSupportedExtension = lowerName.endsWith(".mp4") ||
            lowerName.endsWith(".mov") ||
            lowerName.endsWith(".m4v")

        // Step 1: Inspect metadata via MediaMetadataRetriever
        var width = 0
        var height = 0
        var rotationDegrees = 0
        var durationMs = 0L
        var hasVideoMetadata = false

        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(inputFile.absolutePath)
            width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull() ?: 0
            height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull() ?: 0
            rotationDegrees = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
            durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L
            val hasVideoStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO)
            hasVideoMetadata = (width > 0 && height > 0) || hasVideoStr == "yes"
        } catch (e: Exception) {
            throw VideoCompressionException(
                "COMPRESSION_FAILED",
                "Invalid or corrupted video file: ${e.message}",
                e
            )
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {}
        }

        if (!isSupportedExtension && !hasVideoMetadata) {
            throw VideoCompressionException(
                "COMPRESSION_FAILED",
                "Unsupported video container format for: ${inputFile.name}"
            )
        }

        val durationSec = (durationMs.coerceAtLeast(0L).toDouble() / 1000.0)

        // Step 2: Fast-path if already <= maxBytes (default 15 MB)
        if (inputSizeBytes <= effectiveMaxBytes) {
            Log.i(
                TAG,
                "[FAST_PATH] Video <= ${effectiveMaxBytes / (1024 * 1024)}MB ($inputSizeBytes bytes), skipping transcode."
            )
            return CompressedVideoResult(
                outputPath = inputFile.absolutePath,
                sizeBytes = inputSizeBytes,
                durationSec = durationSec,
                width = if (width > 0) width else 720,
                height = if (height > 0) height else 1280,
                rotationDegrees = rotationDegrees,
                usedFastPath = true
            )
        }

        // Step 3: Transcode for files > maxBytes
        return transcodeVideo(
            inputFile = inputFile,
            sourceWidth = if (width > 0) width else 1080,
            sourceHeight = if (height > 0) height else 1920,
            rotationDegrees = rotationDegrees,
            durationSec = durationSec,
            maxBytes = effectiveMaxBytes,
            timeoutMs = effectiveTimeoutMs
        )
    }

    private fun transcodeVideo(
        inputFile: File,
        sourceWidth: Int,
        sourceHeight: Int,
        rotationDegrees: Int,
        durationSec: Double,
        maxBytes: Long,
        timeoutMs: Long
    ): CompressedVideoResult {
        val deadlineMs = SystemClock.elapsedRealtime() + timeoutMs
        val outputDir = File(context.cacheDir, "video_stories").apply {
            if (!exists()) mkdirs()
        }
        val outputFile = File(outputDir, "story_${System.currentTimeMillis()}.mp4")

        val (targetWidth, targetHeight) = computeTargetDimensions(
            sourceWidth = sourceWidth,
            sourceHeight = sourceHeight,
            maxShortSide = TARGET_MAX_SHORT_SIDE
        )

        // Adaptive bitrate so output stays safely below maxBytes even for longer clips
        val safeDurationSec = if (durationSec > 1.0) durationSec else 15.0
        val maxAllowedBitrateBps = ((maxBytes * 8L * 88L) / (100L * safeDurationSec)).toInt()
        val adaptiveBitrateBps = min(TARGET_BITRATE_BPS, maxAllowedBitrateBps)
            .coerceIn(MIN_BITRATE_BPS, TARGET_BITRATE_BPS)

        var extractor: MediaExtractor? = null
        var decoder: MediaCodec? = null
        var encoder: MediaCodec? = null
        var muxer: MediaMuxer? = null
        var muxerStarted = false

        try {
            extractor = MediaExtractor().apply {
                setDataSource(inputFile.absolutePath)
            }

            var videoTrackIndex = -1
            var inputFormat: MediaFormat? = null
            var inputMime = ""

            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("video/")) {
                    videoTrackIndex = i
                    inputFormat = format
                    inputMime = mime
                    break
                }
            }

            if (videoTrackIndex < 0 || inputFormat == null) {
                throw VideoCompressionException(
                    "COMPRESSION_FAILED",
                    "No video track found in ${inputFile.name}"
                )
            }

            extractor.selectTrack(videoTrackIndex)

            val outputFormat = MediaFormat.createVideoFormat(MIME_AVC, targetWidth, targetHeight).apply {
                setInteger(
                    MediaFormat.KEY_COLOR_FORMAT,
                    MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible
                )
                setInteger(MediaFormat.KEY_BIT_RATE, adaptiveBitrateBps)
                setInteger(MediaFormat.KEY_FRAME_RATE, TARGET_FPS)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, I_FRAME_INTERVAL_SEC)
            }

            encoder = MediaCodec.createEncoderByType(MIME_AVC).apply {
                configure(outputFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                start()
            }

            inputFormat.setInteger(
                MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible
            )
            decoder = MediaCodec.createDecoderByType(inputMime).apply {
                configure(inputFormat, null, null, 0)
                start()
            }

            muxer = MediaMuxer(outputFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4).apply {
                val normalizedRotation = ((rotationDegrees % 360) + 360) % 360
                if (normalizedRotation == 0 || normalizedRotation == 90 ||
                    normalizedRotation == 180 || normalizedRotation == 270
                ) {
                    setOrientationHint(normalizedRotation)
                }
            }

            val decoderBufferInfo = MediaCodec.BufferInfo()
            val encoderBufferInfo = MediaCodec.BufferInfo()
            val minFrameIntervalUs = 1_000_000L / TARGET_FPS
            var lastEncodedPtsUs = -1L

            var extractorEos = false
            var decoderEos = false
            var encoderEos = false
            var muxerVideoTrackIndex = -1

            while (!encoderEos) {
                if (SystemClock.elapsedRealtime() > deadlineMs) {
                    throw VideoCompressionException(
                        "COMPRESSION_TIMEOUT",
                        "Video compression timed out after ${timeoutMs}ms on device"
                    )
                }

                // 1. Feed extractor samples into decoder
                if (!extractorEos) {
                    val inBufIndex = decoder.dequeueInputBuffer(CODEC_TIMEOUT_US)
                    if (inBufIndex >= 0) {
                        val inBuf = decoder.getInputBuffer(inBufIndex)
                        if (inBuf != null) {
                            val sampleSize = extractor.readSampleData(inBuf, 0)
                            if (sampleSize < 0) {
                                decoder.queueInputBuffer(
                                    inBufIndex,
                                    0,
                                    0,
                                    0L,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM
                                )
                                extractorEos = true
                            } else {
                                val sampleTimeUs = extractor.sampleTime.coerceAtLeast(0L)
                                decoder.queueInputBuffer(inBufIndex, 0, sampleSize, sampleTimeUs, 0)
                                extractor.advance()
                            }
                        }
                    }
                }

                // 2. Drain decoded frames and feed into encoder (capped at 30fps)
                if (!decoderEos) {
                    val outBufIndex = decoder.dequeueOutputBuffer(decoderBufferInfo, CODEC_TIMEOUT_US)
                    if (outBufIndex >= 0) {
                        val isDecEos = (decoderBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                        val ptsUs = decoderBufferInfo.presentationTimeUs.coerceAtLeast(0L)
                        val shouldKeepFrame = lastEncodedPtsUs < 0L ||
                            (ptsUs - lastEncodedPtsUs) >= (minFrameIntervalUs - 2_000L)

                        val decodedBuffer = if (decoderBufferInfo.size > 0 && shouldKeepFrame) {
                            decoder.getOutputBuffer(outBufIndex)
                        } else {
                            null
                        }

                        if (decodedBuffer != null) {
                            var encInIndex = encoder.dequeueInputBuffer(CODEC_TIMEOUT_US)
                            while (encInIndex < 0) {
                                if (SystemClock.elapsedRealtime() > deadlineMs) {
                                    decoder.releaseOutputBuffer(outBufIndex, false)
                                    throw VideoCompressionException(
                                        "COMPRESSION_TIMEOUT",
                                        "Video compression timed out waiting for encoder input buffer"
                                    )
                                }
                                muxerVideoTrackIndex = drainEncoderStep(
                                    encoder = encoder,
                                    muxer = muxer,
                                    bufferInfo = encoderBufferInfo,
                                    currentTrackIndex = muxerVideoTrackIndex,
                                    onMuxerStarted = { muxerStarted = true },
                                    onEncoderEos = { encoderEos = true }
                                )
                                encInIndex = encoder.dequeueInputBuffer(CODEC_TIMEOUT_US)
                            }

                            val encInBuf = encoder.getInputBuffer(encInIndex)
                            if (encInBuf != null) {
                                encInBuf.clear()
                                decodedBuffer.position(decoderBufferInfo.offset)
                                decodedBuffer.limit(decoderBufferInfo.offset + decoderBufferInfo.size)
                                val bytesToCopy = min(encInBuf.remaining(), decoderBufferInfo.size)
                                copyByteBufferSlice(decodedBuffer, encInBuf, bytesToCopy)
                                val flags = if (isDecEos) MediaCodec.BUFFER_FLAG_END_OF_STREAM else 0
                                encoder.queueInputBuffer(encInIndex, 0, bytesToCopy, ptsUs, flags)
                                lastEncodedPtsUs = ptsUs
                            }
                        } else if (isDecEos) {
                            var encInIndex = encoder.dequeueInputBuffer(CODEC_TIMEOUT_US)
                            while (encInIndex < 0) {
                                if (SystemClock.elapsedRealtime() > deadlineMs) {
                                    decoder.releaseOutputBuffer(outBufIndex, false)
                                    throw VideoCompressionException(
                                        "COMPRESSION_TIMEOUT",
                                        "Video compression timed out signaling EOS to encoder"
                                    )
                                }
                                muxerVideoTrackIndex = drainEncoderStep(
                                    encoder = encoder,
                                    muxer = muxer,
                                    bufferInfo = encoderBufferInfo,
                                    currentTrackIndex = muxerVideoTrackIndex,
                                    onMuxerStarted = { muxerStarted = true },
                                    onEncoderEos = { encoderEos = true }
                                )
                                encInIndex = encoder.dequeueInputBuffer(CODEC_TIMEOUT_US)
                            }
                            encoder.queueInputBuffer(
                                encInIndex,
                                0,
                                0,
                                ptsUs,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM
                            )
                        }

                        decoder.releaseOutputBuffer(outBufIndex, false)
                        if (isDecEos) {
                            decoderEos = true
                        }
                    }
                }

                // 3. Drain encoder output into MediaMuxer
                muxerVideoTrackIndex = drainEncoderStep(
                    encoder = encoder,
                    muxer = muxer,
                    bufferInfo = encoderBufferInfo,
                    currentTrackIndex = muxerVideoTrackIndex,
                    onMuxerStarted = { muxerStarted = true },
                    onEncoderEos = { encoderEos = true }
                )
            }

            if (muxerStarted) {
                muxer.stop()
                muxerStarted = false
            }

            val outputSizeBytes = outputFile.length()
            if (!outputFile.exists() || outputSizeBytes <= 0L) {
                throw VideoCompressionException(
                    "COMPRESSION_FAILED",
                    "Transcoded output file is empty"
                )
            }
            if (outputSizeBytes > maxBytes) {
                throw VideoCompressionException(
                    "FILE_TOO_LARGE_AFTER_COMPRESS",
                    "Compressed video size ($outputSizeBytes bytes) exceeds limit ($maxBytes bytes)"
                )
            }

            Log.i(
                TAG,
                "[TRANSCODE_OK] ${inputFile.length()} -> $outputSizeBytes bytes (${targetWidth}x${targetHeight} @ ${TARGET_FPS}fps, rot=$rotationDegrees)"
            )

            return CompressedVideoResult(
                outputPath = outputFile.absolutePath,
                sizeBytes = outputSizeBytes,
                durationSec = durationSec,
                width = targetWidth,
                height = targetHeight,
                rotationDegrees = rotationDegrees,
                usedFastPath = false
            )
        } catch (e: VideoCompressionException) {
            if (outputFile.exists()) {
                try {
                    outputFile.delete()
                } catch (_: Exception) {}
            }
            throw e
        } catch (e: Exception) {
            if (outputFile.exists()) {
                try {
                    outputFile.delete()
                } catch (_: Exception) {}
            }
            throw VideoCompressionException(
                "COMPRESSION_FAILED",
                "Video transcode failed: ${e.message ?: e.javaClass.simpleName}",
                e
            )
        } finally {
            try {
                decoder?.stop()
            } catch (_: Exception) {}
            try {
                decoder?.release()
            } catch (_: Exception) {}
            try {
                encoder?.stop()
            } catch (_: Exception) {}
            try {
                encoder?.release()
            } catch (_: Exception) {}
            try {
                if (muxerStarted) {
                    muxer?.stop()
                }
            } catch (_: Exception) {}
            try {
                muxer?.release()
            } catch (_: Exception) {}
            try {
                extractor?.release()
            } catch (_: Exception) {}
        }
    }

    private fun drainEncoderStep(
        encoder: MediaCodec,
        muxer: MediaMuxer,
        bufferInfo: MediaCodec.BufferInfo,
        currentTrackIndex: Int,
        onMuxerStarted: () -> Unit,
        onEncoderEos: () -> Unit
    ): Int {
        var trackIdx = currentTrackIndex
        val encOutIndex = encoder.dequeueOutputBuffer(bufferInfo, CODEC_TIMEOUT_US)
        if (encOutIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
            if (trackIdx < 0) {
                trackIdx = muxer.addTrack(encoder.outputFormat)
                muxer.start()
                onMuxerStarted()
            }
        } else if (encOutIndex >= 0) {
            val encodedData = encoder.getOutputBuffer(encOutIndex)
            if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) {
                bufferInfo.size = 0
            }
            if (bufferInfo.size > 0 && encodedData != null && trackIdx >= 0) {
                encodedData.position(bufferInfo.offset)
                encodedData.limit(bufferInfo.offset + bufferInfo.size)
                muxer.writeSampleData(trackIdx, encodedData, bufferInfo)
            }
            val isEos = (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
            encoder.releaseOutputBuffer(encOutIndex, false)
            if (isEos) {
                onEncoderEos()
            }
        }
        return trackIdx
    }

    private fun copyByteBufferSlice(src: ByteBuffer, dst: ByteBuffer, count: Int) {
        val oldLimit = src.limit()
        src.limit(src.position() + count)
        dst.put(src)
        src.limit(oldLimit)
    }
}
