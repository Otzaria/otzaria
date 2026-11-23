package org.otzaria.otzaria

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.DocumentsProvider
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.json.JSONArray
import org.json.JSONObject

internal object PdfExportFixture {
    const val APP = "org.otzaria.otzaria.pdfexportprobe"
    const val AUTHORITY = "$APP.test.documents"
    const val CONTROL = "$APP.test.control"
    const val ROOT = "fixture-root"
    val tree: Uri get() = DocumentsContract.buildTreeDocumentUri(AUTHORITY, ROOT)
    val documents = ConcurrentHashMap<String, Document>()
    val events = CopyOnWriteArrayList<String>()
    val sequence = AtomicInteger()
    val readers = AtomicInteger()
    @Volatile var options = Bundle()
    @Volatile var release = CountDownLatch(1)
    lateinit var directory: File

    class Document(val id: String, val name: String, val file: File, val options: Bundle) {
        val closed = CountDownLatch(1)
        @Volatile var opened = false
        @Volatile var bytes = 0L
        @Volatile var deleted = false
        @Volatile var readerError: String? = null
    }

    fun initialize(context: Context) {
        directory = File(context.filesDir, "pdf-export-provider-fixture").apply { mkdirs() }
    }

    fun reset(configuration: Bundle) {
        check(readers.get() == 0) { "Previous pipe reader is still active" }
        release.countDown()
        documents.clear()
        directory.listFiles()?.forEach { check(it.delete()) }
        events.clear()
        options = Bundle(configuration)
        release = CountDownLatch(1)
        val existing = File(directory, "existing").apply { writeText("Existing user document must remain unchanged") }
        documents["existing"] = Document("existing", "existing.pdf", existing, Bundle())
    }

    fun awaitRelease() {
        check(release.await(20, TimeUnit.SECONDS)) { "Fixture gate was not released" }
    }

    fun snapshot(): String = JSONObject().apply {
        put("events", JSONArray(events))
        put("readers", readers.get())
        put("documents", JSONArray(documents.values.sortedBy { it.id }.map { document ->
            JSONObject().apply {
                put("id", document.id)
                put("name", document.name)
                put("bytes", if (document.options.getBoolean("pipe")) document.bytes else document.file.length())
                put("opened", document.opened)
                put("closed", document.closed.count == 0L)
                put("deleted", document.deleted)
                put("readerError", document.readerError ?: JSONObject.NULL)
                if (document.file.exists()) put("sha256", sha256(document.file))
            }
        }))
    }.toString()

    fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(65536)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}

class PdfExportDocumentsProvider : DocumentsProvider() {
    override fun onCreate(): Boolean { PdfExportFixture.initialize(requireNotNull(context)); return true }

    override fun queryRoots(projection: Array<out String>?): Cursor {
        val columns = projection ?: arrayOf(DocumentsContract.Root.COLUMN_ROOT_ID,
            DocumentsContract.Root.COLUMN_DOCUMENT_ID, DocumentsContract.Root.COLUMN_TITLE,
            DocumentsContract.Root.COLUMN_FLAGS, DocumentsContract.Root.COLUMN_MIME_TYPES)
        return MatrixCursor(columns).apply {
            newRow().apply {
                for (column in columns) add(column, when (column) {
                    DocumentsContract.Root.COLUMN_ROOT_ID -> "pdf-export"
                    DocumentsContract.Root.COLUMN_DOCUMENT_ID -> PdfExportFixture.ROOT
                    DocumentsContract.Root.COLUMN_TITLE -> "PDF export fixture"
                    DocumentsContract.Root.COLUMN_FLAGS -> DocumentsContract.Root.FLAG_SUPPORTS_CREATE or
                        DocumentsContract.Root.FLAG_SUPPORTS_IS_CHILD
                    DocumentsContract.Root.COLUMN_MIME_TYPES -> "application/pdf"
                    else -> null
                })
            }
        }
    }

