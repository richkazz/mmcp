package com.example.mobile_mcp

import android.app.Activity
import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.view.MotionEvent
import android.view.View
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** MobileMcpPlugin */
class MobileMcpPlugin: FlutterPlugin, MethodCallHandler, ActivityAware {
  private lateinit var channel : MethodChannel
  private var context: Context? = null
  private var activity: Activity? = null
  private var wakeLock: PowerManager.WakeLock? = null

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "mobile_mcp/lifecycle")
    channel.setMethodCallHandler(this)
    context = flutterPluginBinding.applicationContext
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    when (call.method) {
        "acquireBackgroundLock" -> {
            acquireWakeLock()
            result.success(true)
        }
        "releaseBackgroundLock" -> {
            releaseWakeLock()
            result.success(true)
        }
        "getCallingPackage" -> {
            val callingPackage = activity?.callingPackage
            // Fallback for some scenarios if callingPackage is null
            val referrer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                activity?.referrer?.authority
            } else {
                null
            }
            result.success(callingPackage ?: referrer)
        }
        "isWindowObscured" -> {
            // Android 12+ (API 31) introduced a way to prevent non-system overlays
            // We can also check if the current window is potentially obscured.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                activity?.window?.setHideOverlayWindows(true)
            }

            // Check if the current activity has focus. Overlay attacks often steal focus.
            val hasFocus = activity?.hasWindowFocus() ?: true
            result.success(!hasFocus)
        }
        else -> {
            result.notImplemented()
        }
    }
  }

  private fun acquireWakeLock() {
    if (wakeLock == null) {
        val powerManager = context?.getSystemService(Context.POWER_SERVICE) as PowerManager?
        wakeLock = powerManager?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MobileMcp:BackgroundLock")
    }
    wakeLock?.acquire(30 * 1000L /* 30 seconds */)
  }

  private fun releaseWakeLock() {
    if (wakeLock?.isHeld == true) {
        wakeLock?.release()
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    releaseWakeLock()
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivity() {
    activity = null
  }
}
