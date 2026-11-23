package org.otzaria.otzaria

import android.app.Activity
import android.app.Instrumentation
import android.content.ComponentName
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.Bundle
import android.os.SystemClock
import android.system.Os
import android.view.accessibility.AccessibilityNodeInfo
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.File
import java.nio.ByteBuffer
import java.util.UUID
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.json.JSONArray
import org.json.JSONObject

class PdfExportInstrumentation : Instrumentation() {
    private lateinit var activity: PdfExportProbeActivity
    private val cases = JSONArray()
    private val report = JSONObject()
    private val controlUri = Uri.parse("content://${PdfExportFixture.CONTROL}")

    override fun onCreate(arguments: Bundle?) { super.onCreate(arguments); start() }

    override fun onStart() {
        var success = false
        try {
            require(targetContext.packageName == PdfExportFixture.APP)
            report.put("schema", 1).put("applicationId", targetContext.packageName)
                .put("sdk", android.os.Build.VERSION.SDK_INT).put("fingerprint", android.os.Build.FINGERPRINT)
                .put("cases", cases)
            PdfExportProbeState.ready = false
            activity = startActivitySync(Intent().setComponent(ComponentName(targetContext,
                PdfExportProbeActivity::class.java)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as PdfExportProbeActivity
            waitFor("real Dart service readiness") { PdfExportProbeState.ready }

            runCase("documents_ui_new_copy") { successfulExport(realPicker = true, pipe = false) }
            runCase("pipe_bytes_and_pdf_parity") { successfulExport(realPicker = false, pipe = true) }
            runCase("create_failure") { providerFailure("createFailure", "create_failed", "notNeeded") }
            runCase("invalid_created_document") { invalidCreatedDocument() }
            runCase("output_open_failure") { providerFailure("openFailure", "write_failed", "deleted") }
            runCase("pipe_write_failure") { brokenPipe() }
            runCase("cancel_blocked_create") { cancelledCreate() }
            runCase("cancel_blocked_write_deleted") { cancelledWrite(null) }
            runCase("cancel_blocked_write_unsupported_cleanup") { cancelledWrite("unsupported") }
            runCase("cancel_blocked_write_failed_cleanup") { cancelledWrite("failed") }
            runCase("provider_name_unavailable") { missingName() }
            runCase("stale_request_and_duplicate_result") { staleAndDuplicate() }
            runCase("cancel_during_native_prepare") { preparing(detach = false) }
            runCase("detach_before_native_acquire") { preparing(detach = true) }
            runCase("detach_while_picker_open") { detachedPicker() }
            runCase("saved_before_late_cancel_delivery") { savedBeforeDelivery() }
            runCase("staging_leaf_replacement") { replacedStaging("leaf") }
            runCase("staging_child_replacement") { replacedStaging("child") }
            runCase("staging_root_replacement") { replacedStaging("root") }
            runCase("invalid_source_no_provider_document") { invalidSource() }
            runCase("activity_detach_during_write") { detachedActivity() }
            success = true
        } catch (error: Throwable) {
            report.put("failure", error.stackTraceToString())
        } finally {
            try { fixture("release") } catch (_: Exception) { }
            if (::activity.isInitialized) onMain { if (!activity.isFinishing) activity.finish() }
            report.put("passed", success)
            persist()
            finish(if (success) Activity.RESULT_OK else Activity.RESULT_CANCELED,
                Bundle().apply { putString("stream", "PDF_EXPORT_NATIVE ${report}\n") })
        }
    }

    private fun runCase(name: String, action: () -> JSONObject) {
        val row = JSONObject().put("name", name)
        cases.put(row)
        try {
            row.put("evidence", action()).put("passed", true)
        } catch (error: Throwable) {
            row.put("passed", false).put("failure", error.stackTraceToString())
            throw error
        } finally { persist() }
    }

    private fun persist() {
        File(targetContext.filesDir, "pdf-export-native-report.json").writeText(report.toString(2))
    }

    private fun fixture(method: String, options: Bundle? = null): Bundle =
        requireNotNull(targetContext.contentResolver.call(controlUri, method, null, options))

    private fun reset(options: Bundle = Bundle(), picker: String = "scripted", grant: Boolean = true) {
        fixture("reset", options)
        PdfExportProbeState.picker = picker
        PdfExportProbeState.tree = Uri.parse(fixture(if (grant) "grant" else "snapshot").getString("tree"))
    }

    private fun snapshot(): JSONObject = JSONObject(requireNotNull(fixture("snapshot").getString("snapshot")))

    private fun documents(snapshot: JSONObject = snapshot()): List<JSONObject> =
        snapshot.getJSONArray("documents").let { rows -> (0 until rows.length()).map { rows.getJSONObject(it) } }

    private fun copyDocument(): JSONObject = documents().single { it.getString("id") != "existing" }

    private fun hasEvent(prefix: String): Boolean = snapshot().getJSONArray("events").let { rows ->
        (0 until rows.length()).any { rows.getString(it).startsWith(prefix) }
    }

    private fun command(method: String, values: Map<String, Any?> = emptyMap()): Map<*, *> {
        val result = CompletableFuture<Any?>()
        onMain {
            requireNotNull(PdfExportProbeState.control).invokeMethod(method, values, object : MethodChannel.Result {
                override fun success(value: Any?) { result.complete(value) }
                override fun error(code: String, message: String?, details: Any?) { result.completeExceptionally(AssertionError("$code: $message / $details")) }
                override fun notImplemented() { result.completeExceptionally(AssertionError("Probe method missing: $method")) }
            })
        }
        return result.get(30, TimeUnit.SECONDS) as Map<*, *>
    }

    private fun startExport(fileName: String = "עותק.pdf", padding: Int = 16 * 1024 * 1024): String =
        command("start", mapOf("fileName" to fileName, "padding" to padding))["operationId"] as String

    private fun request(method: String, id: String): Map<*, *> = command(method, mapOf("operationId" to id))

    private fun assertClean(id: String): Map<*, *> {
        val state = request("state", id)
        check(state["exists"] == false && state["directoryExists"] == false) { "Staging was not cleaned: $state" }
        val path = state["sourcePath"] as String
        check(openDescriptors(path) == 0) { "The source descriptor is still open" }
        return state
    }

    private fun openDescriptors(path: String): Int = File("/proc/self/fd").listFiles().orEmpty().count { entry ->
        val target = try { Os.readlink(entry.path) } catch (_: Exception) { "" }
        target == path || target == "$path (deleted)"
    }

    private fun successfulExport(realPicker: Boolean, pipe: Boolean): JSONObject {
        reset(Bundle().apply { putBoolean("pipe", pipe) }, if (realPicker) "real" else "scripted", grant = !realPicker)
        val original = documents().single().getString("sha256")
        val id = startExport("existing.pdf")
        val pickerPackage = if (realPicker) selectActualDocumentsUi() else null
        val result = request("result", id)
        check(result["status"] == "saved" && result["cleanupStatus"] == "notNeeded") { result.toString() }
        check(result["displayName"] == "existing (2).pdf") { "Provider collision name was not reported: $result" }
        waitFor("provider writer closed") { copyDocument().getBoolean("closed") && snapshot().getInt("readers") == 0 }
        val state = assertClean(id)
        val copied = copyDocument()
        check(state["sha256"] == copied.getString("sha256"))
        check((state["length"] as Number).toLong() == copied.getLong("bytes"))
        check(documents().single { it.getString("id") == "existing" }.getString("sha256") == original)
        val uri = Uri.parse(result["documentUri"] as String)
        val descriptor = requireNotNull(targetContext.contentResolver.openFileDescriptor(uri, "r"))
        var ink = 0
        descriptor.use { PdfRenderer(it).use { renderer ->
            check(renderer.pageCount == 1)
            renderer.openPage(0).use { page ->
                val bitmap = Bitmap.createBitmap(200, 200, Bitmap.Config.ARGB_8888)
                try {
                    bitmap.eraseColor(Color.WHITE)
                    page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    for (y in 0 until bitmap.height) for (x in 0 until bitmap.width) {
                        val pixel = bitmap.getPixel(x, y)
                        if (Color.blue(pixel) > 150 && Color.red(pixel) < 50) ink++
                    }
                } finally { bitmap.recycle() }
            }
        } }
        check(ink > 100) { "Saved PDF has no visible fixture content" }
        check(request("rawCancel", id)["accepted"] == false)
        return JSONObject().put("result", JSONObject(result)).put("source", JSONObject(state))
            .put("provider", snapshot()).put("bluePixels", ink).put("realDocumentsUi", realPicker)
            .put("pickerPackage", pickerPackage ?: JSONObject.NULL)
    }

    private fun providerFailure(option: String, error: String, cleanup: String): JSONObject {
        reset(Bundle().apply { putBoolean(option, true) })
        val id = startExport(padding = 4096)
        val result = request("result", id)
        check(result["status"] == "failed" && result["errorCode"] == error && result["cleanupStatus"] == cleanup) { result.toString() }
        assertClean(id)
        if (option == "createFailure") check(documents().size == 1)
        else check(copyDocument().getBoolean("deleted"))
        return JSONObject().put("result", JSONObject(result)).put("provider", snapshot())
    }

    private fun invalidCreatedDocument(): JSONObject {
        reset(Bundle().apply { putBoolean("createReturnsParent", true) })
        val id = startExport(padding = 4096)
        val result = request("result", id)
        check(result["status"] == "failed" && result["errorCode"] == "invalid_document") { result.toString() }
        check(result["cleanupStatus"] == "notNeeded" && result["residualDocument"] == null)
        check(documents().single().getString("id") == "existing")
        check(hasEvent("create-enter") && !hasEvent("open-request:") && !hasEvent("delete-request:"))
        assertClean(id)
        return JSONObject().put("result", JSONObject(result)).put("provider", snapshot())
    }

    private fun brokenPipe(): JSONObject {
        reset(Bundle().apply { putBoolean("pipe", true); putLong("failAfter", 65536) })
        val id = startExport()
        val result = request("result", id)
        check(result["status"] == "failed" && result["cleanupStatus"] == "deleted") { result.toString() }
        val state = assertClean(id)
        val partial = copyDocument().getLong("bytes")
        check(partial > 0 && partial < (state["length"] as Number).toLong())
        return JSONObject().put("result", JSONObject(result)).put("partialBytes", partial).put("provider", snapshot())
    }

    private fun cancelledCreate(): JSONObject {
        reset(Bundle().apply { putBoolean("blockCreate", true) })
        val id = startExport(padding = 4096)
        waitFor("create entered") { hasEvent("create-enter") }
        val ack = request("cancel", id)
        check(ack["terminal"] == false && request("state", id)["exists"] == true)
        fixture("release")
        val result = request("result", id)
        check(result["status"] == "cancelled" && result["cleanupStatus"] == "deleted") { result.toString() }
        check(!copyDocument().getBoolean("opened"))
        assertClean(id)
        return JSONObject().put("result", JSONObject(result)).put("provider", snapshot())
    }

    private fun cancelledWrite(deleteMode: String?): JSONObject {
        reset(Bundle().apply { putBoolean("pipe", true); putBoolean("blockWrite", true); putString("deleteMode", deleteMode) })
        val id = startExport()
        waitFor("positive bytes and blocked writer") { hasEvent("write-gate:") }
        val before = request("state", id)
        check(before["exists"] == true && before["terminal"] == false)
        val dartAck = request("cancel", id)
        val nativeAck = request("rawCancel", id)
        val sourceHeld = request("state", id)["exists"]
        check(dartAck["terminal"] == false && nativeAck["accepted"] == true && sourceHeld == true)
        fixture("release")
        val result = request("result", id)
        val expected = deleteMode ?: "deleted"
        check(result["status"] == "cancelled" && result["cleanupStatus"] == expected) { result.toString() }
        waitFor("cancelled pipe reader closed") { copyDocument().getBoolean("closed") && snapshot().getInt("readers") == 0 }
        val partial = copyDocument().getLong("bytes")
        check(partial > 0 && partial < (before["length"] as Number).toLong())
        if (deleteMode == null) check(result["residualDocument"] == null)
        else {
            check(result["residualDocument"] is String && result["residualDisplayName"] == "עותק.pdf")
            check(!copyDocument().getBoolean("deleted"))
        }
        assertClean(id)
        return JSONObject().put("result", JSONObject(result)).put("partialBytes", partial)
            .put("sourceBytes", before["length"]).put("provider", snapshot())
            .put("ack", JSONObject(nativeAck)).put("sourceHeldAfterAck", sourceHeld).put("terminalAtAck", dartAck["terminal"])
    }

    private fun missingName(): JSONObject {
        reset(Bundle().apply { putBoolean("nameFailure", true) })
        val id = startExport(padding = 4096)
        val result = request("result", id)
        check(result["status"] == "saved" && result["displayName"] == null)
        assertClean(id)
        waitFor("provider close") { copyDocument().getBoolean("closed") }
        return JSONObject().put("result", JSONObject(result))
    }

    private fun staleAndDuplicate(): JSONObject {
        reset(picker = "held")
        var count = PdfExportProbeState.requests.size
        val first = startExport(padding = 4096)
        waitFor("first picker") { PdfExportProbeState.requests.size > count }
        val firstCode = PdfExportProbeState.requests.last()
        check(request("busy", first)["errorCode"] == "export_busy")
        request("cancel", first)
        check(request("result", first)["status"] == "cancelled")
        assertClean(first)
        count = PdfExportProbeState.requests.size
        val second = startExport(padding = 4096)
        waitFor("second picker") { PdfExportProbeState.requests.size > count }
        val secondCode = PdfExportProbeState.requests.last()
        check(firstCode != secondCode)
        check(request("rawCancel", first)["accepted"] == false)
        onMain { activity.deliverPickerResult(firstCode, Activity.RESULT_OK, PdfExportProbeState.tree) }
        check(request("state", second)["terminal"] == false && documents().size == 1)
        onMain {
            activity.deliverPickerResult(secondCode, Activity.RESULT_OK, PdfExportProbeState.tree)
            activity.deliverPickerResult(secondCode, Activity.RESULT_OK, PdfExportProbeState.tree)
        }
        val result = request("result", second)
        check(result["status"] == "saved")
        check(documents().size == 2)
        assertClean(second)
        waitFor("provider close") { copyDocument().getBoolean("closed") }
        return JSONObject().put("firstRequestCode", firstCode).put("secondRequestCode", secondCode)
            .put("result", JSONObject(result)).put("provider", snapshot())
    }

    private fun onMain(action: () -> Unit) {
        var failure: Throwable? = null
        super.runOnMainSync { try { action() } catch (error: Throwable) { failure = error } }
        failure?.let { throw it }
    }

    private fun waitFor(description: String, condition: () -> Boolean) {
        val deadline = SystemClock.uptimeMillis() + 15000
        while (SystemClock.uptimeMillis() < deadline) {
            if (condition()) return
            SystemClock.sleep(25)
        }
        error("Timed out: $description")
    }

    private fun selectActualDocumentsUi(): String {
        waitFor("DocumentsUI window") {
            uiAutomation.rootInActiveWindow?.packageName?.toString()?.endsWith(".documentsui") == true
        }
        var root = requireNotNull(uiAutomation.rootInActiveWindow)
        val pickerPackage = root.packageName.toString()
        if (nodes(root).none { it.text?.toString() == "PDF export fixture" }) {
            val menu = nodes(root).firstOrNull { it.contentDescription?.toString() in setOf("Show roots", "Open navigation drawer") }
                ?: error("DocumentsUI roots button not found")
            click(menu)
        }
        waitFor("fixture root in real picker") {
            uiAutomation.rootInActiveWindow?.let { nodes(it).any { node -> node.text?.toString() == "PDF export fixture" } } == true
        }
        root = requireNotNull(uiAutomation.rootInActiveWindow)
        click(nodes(root).first { it.text?.toString() == "PDF export fixture" })
        waitFor("Use this folder button") {
            uiAutomation.rootInActiveWindow?.let { nodes(it).any { node -> node.text?.toString()?.equals("Use this folder", true) == true && node.isEnabled } } == true
        }
        root = requireNotNull(uiAutomation.rootInActiveWindow)
        val screenshot = requireNotNull(uiAutomation.takeScreenshot())
        try {
            File(targetContext.filesDir, "pdf-export-picker.png").outputStream().use { output ->
                check(screenshot.compress(Bitmap.CompressFormat.PNG, 100, output))
            }
        } finally { screenshot.recycle() }
        click(nodes(root).first { it.text?.toString()?.equals("Use this folder", true) == true })
        waitFor("folder permission confirmation") {
            uiAutomation.rootInActiveWindow?.let { nodes(it).any { node -> node.text?.toString()?.equals("Allow", true) == true } } == true
        }
        click(nodes(requireNotNull(uiAutomation.rootInActiveWindow)).first { it.text?.toString()?.equals("Allow", true) == true })
        return pickerPackage
    }

    private fun nodes(root: AccessibilityNodeInfo): List<AccessibilityNodeInfo> = buildList {
        add(root)
        for (index in 0 until root.childCount) root.getChild(index)?.let { addAll(nodes(it)) }
    }

    private fun click(node: AccessibilityNodeInfo) {
        var target: AccessibilityNodeInfo? = node
        while (target != null && !target.isClickable) target = target.parent
        check(target?.performAction(AccessibilityNodeInfo.ACTION_CLICK) == true) { "Accessible click failed" }
    }

    private class NativeMessenger : BinaryMessenger {
        private val handlers = mutableMapOf<String, BinaryMessenger.BinaryMessageHandler>()
        val replies = mutableMapOf<String, AtomicInteger>()
        override fun send(channel: String, message: ByteBuffer?) = error("Unexpected native outbound call")
        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) = error("Unexpected native outbound call")
        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
            if (handler == null) handlers.remove(channel) else handlers[channel] = handler
        }
        fun call(method: String, values: Map<String, Any?>): CompletableFuture<Map<*, *>> {
            val response = CompletableFuture<Map<*, *>>()
            val message = StandardMethodCodec.INSTANCE.encodeMethodCall(MethodCall(method, values)).apply { flip() }
            requireNotNull(handlers["otzaria/pdf_file_export"]).onMessage(message) { envelope ->
                replies.getOrPut(method) { AtomicInteger() }.incrementAndGet()
                try {
                    requireNotNull(envelope).flip()
                    check(response.complete(StandardMethodCodec.INSTANCE.decodeEnvelope(envelope) as Map<*, *>)) { "Duplicate method reply" }
                } catch (error: Throwable) { response.completeExceptionally(error) }
            }
            return response
        }
    }

