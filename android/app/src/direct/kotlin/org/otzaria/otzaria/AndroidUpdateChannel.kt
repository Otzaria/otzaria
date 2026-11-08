package org.otzaria.otzaria

import android.app.Activity
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.lang.ref.WeakReference
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.zip.ZipFile

internal class AndroidUpdateChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "otzaria/android_software_update")
    private val executor = Executors.newSingleThreadExecutor()
    private val preferences by lazy { AndroidUpdateInstallState.preferences(activity) }
    private var permissionResult: MethodChannel.Result? = null
    private var permissionReturned = false
    private var resumed = false
    private var disposed = false
    private var working = false

    init {
        channel.setMethodCallHandler(this)
        AndroidUpdateInstallState.channel = WeakReference(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "environment" -> result.success(AndroidUpdateIdentity.environment(activity, "direct"))
            "status", "resume" -> {
                showConfirmation()
                result.success(status())
            }
            "canInstall" -> result.success(canInstall())
            "requestInstallPermission" -> requestPermission(result)
            "inspectApk" -> runWorker(result) { inspect(call).second }
            "installApk" -> {
                if (!resumed) {
                    result.error("ACTIVITY_NOT_RESUMED", "ACTIVITY_NOT_RESUMED", null)
                } else if (!canInstall()) {
                    result.error("INSTALL_PERMISSION_REQUIRED", "INSTALL_PERMISSION_REQUIRED", null)
                } else {
                    runWorker(result) { install(call) }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun runWorker(result: MethodChannel.Result, action: () -> Any?) {
        if (working) {
            result.error("UPDATE_BUSY", "UPDATE_BUSY", null)
            return
        }
        working = true
        executor.execute {
            try {
                val value = action()
                activity.runOnUiThread {
                    working = false
                    if (!disposed) result.success(value)
                }
            } catch (error: Exception) {
                val code = when (error) {
                    is ApkUpdateException -> error.code
                    is IOException -> "STORAGE_ERROR"
                    else -> "INSTALL_FAILED"
                }
                activity.runOnUiThread {
                    working = false
                    if (!disposed) result.error(code, code, null)
                }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun inspect(call: MethodCall): Pair<File, Map<String, Any?>> {
        val path = call.argument<String>("path") ?: throw ApkUpdateException("INVALID_APK")
        val file = File(path).canonicalFile
        val directory = File(activity.cacheDir, "android-software-update").canonicalFile
        if (file.parentFile != directory || file.name != "update.apk" || !file.isFile) {
            throw ApkUpdateException("INVALID_APK")
        }
        val size = (call.argument<Number>("size"))?.toLong()
        if (size == null || size <= 0 || size > 512L * 1024 * 1024 || file.length() != size) {
            throw ApkUpdateException("SIZE_MISMATCH")
        }
        val expectedHash = call.argument<String>("sha256")
        if (expectedHash == null || !Regex("[0-9a-f]{64}").matches(expectedHash)) {
            throw ApkUpdateException("HASH_MISMATCH")
        }
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                if (Thread.currentThread().isInterrupted) throw IOException("Interrupted")
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        if (hex(digest.digest()) != expectedHash) throw ApkUpdateException("HASH_MISMATCH")
        val flags = if (Build.VERSION.SDK_INT >= 28) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }
        val manager = activity.packageManager
        val candidate = manager.getPackageArchiveInfo(file.path, flags)
            ?: throw ApkUpdateException("INVALID_APK")
        val installed = manager.getPackageInfo(activity.packageName, flags)
        val currentSigners = signers(installed)
        val newSigners = signers(candidate)
        val history = if (Build.VERSION.SDK_INT >= 28 && candidate.signingInfo?.hasMultipleSigners() == false) {
            candidate.signingInfo?.signingCertificateHistory?.map { certificateHash(it.toByteArray()) }?.toSet()
                ?: newSigners
        } else newSigners
        val minSdk = if (Build.VERSION.SDK_INT >= 24) candidate.applicationInfo?.minSdkVersion ?: 1 else 1
        val versionCode = AndroidUpdateIdentity.versionCode(candidate)
        ApkUpdatePolicy.validate(
            activity.packageName, candidate.packageName,
            AndroidUpdateIdentity.versionCode(installed), versionCode,
            currentSigners, newSigners, history, Build.VERSION.SDK_INT, minSdk,
        )
        val expectedVersion = call.argument<Number>("versionCode")?.toLong()
        if (expectedVersion != null && expectedVersion != versionCode) {
            throw ApkUpdateException("METADATA_MISMATCH")
        }
        val expectedPackage = call.argument<String>("applicationId")
        if (expectedPackage != null && expectedPackage != candidate.packageName) {
            throw ApkUpdateException("PACKAGE_MISMATCH")
        }
        val expectedSigners = call.argument<List<String>>("signingCertificateSha256")
        if (expectedSigners != null && expectedSigners.toSet() != newSigners) {
            throw ApkUpdateException("SIGNATURE_MISMATCH")
        }
        val abis = mutableSetOf<String>()
        ZipFile(file).use { zip ->
            val entries = zip.entries()
            while (entries.hasMoreElements()) {
                val name = entries.nextElement().name
                if (name.startsWith("lib/") && name.endsWith(".so")) {
                    name.split('/').getOrNull(1)?.let { abis.add(it) }
                }
            }
        }
        if (abis.isNotEmpty() && Build.SUPPORTED_ABIS.none { it in abis }) {
            throw ApkUpdateException("INCOMPATIBLE_DEVICE")
        }
        return file to mapOf(
            "applicationId" to candidate.packageName,
            "versionCode" to versionCode,
            "versionName" to (candidate.versionName ?: ""),
            "signingCertificateSha256" to newSigners.toList(),
        )
    }

    private fun install(call: MethodCall): Map<String, Any?> {
        val (file, info) = inspect(call)
        if (!canInstall()) throw ApkUpdateException("INSTALL_PERMISSION_REQUIRED")
        val installer = activity.packageManager.packageInstaller
        val oldId = preferences.getInt("sessionId", -1)
        if (oldId >= 0 && installer.getSessionInfo(oldId) != null) {
            if (preferences.getString("stage", "") == "installing") {
                throw ApkUpdateException("UPDATE_BUSY")
            }
            preferences.edit().remove("sessionId").putString("stage", "interrupted").commit()
            installer.abandonSession(oldId)
        }
        AndroidUpdateInstallState.pendingAction = null
        AndroidUpdateInstallState.confirmationDisplayed = false
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
            setAppPackageName(activity.packageName)
            setSize(file.length())
            if (Build.VERSION.SDK_INT >= 31) {
                setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_REQUIRED)
            }
        }
        val sessionId = installer.createSession(params)
        var committed = false
        try {
            preferences.edit().putInt("sessionId", sessionId)
                .putLong("versionCode", info["versionCode"] as Long)
                .putString("stage", "preparing").putBoolean("committed", false).remove("errorCode").commit()
            installer.openSession(sessionId).use { session ->
                file.inputStream().use { input ->
                    session.openWrite("base.apk", 0, file.length()).use { output ->
                        VerifiedApkStream.copy(input, output, call.argument<Number>("size")!!.toLong(), call.argument<String>("sha256")!!)
                        session.fsync(output)
                    }
                }
                val callback = Intent(activity, AndroidUpdateInstallReceiver::class.java)
                    .setAction("${activity.packageName}.SOFTWARE_UPDATE_RESULT.$sessionId")
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                    (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
                val sender = PendingIntent.getBroadcast(activity, sessionId, callback, flags).intentSender
                preferences.edit().putString("stage", "installing").commit()
                session.commit(sender)
                committed = true
                preferences.edit().putBoolean("committed", true).apply()
            }
        } finally {
            if (!committed) {
                runCatching { installer.abandonSession(sessionId) }
                preferences.edit().putString("stage", "failed").apply()
            }
        }
        return status()
    }

    @Suppress("DEPRECATION")
    private fun signers(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= 28) {
            info.signingInfo?.apkContentsSigners
        } else info.signatures
        return signatures?.map { certificateHash(it.toByteArray()) }?.toSet() ?: emptySet()
    }

    private fun certificateHash(bytes: ByteArray) = hex(MessageDigest.getInstance("SHA-256").digest(bytes))
    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it.toInt() and 255) }

    @Suppress("DEPRECATION")
    private fun canInstall(): Boolean = if (Build.VERSION.SDK_INT >= 26) {
        activity.packageManager.canRequestPackageInstalls()
    } else {
        Settings.Secure.getInt(activity.contentResolver, Settings.Secure.INSTALL_NON_MARKET_APPS, 0) == 1
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (canInstall()) {
            result.success(true)
            return
        }
        if (permissionResult != null || !resumed) {
            result.error("UPDATE_BUSY", "UPDATE_BUSY", null)
            return
        }
        permissionResult = result
        permissionReturned = false
        try {
            val intent = if (Build.VERSION.SDK_INT >= 26) {
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}"))
            } else Intent(Settings.ACTION_SECURITY_SETTINGS)
            activity.startActivityForResult(intent, PERMISSION_REQUEST)
        } catch (error: Exception) {
            permissionResult = null
            result.error("INSTALL_PERMISSION_REQUIRED", "INSTALL_PERMISSION_REQUIRED", null)
        }
    }

    private fun status(): Map<String, Any?> {
        var stage = preferences.getString("stage", "idle") ?: "idle"
        val target = preferences.getLong("versionCode", -1)
        val installed = AndroidUpdateIdentity.environment(activity, "direct")["versionCode"] as Long
        if (target > 0 && installed >= target) {
            stage = "completed"
            preferences.edit().putString("stage", stage).apply()
        } else if (stage in setOf("installing", "confirmation", "preparing")) {
            val id = preferences.getInt("sessionId", -1)
            val session = if (id >= 0) activity.packageManager.packageInstaller.getSessionInfo(id) else null
            val sealed = session != null && if (Build.VERSION.SDK_INT >= 26) session.isSealed
                else preferences.getBoolean("committed", false) || stage == "confirmation"
            val recovered = ApkUpdatePolicy.recoverStage(
                stage, session != null, sealed, working,
                AndroidUpdateInstallState.pendingAction != null, AndroidUpdateInstallState.confirmationDisplayed,
            )
            if (recovered != stage) {
                stage = recovered
                preferences.edit().putString("stage", stage).apply()
            }
        }
        return mapOf("stage" to stage, "versionCode" to target, "errorCode" to preferences.getInt("errorCode", 0))
    }

    fun onInstallResult() {
        if (disposed) return
        showConfirmation()
        channel.invokeMethod("status", status())
    }

    private fun showConfirmation() {
        if (!resumed || disposed) return
        val intent = AndroidUpdateInstallState.pendingAction ?: return
        AndroidUpdateInstallState.pendingAction = null
        try {
            AndroidUpdateInstallState.confirmationDisplayed = true
            activity.startActivity(intent)
        } catch (error: Exception) {
            AndroidUpdateInstallState.confirmationDisplayed = false
            preferences.edit().putString("stage", "interrupted").apply()
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        permissionReturned = true
        if (resumed) finishPermissionRequest()
        return true
    }

    private fun finishPermissionRequest() {
        if (!permissionReturned) return
        permissionResult?.success(canInstall())
        permissionResult = null
        permissionReturned = false
    }

    fun onResume() {
        resumed = true
        finishPermissionRequest()
    }
    fun onPause() { resumed = false }

    fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        permissionResult?.error("ACTIVITY_CLOSED", "ACTIVITY_CLOSED", null)
        permissionResult = null
        if (AndroidUpdateInstallState.channel?.get() === this) AndroidUpdateInstallState.channel = null
        executor.shutdownNow()
    }

    companion object { private const val PERMISSION_REQUEST = 8741 }
}
