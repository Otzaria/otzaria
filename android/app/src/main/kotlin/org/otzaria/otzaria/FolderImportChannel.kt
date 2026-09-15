package org.otzaria.otzaria

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors

/**
 * ייבוא תיקייה שלמה דרך SAF: ל-dart:io אין גישה לתיקייה חיצונית באנדרואיד 11+,
 * ולכן המעבר על העץ וההעתקה לאחסון האפליקציה נעשים כאן דרך ContentResolver.
 */
class FolderImportChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, CHANNEL)
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPick: MethodChannel.Result? = null

    @Volatile
    private var cancelRequested = false

    init {
        channel.setMethodCallHandler { call, result -> onMethodCall(call, result) }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        pendingPick?.success(null)
        pendingPick = null
        executor.shutdown()
    }

    /** מחזיר true כשהתוצאה שייכת לבורר התיקיות. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_TREE_REQUEST) return false
        val result = pendingPick ?: return true
        pendingPick = null
        val treeUri = data?.data
        if (resultCode != Activity.RESULT_OK || treeUri == null) {
            result.success(null)
            return true
        }
        result.success(mapOf("uri" to treeUri.toString(), "name" to treeDisplayName(treeUri)))
        return true
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickTree" -> pickTree(result)
            "scanTree" -> runInBackground(result) {
                val files = listBookFiles(treeUriOf(call), extensionsOf(call))
                mapOf("fileCount" to files.size, "totalBytes" to files.sumOf { it.size })
            }
            "cancelCopy" -> {
                cancelRequested = true
                result.success(null)
            }
            "copyTree" -> {
                cancelRequested = false
                runInBackground(result) {
                    copyTree(
                        treeUriOf(call),
                        File(call.argument<String>("destDir")!!),
                        extensionsOf(call),
                    )
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun pickTree(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("already_active", "Folder picker is already open", null)
            return
        }
        pendingPick = result
        try {
            activity.startActivityForResult(
                Intent(Intent.ACTION_OPEN_DOCUMENT_TREE),
                PICK_TREE_REQUEST,
            )
        } catch (e: Exception) {
            pendingPick = null
            result.error("no_picker", e.message, null)
        }
    }

    private fun treeDisplayName(treeUri: Uri): String {
        val rootUri = DocumentsContract.buildDocumentUriUsingTree(
            treeUri,
            DocumentsContract.getTreeDocumentId(treeUri),
        )
        activity.contentResolver.query(
            rootUri,
            arrayOf(Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getString(0) ?: ""
        }
        return ""
    }

    private class TreeFile(val documentId: String, val relativePath: String, val size: Long)

    private fun listBookFiles(treeUri: Uri, extensions: Set<String>): List<TreeFile> {
        val files = mutableListOf<TreeFile>()
        val pendingDirs = ArrayDeque<Pair<String, String>>()
        pendingDirs.addLast(DocumentsContract.getTreeDocumentId(treeUri) to "")
        while (pendingDirs.isNotEmpty()) {
            val (dirId, dirPath) = pendingDirs.removeFirst()
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, dirId)
            activity.contentResolver.query(childrenUri, CHILD_COLUMNS, null, null, null)
                ?.use { cursor ->
                    while (cursor.moveToNext()) {
                        val name = cursor.getString(1)
                        if (name == null || !isSafeName(name)) continue
                        val relative = if (dirPath.isEmpty()) name else "$dirPath/$name"
                        if (cursor.getString(2) == Document.MIME_TYPE_DIR) {
                            pendingDirs.addLast(cursor.getString(0) to relative)
                        } else if (name.substringAfterLast('.', "").lowercase() in extensions) {
                            val size = if (cursor.isNull(3)) 0L else cursor.getLong(3)
                            files.add(TreeFile(cursor.getString(0), relative, size))
                        }
                    }
                }
        }
        return files
    }

    // שם עם '/' או '..' היה כותב מחוץ לתיקיית היעד.
    private fun isSafeName(name: String): Boolean =
        name.isNotEmpty() && !name.contains('/') && name != "." && name != ".."

    private fun copyTree(treeUri: Uri, destDir: File, extensions: Set<String>): Map<String, Any> {
        val copied = mutableListOf<String>()
        val errors = mutableListOf<Map<String, String>>()
        var cancelled = false
        for (file in listBookFiles(treeUri, extensions)) {
            // נבדק בין קבצים בלבד, כדי שלא יישאר ביעד קובץ חצי-מועתק.
            if (cancelRequested) {
                cancelled = true
                break
            }
            try {
                val target = File(destDir, file.relativePath)
                target.parentFile?.mkdirs()
                val source = DocumentsContract.buildDocumentUriUsingTree(treeUri, file.documentId)
                val input = activity.contentResolver.openInputStream(source)
                    ?: throw IOException("Cannot open ${file.relativePath}")
                input.use { src -> target.outputStream().use { dst -> src.copyTo(dst) } }
                copied.add(target.path)
            } catch (e: Exception) {
                errors.add(
                    mapOf(
                        "path" to file.relativePath,
                        "message" to (e.message ?: e.javaClass.simpleName),
                    ),
                )
            }
        }
        return mapOf("copied" to copied, "errors" to errors, "cancelled" to cancelled)
    }

    private fun treeUriOf(call: MethodCall): Uri = Uri.parse(call.argument<String>("uri")!!)

    private fun extensionsOf(call: MethodCall): Set<String> =
        call.argument<List<String>>("extensions")!!.map { it.lowercase() }.toSet()

    private fun runInBackground(result: MethodChannel.Result, work: () -> Any) {
        executor.execute {
            try {
                val value = work()
                mainHandler.post { result.success(value) }
            } catch (e: Exception) {
                mainHandler.post { result.error("folder_import_failed", e.message, null) }
            }
        }
    }

    companion object {
        private const val CHANNEL = "otzaria/folder_import"
        private const val PICK_TREE_REQUEST = 0x4F54
        private val CHILD_COLUMNS = arrayOf(
            Document.COLUMN_DOCUMENT_ID,
            Document.COLUMN_DISPLAY_NAME,
            Document.COLUMN_MIME_TYPE,
            Document.COLUMN_SIZE,
        )
    }
}
