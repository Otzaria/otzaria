package org.otzaria.otzaria

import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest

internal object VerifiedApkStream {
    fun copy(input: InputStream, output: OutputStream, size: Long, sha256: String) {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(64 * 1024)
        var copied = 0L
        while (true) {
            if (Thread.currentThread().isInterrupted) throw IOException("Interrupted")
            val count = input.read(buffer)
            if (count < 0) break
            copied += count
            if (copied > size) throw ApkUpdateException("SIZE_MISMATCH")
            digest.update(buffer, 0, count)
            output.write(buffer, 0, count)
        }
        if (copied != size) throw ApkUpdateException("SIZE_MISMATCH")
        val hash = digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
        if (hash != sha256) throw ApkUpdateException("HASH_MISMATCH")
    }
}
