package org.otzaria.otzaria

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CopyOnWriteArrayList

object PdfExportProbeState {
    @Volatile var ready = false
    @Volatile var picker = "scripted"
    @Volatile var tree: Uri? = null
    @Volatile var control: MethodChannel? = null
    @Volatile var engineId = 0L
    @Volatile var engineDestroyObserved = false
    val requests = CopyOnWriteArrayList<Int>()
}

// מחלקה זו נארזת רק ב־APK הייעודי, ויורשת את רישום הערוץ ואת מחזור החיים של האפליקציה.
class PdfExportProbeActivity : MainActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PdfExportProbeState.engineId = flutterEngine.engineId
        PdfExportProbeState.engineDestroyObserved = false
        flutterEngine.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
            override fun onPreEngineRestart() {}
            override fun onEngineWillDestroy() { PdfExportProbeState.engineDestroyObserved = true }
        })
        PdfExportProbeState.control = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "otzaria/pdf_export_probe").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "ready") {
                    PdfExportProbeState.ready = true
                    result.success(null)
                } else result.notImplemented()
            }
        }
    }

    override fun startActivityForResult(intent: Intent, requestCode: Int) {
        if (intent.action != Intent.ACTION_OPEN_DOCUMENT_TREE) {
            super.startActivityForResult(intent, requestCode)
            return
        }
        PdfExportProbeState.requests.add(requestCode)
        when (PdfExportProbeState.picker) {
            "real" -> super.startActivityForResult(intent, requestCode)
            "held" -> Unit
            "scripted" -> Handler(Looper.getMainLooper()).post {
                onActivityResult(requestCode, Activity.RESULT_OK, Intent().setData(requireNotNull(PdfExportProbeState.tree)))
            }
            else -> error("Unknown picker mode")
        }
    }

    fun deliverPickerResult(code: Int, result: Int, tree: Uri?) {
        onActivityResult(code, result, tree?.let { Intent().setData(it) })
    }

}
