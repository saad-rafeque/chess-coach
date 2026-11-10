package com.saadrafeque.chess_coach

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Rect
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pipChannel: MethodChannel? = null
    private var hintAvailable = false
    private var undoAvailable = false
    private var playHintAvailable = false
    private var receiverRegistered = false
    private val hintReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || !isInPictureInPictureMode) return
            when (intent?.action) {
                HINT_ACTION -> if (hintAvailable) pipChannel?.invokeMethod("hint", null)
                UNDO_ACTION -> if (undoAvailable) pipChannel?.invokeMethod("undo", null)
                PLAY_HINT_ACTION -> if (playHintAvailable) pipChannel?.invokeMethod("playHint", null)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!receiverRegistered) {
            val actions = IntentFilter(HINT_ACTION).apply {
                addAction(UNDO_ACTION)
                addAction(PLAY_HINT_ACTION)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(hintReceiver, actions, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(hintReceiver, actions)
            }
            receiverRegistered = true
        }
        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL)
        pipChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "hintAvailable" -> {
                    hintAvailable = call.arguments == true
                    updateActions()
                    result.success(null)
                }
                "actionsAvailable" -> {
                    hintAvailable = call.argument<Boolean>("hint") == true
                    undoAvailable = call.argument<Boolean>("undo") == true
                    playHintAvailable = call.argument<Boolean>("playHint") == true
                    updateActions()
                    result.success(null)
                }
                "enter" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                        !packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) {
                        result.success(false)
                    } else {
                        try { result.success(enterPictureInPictureMode(pipParams())) }
                        catch (_: Exception) { result.success(false) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun updateActions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && isInPictureInPictureMode) {
            // The window can close between the state check and this call.
            try { setPictureInPictureParams(pipParams()) } catch (_: IllegalStateException) {}
        }
    }

    private fun action(name: String, request: Int, icon: Int, title: String,
                       description: String, available: Boolean): RemoteAction {
        val intent = Intent(name).setPackage(packageName)
        val pending = PendingIntent.getBroadcast(this, request, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return RemoteAction(Icon.createWithResource(this, icon), title, description, pending)
            .apply { isEnabled = available }
    }

    private fun pipParams(): PictureInPictureParams {
        val bounds = Rect()
        window.decorView.getGlobalVisibleRect(bounds)
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
            .setSourceRectHint(bounds)
            .setActions(listOf(
                action(UNDO_ACTION, 2, android.R.drawable.ic_media_rew, "Undo", "Take back the last turn", undoAvailable),
                action(HINT_ACTION, 1, android.R.drawable.ic_menu_help, "Hint", "Ask the coach for a hint", hintAvailable),
                action(PLAY_HINT_ACTION, 3, android.R.drawable.ic_media_play, "Play hint", "Play the revealed coach move", playHintAvailable)
            ))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) builder.setSeamlessResizeEnabled(false)
        return builder.build()
    }

    override fun onDestroy() {
        if (receiverRegistered) unregisterReceiver(hintReceiver)
        pipChannel?.setMethodCallHandler(null)
        pipChannel = null
        super.onDestroy()
    }

    override fun onPictureInPictureModeChanged(inPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(inPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("modeChanged", inPictureInPictureMode)
    }

    private companion object {
        const val PIP_CHANNEL = "com.saadrafeque.chess_coach/pip"
        const val HINT_ACTION = "com.saadrafeque.chess_coach.PIP_HINT"
        const val UNDO_ACTION = "com.saadrafeque.chess_coach.PIP_UNDO"
        const val PLAY_HINT_ACTION = "com.saadrafeque.chess_coach.PIP_PLAY_HINT"
    }
}