    private data class NativeOperation(val id: String, val file: File) {
        fun arguments(): Map<String, Any> = mapOf("version" to 1, "operationId" to id, "sourcePath" to file.path, "fileName" to file.name)
    }

    private fun nativeSource(): NativeOperation {
        val id = UUID.randomUUID().toString().replace("-", "")
        val directory = File(targetContext.cacheDir.canonicalFile, "otzaria-pdf-exports-v1/$id").apply { check(mkdirs()) }
        val pdf = StringBuilder("%PDF-1.4\n")
        val offsets = mutableListOf<Int>()
        val objects = listOf("<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R >>", "<< /Length 0 >>\nstream\nendstream")
        objects.forEachIndexed { index, value -> offsets.add(pdf.length); pdf.append("${index + 1} 0 obj\n$value\nendobj\n") }
        val xref = pdf.length
        pdf.append("xref\n0 5\n0000000000 65535 f \n")
        offsets.forEach { pdf.append(it.toString().padStart(10, '0')).append(" 00000 n \n") }
        pdf.append("trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n")
        val file = File(directory, "contract.pdf").apply { writeText(pdf.toString(), Charsets.US_ASCII) }
        return NativeOperation(id, file)
    }

    private fun preparing(detach: Boolean): JSONObject {
        reset(picker = "held")
        val source = nativeSource()
        val gate = CountDownLatch(1)
        val executor = Executors.newSingleThreadExecutor()
        executor.execute { check(gate.await(20, TimeUnit.SECONDS)) }
        val messenger = NativeMessenger()
        lateinit var channel: PdfFileExportChannel
        lateinit var result: CompletableFuture<Map<*, *>>
        val requestCount = PdfExportProbeState.requests.size
        onMain {
            channel = PdfFileExportChannel(activity, messenger, executor)
            result = messenger.call("exportFile", source.arguments())
            if (detach) channel.dispose() else check(messenger.call("cancelExport", source.arguments()).get()["accepted"] == true)
        }
        try {
            check(!result.isDone && source.file.exists())
            gate.countDown()
            val terminal = result.get(15, TimeUnit.SECONDS)
            check(terminal["status"] == "cancelled" && terminal["cleanupError"] == null) { terminal.toString() }
            check(!source.file.parentFile!!.exists() && openDescriptors(source.file.path) == 0)
            check(PdfExportProbeState.requests.size == requestCount && documents().size == 1)
            return JSONObject().put("result", JSONObject(terminal)).put("dartFinallyUsed", false)
        } finally {
            gate.countDown()
            onMain { channel.dispose() }
        }
    }

