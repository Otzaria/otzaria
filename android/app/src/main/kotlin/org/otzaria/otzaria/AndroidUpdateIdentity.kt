package org.otzaria.otzaria

import android.content.Context
import android.content.pm.PackageInfo
import android.os.Build

internal object AndroidUpdateIdentity {
    @Suppress("DEPRECATION")
    fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()

    @Suppress("DEPRECATION")
    fun environment(context: Context, distribution: String): Map<String, Any?> {
        val installed = context.packageManager.getPackageInfo(context.packageName, 0)
        return mapOf(
            "distribution" to distribution,
            "applicationId" to context.packageName,
            "versionCode" to versionCode(installed),
            "versionName" to (installed.versionName ?: ""),
            "sdkInt" to Build.VERSION.SDK_INT,
            "abis" to Build.SUPPORTED_ABIS.toList(),
        )
    }
}
