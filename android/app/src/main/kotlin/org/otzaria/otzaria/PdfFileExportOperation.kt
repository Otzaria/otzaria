package org.otzaria.otzaria

import java.io.Closeable
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.atomic.AtomicReference

internal class PdfFileExportOperation(val id: String) {
    private enum class State { ACTIVE, CANCELLING, SAVED, CANCELLED, FAILED }
    private val state = AtomicReference(State.ACTIVE)

    val isCancelled: Boolean
        get() = state.get() == State.CANCELLING || state.get() == State.CANCELLED

    fun cancel(): Boolean {
        while (true) {
            when (val current = state.get()) {
                State.ACTIVE -> if (state.compareAndSet(current, State.CANCELLING)) return true
                State.CANCELLING -> return true
                else -> return false
            }
        }
    }

    fun throwIfCancelled() {
        if (isCancelled) throw PdfFileExportCancelled()
    }

    // גם ביטול מה־UI וגם סיום הכתיבה מכריעים באותו משתנה, לפני משלוח התוצאה.
    fun commitSaved(): Boolean = state.compareAndSet(State.ACTIVE, State.SAVED)

    fun finishUnsuccessful(): String {
        while (true) {
            when (val current = state.get()) {
                State.ACTIVE -> if (state.compareAndSet(current, State.FAILED)) return "failed"
                State.CANCELLING -> if (state.compareAndSet(current, State.CANCELLED)) return "cancelled"
                else -> error("PDF export already completed")
            }
        }
    }
}

internal class PdfFileExportCancelled : Exception("PDF export cancelled")

internal class PdfFileExportFailure(val code: String, message: String, cause: Exception? = null) :
    Exception(message, cause)

internal class PdfFileExportSource(val stream: InputStream, val length: Long) : Closeable {
    override fun close() = stream.close()
}

internal interface PdfFileExportStore {
    fun create(): String
    fun displayName(document: String): String?
    fun openOutput(document: String): OutputStream
    fun delete(document: String): Boolean
}

internal data class PdfFileExportTerminal(
    val operationId: String,
    val status: String,
    val documentUri: String? = null,
    val displayName: String? = null,
    val errorCode: String? = null,
    val errorMessage: String? = null,
    val residualDocument: String? = null,
    val residualDisplayName: String? = null,
    val cleanupStatus: String = "notNeeded",
    val cleanupError: String? = null,
) {
    fun toMap(): Map<String, Any?> = linkedMapOf(
        "version" to 1,
        "operationId" to operationId,
        "status" to status,
        "documentUri" to documentUri,
        "displayName" to displayName,
        "errorCode" to errorCode,
        "errorMessage" to errorMessage,
        "residualDocument" to residualDocument,
        "residualDisplayName" to residualDisplayName,
        "cleanupStatus" to cleanupStatus,
        "cleanupError" to cleanupError,
    )
}

internal object PdfFileExportWorker {
    const val BUFFER_SIZE = 64 * 1024

    fun export(
        operation: PdfFileExportOperation,
        openSource: () -> PdfFileExportSource,
        store: PdfFileExportStore,
    ): PdfFileExportTerminal {
        var ownedDocument: String? = null
        var displayName: String? = null
        var phase = "source_open_failed"
        val failure: Exception
        try {
            operation.throwIfCancelled()
            openSource().use { source ->
                operation.throwIfCancelled()
                phase = "create_failed"
                val created = store.create()
                ownedDocument = created
                displayName = verifiedName(store, created)
                operation.throwIfCancelled()
                phase = "write_failed"
                store.openOutput(created).use { output ->
                    copy(source, output, operation)
                    output.flush()
                    operation.throwIfCancelled()
                }
            }
            displayName = verifiedName(store, ownedDocument!!)
            if (operation.commitSaved()) {
                return PdfFileExportTerminal(operation.id, "saved", ownedDocument, displayName)
            }
            throw PdfFileExportCancelled()
        } catch (error: Exception) {
            failure = error
        }

        var cleanup = "notNeeded"
        var cleanupError: String? = null
        if (ownedDocument != null) {
            try {
                cleanup = if (store.delete(ownedDocument)) "deleted" else "failed"
                if (cleanup == "failed") cleanupError = "The document provider did not delete the partial copy"
            } catch (error: UnsupportedOperationException) {
                cleanup = "unsupported"
                cleanupError = error.message
            } catch (error: Exception) {
                cleanup = "failed"
                cleanupError = error.message ?: error.javaClass.simpleName
            }
        }
        if (failure is PdfFileExportFailure && failure.code in setOf("invalid_source", "source_changed")) {
            cleanupError = "staging_cleanup_failed: ${failure.message}" +
                (cleanupError?.let { "; target cleanup: $it" } ?: "")
        }
        val residual = ownedDocument.takeIf { cleanup != "deleted" }
        return PdfFileExportTerminal(
            operationId = operation.id,
            status = operation.finishUnsuccessful(),
            errorCode = when (failure) {
                is PdfFileExportCancelled -> null
                is PdfFileExportFailure -> failure.code
                else -> phase
            },
            errorMessage = if (failure is PdfFileExportCancelled) null else failure.message,
            residualDocument = residual,
            residualDisplayName = displayName.takeIf { residual != null },
            cleanupStatus = cleanup,
            cleanupError = cleanupError,
        )
    }

    private fun verifiedName(store: PdfFileExportStore, document: String): String? = try {
        store.displayName(document)?.takeIf { it.isNotEmpty() }
    } catch (_: Exception) { null }

    private fun copy(source: PdfFileExportSource, output: OutputStream, operation: PdfFileExportOperation) {
        val buffer = ByteArray(BUFFER_SIZE)
        var copied = 0L
        while (true) {
            operation.throwIfCancelled()
            val count = source.stream.read(buffer)
            if (count < 0) break
            if (count == 0) continue
            if (count.toLong() > source.length - copied) {
                throw PdfFileExportFailure("source_changed", "The staged PDF grew while being exported")
            }
            operation.throwIfCancelled()
            output.write(buffer, 0, count)
            copied += count
        }
        if (copied != source.length || copied == 0L) {
            throw PdfFileExportFailure("source_changed", "The staged PDF length changed while being exported")
        }
    }
}
