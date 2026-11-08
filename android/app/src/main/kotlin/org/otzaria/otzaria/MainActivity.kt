package org.otzaria.otzaria

import android.content.Intent
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var externalActivationChannel: MethodChannel? = null
    private var folderImportChannel: FolderImportChannel? = null
    private var appExitInfoChannel: AppExitInfoChannel? = null
    private var foregroundWorkChannel: ForegroundWorkChannel? = null
    private var androidUpdateChannel: AndroidUpdateChannel? = null
    private var dartActivationListenerReady = false
    private val pendingActivationUris = mutableListOf<String>()

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        externalActivationChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EXTERNAL_ACTIVATION_CHANNEL,
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    GET_PENDING_URI_STRINGS_METHOD -> {
                        dartActivationListenerReady = true
                        val pendingUris = pendingActivationUris.toList()
                        pendingActivationUris.clear()
                        result.success(pendingUris)
                    }

                    else -> result.notImplemented()
                }
            }
        }

        folderImportChannel = FolderImportChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        appExitInfoChannel = AppExitInfoChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        foregroundWorkChannel = ForegroundWorkChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        androidUpdateChannel = AndroidUpdateChannel(this, flutterEngine.dartExecutor.binaryMessenger)

        enqueueIntentUriIfNeeded(intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (androidUpdateChannel?.onActivityResult(requestCode, resultCode, data) == true) return
        if (folderImportChannel?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onResume() {
        super.onResume()
        androidUpdateChannel?.onResume()
    }

    override fun onPause() {
        androidUpdateChannel?.onPause()
        super.onPause()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val activationUri = extractActivationUriString(intent) ?: return
        if (dartActivationListenerReady && externalActivationChannel != null) {
            externalActivationChannel?.invokeMethod(
                EXTERNAL_ACTIVATION_METHOD,
                activationUri,
            )
            return
        }

        pendingActivationUris.add(activationUri)
    }

    override fun cleanUpFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        externalActivationChannel?.setMethodCallHandler(null)
        externalActivationChannel = null
        folderImportChannel?.dispose()
        folderImportChannel = null
        appExitInfoChannel?.dispose()
        appExitInfoChannel = null
        foregroundWorkChannel?.dispose()
        foregroundWorkChannel = null
        androidUpdateChannel?.dispose()
        androidUpdateChannel = null
        dartActivationListenerReady = false
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun enqueueIntentUriIfNeeded(intent: Intent?) {
        val activationUri = extractActivationUriString(intent) ?: return
        if (!pendingActivationUris.contains(activationUri)) {
            pendingActivationUris.add(activationUri)
        }
    }

    private fun extractActivationUriString(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_VIEW) {
            return null
        }

        val data = intent.data ?: return null
        if (data.scheme?.lowercase() != OTZARIA_SCHEME) {
            return null
        }

        return data.toString()
    }

    companion object {
        private const val EXTERNAL_ACTIVATION_CHANNEL = "otzaria/external_activation"
        private const val GET_PENDING_URI_STRINGS_METHOD = "getPendingUriStrings"
        private const val EXTERNAL_ACTIVATION_METHOD = "externalActivation"
        private const val OTZARIA_SCHEME = "otzaria"
    }
}
