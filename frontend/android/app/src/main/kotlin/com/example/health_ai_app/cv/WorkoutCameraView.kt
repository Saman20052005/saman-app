package com.example.health_ai_app.cv

import android.graphics.SurfaceTexture
import android.os.SystemClock
import android.util.Log
import android.view.Surface
import android.view.TextureView
import java.io.File
import android.app.Activity
import android.content.Context
import android.util.Size
import android.view.View
import android.widget.FrameLayout
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class WorkoutCameraView(
    private val context: Context,
    private val activity: Activity?,
    private val viewId: Int,
    private val creationParams: Map<String, Any>?,
    private val cvPlugin: WorkoutCvPlugin
) : PlatformView, WorkoutVideoDecoder.VideoDecoderListener {

    private val container: FrameLayout = FrameLayout(context)
    private val previewView: PreviewView = PreviewView(context)
    private val cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var cameraProvider: ProcessCameraProvider? = null
    private var imageAnalysis: ImageAnalysis? = null
    private var isBound: Boolean = false
    private var isDisposed: Boolean = false

    private val videoTextureView = TextureView(context)
    private var videoDecoder: WorkoutVideoDecoder? = null
    private var videoSurface: Surface? = null
    private var pendingVideoFile: File? = null
    private var pendingSessionGen: Long = 0L
    private var pendingSurfacePtsUs = -1L
    private var surfaceDrawDeadlineMs = 0L
    private val redrawPendingFrame = object : Runnable {
        override fun run() {
            if (isDisposed || videoDecoder == null || pendingSurfacePtsUs < 0L ||
                SystemClock.uptimeMillis() >= surfaceDrawDeadlineMs) return
            // A quiet TextureView inside a Flutter platform view needs explicit redraws
            // until its single queued buffer is latched. Stop as soon as PTS is observed.
            videoTextureView.invalidate()
            container.invalidate()
            videoTextureView.postOnAnimation(this)
        }
    }

    init {
        container.layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        )
        previewView.layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        )
        previewView.scaleType = PreviewView.ScaleType.FILL_CENTER
        container.addView(previewView)

        // 2. Video TextureView setup
        videoTextureView.layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        )
        videoTextureView.visibility = View.GONE
        container.addView(videoTextureView)

        videoTextureView.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(surfaceTexture: SurfaceTexture, width: Int, height: Int) {
                videoSurface = Surface(surfaceTexture)
                val file = pendingVideoFile
                if (file != null) {
                    startDecoderOnSurface(file, videoSurface!!, pendingSessionGen)
                }
            }

            override fun onSurfaceTextureSizeChanged(surfaceTexture: SurfaceTexture, width: Int, height: Int) {}

            override fun onSurfaceTextureDestroyed(surfaceTexture: SurfaceTexture): Boolean {
                stopVideoDecoder()
                videoSurface?.release()
                videoSurface = null
                return true
            }

            override fun onSurfaceTextureUpdated(surfaceTexture: SurfaceTexture) {
                if (surfaceTexture.timestamp / 1000L == pendingSurfacePtsUs) {
                    pendingSurfacePtsUs = -1L
                    videoTextureView.removeCallbacks(redrawPendingFrame)
                }
                cvPlugin.onTextureFrameUpdated(videoTextureView, surfaceTexture)
            }
        }

        cvPlugin.attachCameraView(this)
        if (cvPlugin.isSessionActive && cvPlugin.hasCameraPermission()) {
            ensureCameraStarted()
        }
    }

    override fun getView(): View = container

    fun switchToCamera() {
        pendingVideoFile = null
        stopVideoDecoder()
        activity?.runOnUiThread {
            videoTextureView.visibility = View.GONE
            previewView.visibility = View.VISIBLE
            ensureCameraStarted()
        }
    }

    fun switchToVideoReplay(videoFile: File, sessionGen: Long) {
        pendingVideoFile = videoFile
        pendingSessionGen = sessionGen
        stopCamera()
        activity?.runOnUiThread {
            previewView.visibility = View.GONE
            videoTextureView.visibility = View.VISIBLE
            val surface = videoSurface
            if (surface != null && surface.isValid) {
                startDecoderOnSurface(videoFile, surface, sessionGen)
            }
        }
    }

    private fun startDecoderOnSurface(file: File, surface: Surface, sessionGen: Long) {
        stopVideoDecoder()
        Log.i("WorkoutCameraView", "Starting WorkoutVideoDecoder for ${file.name} (sessionGen=$sessionGen)")
        videoDecoder = WorkoutVideoDecoder(file, surface, sessionGen, this).apply {
            start()
        }
    }

    fun stopVideoDecoder() {
        pendingSurfacePtsUs = -1L
        videoTextureView.removeCallbacks(redrawPendingFrame)
        videoDecoder?.stop()
        videoDecoder = null
    }

    fun acknowledgeReplayFrame(sessionGen: Long, ptsMs: Long, phase: String): Boolean =
        videoDecoder?.acknowledgeFrame(sessionGen, ptsMs, phase) ?: false

    fun onReplayFrameCaptured(sessionGen: Long, ptsUs: Long) {
        if (sessionGen != cvPlugin.currentSessionGeneration || pendingSurfacePtsUs != ptsUs) return
        pendingSurfacePtsUs = -1L
        videoTextureView.removeCallbacks(redrawPendingFrame)
        container.invalidate()
    }

    fun ensureCameraStarted() {
        if (isDisposed || isBound || cvPlugin.currentSourceMode != "camera" || !cvPlugin.hasCameraPermission()) return
        val lifecycleOwner = activity as? LifecycleOwner ?: return
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)

        cameraProviderFuture.addListener({
            if (isDisposed || !cvPlugin.isSessionActive || cvPlugin.currentSourceMode != "camera") return@addListener
            try {
                cameraProvider = cameraProviderFuture.get()
                bindCameraUseCases(lifecycleOwner)
            } catch (e: Exception) {
                cvPlugin.sendErrorEvent("Failed to initialize camera: ${e.message}")
            }
        }, ContextCompat.getMainExecutor(context))
    }

    private fun bindCameraUseCases(lifecycleOwner: LifecycleOwner) {
        if (isDisposed || isBound || cvPlugin.currentSourceMode != "camera" || !cvPlugin.hasCameraPermission()) return
        val provider = cameraProvider ?: return

        val preview = Preview.Builder()
            .setTargetResolution(Size(720, 1280))
            .build()
            .also {
                it.setSurfaceProvider(previewView.surfaceProvider)
            }

        val analysis = ImageAnalysis.Builder()
            .setTargetResolution(Size(480, 640))
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
            .build()

        analysis.setAnalyzer(cameraExecutor) { imageProxy ->
            val helper = cvPlugin.poseHelper
            if (!isDisposed && cvPlugin.isSessionActive && cvPlugin.currentSourceMode == "camera" && helper != null) {
                helper.detectLiveStream(imageProxy, isFrontCamera = false, sessionGen = cvPlugin.currentSessionGeneration)
            } else {
                imageProxy.close()
            }
        }
        imageAnalysis = analysis

        val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA

        try {
            provider.unbindAll()
            provider.bindToLifecycle(
                lifecycleOwner,
                cameraSelector,
                preview,
                analysis
            )
            isBound = true
        } catch (e: Exception) {
            isBound = false
            cvPlugin.sendErrorEvent("Use case binding failed: ${e.message}")
        }
    }

    fun stopCamera() {
        imageAnalysis?.clearAnalyzer()
        imageAnalysis = null
        cameraProvider?.unbindAll()
        isBound = false
    }

    // VideoDecoderListener callbacks
    override fun onFramePreparing(sessionGen: Long, presentationTimeUs: Long) {
        cvPlugin.onVideoFramePreparing(sessionGen, presentationTimeUs)
    }

    override fun onVideoStarted(sessionGen: Long, durationUs: Long, width: Int, height: Int, fps: Double) {
        cvPlugin.onVideoStarted(sessionGen, durationUs, width, height, fps)
    }

    override fun onFrameRendered(sessionGen: Long, presentationTimeUs: Long) {
        cvPlugin.onVideoFrameRendered(sessionGen, presentationTimeUs)
        videoTextureView.post {
            if (isDisposed || sessionGen != cvPlugin.currentSessionGeneration || videoDecoder == null) return@post
            pendingSurfacePtsUs = presentationTimeUs
            surfaceDrawDeadlineMs = SystemClock.uptimeMillis() + 5_000L
            videoTextureView.postOnAnimation(redrawPendingFrame)
        }
    }

    override fun onEndOfStream(sessionGen: Long, totalFramesRendered: Long, lastPtsUs: Long) {
        cvPlugin.onVideoEndOfStream(sessionGen, totalFramesRendered, lastPtsUs)
    }

    override fun onError(sessionGen: Long, error: String) {
        cvPlugin.onVideoDecoderError(sessionGen, error)
    }

    override fun dispose() {
        if (isDisposed) return
        isDisposed = true
        pendingVideoFile = null
        stopVideoDecoder()
        videoSurface?.release()
        videoSurface = null
        cvPlugin.detachCameraView(this)
        stopCamera()
        cameraProvider = null
        if (!cameraExecutor.isShutdown) {
            cameraExecutor.shutdown()
        }
    }
}

class WorkoutCameraViewFactory(
    private val activity: Activity?,
    private val cvPlugin: WorkoutCvPlugin
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any>
        return WorkoutCameraView(context, activity, viewId, params, cvPlugin)
    }
}
