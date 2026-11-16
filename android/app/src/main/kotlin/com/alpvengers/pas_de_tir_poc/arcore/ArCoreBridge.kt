package com.alpvengers.pas_de_tir_poc.arcore

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import com.google.ar.core.ArCoreApk
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/** Canaux Flutter ↔ ARCore : disponibilité, permission caméra, vue AR, frames. */
object ArCoreBridge {
    private const val METHODS = "alpvengers/arcore"
    private const val FRAMES = "alpvengers/arcore/frames"
    const val VIEW_TYPE = "alpvengers/arcore_view"
    const val CAMERA_REQUEST = 4242

    var activeView: ArCoreView? = null
    private var sink: EventChannel.EventSink? = null
    private var pendingPermission: MethodChannel.Result? = null

    fun register(activity: Activity, engine: FlutterEngine) {
        val messenger = engine.dartExecutor.binaryMessenger
        MethodChannel(messenger, METHODS).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkAvailability" -> {
                    val a = ArCoreApk.getInstance().checkAvailability(activity)
                    result.success(
                        when {
                            a.isTransient -> "checking"
                            a == ArCoreApk.Availability.SUPPORTED_INSTALLED -> "installed"
                            a.isSupported -> "supported_not_installed"
                            else -> "unsupported"
                        }
                    )
                }
                "ensureInstalled" -> try {
                    val status = ArCoreApk.getInstance().requestInstall(activity, true)
                    result.success(status == ArCoreApk.InstallStatus.INSTALLED)
                } catch (e: Exception) {
                    result.success(false)
                }
                "requestCameraPermission" -> {
                    if (activity.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                        result.success(true)
                    } else {
                        pendingPermission?.success(false)
                        pendingPermission = result
                        activity.requestPermissions(arrayOf(Manifest.permission.CAMERA), CAMERA_REQUEST)
                    }
                }
                "setMode" -> {
                    activeView?.setMode(call.argument<String>("mode") ?: ArCoreView.MODE_SCANNING)
                    result.success(null)
                }
                "setPlacementPoint" -> {
                    val x = call.argument<Double>("x") ?: -1.0
                    val y = call.argument<Double>("y") ?: -1.0
                    activeView?.setPlacementPoint(x.toFloat(), y.toFloat())
                    result.success(null)
                }
                "confirmPlacement" -> {
                    activeView?.confirmPlacement()
                    result.success(null)
                }
                "capture" -> activeView?.capture(result) ?: result.success(null)
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, FRAMES).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sink = events
            }

            override fun onCancel(arguments: Any?) {
                sink = null
            }
        })

        engine.platformViewsController.registry.registerViewFactory(
            VIEW_TYPE,
            object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
                override fun create(context: Context, viewId: Int, args: Any?): PlatformView = ArCoreView(activity)
            },
        )
    }

    fun emitFrame(data: Map<String, Any>) {
        sink?.success(data)
    }

    fun emitError(code: String) {
        sink?.error("arcore", code, null)
    }

    fun onPermissionResult(granted: Boolean) {
        pendingPermission?.success(granted)
        pendingPermission = null
    }
}
