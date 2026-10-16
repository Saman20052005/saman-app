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

            val eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL_NAME)
            eventChannel.setStreamHandler(plugin)

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

    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPermissionResult: MethodChannel.Result? = null

    init {
        poseHelper = PoseLandmarkerHelper(activity.applicationContext, this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
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
                    pendingPermissionResult = result
                    ActivityCompat.requestPermissions(
                        activity,
                        arrayOf(Manifest.permission.CAMERA),
                        CAMERA_PERMISSION_CODE
                    )
                }
            }
            "startSession" -> {
                isSessionActive = true
                if (poseHelper == null) {
                    poseHelper = PoseLandmarkerHelper(activity.applicationContext, this)
                }
                result.success(true)
            }
            "stopSession" -> {
                isSessionActive = false
                poseHelper?.clearPoseLandmarker()
                poseHelper = null
                result.success(true)
            }
            else -> result.notImplemented()
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
        mainHandler.post {
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
        if (!isSessionActive) return

        val result = resultBundle.results.firstOrNull() ?: return
        val landmarks = result.landmarks()

        mainHandler.post {
            if (!isSessionActive) return@post
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
