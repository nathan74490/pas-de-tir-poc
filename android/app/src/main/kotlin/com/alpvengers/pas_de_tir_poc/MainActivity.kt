package com.alpvengers.pas_de_tir_poc

import android.content.pm.PackageManager
import com.alpvengers.pas_de_tir_poc.arcore.ArCoreBridge
import com.alpvengers.pas_de_tir_poc.gyro.GyroBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ArCoreBridge.register(this, flutterEngine)
        GyroBridge.register(this, flutterEngine)
    }

    override fun onResume() {
        super.onResume()
        ArCoreBridge.activeView?.resume()
    }

    override fun onPause() {
        ArCoreBridge.activeView?.pause()
        super.onPause()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == ArCoreBridge.CAMERA_REQUEST) {
            ArCoreBridge.onPermissionResult(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        }
    }
}
