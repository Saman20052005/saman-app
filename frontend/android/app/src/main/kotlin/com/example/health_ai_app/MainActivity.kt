package com.example.health_ai_app

import com.example.health_ai_app.cv.WorkoutCvPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var cvPlugin: WorkoutCvPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        cvPlugin?.dispose()
        cvPlugin = WorkoutCvPlugin.registerWith(this, flutterEngine)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        cvPlugin?.dispose()
        cvPlugin = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        cvPlugin?.dispose()
        cvPlugin = null
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        cvPlugin?.handleRequestPermissionsResult(requestCode, permissions, grantResults)
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}