    private fun detachedPicker(): JSONObject {
        reset(picker = "held")
        val source = nativeSource()
        val messenger = NativeMessenger()
        lateinit var channel: PdfFileExportChannel
        lateinit var result: CompletableFuture<Map<*, *>>
        val requestCount = PdfExportProbeState.requests.size
        onMain { channel = PdfFileExportChannel(activity, messenger); result = messenger.call("exportFile", source.arguments()) }
        waitFor("native picker acquired source") { PdfExportProbeState.requests.size > requestCount }
        check(source.file.exists() && openDescriptors(source.file.path) == 1)
        onMain { channel.dispose() }
        val terminal = result.get(15, TimeUnit.SECONDS)
        check(terminal["status"] == "cancelled" && terminal["cleanupError"] == null)
        check(!source.file.parentFile!!.exists() && openDescriptors(source.file.path) == 0)
        return JSONObject().put("result", JSONObject(terminal)).put("dartFinallyUsed", false)
    }

    private fun savedBeforeDelivery(): JSONObject {
        reset(picker = "held")
        val source = nativeSource()
        val messenger = NativeMessenger()
        lateinit var channel: PdfFileExportChannel
        lateinit var result: CompletableFuture<Map<*, *>>
        var ack: Map<*, *>? = null
        val requestCount = PdfExportProbeState.requests.size
        onMain { channel = PdfFileExportChannel(activity, messenger); result = messenger.call("exportFile", source.arguments()) }
        waitFor("native picker") { PdfExportProbeState.requests.size > requestCount }
        try {
            onMain {
                check(channel.onActivityResult(PdfExportProbeState.requests.last(), Activity.RESULT_OK, Intent().setData(PdfExportProbeState.tree)))
                check(!channel.onActivityResult(PdfExportProbeState.requests.last(), Activity.RESULT_OK, Intent().setData(PdfExportProbeState.tree)))
                waitFor("worker cleanup before main-thread delivery") { !source.file.parentFile!!.exists() }
                check(!result.isDone)
                ack = messenger.call("cancelExport", source.arguments()).get()
            }
            val terminal = result.get(15, TimeUnit.SECONDS)
            check(ack!!["accepted"] == false && terminal["status"] == "saved")
            check(messenger.replies["exportFile"]?.get() == 1 && messenger.replies["cancelExport"]?.get() == 1)
            waitFor("provider close") { copyDocument().getBoolean("closed") }
            return JSONObject().put("ack", JSONObject(ack)).put("result", JSONObject(terminal))
        } finally { onMain { channel.dispose() } }
    }

