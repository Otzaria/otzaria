package org.otzaria.otzaria

import java.io.ByteArrayInputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.CyclicBarrier
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class PdfFileExportOperationTest {
    private val id = "0123456789abcdef0123456789abcdef"

    private class Store : PdfFileExportStore {
        val events = mutableListOf<String>()
        var onCreate: () -> String = { "content://fixture/new-copy" }
        var onOpen: () -> OutputStream = { object : OutputStream() { override fun write(value: Int) {} } }
        var onDelete: () -> Boolean = { true }
        var onName: () -> String? = { "עותק (2).pdf" }

        override fun create(): String { events.add("create"); return onCreate() }
        override fun displayName(document: String): String? = onName()
        override fun openOutput(document: String): OutputStream { events.add("open"); return onOpen() }
        override fun delete(document: String): Boolean { events.add("delete"); return onDelete() }
    }

    private fun source(store: Store, bytes: ByteArray = byteArrayOf(1, 2, 3)): PdfFileExportSource =
        PdfFileExportSource(object : ByteArrayInputStream(bytes) {
            override fun close() { store.events.add("source-close"); super.close() }
        }, bytes.size.toLong())

    @Test fun streamsInBoundedBlocksAndClosesBeforeSaved() {
        val store = Store()
        val size = 16L * 1024 * 1024 + 13
        var position = 0L
        var written = 0L
        var largestRead = 0
        var largestWrite = 0
        val input = object : InputStream() {
            override fun read(): Int = error("bulk reads required")
            override fun read(buffer: ByteArray, offset: Int, count: Int): Int {
                if (position == size) return -1
                largestRead = maxOf(largestRead, count)
                val length = minOf(count.toLong(), size - position).toInt()
                for (index in 0 until length) buffer[offset + index] = ((position + index) % 251).toByte()
                position += length
                return length
            }
            override fun close() { store.events.add("source-close") }
        }
        store.onOpen = { object : OutputStream() {
            override fun write(value: Int) = error("bulk writes required")
            override fun write(buffer: ByteArray, offset: Int, count: Int) {
                largestWrite = maxOf(largestWrite, count)
                for (index in 0 until count) assertEquals(((written + index) % 251).toByte(), buffer[offset + index])
                written += count
            }
            override fun close() { store.events.add("output-close") }
        } }
        val operation = PdfFileExportOperation(id)
        val result = PdfFileExportWorker.export(operation, { PdfFileExportSource(input, size) }, store)
        assertEquals("saved", result.status)
        assertEquals(size, written)
        assertEquals(65536, largestRead)
        assertEquals(65536, largestWrite)
        assertEquals(listOf("create", "open", "output-close", "source-close"), store.events)
        assertEquals("עותק (2).pdf", result.displayName)
        assertEquals("notNeeded", result.cleanupStatus)
        assertFalse(operation.cancel())
    }

    @Test fun sourceFailureNeverCreatesAnExternalDocument() {
        val store = Store()
        val result = PdfFileExportWorker.export(PdfFileExportOperation(id), { throw IOException("source unavailable") }, store)
        assertEquals("failed", result.status)
        assertEquals("source_open_failed", result.errorCode)
        assertTrue(store.events.isEmpty())
        assertNull(result.residualDocument)
    }

    @Test fun cancellationBeforeStartNeverOpensTheSource() {
        val operation = PdfFileExportOperation(id)
        assertTrue(operation.cancel())
        val result = PdfFileExportWorker.export(operation, { error("must not open") }, Store())
        assertEquals("cancelled", result.status)
        assertEquals("notNeeded", result.cleanupStatus)
        assertFalse(operation.cancel())
    }

    @Test fun cancellationDuringCreateOwnsAndCleansTheReturnedDocument() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val store = Store()
        val operation = PdfFileExportOperation(id)
        store.onCreate = {
            entered.countDown()
            assertTrue(release.await(5, TimeUnit.SECONDS))
            "content://fixture/created-after-cancel"
        }
        val executor = Executors.newSingleThreadExecutor()
        val task = executor.submit<PdfFileExportTerminal> { PdfFileExportWorker.export(operation, { source(store) }, store) }
        try {
            assertTrue(entered.await(5, TimeUnit.SECONDS))
            assertTrue(operation.cancel())
            assertFalse(task.isDone)
            release.countDown()
            val result = task.get(5, TimeUnit.SECONDS)
            assertEquals("cancelled", result.status)
            assertEquals("deleted", result.cleanupStatus)
            assertEquals(listOf("create", "source-close", "delete"), store.events)
        } finally {
            release.countDown()
            try { task.get(5, TimeUnit.SECONDS) } finally { executor.shutdownNow() }
        }
    }

    @Test fun cancellationDuringWriteWaitsForBothClosesBeforeDeleting() {
        val operation = PdfFileExportOperation(id)
        val store = Store()
        var writes = 0
        store.onOpen = { object : OutputStream() {
            override fun write(value: Int) { writes++; assertTrue(operation.cancel()) }
            override fun close() { store.events.add("output-close") }
        } }
        val result = PdfFileExportWorker.export(operation, { source(store, ByteArray(131072)) }, store)
        assertEquals("cancelled", result.status)
        assertEquals(65536, writes)
        assertEquals(listOf("create", "open", "output-close", "source-close", "delete"), store.events)
        assertEquals("deleted", result.cleanupStatus)
    }

    @Test fun failedOutputOpenStillDeletesOnlyTheNewDocument() {
        val store = Store()
        store.onOpen = { throw IOException("cannot open") }
        val result = PdfFileExportWorker.export(PdfFileExportOperation(id), { source(store) }, store)
        assertEquals("write_failed", result.errorCode)
        assertEquals("deleted", result.cleanupStatus)
        assertEquals(listOf("create", "open", "source-close", "delete"), store.events)
    }

    @Test fun createFailureClosesSourceWithoutAttemptingUnownedCleanup() {
        val store = Store()
        store.onCreate = { throw IOException("create denied") }
        val result = PdfFileExportWorker.export(PdfFileExportOperation(id), { source(store) }, store)
        assertEquals("create_failed", result.errorCode)
        assertEquals(listOf("create", "source-close"), store.events)
        assertEquals("notNeeded", result.cleanupStatus)
    }

    @Test fun writeFailureSurvivesSecondaryCloseAndCleanupFailures() {
        val store = Store()
        store.onOpen = { object : OutputStream() {
            override fun write(value: Int) { throw IOException("original write failure") }
            override fun close() { store.events.add("output-close"); throw IOException("secondary close failure") }
        } }
        store.onDelete = { throw SecurityException("delete denied") }
        val result = PdfFileExportWorker.export(PdfFileExportOperation(id), { source(store) }, store)
        assertEquals("original write failure", result.errorMessage)
        assertEquals("failed", result.cleanupStatus)
        assertEquals("delete denied", result.cleanupError)
        assertEquals("content://fixture/new-copy", result.residualDocument)
        assertEquals("עותק (2).pdf", result.residualDisplayName)
        assertEquals(listOf("create", "open", "output-close", "source-close", "delete"), store.events)
    }

    @Test fun outputCloseFailureCannotCommitSaved() {
        val store = Store()
        store.onOpen = { object : OutputStream() {
            override fun write(value: Int) {}
            override fun close() { throw IOException("close failed") }
        } }
        val result = PdfFileExportWorker.export(PdfFileExportOperation(id), { source(store) }, store)
        assertEquals("failed", result.status)
        assertEquals("close failed", result.errorMessage)
        assertEquals("deleted", result.cleanupStatus)
    }

    @Test fun unsupportedCleanupReportsTheOwnedPartialDocumentAfterCancel() {
        val operation = PdfFileExportOperation(id)
        val store = Store()
        store.onOpen = { operation.cancel(); object : OutputStream() { override fun write(value: Int) {} } }
        store.onDelete = { throw UnsupportedOperationException("delete unavailable") }
        val result = PdfFileExportWorker.export(operation, { source(store) }, store)
        assertEquals("cancelled", result.status)
        assertEquals("unsupported", result.cleanupStatus)
        assertNotNull(result.residualDocument)
        assertEquals("עותק (2).pdf", result.residualDisplayName)
    }

    @Test fun falseCleanupRetainsTheUriAndDoesNotInventAName() {
        val store = Store()
        store.onName = { throw IOException("query denied") }
        store.onOpen = { throw IOException("open failed") }
        store.onDelete = { false }
        val result = PdfFileExportWorker.export(PdfFileExportOperation(id), { source(store) }, store)
        assertEquals("failed", result.cleanupStatus)
        assertNotNull(result.residualDocument)
        assertNull(result.residualDisplayName)
    }

    @Test fun providerNameIsOptionalOnSuccess() {
        val store = Store()
        store.onName = { null }
        val result = PdfFileExportWorker.export(PdfFileExportOperation(id), { source(store) }, store)
        assertEquals("saved", result.status)
        assertNull(result.displayName)
    }

    @Test fun savedUsesTheProviderNameObservedAfterClose() {
        val store = Store()
        var currentName = "before-close.pdf"
        store.onName = { currentName }
        store.onOpen = { object : OutputStream() {
            override fun write(value: Int) {}
            override fun close() { currentName = "after-close.pdf" }
        } }
        val result = PdfFileExportWorker.export(PdfFileExportOperation(id), { source(store) }, store)
        assertEquals("saved", result.status)
        assertEquals("after-close.pdf", result.displayName)
    }

    @Test fun changedSourceLengthCannotPublishSaved() {
        for (declared in listOf(2L, 4L)) {
            val store = Store()
            val result = PdfFileExportWorker.export(PdfFileExportOperation(id),
                { PdfFileExportSource(ByteArrayInputStream(byteArrayOf(1, 2, 3)), declared) }, store)
            assertEquals("source_changed", result.errorCode)
            assertEquals("deleted", result.cleanupStatus)
        }
    }

    @Test fun cancelAndSavedShareOneAtomicDecision() {
        val executor = Executors.newFixedThreadPool(2)
        try {
            repeat(100) {
                val operation = PdfFileExportOperation(id)
                val barrier = CyclicBarrier(2)
                val cancel = executor.submit<Boolean> { barrier.await(5, TimeUnit.SECONDS); operation.cancel() }
                val commit = executor.submit<Boolean> { barrier.await(5, TimeUnit.SECONDS); operation.commitSaved() }
                val accepted = cancel.get(5, TimeUnit.SECONDS)
                val saved = commit.get(5, TimeUnit.SECONDS)
                assertNotEquals(accepted, saved)
                if (accepted) assertEquals("cancelled", operation.finishUnsuccessful())
                assertFalse(operation.cancel())
            }
        } finally { executor.shutdownNow() }
    }
}
