package org.otzaria.otzaria

import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import android.system.StructStat
import java.io.File
import java.io.FileInputStream

internal class PdfFileExportStaging private constructor(
    private val root: File,
    private val directory: File,
    private val file: File,
    private val rootIdentity: StructStat,
    private val directoryIdentity: StructStat,
    private val fileIdentity: StructStat,
    private val input: FileInputStream,
) {
    fun source() = PdfFileExportSource(input, fileIdentity.st_size)

    // מחיקת עלה ידוע ותיקייה ריקה בלבד; החלפת זהות לעולם אינה הרשאה למחיקה.
    fun closeAndDelete() {
        input.close()
        requireIdentity(root, rootIdentity, directory = true)
        requireIdentity(directory, directoryIdentity, directory = true)
        val current = statOrMissing(file)
        if (current != null) {
            if (!sameIdentity(current, fileIdentity) || !OsConstants.S_ISREG(current.st_mode) ||
                current.st_nlink != 1L || current.st_size != fileIdentity.st_size) {
                throw PdfFileExportFailure("invalid_source", "The staged PDF identity changed before cleanup")
            }
            Os.remove(file.path)
        }
        requireIdentity(root, rootIdentity, directory = true)
        requireIdentity(directory, directoryIdentity, directory = true)
        Os.remove(directory.path)
    }

    companion object {
        fun acquire(cache: File, path: String, name: String, id: String): PdfFileExportStaging {
            val root = File(cache, "otzaria-pdf-exports-v1")
            val directory = File(root, id)
            val file = File(directory, name)
            if (path != file.path || file.canonicalPath != path) {
                throw PdfFileExportFailure("invalid_source", "The PDF is outside its export staging directory")
            }
            val rootIdentity = Os.lstat(root.path)
            val directoryIdentity = Os.lstat(directory.path)
            if (!OsConstants.S_ISDIR(rootIdentity.st_mode) || !OsConstants.S_ISDIR(directoryIdentity.st_mode)) {
                throw PdfFileExportFailure("invalid_source", "The export staging directory is not a directory")
            }
            val before = Os.lstat(path)
            if (!OsConstants.S_ISREG(before.st_mode) || before.st_nlink != 1L || before.st_size <= 0L) {
                throw PdfFileExportFailure("invalid_source", "The staged PDF must be a nonempty regular file")
            }
            // אם המקור הוחלף ב־FIFO, פתיחה רגילה תמתין לכותב לפני fstat.
            val flags = OsConstants.O_RDONLY or OsConstants.O_CLOEXEC or
                OsConstants.O_NOFOLLOW or OsConstants.O_NONBLOCK
            val descriptor = Os.open(path, flags, 0)
            try {
                val opened = Os.fstat(descriptor)
                if (!sameIdentity(opened, before) || opened.st_nlink != 1L || !OsConstants.S_ISREG(opened.st_mode)) {
                    throw PdfFileExportFailure("invalid_source", "The staged PDF changed before it could be opened")
                }
                requireIdentity(root, rootIdentity, directory = true)
                requireIdentity(directory, directoryIdentity, directory = true)
                val input = object : FileInputStream(descriptor) {
                    override fun close() {
                        try {
                            super.close()
                        } finally {
                            // באנדרואיד FileInputStream אינו הבעלים של מתאר שהועבר לבנאי.
                            if (descriptor.valid()) Os.close(descriptor)
                        }
                    }
                }
                return PdfFileExportStaging(root, directory, file, rootIdentity, directoryIdentity, opened, input)
            } catch (error: Exception) {
                try { Os.close(descriptor) } catch (closeError: Exception) { error.addSuppressed(closeError) }
                throw error
            }
        }

        private fun sameIdentity(first: StructStat, second: StructStat): Boolean =
            first.st_dev == second.st_dev && first.st_ino == second.st_ino

        private fun requireIdentity(file: File, expected: StructStat, directory: Boolean) {
            val actual = Os.lstat(file.path)
            if (!sameIdentity(actual, expected) || (directory && !OsConstants.S_ISDIR(actual.st_mode))) {
                throw PdfFileExportFailure("invalid_source", "The export staging directory identity changed")
            }
        }

        private fun statOrMissing(file: File): StructStat? = try {
            Os.lstat(file.path)
        } catch (error: ErrnoException) {
            if (error.errno == OsConstants.ENOENT) null else throw error
        }
    }
}
