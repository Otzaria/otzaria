package org.otzaria.otzaria

import android.content.Intent
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.security.cert.X509Certificate
import android.util.Base64

class MainActivity : FlutterActivity() {
    private var externalActivationChannel: MethodChannel? = null
    private var userCertificatesChannel: MethodChannel? = null
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

        // dart:io סומך רק על תעודות המערכת; תעודת סינון שהמשתמש התקין (נטפרי
        // וכדומה) חיה במאגר המשתמש ומועברת ל-Dart כ-PEM (issue #1305).
        userCertificatesChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            USER_CERTIFICATES_CHANNEL,
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    GET_USER_CERTIFICATES_METHOD -> Thread {
                        // קריאת מאגר התעודות היא I/O — לא על ה-thread הראשי.
                        val pems = userInstalledCertificatesPem()
                        runOnUiThread { result.success(pems) }
                    }.start()
                    else -> result.notImplemented()
                }
            }
        }

        enqueueIntentUriIfNeeded(intent)
    }

    private fun userInstalledCertificatesPem(): List<String> {
        val pems = mutableListOf<String>()
        try {
            val store = KeyStore.getInstance("AndroidCAStore").apply { load(null, null) }
            for (alias in store.aliases()) {
                if (!alias.startsWith("user:")) continue
                val cert = store.getCertificate(alias) as? X509Certificate ?: continue
                val body = Base64.encodeToString(cert.encoded, Base64.NO_WRAP)
                    .chunked(64).joinToString("\n")
                pems.add("-----BEGIN CERTIFICATE-----\n$body\n-----END CERTIFICATE-----\n")
            }
        } catch (_: Exception) {
            // בלי מאגר תעודות נגיש ממשיכים עם תעודות המערכת בלבד.
        }
        return pems
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
        userCertificatesChannel?.setMethodCallHandler(null)
        userCertificatesChannel = null
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
        private const val USER_CERTIFICATES_CHANNEL = "otzaria/user_certificates"
        private const val GET_USER_CERTIFICATES_METHOD = "getUserInstalledCertificates"
    }
}
