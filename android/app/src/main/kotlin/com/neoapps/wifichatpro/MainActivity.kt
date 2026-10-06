package com.neoapps.wifichatpro

import android.app.StatusBarManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.StrictMode
import android.service.quicksettings.Tile
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var closeReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestQuickSettingsTile" -> requestQuickSettingsTile(result)
                "openPath" -> openPath(call.argument<String>("path"), result)
                else -> result.notImplemented()
            }
        }
    }

    override fun onStart() {
        super.onStart()
        setTileActive(this, true)
        registerCloseReceiver()
    }

    override fun onDestroy() {
        unregisterCloseReceiver()
        if (isFinishing) {
            setTileActive(this, false)
        }
        super.onDestroy()
    }

    private fun requestQuickSettingsTile(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(false)
            return
        }

        val statusBarManager = getSystemService(StatusBarManager::class.java)
        if (statusBarManager == null) {
            result.success(false)
            return
        }

        val componentName = ComponentName(this, WifiChatProTileService::class.java)
        statusBarManager.requestAddTileService(
            componentName,
            "Wifi Chat Pro",
            Icon.createWithResource(this, R.mipmap.ic_launcher),
            mainExecutor,
        ) { response ->
            result.success(
                response == StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ADDED ||
                    response == StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ALREADY_ADDED
            )
        }
    }

    private fun openPath(path: String?, result: MethodChannel.Result) {
        val file = path?.let { File(it) }
        if (file == null || !file.exists()) {
            result.success(false)
            return
        }
        try {
            @Suppress("DiscouragedPrivateApi")
            StrictMode::class.java
                .getMethod("disableDeathOnFileUriExposure")
                .invoke(null)
        } catch (_: Exception) {
        }

        val uri = Uri.fromFile(file)
        val mimeType = if (file.isDirectory) {
            "resource/folder"
        } else {
            val extension = file.extension.lowercase()
            MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: "*/*"
        }
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            startActivity(Intent.createChooser(intent, "Open with"))
            result.success(true)
        } catch (_: Exception) {
            result.success(false)
        }
    }

    private fun registerCloseReceiver() {
        if (closeReceiver != null) {
            return
        }
        closeReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action == ACTION_CLOSE_APP) {
                    setTileActive(context, false)
                    finishAndRemoveTask()
                }
            }
        }
        val filter = IntentFilter(ACTION_CLOSE_APP)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(closeReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(closeReceiver, filter)
        }
    }

    private fun unregisterCloseReceiver() {
        val receiver = closeReceiver ?: return
        unregisterReceiver(receiver)
        closeReceiver = null
    }

    companion object {
        const val CHANNEL = "wifi_chat_pro/android"
        const val ACTION_CLOSE_APP = "com.neoapps.wifichatpro.CLOSE_APP"
        private const val PREFS = "wifi_chat_pro_quick_settings"
        private const val KEY_TILE_ACTIVE = "tile_active"

        fun isTileActive(context: Context): Boolean {
            return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getBoolean(KEY_TILE_ACTIVE, false)
        }

        fun setTileActive(context: Context, active: Boolean) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_TILE_ACTIVE, active)
                .apply()
            WifiChatProTileService.requestTileStateUpdate(context)
        }
    }
}
