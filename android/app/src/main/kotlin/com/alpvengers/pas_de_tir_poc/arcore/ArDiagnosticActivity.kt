package com.alpvengers.pas_de_tir_poc.arcore

import android.app.Activity
import android.os.Bundle

/** Diagnostic : la même vue ARCore, sans Flutter (lancée via adb uniquement). */
class ArDiagnosticActivity : Activity() {
    private var arView: ArCoreView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        arView = ArCoreView(this).also { setContentView(it.view) }
    }

    override fun onResume() {
        super.onResume()
        arView?.resume()
    }

    override fun onPause() {
        arView?.pause()
        super.onPause()
    }

    override fun onDestroy() {
        arView?.dispose()
        super.onDestroy()
    }
}
