package com.example.health_ai_app.cv

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class WorkoutCvPlugin(private val activity: Activity) :
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    PoseLandmarkerHelper.LandmarkerListener {

    companion object {
        const val CAMERA_PERMISSION_CODE = 2001
        private const val METHOD_CHANNEL_NAME = "com.example.health_ai_app/workout_cv/method"
        private const val EVENT_CHANNEL_NAME = "com.example.health_ai_app/workout_cv/events"
        private const val VIEW_TYPE = "workout_camera_view"

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

    var isSessionActive: Boolean = false
        private set

    var poseHelper: PoseLandmarkerHelper? = null
        private set

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var activeCameraView: WorkoutCameraView? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var isDisposed: Boolean = false

    fun hasCameraPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            activity,
            Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun attachCameraView(view: WorkoutCameraView) {
        if (activeCameraView !== view) {
            activeCameraView?.stopCamera()
            activeCameraView = view
        }
    }

    fun detachCameraView(view: WorkoutCameraView) {
        if (activeCameraView === view) {
            activeCameraView = null
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (isDisposed) {
            result.success(false)
            return
        }
        when (call.method) {
            "checkPermission" -> {
                result.success(if (hasCameraPermission()) "granted" else "denied")
            }
            "requestPermission" -> {
                if (hasCameraPermission()) {
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
                if (!hasCameraPermission()) {
                    isSessionActive = false
                    result.success(false)
                    return
                }
                if (poseHelper == null) {
                    poseHelper = PoseLandmarkerHelper(activity.applicationContext, this)
                }
                if (poseHelper?.isInitialized != true) {
                    isSessionActive = false
                    poseHelper?.clearPoseLandmarker()
                    poseHelper = null
                    result.success(false)
                    return
                }
                isSessionActive = true
                activeCameraView?.ensureCameraStarted()
                result.success(true)
            }
            "stopSession" -> {
                stopActiveSession()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun stopActiveSession() {
        isSessionActive = false
        activeCameraView?.stopCamera()
        poseHelper?.clearPoseLandmarker()
        poseHelper = null
    }

    fun dispose() {
        if (isDisposed) return
        isDisposed = true
        pendingPermissionResult?.success(false)
        pendingPermissionResult = null
        stopActiveSession()
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
                    "errorMessage" to errorMessage
                )
            )
        }
    }

    override fun onError(error: String, errorCode: Int) {
        sendErrorEvent(error)
    }

    override fun onResults(resultBundle: PoseLandmarkerHelper.ResultBundle) {
        if (isDisposed || !isSessionActive) return

        val result = resultBundle.results.firstOrNull() ?: return
        val landmarks = result.landmarks()

        mainHandler.post {
            if (isDisposed || !isSessionActive) return@post
            val sink = eventSink ?: return@post

            if (landmarks.isEmpty()) {
                sink.success(
                    mapOf(
                        "status" to "lost",
                        "timestamp" to resultBundle.timestamp,
                        "latencyMs" to resultBundle.inferenceTime,
                        "numPoses" to 0,
                        "landmarks" to emptyList<Map<String, Any>>()
                    )
                )
                return@post
            }

            if (landmarks.size > 1) {
                // Quality gate: Multiple people in view
                sink.success(
                    mapOf(
                        "status" to "multiplePeople",
                        "timestamp" to resultBundle.timestamp,
                        "latencyMs" to resultBundle.inferenceTime,
                        "numPoses" to landmarks.size,
                        "landmarks" to emptyList<Map<String, Any>>()
                    )
                )
                return@post
            }

            val singlePose = landmarks[0]
            val landmarkList = singlePose.mapIndexed { index, lm ->
                val visibilityVal = if (lm.visibility().isPresent) lm.visibility().get() else 1.0f
                mapOf(
                    "index" to index,
                    "x" to lm.x(),
                    "y" to lm.y(),
                    "z" to lm.z(),
                    "visibility" to visibilityVal
                )
            }

            sink.success(
                mapOf(
                    "status" to "detecting",
                    "timestamp" to resultBundle.timestamp,
                    "latencyMs" to resultBundle.inferenceTime,
                    "numPoses" to 1,
                    "landmarks" to landmarkList
                )
            )
        }
    }
}
