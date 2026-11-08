package org.otzaria.otzaria

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

class VerifiedApkStreamTest {
    private val original = ByteArray(256 * 1024 + 13) { (it % 251).toByte() }
    private val hash = MessageDigest.getInstance("SHA-256").digest(original)
        .joinToString("") { "%02x".format(it.toInt() and 255) }

    @Test fun copiesVerifiedBytesInBoundedChunks() {
        val output = ByteArrayOutputStream()
        VerifiedApkStream.copy(ByteArrayInputStream(original), output, original.size.toLong(), hash)
        assertArrayEquals(original, output.toByteArray())
    }

    @Test fun rejectsBytesChangedBetweenInspectionAndSessionCopy() {
        val changed = original.copyOf().apply { this[100] = (this[100] + 1).toByte() }
        rejected(changed, "HASH_MISMATCH")
    }

    @Test fun rejectsTruncatedAndGrowingFiles() {
        rejected(original.copyOf(original.size - 1), "SIZE_MISMATCH")
        rejected(original.copyOf(original.size + 1), "SIZE_MISMATCH")
    }

    private fun rejected(bytes: ByteArray, expected: String) {
        try {
            VerifiedApkStream.copy(ByteArrayInputStream(bytes), ByteArrayOutputStream(), original.size.toLong(), hash)
            fail("Unverified bytes must not reach commit")
        } catch (error: ApkUpdateException) {
            assertEquals(expected, error.code)
        }
    }
}
