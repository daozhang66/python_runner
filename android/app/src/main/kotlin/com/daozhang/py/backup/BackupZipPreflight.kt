package com.daozhang.py.backup

import java.io.File
import java.io.RandomAccessFile
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Bounds Commons Compress's eager central/local-header allocation before it sees untrusted input.
 * Traversal uses fixed buffers and actual records, not the EOCD's advertised entry count. ZIP64
 * sizes and offsets stay 64-bit.
 */
internal object BackupZipPreflight {
    const val MAX_METADATA_BYTES = 32L * 1024 * 1024
    private const val MAX_PAYLOAD_BYTES = 8L * 1024 * 1024 * 1024

    data class Statistics(val entryCount: Int, val metadataBytes: Long)

    fun inspect(
        file: File,
        cancel: AtomicBoolean,
        maxEntries: Int = 100001,
        maxMetadataBytes: Long = MAX_METADATA_BYTES,
        onEntry: (Int) -> Unit = {},
    ): Statistics {
        fun cancellation() {
            checkBackup(!cancel.get(), "CANCELLED", "Backup operation cancelled")
        }
        try {
            cancellation()
            RandomAccessFile(file, "r").use { input ->
                val length = input.length()
                checkBackup(length >= 22)
                val tail = ByteArray(minOf(length, 65557L).toInt())
                input.seek(length - tail.size)
                input.readFully(tail)
                var eocd = -1
                // Commons Compress 1.26.2 searches [EOF-22, EOF-65557]
                // backwards and selects the first signature without checking
                // comment length. Select precisely that same record, then
                // validate it. Never fall back to an earlier valid-looking
                // EOCD: the constructor would still follow the later one.
                for (index in tail.size - 22 downTo 0) {
                    if (u32(tail, index) == 0x06054b50L) {
                        eocd = index
                        break
                    }
                }
                checkBackup(eocd >= 0)
                checkBackup(eocd + 22 + u16(tail, eocd + 20) == tail.size)
                checkBackup(u16(tail, eocd + 4) == 0 && u16(tail, eocd + 6) == 0)
                checkBackup(u16(tail, eocd + 8) == u16(tail, eocd + 10))
                val eocdOffset = length - tail.size + eocd
                var declaredCount = u16(tail, eocd + 10).toLong()
                var centralSize = u32(tail, eocd + 12)
                var centralOffset = u32(tail, eocd + 16)
                var footerOffset = eocdOffset
                var metadataBytes = length - eocdOffset
                val locator = ByteArray(20)
                val hasLocator =
                    // The pinned parser tests locator presence independently
                    // of classic sentinel fields, and only at positions > 20.
                    if (eocdOffset > 20) {
                        input.seek(eocdOffset - 20)
                        input.readFully(locator)
                        u32(locator, 0) == 0x07064b50L
                    } else false
                if (hasLocator) {
                    checkBackup(u32(locator, 4) == 0L && u32(locator, 16) == 1L)
                    val zip64Offset = u64(locator, 8)
                    checkBackup(zip64Offset <= eocdOffset - 20 - 56)
                    val zip64 = ByteArray(56)
                    input.seek(zip64Offset)
                    input.readFully(zip64)
                    checkBackup(u32(zip64, 0) == 0x06064b50L)
                    val recordSize = u64(zip64, 4)
                    checkBackup(
                        recordSize >= 44 && recordSize <= eocdOffset - 20 - zip64Offset - 12
                    )
                    checkBackup(zip64Offset + 12 + recordSize == eocdOffset - 20)
                    checkBackup(u32(zip64, 16) == 0L && u32(zip64, 20) == 0L)
                    declaredCount = u64(zip64, 32)
                    checkBackup(u64(zip64, 24) == declaredCount)
                    centralSize = u64(zip64, 40)
                    centralOffset = u64(zip64, 48)
                    footerOffset = zip64Offset
                    metadataBytes = length - zip64Offset
                } else
                    checkBackup(
                        declaredCount != 65535L &&
                            centralSize != 0xffffffffL &&
                            centralOffset != 0xffffffffL
                    )
                checkBackup(
                    centralOffset <= footerOffset && centralSize <= footerOffset - centralOffset
                )
                checkBackup(centralOffset + centralSize == footerOffset)
                // For ZIP32 this equality also forces Commons' inferred
                // leading-data adjustment to zero. Both readers start at the
                // same centralOffset and stop on the same non-CFH footer.
                checkBackup(
                    metadataBytes <= maxMetadataBytes,
                    "LIMIT_EXCEEDED",
                    "ZIP structural metadata exceeds 32 MiB",
                )
                val central = ByteArray(46)
                val local = ByteArray(30)
                val centralName = ByteArray(4097)
                val localName = ByteArray(4097)
                val extra = ByteArray(65535)
                var position = centralOffset
                var count = 0
                var payloadBytes = 0L
                while (position < footerOffset) {
                    cancellation()
                    checkBackup(footerOffset - position >= 46)
                    input.seek(position)
                    input.readFully(central)
                    checkBackup(u32(central, 0) == 0x02014b50L)
                    count++
                    checkBackup(count <= maxEntries, "LIMIT_EXCEEDED", "Too many archive entries")
                    val nameLength = u16(central, 28)
                    val extraLength = u16(central, 30)
                    val commentLength = u16(central, 32)
                    checkBackup(
                        nameLength in 1..4097,
                        "LIMIT_EXCEEDED",
                        "ZIP entry name is too long",
                    )
                    val centralRecordSize = 46L + nameLength + extraLength + commentLength
                    checkBackup(centralRecordSize <= footerOffset - position)
                    metadataBytes += centralRecordSize
                    checkBackup(
                        metadataBytes <= maxMetadataBytes,
                        "LIMIT_EXCEEDED",
                        "ZIP structural metadata exceeds 32 MiB",
                    )
                    input.readFully(centralName, 0, nameLength)
                    input.readFully(extra, 0, extraLength)
                    var compressed = u32(central, 20)
                    var uncompressed = u32(central, 24)
                    var localOffset = u32(central, 42)
                    var disk = u16(central, 34).toLong()
                    val needsZip64 =
                        compressed == 0xffffffffL ||
                            uncompressed == 0xffffffffL ||
                            localOffset == 0xffffffffL ||
                            disk == 65535L
                    var foundZip64 = false
                    var extraPosition = 0
                    while (extraPosition < extraLength) {
                        checkBackup(extraLength - extraPosition >= 4)
                        val tag = u16(extra, extraPosition)
                        val size = u16(extra, extraPosition + 2)
                        val end = extraPosition + 4 + size
                        checkBackup(end <= extraLength)
                        if (tag == 1 && needsZip64) {
                            checkBackup(!foundZip64)
                            foundZip64 = true
                            var p = extraPosition + 4
                            fun next64(): Long {
                                checkBackup(end - p >= 8)
                                val value = u64(extra, p)
                                p += 8
                                return value
                            }
                            if (uncompressed == 0xffffffffL) uncompressed = next64()
                            if (compressed == 0xffffffffL) compressed = next64()
                            if (localOffset == 0xffffffffL) localOffset = next64()
                            if (disk == 65535L) {
                                checkBackup(end - p >= 4)
                                disk = u32(extra, p)
                            }
                        }
                        extraPosition = end
                    }
                    checkBackup(!needsZip64 || foundZip64)
                    checkBackup(disk == 0L)
                    checkBackup(
                        uncompressed <= MAX_PAYLOAD_BYTES - payloadBytes,
                        "LIMIT_EXCEEDED",
                        "Archive expands beyond size limit",
                    )
                    payloadBytes += uncompressed
                    checkBackup(localOffset <= centralOffset && centralOffset - localOffset >= 30)
                    input.seek(localOffset)
                    input.readFully(local)
                    checkBackup(u32(local, 0) == 0x04034b50L)
                    val localNameLength = u16(local, 26)
                    val localExtraLength = u16(local, 28)
                    checkBackup(localNameLength == nameLength)
                    val localRecordSize = 30L + localNameLength + localExtraLength
                    checkBackup(localRecordSize <= centralOffset - localOffset)
                    checkBackup(compressed <= centralOffset - localOffset - localRecordSize)
                    metadataBytes += localRecordSize
                    checkBackup(
                        metadataBytes <= maxMetadataBytes,
                        "LIMIT_EXCEEDED",
                        "ZIP structural metadata exceeds 32 MiB",
                    )
                    input.readFully(localName, 0, localNameLength)
                    for (index in 0 until nameLength) checkBackup(
                        localName[index] == centralName[index]
                    )
                    position += centralRecordSize
                    onEntry(count)
                }
                cancellation()
                checkBackup(count.toLong() == declaredCount)
                return Statistics(count, metadataBytes)
            }
        } catch (e: BackupException) {
            throw e
        } catch (_: Exception) {
            throw BackupException("INVALID_ARCHIVE", "Invalid ZIP structure")
        }
    }

    private fun u16(bytes: ByteArray, index: Int): Int =
        (bytes[index].toInt() and 255) or ((bytes[index + 1].toInt() and 255) shl 8)

    private fun u32(bytes: ByteArray, index: Int): Long =
        u16(bytes, index).toLong() or (u16(bytes, index + 2).toLong() shl 16)

    private fun u64(bytes: ByteArray, index: Int): Long {
        val high = u32(bytes, index + 4)
        checkBackup(high <= 0x7fffffffL)
        return u32(bytes, index) or (high shl 32)
    }
}
