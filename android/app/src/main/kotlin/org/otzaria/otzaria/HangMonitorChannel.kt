package org.otzaria.otzaria

import android.os.Debug
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.os.Process
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.ScheduledThreadPoolExecutor
import java.util.concurrent.TimeUnit

internal class HangMonitorChannel(messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "otzaria/hang_monitor")
    var isStarted = false
        private set

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val path = call.argument<String>("logPath")
                    if (path.isNullOrEmpty()) {
                        result.error("MISSING_LOG_PATH", null, null)
                    } else {
                        isStarted = true
                        ProcessHangMonitor.start(path, call.argument<String>("version") ?: "unknown")
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun onResume() = ProcessHangMonitor.onResume(this)

    fun onPause() = ProcessHangMonitor.onPause(this)

    fun dispose() {
        onPause()
        isStarted = false
        channel.setMethodCallHandler(null)
    }

    fun reportRecovery(id: String, durationMs: Long, record: String) {
        channel.invokeMethod(
            "appHangRecovered",
            mapOf("hangId" to id, "durationMs" to durationMs, "record" to record),
        )
    }
}

/** לכל תהליך יש לולאת UI אחת, גם כשיותר מפעילות אחת בחזית. */
private object ProcessHangMonitor {
    private const val POLL_INTERVAL_MS = 1000L
    private const val HUNG_THRESHOLD_MS = 5000L
    private const val MAX_REPORTED_HANGS = 5
    private const val MAX_FRAMES = 48

    private data class LogConfig(val path: String, val version: String)

    private class Probe(val sentAt: Long) {
        var hang: Hang? = null
    }

    private class Hang(
        val id: String,
        val log: LogConfig,
        val detectedAt: Long,
        val unansweredMs: Long,
        val resumedForMs: Long,
    ) {
        var record: String? = null // נגיש רק ב-worker.
    }

    private val lock = Any()
    private val resumed = linkedSetOf<HangMonitorChannel>()
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }
    private val worker by lazy {
        ScheduledThreadPoolExecutor(1) { task ->
            Thread(task, "otzaria-hang-monitor").apply { isDaemon = true }
        }.apply { removeOnCancelPolicy = true }
    }

    private var log: LogConfig? = null
    private var polling: ScheduledFuture<*>? = null
    private var generation = 0L
    private var resumedAt = 0L
    private var pending: Probe? = null
    private var reportedHangs = 0

    fun start(path: String, version: String) {
        synchronized(lock) {
            log = LogConfig(path, version)
            startPolling()
        }
    }

    fun onResume(channel: HangMonitorChannel) {
        synchronized(lock) {
            if (resumed.isEmpty()) resumedAt = SystemClock.uptimeMillis()
            resumed.add(channel)
            startPolling()
        }
    }

    fun onPause(channel: HangMonitorChannel) {
        synchronized(lock) {
            if (!resumed.remove(channel) || resumed.isNotEmpty()) return
            generation++
            polling?.cancel(false)
            polling = null
            // עצם הכניסה ל-onPause מעידה שהלולאה חזרה לענות.
            pending?.let { finishProbe(it, notifyGeneration = null) }
            pending = null
        }
    }

    private fun startPolling() {
        if (resumed.isEmpty() || log == null || polling != null) return
        val expectedGeneration = generation
        polling = worker.scheduleWithFixedDelay(
            { check(expectedGeneration) },
            0L,
            POLL_INTERVAL_MS,
            TimeUnit.MILLISECONDS,
        )
    }

    private fun check(expectedGeneration: Long) {
        val handler = mainHandler
        val now = SystemClock.uptimeMillis()
        val debugger = Debug.isDebuggerConnected()
        val hang = synchronized(lock) {
            if (expectedGeneration != generation) return
            val config = log ?: return
            val probe = pending
            if (probe == null) {
                val next = Probe(now)
                pending = next
                // מחסום סנכרון של הציור אינו מעיד שהלולאה עצמה תקועה.
                Message.obtain(handler) { answer(next) }.apply { isAsynchronous = true }.sendToTarget()
                return
            }
            val waited = now - probe.sentAt
            if (probe.hang != null || waited < HUNG_THRESHOLD_MS || debugger ||
                reportedHangs >= MAX_REPORTED_HANGS
            ) return

            val id = "${Process.myPid()}-${Process.getStartUptimeMillis()}-${++reportedHangs}"
            Hang(id, config, now, waited, probe.sentAt - resumedAt).also { probe.hang = it }
        }

        val record = hangRecord(hang)
        if (append(hang.log.path, record)) hang.record = record
    }

    private fun answer(probe: Probe) {
        synchronized(lock) {
            if (probe !== pending) return
            pending = null
            finishProbe(probe, generation)
        }
    }

    private fun finishProbe(probe: Probe, notifyGeneration: Long?) {
        val hang = probe.hang ?: return
        val durationMs = SystemClock.uptimeMillis() - probe.sentAt
        val recoveredAt = System.currentTimeMillis()
        // אותו תור שומר על סדר הכתיבה של התקיעה ושל ההתאוששות.
        worker.execute {
            val record = hang.record ?: return@execute
            val recovery = "\n=== App hang recovered ${utcTimestamp(recoveredAt)} ===\n" +
                "Hang ID: ${hang.id}\nDuration: ${durationMs}ms\n"
            if (!append(hang.log.path, recovery) || notifyGeneration == null) return@execute
            mainHandler.post {
                val recipient = synchronized(lock) {
                    if (notifyGeneration == generation) resumed.lastOrNull { it.isStarted } else null
                }
                recipient?.reportRecovery(hang.id, durationMs, record)
            }
        }
    }

    private fun hangRecord(hang: Hang): String {
        val sinceLaunch = hang.detectedAt - Process.getStartUptimeMillis()
        val stack = Looper.getMainLooper().thread.stackTrace
        return buildString {
            append("\n=== App hang ${utcTimestamp(System.currentTimeMillis())} ===\n")
            append("Version: ${hang.log.version}\n")
            append("Message: AppHang: UI thread not responding\n")
            append("Hang ID: ${hang.id}\n")
            append("Detected: ${sinceLaunch}ms after launch\n")
            append("Unanswered: ${hang.unansweredMs}ms\n")
            append("Resumed: ${hang.resumedForMs}ms before the probe\n")
            if (stack.firstOrNull()?.methodName == "nativePollOnce") {
                append("Main thread: native looper boundary (Dart and engine frames unavailable)\n")
            }
            append("Stack:\n")
            stack.take(MAX_FRAMES).forEach { append("  at ").append(it).append('\n') }
            if (stack.size > MAX_FRAMES) append("  ... (${stack.size - MAX_FRAMES} frames omitted) ...\n")
        }
    }

    private fun append(path: String, text: String): Boolean =
        try {
            File(path).apply { parentFile?.mkdirs() }.appendText(text)
            true
        } catch (_: IOException) {
            false
        } catch (_: SecurityException) {
            false
        }

    private fun utcTimestamp(at: Long): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
            .apply { timeZone = TimeZone.getTimeZone("UTC") }
            .format(Date(at))
}
