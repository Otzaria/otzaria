package org.otzaria.otzaria

import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.InstallStatus

internal object PlayUpdatePolicy {
    fun type(flexibleAllowed: Boolean, immediateAllowed: Boolean, inProgress: Boolean): Int? = when {
        inProgress -> if (immediateAllowed) AppUpdateType.IMMEDIATE else null
        flexibleAllowed -> AppUpdateType.FLEXIBLE
        immediateAllowed -> AppUpdateType.IMMEDIATE
        else -> null
    }

    fun stage(status: Int, available: Boolean, inProgress: Boolean, updateAllowed: Boolean = true): String = when (status) {
        InstallStatus.PENDING, InstallStatus.DOWNLOADING -> "downloading"
        InstallStatus.DOWNLOADED -> "ready"
        InstallStatus.INSTALLING -> "installing"
        InstallStatus.INSTALLED -> "completed"
        InstallStatus.CANCELED -> "cancelled"
        InstallStatus.FAILED -> "failed"
        else -> if ((available || inProgress) && !updateAllowed) "unavailable"
            else if (inProgress) "confirmation" else if (available) "available" else "upToDate"
    }
}