    private fun replacedStaging(kind: String): JSONObject {
        reset(picker = "held")
        val count = PdfExportProbeState.requests.size
        val id = startExport(padding = 4096)
        waitFor("source acquired before replacement") { PdfExportProbeState.requests.size > count }
        val state = request("state", id)
        val source = File(state["sourcePath"] as String)
        val victim = when (kind) { "leaf" -> source; "child" -> source.parentFile!!; else -> source.parentFile!!.parentFile!! }
        val moved = File(victim.parentFile, victim.name + ".preserved")
        check(victim.renameTo(moved))
        val sentinel = if (kind == "leaf") victim else File(victim.apply { check(mkdir()) }, "unrelated.txt")
        sentinel.writeText("replacement must survive")
        try {
            request("cancel", id)
            val terminal = request("result", id)
            check(terminal["status"] == "cancelled" && (terminal["cleanupError"] as String).contains("staging_cleanup_failed:"))
            check(sentinel.readText() == "replacement must survive")
            val movedSource = when (kind) { "leaf" -> moved; "child" -> File(moved, source.name); else -> File(moved, "$id/${source.name}") }
            check(moved.exists() && openDescriptors(source.path) == 0 && openDescriptors(movedSource.path) == 0)
            return JSONObject().put("result", JSONObject(terminal)).put("replacementPreserved", true)
        } finally {
            check(sentinel.delete())
            if (kind != "leaf") check(victim.delete())
            check(moved.renameTo(victim))
            check(source.delete())
            check(source.parentFile!!.delete())
        }
    }

