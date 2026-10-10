package org.otzaria.otzaria

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * ייבוא תיקייה שלמה דרך SAF: ל-dart:io אין גישה לתיקייה חיצונית באנדרואיד 11+,
 * ולכן המעבר על העץ וההעתקה לאחסון האפליקציה נעשים כאן דרך ContentResolver.
 */
class FolderImportChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, CHANNEL)
    private val executor = Executors.newSingleThreadExecutor()

    // קריאת קבצים בנתחים (ייבוא ספרייה) — בנפרד, כדי שהעתקה ארוכה לא תחסום אותה.
    private val streamExecutor = Executors.newSingleThreadExecutor()
    private val openStreams = ConcurrentHashMap<Int, InputStream>()
    private val nextHandle = AtomicInteger(0)
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
        openStreams.values.forEach { runCatching { it.close() } }
        openStreams.clear()
        streamExecutor.shutdown()
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
        result.success(
            mapOf(
                "uri" to treeUri.toString(),
                "name" to treeDisplayName(treeUri),
                "path" to treePath(treeUri),
            ),
        )
        return true
    }

    /** הנתיב שמאחורי עץ של ExternalStorageProvider (`primary:Download/x`), או null. */
    private fun treePath(treeUri: Uri): String? {
        if (treeUri.authority != "com.android.externalstorage.documents") return null
        val docId = runCatching { DocumentsContract.getTreeDocumentId(treeUri) }
            .getOrNull() ?: return null
        val volume = docId.substringBefore(':')
        val relative = docId.substringAfter(':', "")
        val base = if (volume == "primary") {
            Environment.getExternalStorageDirectory().path
        } else {
            "/storage/$volume"
        }
        return if (relative.isEmpty()) base else "$base/$relative"
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickTree" -> pickTree(result)
            "scanTree" -> runInBackground(result) {
                val files = listBookFiles(treeUriOf(call), extensionsOf(call))
                mapOf("fileCount" to files.size, "totalBytes" to files.sumOf { it.size })
            }
            "listFiles" -> runInBackground(result) {
                listTopFiles(treeUriOf(call), call.argument<String>("parentId"))
            }
            "listFolders" -> runInBackground(result) {
                listChildFolders(treeUriOf(call), call.argument<String>("parentId"))
            }
            "childFolder" -> runInBackground(result) {
                childFolderId(
                    treeUriOf(call),
                    call.argument<String>("parentId"),
                    call.argument<String>("name")!!,
                )
            }
            "openDocument" -> runInBackground(result, streamExecutor) {
                val uri = DocumentsContract.buildDocumentUriUsingTree(
                    treeUriOf(call),
                    call.argument<String>("id")!!,
                )
                val stream = activity.contentResolver.openInputStream(uri)
                    ?: throw IOException("Cannot open $uri")
                val handle = nextHandle.incrementAndGet()
                openStreams[handle] = stream
                handle
            }
            "readDocument" -> runInBackground(result, streamExecutor) {
                val stream = openStreams[call.argument<Int>("handle")!!]
                    ?: throw IOException("Stream is closed")
                readChunk(stream, call.argument<Int>("max")!!)
            }
            "closeDocument" -> runInBackground(result, streamExecutor) {
                openStreams.remove(call.argument<Int>("handle")!!)?.close()
                true
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

    /** הקבצים שישירות תחת [parentId] (שורש העץ כשהוא null), עם המזהה ל-openDocument. */
    private fun listTopFiles(treeUri: Uri, parentId: String?): List<Map<String, Any>> {
        val files = mutableListOf<Map<String, Any>>()
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri,
            parentId ?: DocumentsContract.getTreeDocumentId(treeUri),
        )
        activity.contentResolver.query(childrenUri, CHILD_COLUMNS, null, null, null)
            ?.use { cursor ->
                while (cursor.moveToNext()) {
                    val name = cursor.getString(1)
                    if (name == null || !isSafeName(name)) continue
                    if (cursor.getString(2) == Document.MIME_TYPE_DIR) continue
                    val size = if (cursor.isNull(3)) 0L else cursor.getLong(3)
                    files.add(mapOf("id" to cursor.getString(0), "name" to name, "size" to size))
                }
            }
        return files
    }

    /** שמות תתי-התיקיות שישירות תחת [parentId] (שורש העץ כשהוא null). */
    private fun listChildFolders(treeUri: Uri, parentId: String?): List<String> {
        val names = mutableListOf<String>()
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri,
            parentId ?: DocumentsContract.getTreeDocumentId(treeUri),
        )
        activity.contentResolver.query(childrenUri, CHILD_COLUMNS, null, null, null)
            ?.use { cursor ->
                while (cursor.moveToNext()) {
                    val name = cursor.getString(1)
                    if (name == null || !isSafeName(name)) continue
                    if (cursor.getString(2) == Document.MIME_TYPE_DIR) names.add(name)
                }
            }
        return names
    }

    /** מזהה תת-התיקייה [name] שתחת [parentId] (שורש העץ כשהוא null), או null. */
    private fun childFolderId(treeUri: Uri, parentId: String?, name: String): String? {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri,
            parentId ?: DocumentsContract.getTreeDocumentId(treeUri),
        )
        activity.contentResolver.query(childrenUri, CHILD_COLUMNS, null, null, null)
            ?.use { cursor ->
                while (cursor.moveToNext()) {
                    if (cursor.getString(1) == name &&
                        cursor.getString(2) == Document.MIME_TYPE_DIR
                    ) {
                        return cursor.getString(0)
                    }
                }
            }
        return null
    }

    /** ממלא עד [max] בתים; מערך קצר יותר רק בסוף הקובץ, וריק אחריו. */
    private fun readChunk(stream: InputStream, max: Int): ByteArray {
        val buffer = ByteArray(max)
        var filled = 0
        while (filled < max) {
            val read = stream.read(buffer, filled, max - filled)
            if (read < 0) break
            filled += read
        }
        return if (filled == max) buffer else buffer.copyOf(filled)
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

    private fun runInBackground(
        result: MethodChannel.Result,
        on: java.util.concurrent.Executor = executor,
        work: () -> Any?,
    ) {
        on.execute {
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
