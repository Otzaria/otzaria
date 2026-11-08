package org.otzaria.otzaria

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import java.lang.ref.WeakReference

internal object AndroidUpdateInstallState {
    const val PREFERENCES = "android_software_update"
    var channel: WeakReference<AndroidUpdateChannel>? = null
    var pendingAction: Intent? = null
    var confirmationDisplayed = false

    fun preferences(context: Context) = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
}

class AndroidUpdateInstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val preferences = AndroidUpdateInstallState.preferences(context)
        val sessionId = intent.getIntExtra(PackageInstaller.EXTRA_SESSION_ID, -1)
        if (sessionId < 0 || sessionId != preferences.getInt("sessionId", -1)) return
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        val stage = when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> "confirmation"
            PackageInstaller.STATUS_SUCCESS -> "completed"
            PackageInstaller.STATUS_FAILURE_ABORTED -> "cancelled"
            else -> "failed"
        }
        preferences.edit().putString("stage", stage).putInt("errorCode", status).putBoolean("committed", true).apply()
        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            AndroidUpdateInstallState.confirmationDisplayed = false
            @Suppress("DEPRECATION")
            val confirmation = if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
            } else {
                intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
            }
            AndroidUpdateInstallState.pendingAction = confirmation
            if (confirmation == null) preferences.edit().putString("stage", "interrupted").apply()
        } else {
            AndroidUpdateInstallState.pendingAction = null
            AndroidUpdateInstallState.confirmationDisplayed = false
        }
        AndroidUpdateInstallState.channel?.get()?.onInstallResult()
    }
}