    override fun queryDocument(documentId: String, projection: Array<out String>?): Cursor {
        val columns = projection ?: DOCUMENT_COLUMNS
        if (documentId != PdfExportFixture.ROOT && PdfExportFixture.documents[documentId]?.options?.getBoolean("nameFailure") == true &&
            columns.contentEquals(arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME))) {
            throw FileNotFoundException("Fixture name query denied")
        }
        return MatrixCursor(columns).apply { addDocument(this, documentId) }
    }

    override fun queryChildDocuments(parentDocumentId: String, projection: Array<out String>?, sortOrder: String?): Cursor {
        require(parentDocumentId == PdfExportFixture.ROOT)
        return MatrixCursor(projection ?: DOCUMENT_COLUMNS).apply {
            PdfExportFixture.documents.values.filter { !it.deleted }.sortedBy { it.name }.forEach { addDocument(this, it.id) }
        }
    }

    private fun addDocument(cursor: MatrixCursor, id: String) {
        val root = id == PdfExportFixture.ROOT
        val document = if (root) null else PdfExportFixture.documents[id] ?: throw FileNotFoundException(id)
        val flags = if (root) DocumentsContract.Document.FLAG_DIR_SUPPORTS_CREATE else
            DocumentsContract.Document.FLAG_SUPPORTS_WRITE or
                (if (document!!.options.getString("deleteMode") == "unsupported") 0 else DocumentsContract.Document.FLAG_SUPPORTS_DELETE)
        cursor.newRow().apply {
            for (column in cursor.columnNames) add(column, when (column) {
                DocumentsContract.Document.COLUMN_DOCUMENT_ID -> id
                DocumentsContract.Document.COLUMN_DISPLAY_NAME -> if (root) "PDF export fixture" else document!!.name
                DocumentsContract.Document.COLUMN_MIME_TYPE -> if (root) DocumentsContract.Document.MIME_TYPE_DIR else "application/pdf"
                DocumentsContract.Document.COLUMN_FLAGS -> flags
                DocumentsContract.Document.COLUMN_SIZE -> document?.file?.length() ?: 0L
                DocumentsContract.Document.COLUMN_LAST_MODIFIED -> document?.file?.lastModified() ?: 0L
                else -> null
            })
        }
    }

    override fun isChildDocument(parentDocumentId: String, documentId: String): Boolean =
        parentDocumentId == PdfExportFixture.ROOT && PdfExportFixture.documents.containsKey(documentId)

    override fun createDocument(parentDocumentId: String, mimeType: String, displayName: String): String {
        require(parentDocumentId == PdfExportFixture.ROOT && mimeType == "application/pdf")
        val options = Bundle(PdfExportFixture.options)
        PdfExportFixture.events.add("create-enter")
        if (options.getBoolean("blockCreate")) PdfExportFixture.awaitRelease()
        if (options.getBoolean("createFailure")) throw FileNotFoundException("Fixture create failure")
        val id = "copy-${PdfExportFixture.sequence.incrementAndGet()}"
        val used = PdfExportFixture.documents.values.map { it.name }.toSet()
        var actualName = displayName
        var suffix = 2
        while (actualName in used) actualName = displayName.removeSuffix(".pdf") + " (${suffix++}).pdf"
        val file = File(PdfExportFixture.directory, id)
        check(file.createNewFile())
        PdfExportFixture.documents[id] = PdfExportFixture.Document(id, actualName, file, options)
        PdfExportFixture.events.add("create-return:$id")
        return id
    }

    override fun openDocument(documentId: String, mode: String, signal: CancellationSignal?): ParcelFileDescriptor {
        val document = PdfExportFixture.documents[documentId] ?: throw FileNotFoundException(documentId)
        if (mode == "r") return ParcelFileDescriptor.open(document.file, ParcelFileDescriptor.MODE_READ_ONLY)
        check(documentId != "existing") { "Existing user document must not be opened for writing" }
        check(mode == "w") { "The export path must support a nonseekable writer" }
        if (document.options.getBoolean("openFailure")) throw FileNotFoundException("Fixture output open failure")
        document.opened = true
        PdfExportFixture.events.add("write-open:$documentId")
        if (!document.options.getBoolean("pipe")) {
            return ParcelFileDescriptor.open(document.file, ParcelFileDescriptor.MODE_WRITE_ONLY or ParcelFileDescriptor.MODE_TRUNCATE,
                Handler(Looper.getMainLooper())) { error ->
                document.readerError = error?.message
                document.closed.countDown()
                PdfExportFixture.events.add("write-close:$documentId")
            }
        }
        val pipe = ParcelFileDescriptor.createReliablePipe()
        PdfExportFixture.readers.incrementAndGet()
        Thread({
            try {
                ParcelFileDescriptor.AutoCloseInputStream(pipe[0]).use { input ->
                    document.file.outputStream().use { output ->
                        val buffer = ByteArray(65536)
                        var gated = false
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            output.write(buffer, 0, count)
                            document.bytes += count
                            if (!gated && document.options.getBoolean("blockWrite")) {
                                gated = true
                                PdfExportFixture.events.add("write-gate:$documentId")
                                PdfExportFixture.awaitRelease()
                            }
                            val failAfter = document.options.getLong("failAfter")
                            if (failAfter > 0 && document.bytes >= failAfter) {
                                pipe[0].closeWithError("Fixture pipe failed after positive bytes")
                                break
                            }
                        }
                    }
                }
            } catch (error: Exception) {
                document.readerError = error.message
            } finally {
                document.closed.countDown()
                PdfExportFixture.readers.decrementAndGet()
                PdfExportFixture.events.add("write-close:$documentId")
            }
        }, "pdf-export-fixture-pipe").start()
        return pipe[1]
    }

    override fun deleteDocument(documentId: String) {
        check(documentId != "existing") { "Existing user document must not be deleted" }
        val document = PdfExportFixture.documents[documentId] ?: throw FileNotFoundException(documentId)
        PdfExportFixture.events.add("delete:$documentId")
        if (document.opened && !document.closed.await(10, TimeUnit.SECONDS)) throw IOException("Writer did not close before cleanup")
        when (document.options.getString("deleteMode")) {
            "unsupported" -> throw UnsupportedOperationException("Fixture does not support deletion")
            "failed" -> throw FileNotFoundException("Fixture deletion refused")
        }
        check(document.file.delete())
        document.deleted = true
    }

    companion object {
        private val DOCUMENT_COLUMNS = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_FLAGS, DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED)
    }
}

// ערוץ הפיקוח קיים רק ב־test APK ופתוח רק לחתימת ה־probe; הרשאת DocumentsProvider לא משתנה.
class PdfExportControlProvider : ContentProvider() {
    override fun onCreate(): Boolean { PdfExportFixture.initialize(requireNotNull(context)); return true }
    override fun call(method: String, arg: String?, extras: Bundle?): Bundle {
        requireNotNull(context).enforceCallingOrSelfPermission("${PdfExportFixture.APP}.CONTROL", "PDF fixture control requires the probe signature")
        when (method) {
            "reset" -> PdfExportFixture.reset(extras ?: Bundle())
            "release" -> PdfExportFixture.release.countDown()
            "grant" -> {
                PdfExportFixture.events.add("test-grant")
                requireNotNull(context).grantUriPermission(PdfExportFixture.APP, PdfExportFixture.tree,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
            }
            "snapshot" -> Unit
            else -> error("Unknown fixture command: $method")
        }
        return Bundle().apply { putString("tree", PdfExportFixture.tree.toString()); putString("snapshot", PdfExportFixture.snapshot()) }
    }
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null
    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
}
