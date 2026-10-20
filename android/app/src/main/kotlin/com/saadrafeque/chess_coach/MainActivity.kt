package com.saadrafeque.chess_coach

import android.app.PictureInPictureParams
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "enter") {
                    result.notImplemented()
                } else if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                    result.success(false)
                } else {
                    try {
                        val params = PictureInPictureParams.Builder()
                            .setAspectRatio(Rational(1, 1))
                            .build()
                        result.success(enterPictureInPictureMode(params))
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
            }
    }

    private companion object {
        const val PIP_CHANNEL = "com.saadrafeque.chess_coach/pip"
    }
}
