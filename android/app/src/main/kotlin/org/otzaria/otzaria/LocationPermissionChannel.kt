package org.otzaria.otzaria

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * אישור מיקום משוער מהמשתמש, עבור בקשות `navigator.geolocation` של דפי תוספים.
 *
 * ה-WebView מחזיר לדף שגיאה כשלאפליקציה אין הרשאת מיקום, גם אם המארח התיר את
 * הבקשה — לכן ההרשאה מתבקשת כאן, רק אחרי שהשער של התוסף כבר אישר. מבקשים
 * `ACCESS_COARSE_LOCATION` בלבד: מיקום משוער מספיק, והמערכת מציגה למשתמש בחירה
 * של מיקום משוער.
 *
 * בקשה שהצד של Dart ויתר עליה (`cancel`) מנוקה מכאן: בלי זה בקשה שלא נענתה הייתה
 * חוסמת כל בקשה אחריה, כי `requestPermissions` נקרא רק כשאין בקשה ממתינה.
 */
class LocationPermissionChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, CHANNEL)

    // בקשות שהגיעו בזמן שחלון המערכת פתוח: כולן נענות באותה תשובה.
    private val pending = mutableListOf<MethodChannel.Result>()

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestCoarse" -> requestCoarse(result)
                "cancel" -> {
                    completePending(false)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        completePending(false)
    }

    /** מחזיר true כשהתוצאה שייכת לבקשת המיקום. */
    fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_CODE) return false
        completePending(grantResults.isNotEmpty() && grantResults.any { it == PackageManager.PERMISSION_GRANTED })
        return true
    }

    private fun requestCoarse(result: MethodChannel.Result) {
        if (isGranted()) {
            result.success(true)
            return
        }
        val firstRequest = pending.isEmpty()
        pending.add(result)
        if (firstRequest) {
            activity.requestPermissions(arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION), REQUEST_CODE)
        }
    }

    // הרשאה מדויקת (אם ניתנה בעבר) מכסה גם בקשה למשוערת.
    private fun isGranted(): Boolean =
        activity.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED ||
            activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    private fun completePending(granted: Boolean) {
        val waiting = pending.toList()
        pending.clear()
        waiting.forEach { it.success(granted) }
    }

    companion object {
        private const val CHANNEL = "otzaria/location_permission"
        private const val REQUEST_CODE = 0x4C0C
    }
}
