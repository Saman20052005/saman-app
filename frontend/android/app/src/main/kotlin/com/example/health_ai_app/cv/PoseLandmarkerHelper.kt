package com.example.health_ai_app.cv

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.os.SystemClock
import androidx.camera.core.ImageProxy
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult

class PoseLandmarkerHelper(
    private val context: Context,
    private val poseLandmarkerListener: LandmarkerListener
) {
    interface LandmarkerListener {
        fun onError(error: String, errorCode: Int = 0)
        fun onResults(resultBundle: ResultBundle)
    }

    data class ResultBundle(
        val results: List<PoseLandmarkerResult>,
        val inferenceTime: Long,
        val inputImageHeight: Int,
        val inputImageWidth: Int,
        val timestamp: Long
    )

    private var poseLandmarker: PoseLandmarker? = null
    private var lastTimestampMs = Long.MIN_VALUE

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
                    val finishTimeMs = SystemClock.uptimeMillis()
                    val inferenceTime = finishTimeMs - result.timestampMs()
                    poseLandmarkerListener.onResults(
                        ResultBundle(
                            results = listOf(result),
                            inferenceTime = inferenceTime,
                            inputImageHeight = input.height,
                            inputImageWidth = input.width,
                            timestamp = result.timestampMs()
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

    fun detectLiveStream(imageProxy: ImageProxy, isFrontCamera: Boolean) {
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
            val bitmap = imageProxy.toBitmap()
            val rotationDegrees = imageProxy.imageInfo.rotationDegrees

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
            landmarker.detectAsync(mpImage, frameTime)
        } catch (e: Exception) {
            poseLandmarkerListener.onError("Inference error: ${e.message}")
        } finally {
            imageProxy.close()
        }
    }

    fun clearPoseLandmarker() {
        val landmarker = poseLandmarker ?: return
        poseLandmarker = null
        landmarker.close()
    }
}
