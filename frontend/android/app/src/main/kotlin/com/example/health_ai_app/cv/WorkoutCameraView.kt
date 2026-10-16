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
    private var cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var cameraProvider: ProcessCameraProvider? = null

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

        startCamera()
    }

    override fun getView(): View = container

    private fun startCamera() {
        val lifecycleOwner = activity as? LifecycleOwner ?: return
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)

        cameraProviderFuture.addListener({
            try {
                cameraProvider = cameraProviderFuture.get()
                bindCameraUseCases(lifecycleOwner)
            } catch (e: Exception) {
                cvPlugin.sendErrorEvent("Failed to initialize camera: ${e.message}")
            }
        }, ContextCompat.getMainExecutor(context))
    }

    private fun bindCameraUseCases(lifecycleOwner: LifecycleOwner) {
        val provider = cameraProvider ?: return

        val preview = Preview.Builder()
            .setTargetResolution(Size(720, 1280))
            .build()
            .also {
                it.setSurfaceProvider(previewView.surfaceProvider)
            }

        val imageAnalysis = ImageAnalysis.Builder()
            .setTargetResolution(Size(480, 640))
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
            .build()

        imageAnalysis.setAnalyzer(cameraExecutor) { imageProxy ->
            if (cvPlugin.isSessionActive) {
                cvPlugin.poseHelper?.detectLiveStream(imageProxy, isFrontCamera = false)
            } else {
                imageProxy.close()
            }
        }

        val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA

        try {
            provider.unbindAll()
            provider.bindToLifecycle(
                lifecycleOwner,
                cameraSelector,
                preview,
                imageAnalysis
            )
        } catch (e: Exception) {
            cvPlugin.sendErrorEvent("Use case binding failed: ${e.message}")
        }
    }

    override fun dispose() {
        try {
            cameraProvider?.unbindAll()
            cameraExecutor.shutdown()
        } catch (_: Exception) {}
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