    private fun invalidSource(): JSONObject {
        reset(picker = "held")
        val source = nativeSource()
        val elsewhere = File(targetContext.cacheDir, "unowned-pdf-export-source.pdf").apply { writeText("must survive") }
        val messenger = NativeMessenger()
        lateinit var channel: PdfFileExportChannel
        lateinit var result: CompletableFuture<Map<*, *>>
        val count = PdfExportProbeState.requests.size
        onMain {
            channel = PdfFileExportChannel(activity, messenger)
            result = messenger.call("exportFile", source.arguments() + ("sourcePath" to elsewhere.path))
        }
        try {
            val terminal = result.get(15, TimeUnit.SECONDS)
            check(terminal["status"] == "failed" && terminal["errorCode"] == "invalid_source")
            check(elsewhere.readText() == "must survive" && PdfExportProbeState.requests.size == count && documents().size == 1)
            return JSONObject().put("result", JSONObject(terminal)).put("unownedFilePreserved", true)
        } finally {
            onMain { channel.dispose() }
            check(elsewhere.delete()); check(source.file.delete()); check(source.file.parentFile!!.delete())
        }
    }

    private fun detachedActivity(): JSONObject {
        reset(Bundle().apply { putBoolean("pipe", true); putBoolean("blockWrite", true) })
        val id = startExport()
        waitFor("blocked writer before Activity destruction") { hasEvent("write-gate:") }
        val state = request("state", id)
        val source = File(state["sourcePath"] as String)
        check(source.exists())
        onMain { activity.finish() }
        waitFor("Activity and engine destruction") { activity.isDestroyed && PdfExportProbeState.engineDestroyObserved }
        onMain { check(FlutterEngine.engineForId(PdfExportProbeState.engineId) == null) }
        check(source.exists())
        fixture("release")
        waitFor("detached native worker cleanup") {
            !source.parentFile!!.exists() && copyDocument().getBoolean("deleted") && snapshot().getInt("readers") == 0
        }
        check(openDescriptors(source.path) == 0)
        return JSONObject().put("dartEngineDestroyed", true).put("stagingRemoved", true)
            .put("engineDestroyCallback", PdfExportProbeState.engineDestroyObserved)
            .put("engineId", PdfExportProbeState.engineId).put("engineStillRegistered", false)
            .put("sourceBytes", state["length"]).put("provider", snapshot())
    }
}
