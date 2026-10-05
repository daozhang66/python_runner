package com.daozhang.py.backup

import java.io.File
import java.io.RandomAccessFile
import java.util.concurrent.atomic.AtomicBoolean
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.apache.commons.compress.archivers.zip.Zip64Mode
import org.apache.commons.compress.archivers.zip.ZipArchiveEntry
import org.apache.commons.compress.archivers.zip.ZipArchiveOutputStream
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class BackupZipPreflightTest {
    @get:Rule val temp = TemporaryFolder()

    private fun zip(count: Int, extra: ByteArray? = null, comment: String? = null): File {
        val file = File(temp.root, "input.zip")
        ZipOutputStream(file.outputStream().buffered()).use { out ->
            if (comment != null) out.setComment(comment)
            repeat(count) { index ->
                val entry =
                    ZipEntry("file$index").apply {
                        method = ZipEntry.STORED
                        size = 0
                        compressedSize = 0
                        crc = 0
                        this.extra = extra
                    }
                out.putNextEntry(entry)
                out.closeEntry()
            }
        }
        return file
    }

    @Test
    fun competingEocdInsideCommentCannotSelectAnUnboundedDirectory() {
        val file = zip(4)
        val bytes = file.readBytes()
        val originalEnd = bytes.size - 22
        fun read32(offset: Int): Int =
            (0..3).sumOf { (bytes[offset + it].toInt() and 255) shl (8 * it) }
        val originalCentral = read32(originalEnd + 16)
        val extraHeader = bytes.copyOfRange(originalCentral, originalCentral + 46 + "file0".length)
        val extraOffset = originalEnd
        val realEocdOffset = extraOffset + extraHeader.size
        val fakeEocdOffset = realEocdOffset + 22
        file.outputStream().use { output ->
            output.write(bytes, 0, originalEnd)
            output.write(extraHeader)
            output.write(eocd(1, extraHeader.size, extraOffset, 23))
            output.write(eocd(5, fakeEocdOffset - originalCentral, originalCentral, 0))
            output.write(0)
        }
        // Characterize the pinned dependency only with this tiny trusted fixture:
        // its constructor chooses the fake signature, ignoring comment length.
        assertEquals(5, commonsCount(file))
        assertEquals(
            "INVALID_ARCHIVE",
            failure { BackupZipPreflight.inspect(file, AtomicBoolean(false), maxEntries = 3) }.code,
        )
    }

    @Test
    fun ordinaryCommentsAndSignaturesOutsideCommonsSearchRemainValid() {
        for (comment in
            listOf("normal Unicode 备份", "prefix PK\u0005\u0006 short", "x".repeat(65535))) {
            val file = zip(2, comment = comment)
            assertEquals(2, BackupZipPreflight.inspect(file, AtomicBoolean(false)).entryCount)
            assertEquals(2, commonsCount(file))
        }
    }

    @Test
    fun optionalZip64LocatorWinsEvenWithoutClassicSentinelFields() {
        val file = File(temp.root, "optional64.zip")
        ZipArchiveOutputStream(file).use { output ->
            output.setUseZip64(Zip64Mode.Always)
            output.setComment("normal ZIP64 comment")
            repeat(4) { index ->
                output.putArchiveEntry(ZipArchiveEntry("item$index"))
                output.closeArchiveEntry()
            }
        }
        // Commons checks the locator independently of classic sentinel values.
        // Make classic fields describe zero entries while retaining valid ZIP64.
        RandomAccessFile(file, "rw").use { input ->
            val eocdOffset = input.length() - 22 - "normal ZIP64 comment".length
            input.seek(eocdOffset + 8)
            input.write(ByteArray(12))
        }
        assertEquals(4, commonsCount(file))
        assertEquals(
            "LIMIT_EXCEEDED",
            failure { BackupZipPreflight.inspect(file, AtomicBoolean(false), maxEntries = 3) }.code,
        )
        assertEquals(4, BackupZipPreflight.inspect(file, AtomicBoolean(false)).entryCount)
    }

    private fun eocd(count: Int, size: Int, offset: Int, comment: Int): ByteArray =
        java.nio.ByteBuffer.allocate(22)
            .order(java.nio.ByteOrder.LITTLE_ENDIAN)
            .putInt(0x06054b50)
            .putShort(0)
            .putShort(0)
            .putShort(count.toShort())
            .putShort(count.toShort())
            .putInt(size)
            .putInt(offset)
            .putShort(comment.toShort())
            .array()

    @Suppress("DEPRECATION")
    private fun commonsCount(file: File): Int =
        org.apache.commons.compress.archivers.zip.ZipFile(file).use {
            it.entries.asSequence().count()
        }

    @Test
    fun actualRecordsOverrideDishonestEocdCount() {
        val file = zip(4)
        RandomAccessFile(file, "rw").use { f ->
            f.seek(f.length() - 22 + 8)
            f.write(byteArrayOf(1, 0, 1, 0))
        }
        val error = failure {
            BackupZipPreflight.inspect(file, AtomicBoolean(false), maxEntries = 3)
        }
        assertEquals("LIMIT_EXCEEDED", error.code)
    }

    @Test
    fun overHundredThousandActualEntriesRejectBeforeZipReaderAllocation() {
        val error = failure { BackupZipPreflight.inspect(zip(100002), AtomicBoolean(false)) }
        assertEquals("LIMIT_EXCEEDED", error.code)
    }

    @Test
    fun zip64Over65535EntriesAndForcedZip64OffsetsAreAccepted() {
        assertEquals(65536, BackupZipPreflight.inspect(zip(65536), AtomicBoolean(false)).entryCount)
        val file = File(temp.root, "forced.zip")
        ZipArchiveOutputStream(file).use { out ->
            out.setUseZip64(Zip64Mode.Always)
            out.putArchiveEntry(ZipArchiveEntry("main.py"))
            out.write("print(1)".toByteArray())
            out.closeArchiveEntry()
        }
        assertEquals(1, BackupZipPreflight.inspect(file, AtomicBoolean(false)).entryCount)
        assertTrue(
            BackupArchive(temp.root)
                .stage("forced", file.inputStream(), "forced.zip", AtomicBoolean(false))
                .getBoolean("legacy")
        )
    }

    @Test
    fun aggregateLocalAndCentralMetadataBudgetIsEnforced() {
        val extra =
            ByteArray(400).apply {
                this[0] = 0xfe.toByte()
                this[1] = 0xca.toByte()
                this[2] = 0x8c.toByte()
                this[3] = 1
            }
        val file = zip(2, extra)
        // Central headers alone are under 1200 bytes; their referenced local
        // headers repeat the extra fields and exceed the combined budget.
        assertEquals(
            "LIMIT_EXCEEDED",
            failure {
                    BackupZipPreflight.inspect(file, AtomicBoolean(false), maxMetadataBytes = 1200)
                }
                .code,
        )
        assertEquals(
            2,
            BackupZipPreflight.inspect(file, AtomicBoolean(false), maxMetadataBytes = 2048)
                .entryCount,
        )
    }

    @Test
    fun preflightCancellationStopsDuringActualRecordTraversal() {
        val cancel = AtomicBoolean(false)
        var visited = 0
        val error = failure {
            BackupZipPreflight.inspect(
                zip(30),
                cancel,
                onEntry = {
                    visited = it
                    if (it == 17) cancel.set(true)
                },
            )
        }
        assertEquals("CANCELLED", error.code)
        assertEquals(17, visited)
    }

    @Test
    fun overflowingOrOverlappingCentralBoundsReject() {
        val file = zip(1)
        RandomAccessFile(file, "rw").use { f ->
            f.seek(f.length() - 22 + 16)
            f.write(byteArrayOf(-1, -1, -1, 0x7f))
        }
        assertEquals(
            "INVALID_ARCHIVE",
            failure { BackupZipPreflight.inspect(file, AtomicBoolean(false)) }.code,
        )
    }

    private fun failure(block: () -> Unit): BackupException {
        try {
            block()
            fail("ZIP must reject")
        } catch (e: BackupException) {
            return e
        }
        throw AssertionError()
    }
}
