package org.otzaria.otzaria

import android.app.Activity
import android.content.Intent
import com.google.android.play.core.appupdate.AppUpdateInfo
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.InstallStatus
import com.google.android.play.core.install.model.UpdateAvailability
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal class AndroidUpdateChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "otzaria/android_software_update")
    private val manager by lazy { AppUpdateManagerFactory.create(activity) }
    private var listening = false
    private var resumed = false
    private var disposed = false
    private var flowOpen = false
    private val listener = InstallStateUpdatedListener { state ->
        publish(mapOf(
            "stage" to PlayUpdatePolicy.stage(state.installStatus(), true, false),
            "bytesDownloaded" to state.bytesDownloaded(),
            "totalBytes" to state.totalBytesToDownload(),
            "errorCode" to state.installErrorCode(),
        ))
    }

    init { channel.setMethodCallHandler(this) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "environment" -> result.success(AndroidUpdateIdentity.environment(activity, "play"))
            "checkPlay", "status", "resume" -> withInfo(result) { info ->
                if (call.method == "resume" && resumed && !flowOpen &&
                    info.updateAvailability() == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS) {
                    if (!startFlow(info)) {
                        result.error("PLAY_UNAVAILABLE", "PLAY_UNAVAILABLE", null)
                        return@withInfo
                    }
                }
                result.success(snapshot(info))
            }
            "startPlay" -> withInfo(result) { info ->
                if (info.installStatus() == InstallStatus.DOWNLOADED) {
                    result.success(snapshot(info))
                } else {
                    if (startFlow(info)) result.success(mapOf("stage" to "confirmation"))
                    else result.error("PLAY_UNAVAILABLE", "PLAY_UNAVAILABLE", null)
                }
            }
            "completePlay" -> withInfo(result) { info ->
                if (!resumed || info.installStatus() != InstallStatus.DOWNLOADED) {
                    result.error("PLAY_NOT_READY", "PLAY_NOT_READY", null)
                } else {
                    manager.completeUpdate()
                        .addOnSuccessListener { if (!disposed) result.success(mapOf("stage" to "installing")) }
                        .addOnFailureListener { if (!disposed) result.error("PLAY_UPDATE_FAILED", "PLAY_UPDATE_FAILED", null) }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun withInfo(result: MethodChannel.Result, action: (AppUpdateInfo) -> Unit) {
        if (!listening) {
            manager.registerListener(listener)
            listening = true
        }
        manager.appUpdateInfo.addOnSuccessListener { info ->
            if (!disposed) {
                try { action(info) } catch (error: Exception) {
                    result.error("PLAY_UPDATE_FAILED", "PLAY_UPDATE_FAILED", null)
                }
            }
        }.addOnFailureListener {
            if (!disposed) result.error("PLAY_UNAVAILABLE", "PLAY_UNAVAILABLE", null)
        }
    }

    private fun startFlow(info: AppUpdateInfo): Boolean {
        check(resumed && !flowOpen)
        val inProgress = info.updateAvailability() == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS
        check(inProgress || info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE)
        val type = PlayUpdatePolicy.type(
            info.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE),
            info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE), inProgress,
        ) ?: return false
        flowOpen = manager.startUpdateFlowForResult(info, activity, AppUpdateOptions.newBuilder(type).build(), UPDATE_REQUEST)
        check(flowOpen)
        return true
    }

    private fun snapshot(info: AppUpdateInfo): Map<String, Any?> {
        val available = info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE
        val inProgress = info.updateAvailability() == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS
        return mapOf(
            "stage" to PlayUpdatePolicy.stage(info.installStatus(), available, inProgress,
                PlayUpdatePolicy.type(info.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE),
                    info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE), inProgress) != null),
            "versionCode" to info.availableVersionCode(),
            "bytesDownloaded" to info.bytesDownloaded(),
            "totalBytes" to info.totalBytesToDownload(),
        )
    }

    private fun publish(state: Map<String, Any?>) {
        if (!disposed) channel.invokeMethod("status", state)
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != UPDATE_REQUEST) return false
        flowOpen = false
        when (resultCode) {
            Activity.RESULT_CANCELED -> publish(mapOf("stage" to "cancelled"))
            Activity.RESULT_OK -> manager.appUpdateInfo.addOnSuccessListener { publish(snapshot(it)) }
            else -> publish(mapOf("stage" to "failed"))
        }
        return true
    }

    fun onResume() { resumed = true }
    fun onPause() { resumed = false }
    fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        if (listening) manager.unregisterListener(listener)
    }

    companion object { private const val UPDATE_REQUEST = 8742 }
}
