package org.otzaria.otzaria

import android.os.Debug
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * המקביל של `hang_monitor.cpp`: Dart רץ על ה-thread הראשי, ולכן תקיעה שלו היא תקיעת ה-UI.
 * ANR של המערכת נרשם רק אם המשתמש נגע במסך התקוע; הגלאי רושם גם בלי מגע.
 */
class HangMonitorChannel(messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val lock = Any()

    private var logPath: String? = null
    private var version = "unknown"
    private var worker: HandlerThread? = null
    private var workerHandler: Handler? = null
    private var resumed = false
    private var resumedAt = 0L
    private var pingSentAt = 0L
    private var hangStartedAt = 0L
    private var hangReported = false
    private var reportedHangs = 0

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    synchronized(lock) {
                        logPath = call.argument<String>("logPath")
                        version = call.argument<String>("version") ?: version
                    }
                    updatePolling()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun onResume() {
        synchronized(lock) {
            resumed = true
            resumedAt = SystemClock.uptimeMillis()
        }
        updatePolling()
    }

    fun onPause() {
        synchronized(lock) { resumed = false }
        updatePolling()
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        synchronized(lock) {
            resumed = false
            logPath = null
        }
        updatePolling()
    }

    private fun updatePolling() {
        synchronized(lock) {
            val shouldRun = resumed && logPath != null
            if (shouldRun && worker == null) {
                val thread = HandlerThread("otzaria-hang-monitor").apply { start() }
                worker = thread
                workerHandler = Handler(thread.looper).also { it.postDelayed(poll, POLL_INTERVAL_MS) }
            } else if (!shouldRun && worker != null) {
                workerHandler?.removeCallbacksAndMessages(null)
                worker?.quitSafely()
                worker = null
                workerHandler = null
                // בדיקה שעוד לא נענתה שייכת לתקופה שבחזית; ברקע אין מה למדוד.
                pingSentAt = 0L
            }
        }
    }

    private val poll = object : Runnable {
        override fun run() {
            check()
            synchronized(lock) {
                // worker שהוחלף בזמן הבדיקה כבר מתזמן את עצמו; אחרת היו שתי שרשראות.
                if (Looper.myLooper() == worker?.looper) workerHandler?.postDelayed(this, POLL_INTERVAL_MS)
            }
        }
    }

    private fun check() {
        val now = SystemClock.uptimeMillis()
        synchronized(lock) {
            if (pingSentAt == 0L) {
                pingSentAt = now
                mainHandler.post(pong)
                return
            }
            val waited = now - pingSentAt
            if (hangStartedAt != 0L || waited < HUNG_THRESHOLD_MS) return
            // מחובר debugger: עצירה בנקודת עצירה אינה תקיעה.
            if (Debug.isDebuggerConnected()) return
            hangStartedAt = pingSentAt
            hangReported = reportedHangs < MAX_REPORTED_HANGS && logPath != null
            if (!hangReported) return
            reportedHangs++
            // בתוך ה-lock: ה-pong לא יכתוב את השחרור לפני רשומת התקיעה.
            append(logPath ?: return, hangRecord(waited, pingSentAt - resumedAt))
        }
    }

    private val pong = Runnable {
        val path: String
        val durationMs: Long
        synchronized(lock) {
            val started = hangStartedAt
            pingSentAt = 0L
            if (started == 0L) return@Runnable
            hangStartedAt = 0L
            if (!hangReported) return@Runnable
            path = logPath ?: return@Runnable
            durationMs = SystemClock.uptimeMillis() - started
        }
        append(path, "\n=== App hang recovered ${utcTimestamp()} ===\nDuration: ${durationMs}ms\n")
        channel.invokeMethod("appHangRecovered", mapOf("durationMs" to durationMs))
    }

    private fun hangRecord(waitedMs: Long, sinceResumeMs: Long): String {
        val sinceLaunch = SystemClock.uptimeMillis() - Process.getStartUptimeMillis()
        val stack = Looper.getMainLooper().thread.stackTrace
        return buildString {
            append("\n=== App hang ${utcTimestamp()} ===\n")
            append("Version: $version\n")
            // בלי מספרים בשורה: ממנה נגזר סוג החתימה (AppHang).
            append("Message: AppHang: UI thread not responding\n")
            append("Detected: ${sinceLaunch}ms after launch\n")
            append("Unanswered: ${waitedMs}ms\n")
            append("Resumed: ${sinceResumeMs}ms before the hang\n")
            // Dart והמנוע רצים מתוך callback של ה-looper, ולכן אין להם פריימי Java.
            if (stack.firstOrNull()?.methodName == "nativePollOnce") {
                append("Main thread: inside a native looper callback (Dart or engine)\n")
            }
            append("Stack:\n")
            stack.take(MAX_FRAMES).forEach { append("  at ").append(it).append('\n') }
            if (stack.size > MAX_FRAMES) append("  ... (${stack.size - MAX_FRAMES} frames omitted) ...\n")
        }
    }

    private fun append(path: String, text: String) {
        try {
            File(path).apply { parentFile?.mkdirs() }.appendText(text)
        } catch (_: Exception) {
            // לוג לא נגיש אינו סיבה להפיל את האפליקציה.
        }
    }

    private fun utcTimestamp(): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
            .apply { timeZone = TimeZone.getTimeZone("UTC") }
            .format(Date())

    companion object {
        private const val CHANNEL = "otzaria/hang_monitor"
        private const val POLL_INTERVAL_MS = 1000L
        private const val HUNG_THRESHOLD_MS = 5000L
        private const val MAX_REPORTED_HANGS = 5
        private const val MAX_FRAMES = 48
    }
}
