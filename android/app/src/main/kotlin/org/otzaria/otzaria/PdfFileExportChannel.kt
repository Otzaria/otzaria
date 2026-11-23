package org.otzaria.otzaria

import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream
import java.util.concurrent.Executors
import java.util.concurrent.ExecutorService
import java.util.concurrent.atomic.AtomicInteger

internal class PdfFileExportChannel(
    activity: Activity,
    messenger: BinaryMessenger,
    private val worker: ExecutorService = Executors.newSingleThreadExecutor(),
) {
    private var activity: Activity? = activity
    private val applicationContext = activity.applicationContext
    private val resolver = activity.applicationContext.contentResolver
    private val channel = MethodChannel(messenger, "otzaria/pdf_file_export")
    private val main = Handler(Looper.getMainLooper())
    private var pending: Pending? = null

    private enum class Phase { PREPARING, PICKING, WRITING, FINISHING }

    private data class Pending(
        val operation: PdfFileExportOperation,
        val requestCode: Int,
        val sourcePath: String,
        val fileName: String,
        val reply: MethodChannel.Result,
        var phase: Phase = Phase.PREPARING,
        var staging: PdfFileExportStaging? = null,
        var finished: Boolean = false,
    )

    init {
        channel.setMethodCallHandler { call, reply ->
            when (call.method) {
                "exportFile" -> start(call, reply)
                "cancelExport" -> cancel(call, reply)
                else -> reply.notImplemented()
            }
        }
    }

    private fun operationId(call: MethodCall): String? {
        val arguments = call.arguments as? Map<*, *> ?: return null
        if (arguments["version"] != 1) return null
        return (arguments["operationId"] as? String)?.takeIf { it.matches(OPERATION_ID) }
    }

    private fun start(call: MethodCall, reply: MethodChannel.Result) {
        val id = operationId(call)
        val arguments = call.arguments as? Map<*, *>
        val path = arguments?.get("sourcePath") as? String
        val name = arguments?.get("fileName") as? String
        if (id == null || path == null || name == null || !validName(name)) {
            reply.error("invalid_request", "Invalid PDF export request", null)
            return
        }
        if (pending != null || activity == null) {
            reply.success(PdfFileExportTerminal(id, "failed", errorCode = "export_busy",
                errorMessage = "A PDF export is already active or the activity is detached").toMap())
            return
        }
        val code = nextRequestCode.getAndIncrement()
        if (code < FIRST_REQUEST_CODE || code > LAST_REQUEST_CODE) {
            reply.success(PdfFileExportTerminal(id, "failed", errorCode = "request_codes_exhausted",
                errorMessage = "Restart the application before exporting another PDF").toMap())
            return
        }
        val current = Pending(PdfFileExportOperation(id), code, path, name, reply)
        pending = current
        worker.execute {
            try {
                val staging = PdfFileExportStaging.acquire(applicationContext.cacheDir.canonicalFile, path, name, id)
                main.post {
                    current.staging = staging
                    if (current.operation.isCancelled || activity == null) {
                        finishWithoutTarget(current)
                    } else {
                        launchPicker(current)
                    }
                }
            } catch (error: Exception) {
                val result = PdfFileExportTerminal(id, current.operation.finishUnsuccessful(),
                    errorCode = "invalid_source", errorMessage = error.message,
                    cleanupError = "staging_cleanup_failed: ${error.message}")
                main.post { complete(current, result) }
            }
        }
    }

    private fun launchPicker(current: Pending) {
        current.phase = Phase.PICKING
        try {
            activity!!.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            }, current.requestCode)
        } catch (error: Exception) {
            finishWithoutTarget(current, "picker_failed", error.message)
        }
    }

    private fun cancel(call: MethodCall, reply: MethodChannel.Result) {
        val id = operationId(call)
        if (id == null) {
            reply.error("invalid_request", "Invalid PDF cancellation request", null)
            return
        }
        val current = pending?.takeIf { it.operation.id == id }
        val accepted = current?.operation?.cancel() == true
        reply.success(mapOf("operationId" to id, "accepted" to accepted))
        if (accepted && current.phase == Phase.PICKING) cancelPicker(current)
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        val current = pending ?: return false
        if (requestCode != current.requestCode || current.phase != Phase.PICKING) return false
        current.phase = Phase.WRITING
        val tree = data?.data
        if (resultCode != Activity.RESULT_OK || tree == null) {
            current.operation.cancel()
            finishWithoutTarget(current)
            return true
        }
        worker.execute {
            val result = PdfFileExportWorker.export(
                current.operation,
                { current.staging!!.source() },
                AndroidDocumentStore(resolver, tree, current.fileName),
            )
            finishStaging(current, result)
        }
        return true
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        pending?.let { current ->
            current.operation.cancel()
            if (current.phase == Phase.PICKING) cancelPicker(current)
        }
        activity = null
        // אין shutdownNow: תשובת הסיום חייבת לחכות לסגירת הקובץ ולניקוי המסמך החדש.
        if (pending == null) worker.shutdown()
    }

    private fun cancelPicker(current: Pending) {
        try { activity?.finishActivity(current.requestCode) } catch (_: Exception) { }
        finishWithoutTarget(current)
    }

    private fun finishWithoutTarget(current: Pending, code: String? = null, message: String? = null) {
        current.phase = Phase.FINISHING
        worker.execute {
            val result = PdfFileExportTerminal(current.operation.id, current.operation.finishUnsuccessful(),
                errorCode = code, errorMessage = message)
            finishStaging(current, result)
        }
    }

    private fun finishStaging(current: Pending, result: PdfFileExportTerminal) {
        val terminal = try {
            current.staging!!.closeAndDelete()
            result
        } catch (error: Exception) {
            result.copy(cleanupError = "staging_cleanup_failed: ${error.message}" +
                (result.cleanupError?.let { "; $it" } ?: ""))
        }
        main.post { complete(current, terminal) }
    }

    private fun complete(current: Pending, result: PdfFileExportTerminal) {
        if (current.finished) return
        current.finished = true
        if (pending === current) pending = null
        if (activity == null) worker.shutdown()
        try { current.reply.success(result.toMap()) } catch (error: RuntimeException) {
            Log.w("PdfFileExport", "PDF export completed after the engine detached", error)
        }
    }

    private class AndroidDocumentStore(
        private val resolver: ContentResolver,
        private val tree: Uri,
        private val fileName: String,
    ) : PdfFileExportStore {
        override fun create(): String {
            if (tree.scheme != "content" || !DocumentsContract.isTreeUri(tree)) {
                throw PdfFileExportFailure("invalid_tree", "The picker did not return a document tree")
            }
            val treeId = DocumentsContract.getTreeDocumentId(tree)
            val parent = DocumentsContract.buildDocumentUriUsingTree(tree, treeId)
            val created = DocumentsContract.createDocument(resolver, parent, "application/pdf", fileName)
                ?: throw PdfFileExportFailure("create_failed", "The document provider did not create a PDF")
            val documentId = created.pathSegments.lastOrNull()
            if (documentId == null || documentId == treeId ||
                created != DocumentsContract.buildDocumentUriUsingTree(tree, documentId)) {
                throw PdfFileExportFailure("invalid_document", "The provider did not return a new document in the selected tree")
            }
            return created.toString()
        }

        override fun displayName(document: String): String? = resolver.query(
            Uri.parse(document), arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null,
        )?.use { cursor ->
            if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getString(0)?.takeIf { it.isNotEmpty() } else null
        }

        override fun openOutput(document: String): OutputStream =
            resolver.openOutputStream(Uri.parse(document), "w")
                ?: throw PdfFileExportFailure("write_failed", "The document provider did not open the new PDF")

        override fun delete(document: String): Boolean {
            val uri = Uri.parse(document)
            val flags = resolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_FLAGS), null, null, null)
                ?.use { cursor -> if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getInt(0) else null }
            if (flags != null && flags and DocumentsContract.Document.FLAG_SUPPORTS_DELETE == 0) {
                throw UnsupportedOperationException("The document provider cannot delete the partial copy")
            }
            return DocumentsContract.deleteDocument(resolver, uri)
        }
    }

    companion object {
        private val OPERATION_ID = Regex("[0-9a-f]{32}")
        private const val FIRST_REQUEST_CODE = 0x50440000
        private const val LAST_REQUEST_CODE = 0x5044ffff
        private val nextRequestCode = AtomicInteger(FIRST_REQUEST_CODE)

        private fun validName(name: String): Boolean = name.endsWith(".pdf") && name.length > 4 &&
            name.toByteArray(Charsets.UTF_8).size <= 255 &&
            name.none { it == '/' || it == '\\' || it.code < 32 || it.code == 127 }
    }
}
