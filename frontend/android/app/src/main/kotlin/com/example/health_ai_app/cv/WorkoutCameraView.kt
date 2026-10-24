package com.example.health_ai_app.cv

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
) : PlatformView {

    private val container: FrameLayout = FrameLayout(context)
    private val previewView: PreviewView = PreviewView(context)
    private val cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var cameraProvider: ProcessCameraProvider? = null
    private var imageAnalysis: ImageAnalysis? = null
    private var isBound: Boolean = false
    private var isDisposed: Boolean = false

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

        cvPlugin.attachCameraView(this)
        if (cvPlugin.isSessionActive && cvPlugin.hasCameraPermission()) {
            ensureCameraStarted()
        }
    }

    override fun getView(): View = container

    fun ensureCameraStarted() {
        if (isDisposed || isBound) return
        val lifecycleOwner = activity as? LifecycleOwner ?: return
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)

        cameraProviderFuture.addListener({
            if (isDisposed || !cvPlugin.isSessionActive) return@addListener
            try {
                cameraProvider = cameraProviderFuture.get()
                bindCameraUseCases(lifecycleOwner)
            } catch (e: Exception) {
                cvPlugin.sendErrorEvent("Failed to initialize camera: ${e.message}")
            }
        }, ContextCompat.getMainExecutor(context))
    }

    private fun bindCameraUseCases(lifecycleOwner: LifecycleOwner) {
        if (isDisposed || isBound) return
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
            if (!isDisposed && cvPlugin.isSessionActive && helper != null) {
                helper.detectLiveStream(imageProxy, isFrontCamera = false)
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

    override fun dispose() {
        if (isDisposed) return
        isDisposed = true
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
