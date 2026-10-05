package com.daozhang.py.backup

import java.io.*
import java.nio.file.Files
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.atomic.AtomicBoolean
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.apache.commons.compress.archivers.zip.ZipFile
import org.json.JSONArray
import org.json.JSONObject

class BackupArchive(
    private val filesDir: File,
    private val progress: (String, String, Long, Long) -> Unit = { _, _, _, _ -> },
    private val maxBytes: Long = 8L * 1024 * 1024 * 1024,
    private val maxStructuralBytes: Long = BackupZipPreflight.MAX_METADATA_BYTES,
) {
    companion object {
        const val MARKER = ".python_runner_backup.json"
        const val MAX_MANIFEST = 16 * 1024 * 1024
        private val excluded =
            setOf(
                "__pycache__",
                ".pytest_cache",
                ".python_runner_sync",
                ".python_runner_linux_like",
            )
    }

    fun operationDir(id: String): File = operationPath(filesDir, id)

    fun payload(id: String): File = File(operationDir(id), "payload")

    private fun prepare(id: String): File {
        val op = operationDir(id)
        checkBackup(
            !File(op, "journal.json").exists(),
            "RECOVERY_REQUIRED",
            "Restore recovery required",
        )
        checkBackup(
            op.mkdirs() || op.isDirectory,
            "IO_ERROR",
            "Cannot create private staging directory",
        )
        return op
    }

    fun transferFile(id: String): File {
        val file = File(prepare(id), "transfer.zip")
        checkBackup(file.createNewFile(), "OPERATION_EXISTS", "Transfer already exists")
        return file
    }

    fun knownArchive(id: String, path: String): File {
        val root = operationDir(id)
        val file = File(path)
        checkBackup(
            file.parentFile?.canonicalFile == root.canonicalFile &&
                file.canonicalFile == file.absoluteFile &&
                (file.name == "transfer.zip" ||
                    Regex("^python-runner-backup-[A-Za-z0-9_-]+\\.zip$").matches(file.name)) &&
                file.isFile,
            "INVALID_ARGUMENT",
            "Archive is not an owned temporary file",
        )
        checkBackup(
            !Files.isSymbolicLink(file.toPath()),
            "UNSAFE_PATH",
            "Symbolic links are not supported",
        )
        return file
    }

    fun discard(id: String) {
        val op = operationDir(id)
        checkBackup(
            !File(op, "journal.json").exists(),
            "RECOVERY_REQUIRED",
            "Restore recovery required",
        )
        removeOwned(op)
    }

    /**
     * Caller must hold the global idle gate. Journals, including damaged ones, retain every file
     * needed by manual or automatic recovery.
     */
    fun cleanupAbandoned() {
        val root = operationDir("cleanup_probe").parentFile!!
        if (!root.exists()) return
        val children =
            root.listFiles()
                ?: throw BackupException("IO_ERROR", "Cannot inspect temporary operations")
        children.forEach { child ->
            if (!Regex("^[A-Za-z0-9_-]{1,100}$").matches(child.name)) return@forEach
            val owned = operationDir(child.name)
            if (!File(owned, "journal.json").exists()) removeOwned(owned)
        }
    }

    private data class Source(
        val path: String,
        val file: File,
        val directory: Boolean,
        val size: Long,
        val modified: Long,
    )

    fun create(id: String, metadata: JSONObject, cancel: AtomicBoolean): JSONObject = translate {
        val op = prepare(id)
        val manifest = JSONObject(metadata.toString())
        BackupManifestValidator.validate(manifest, false)
        val sources = mutableListOf<Source>()
        fun visit(path: String, file: File, project: Boolean) {
            cancelled(cancel)
            safePath(path)
            checkBackup(
                !Files.isSymbolicLink(file.toPath()),
                "UNSAFE_PATH",
                "Symbolic links are not supported",
            )
            checkBackup(
                file.exists() && (file.isFile || file.isDirectory),
                "SOURCE_MISSING",
                "Backup source is missing",
            )
            val directory = file.isDirectory
            sources.add(
                Source(
                    path,
                    file,
                    directory,
                    if (directory) 0 else file.length(),
                    file.lastModified(),
                )
            )
            checkBackup(sources.size <= 100000, "LIMIT_EXCEEDED", "Too many archive entries")
            progress(id, "scanning", sources.size.toLong(), 0)
            if (directory)
                (file.listFiles()
                        ?: throw BackupException("IO_ERROR", "Cannot read source directory"))
                    .sortedBy { it.name }
                    .forEach { child ->
                        if (!(project && child.isDirectory && child.name in excluded))
                            visit("$path/${child.name}", child, project)
                    }
        }
        manifest.getJSONArray("scripts").objects().forEach { s ->
            val name = s.getString("name")
            val file = contained(File(filesDir, "scripts"), name)
            checkBackup(file.isFile, "SOURCE_MISSING", "Backup script is missing")
            visit("scripts/$name", file, false)
        }
        manifest
            .getJSONArray("groups")
            .objects()
            .filter { it.getBoolean("isProject") }
            .forEach { g ->
                val key = g.getString("projectKey")
                val file = contained(File(filesDir, "script_projects"), key)
                checkBackup(file.isDirectory, "SOURCE_MISSING", "Backup project is missing")
                visit("projects/$key", file, true)
            }
        val total = sources.sumOf { it.size }
        checkBackup(total <= maxBytes, "LIMIT_EXCEEDED", "Archive is too large")
        space(op, total + MAX_MANIFEST)
        val date =
            SimpleDateFormat("yyyyMMdd'T'HHmmssSSS'Z'", Locale.US)
                .apply { timeZone = TimeZone.getTimeZone("UTC") }
                .format(Date())
        val file = File(op, "python-runner-backup-$date-${UUID.randomUUID()}.zip")
        try {
            val records = JSONArray()
            var completed = 0L
            FileOutputStream(file).use { fileOut ->
                ZipOutputStream(BufferedOutputStream(fileOut)).use { zip ->
                    sources.forEach { source ->
                        cancelled(cancel)
                        val entry = ZipEntry(source.path + if (source.directory) "/" else "")
                        entry.time = source.modified
                        zip.putNextEntry(entry)
                        val digest = MessageDigest.getInstance("SHA-256")
                        if (!source.directory)
                            source.file.inputStream().buffered().use { input ->
                                val copied =
                                    stream(input, zip, cancel, source.size) { buffer, count ->
                                        digest.update(buffer, 0, count)
                                        completed += count
                                        progress(id, "compressing", completed, total)
                                    }
                                checkBackup(
                                    copied == source.size,
                                    "SOURCE_CHANGED",
                                    "Source changed during backup",
                                )
                            }
                        zip.closeEntry()
                        records.put(
                            record(
                                source.path,
                                source.directory,
                                source.size,
                                if (source.directory) null else hex(digest.digest()),
                                source.modified,
                            )
                        )
                    }
                    sources.forEach {
                        checkBackup(
                            it.file.exists() &&
                                !Files.isSymbolicLink(it.file.toPath()) &&
                                it.file.lastModified() == it.modified &&
                                (it.directory || it.file.length() == it.size),
                            "SOURCE_CHANGED",
                            "Source changed during backup",
                        )
                    }
                    manifest.put("files", records)
                    BackupManifestValidator.validate(manifest)
                    val bytes = manifest.toString().toByteArray(Charsets.UTF_8)
                    checkBackup(
                        bytes.size <= MAX_MANIFEST,
                        "LIMIT_EXCEEDED",
                        "Backup metadata is too large",
                    )
                    zip.putNextEntry(ZipEntry(MARKER))
                    zip.write(bytes)
                    zip.closeEntry()
                    zip.finish()
                    zip.flush()
                    fileOut.fd.sync()
                }
            }
            cancelled(cancel)
            checkBackup(
                file.length() <= maxBytes,
                "LIMIT_EXCEEDED",
                "Archive exceeds input size limit",
            )
            BackupZipPreflight.inspect(file, cancel, maxMetadataBytes = maxStructuralBytes)
            JSONObject()
                .put("path", file.absolutePath)
                .put("fileName", file.name)
                .put("manifest", manifest)
        } catch (e: Throwable) {
            removeOwned(file)
            throw e
        }
    }

    fun stage(
        id: String,
        input: InputStream,
        displayName: String,
        cancel: AtomicBoolean,
    ): JSONObject = translate {
        val op = prepare(id)
        val archive = File(op, "input.zip")
        val destination = payload(id)
        checkBackup(
            !archive.exists() && !destination.exists(),
            "OPERATION_EXISTS",
            "Archive already staged",
        )
        try {
            input.use { source ->
                FileOutputStream(archive).use { out ->
                    var copied = 0L
                    stream(source, out, cancel, maxBytes) { _, n ->
                        copied += n
                        if (copied % (1024 * 1024) < n) space(op, 1024 * 1024L)
                        progress(id, "copying", copied, 0)
                    }
                    out.fd.sync()
                }
            }
            BackupZipPreflight.inspect(archive, cancel, maxMetadataBytes = maxStructuralBytes) {
                count ->
                progress(id, "scanning", count.toLong(), 0)
            }
            @Suppress("DEPRECATION")
            ZipFile(archive).use { zip ->
                val entries = zip.entries.asSequence().take(100002).toList()
                checkBackup(entries.size <= 100001, "LIMIT_EXCEEDED", "Too many archive entries")
                val paths = hashMapOf<String, Boolean>()
                var expanded = 0L
                entries.forEachIndexed { index, entry ->
                    cancelled(cancel)
                    // Commons Compress normalizes FAT backslashes when it
                    // creates entry.name. Inspect original central-header
                    // bytes as well so normalization cannot hide an unsafe path.
                    checkBackup(
                        entry.rawName.none {
                            val b = it.toInt() and 255
                            b == 92 || b == 0 || b < 32 || b == 127
                        }
                    )
                    checkBackup(
                        !entry.generalPurposeBit.usesEncryption() &&
                            !entry.isUnixSymlink &&
                            zip.canReadEntryData(entry)
                    )
                    val type = entry.unixMode and 61440
                    checkBackup(type == 0 || type == 32768 || type == 16384)
                    val path =
                        safePath(if (entry.isDirectory) entry.name.dropLast(1) else entry.name)
                    checkBackup(paths.put(path, entry.isDirectory) == null)
                    checkBackup(
                        entry.size >= 0 &&
                            entry.size <= maxBytes &&
                            (!entry.isDirectory || (entry.size == 0L && entry.crc == 0L)),
                        "LIMIT_EXCEEDED",
                        "Invalid archive entry size",
                    )
                    expanded += entry.size
                    checkBackup(
                        expanded <= maxBytes,
                        "LIMIT_EXCEEDED",
                        "Archive expands beyond size limit",
                    )
                    if (path == MARKER)
                        checkBackup(!entry.isDirectory && entry.size <= MAX_MANIFEST)
                    progress(id, "validating", index.toLong() + 1, entries.size.toLong())
                }
                paths.forEach { (path, _) ->
                    var parent = path.substringBeforeLast('/', "")
                    while (parent.isNotEmpty()) {
                        checkBackup(paths[parent] != false)
                        parent = parent.substringBeforeLast('/', "")
                    }
                }
                space(op, expanded)
                val marker = entries.firstOrNull { it.name == MARKER }
                val legacy = marker == null
                val manifest =
                    if (marker != null) {
                        val bytes = ByteArrayOutputStream()
                        zip.getInputStream(marker).use { source ->
                            readEntry(source, bytes, marker.size, marker.crc, cancel)
                        }
                        BackupManifestValidator.parse(bytes.toByteArray())
                    } else legacyMetadata(id, displayName)
                val declared =
                    if (legacy) emptyMap()
                    else
                        manifest.getJSONArray("files").objects().associateBy {
                            it.getString("path")
                        }
                val records = JSONArray()
                val seen = hashSetOf<String>()
                val legacyRoot = "projects/legacy_$id"
                checkBackup(destination.mkdirs(), "IO_ERROR", "Cannot create staging directory")
                if (legacy) {
                    contained(destination, legacyRoot).mkdirs()
                    records.put(record(legacyRoot, true, 0, null, System.currentTimeMillis()))
                }
                var completed = 0L
                entries.forEach { entry ->
                    if (entry.name == MARKER) return@forEach
                    cancelled(cancel)
                    val original = if (entry.isDirectory) entry.name.dropLast(1) else entry.name
                    if (
                        legacy && original.split('/').any { it == "__MACOSX" || it == ".DS_Store" }
                    ) {
                        zip.getInputStream(entry).use { source ->
                            readEntry(
                                source,
                                object : OutputStream() {
                                    override fun write(b: Int) {}

                                    override fun write(b: ByteArray, off: Int, len: Int) {}
                                },
                                entry.size,
                                entry.crc,
                                cancel,
                            )
                        }
                        return@forEach
                    }
                    val path = if (legacy) "$legacyRoot/$original" else original
                    val expected = declared[path]
                    if (!legacy)
                        checkBackup(
                            expected != null &&
                                expected.getBoolean("isDirectory") == entry.isDirectory &&
                                expected.getLong("size") == entry.size
                        )
                    val target = contained(destination, path)
                    val modified =
                        if (legacy) entry.time.coerceAtLeast(0)
                        else expected!!.getLong("modifiedAt")
                    val digest = MessageDigest.getInstance("SHA-256")
                    if (entry.isDirectory) {
                        checkBackup(
                            target.mkdirs() || target.isDirectory,
                            "IO_ERROR",
                            "Cannot create staged directory",
                        )
                    } else {
                        checkBackup(
                            target.parentFile!!.mkdirs() || target.parentFile!!.isDirectory,
                            "IO_ERROR",
                            "Cannot create staged directory",
                        )
                        FileOutputStream(target).use { out ->
                            zip.getInputStream(entry).use { source ->
                                readEntry(source, out, entry.size, entry.crc, cancel) { bytes, n ->
                                    digest.update(bytes, 0, n)
                                    completed += n
                                    progress(id, "staging", completed, expanded)
                                }
                            }
                            out.fd.sync()
                        }
                    }
                    val hash = if (entry.isDirectory) null else hex(digest.digest())
                    if (!legacy && !entry.isDirectory)
                        checkBackup(
                            expected!!.getString("sha256") == hash,
                            "HASH_MISMATCH",
                            "Backup checksum mismatch",
                        )
                    target.setLastModified(modified)
                    seen.add(path)
                    records.put(record(path, entry.isDirectory, entry.size, hash, modified))
                }
                if (!legacy)
                    checkBackup(
                        seen == declared.keys,
                        "INVALID_MANIFEST",
                        "Backup payload does not match metadata",
                    )
                else {
                    manifest.put("files", records)
                    BackupManifestValidator.validate(manifest)
                }
                // Files created later can change directory mtimes: restore these last.
                manifest
                    .getJSONArray("files")
                    .objects()
                    .filter { it.getBoolean("isDirectory") }
                    .asReversed()
                    .forEach {
                        contained(destination, it.getString("path"))
                            .setLastModified(it.getLong("modifiedAt"))
                    }
                File(op, "manifest.json").writeText(manifest.toString(), Charsets.UTF_8)
                cancelled(cancel)
                progress(id, "staging", expanded, expanded)
                JSONObject().put("manifest", manifest).put("legacy", legacy).put("stagingId", id)
            }
        } catch (e: Throwable) {
            removeOwned(destination)
            removeOwned(archive)
            throw e
        }
    }

    private fun legacyMetadata(id: String, displayName: String): JSONObject {
        val name =
            displayName
                .substringAfterLast('/')
                .substringBeforeLast('.', displayName)
                .replace(Regex("[\\x00-\\x1f\\x7f]"), "")
                .trim()
                .take(255)
                .ifEmpty { "Imported project" }
        val now = System.currentTimeMillis()
        val group =
            JSONObject()
                .put("id", 1)
                .put("name", name)
                .put("sortOrder", 0)
                .put("createdAt", now)
                .put("modifiedAt", now)
                .put("isProject", true)
                .put("projectKey", "legacy_$id")
                .put("mainFilePath", JSONObject.NULL)
                .put("homeSortOrder", 0)
        return JSONObject()
            .put("format", "python_runner_backup")
            .put("version", 1)
            .put("createdAt", now)
            .put("scripts", JSONArray())
            .put("groups", JSONArray().put(group))
    }

    private fun record(
        path: String,
        directory: Boolean,
        size: Long,
        hash: String?,
        modified: Long,
    ) =
        JSONObject()
            .put("path", path)
            .put("isDirectory", directory)
            .put("size", size)
            .put("sha256", hash ?: JSONObject.NULL)
            .put("modifiedAt", modified)

    private fun readEntry(
        input: InputStream,
        out: OutputStream,
        size: Long,
        crc: Long,
        cancel: AtomicBoolean,
        consume: (ByteArray, Int) -> Unit = { _, _ -> },
    ) {
        val check = CRC32()
        val count =
            stream(input, out, cancel, size) { bytes, n ->
                check.update(bytes, 0, n)
                consume(bytes, n)
            }
        checkBackup(count == size && check.value == crc, "CRC_MISMATCH", "Invalid ZIP checksum")
    }

    private fun stream(
        input: InputStream,
        out: OutputStream,
        cancel: AtomicBoolean,
        limit: Long,
        consume: (ByteArray, Int) -> Unit,
    ): Long {
        val buffer = ByteArray(64 * 1024)
        var count = 0L
        while (true) {
            cancelled(cancel)
            val n = input.read(buffer)
            if (n < 0) break
            if (n == 0) continue
            count += n
            checkBackup(count <= limit, "LIMIT_EXCEEDED", "Archive exceeds size limit")
            out.write(buffer, 0, n)
            consume(buffer, n)
        }
        return count
    }

    private fun space(directory: File, needed: Long) {
        checkBackup(
            directory.usableSpace >= needed + 8 * 1024 * 1024,
            "NO_SPACE",
            "Not enough free storage",
        )
    }

    private fun cancelled(cancel: AtomicBoolean) {
        checkBackup(!cancel.get(), "CANCELLED", "Backup operation cancelled")
    }

    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it.toInt() and 255) }

    private fun <T> translate(action: () -> T): T =
        try {
            action()
        } catch (e: BackupException) {
            throw e
        } catch (_: Exception) {
            throw BackupException("INVALID_ARCHIVE", "Cannot read or write backup archive")
        }
}
