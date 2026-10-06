package com.daozhang.py.backup

import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import org.json.JSONArray
import org.json.JSONObject

class BackupException(val code: String, message: String) : Exception(message)

internal fun checkBackup(
    ok: Boolean,
    code: String = "INVALID_ARCHIVE",
    message: String = "Invalid backup archive",
) {
    if (!ok) throw BackupException(code, message)
}

internal fun operationPath(root: File, id: String): File {
    checkBackup(
        Regex("^[A-Za-z0-9_-]{1,100}$").matches(id),
        "INVALID_ARGUMENT",
        "Invalid operation ID",
    )
    val directory = File(root, "backup_operations")
    val operation = File(directory, id)
    checkBackup(
        !Files.isSymbolicLink(directory.toPath()) && !Files.isSymbolicLink(operation.toPath()),
        "UNSAFE_PATH",
        "Invalid temporary operation location",
    )
    checkBackup(
        operation.canonicalFile.toPath().startsWith(root.canonicalFile.toPath()),
        "UNSAFE_PATH",
        "Invalid temporary operation location",
    )
    return operation
}

internal fun safePath(path: String): String {
    checkBackup(
        path.isNotEmpty() &&
            path.length <= 4096 &&
            path.trim() == path &&
            !path.contains('\\') &&
            !path.contains(':') &&
            path.none { it.code < 32 || it.code == 127 } &&
            path.split('/').none { it.isEmpty() || it == "." || it == ".." }
    )
    checkBackup(path.split('/').all { it.toByteArray(Charsets.UTF_8).size <= 255 })
    return path
}

internal fun safeScript(name: String) {
    safePath(name)
    checkBackup(
        !name.contains('/') &&
            !name.endsWith('.') &&
            name.none { it in "<>\"|?*" } &&
            !Regex("(?i)^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\\..*)?$").matches(name)
    )
}

internal fun safeRoot(path: String): String {
    safePath(path)
    val parts = path.split('/')
    checkBackup(
        parts.size == 2 && parts[0] in setOf("scripts", "projects"),
        "INVALID_ARGUMENT",
        "Invalid restore root",
    )
    if (parts[0] == "projects") checkBackup(Regex("^[A-Za-z0-9_-]+$").matches(parts[1]))
    else safeScript(parts[1])
    return path
}

internal fun contained(root: File, path: String): File {
    safePath(path)
    val file = File(root, path)
    var current: File? = file
    while (current != null && current != root.parentFile) {
        checkBackup(
            !Files.isSymbolicLink(current.toPath()),
            "UNSAFE_PATH",
            "Symbolic links are not supported",
        )
        current = current.parentFile
    }
    checkBackup(
        file.canonicalFile.toPath().startsWith(root.canonicalFile.toPath()),
        "UNSAFE_PATH",
        "Invalid file location",
    )
    return file
}

internal fun removeOwned(file: File) {
    if (!file.exists() && !Files.isSymbolicLink(file.toPath())) return
    // Never follow a link during cleanup, including links planted by another app entry point.
    if (file.isDirectory && !Files.isSymbolicLink(file.toPath())) {
        (file.listFiles() ?: throw BackupException("IO_ERROR", "Cannot read temporary directory"))
            .forEach(::removeOwned)
    }
    checkBackup(file.delete(), "IO_ERROR", "Cannot remove temporary file")
}

/**
 * Directory sync is injected by Android (Os.fsync), since Java cannot open directory handles
 * portably on every host used by the JVM tests.
 */
internal class DurableFiles(private val syncDirectory: (File) -> Unit) {
    fun mkdir(file: File) {
        if (file.isDirectory) return
        file.parentFile?.let { mkdir(it) }
        checkBackup(file.mkdir(), "IO_ERROR", "Cannot create private directory")
        file.parentFile?.let(syncDirectory)
    }

    fun write(file: File, json: JSONObject) {
        mkdir(file.parentFile!!)
        val temp = File(file.parentFile, file.name + ".tmp")
        FileOutputStream(temp).use { out ->
            out.write(json.toString().toByteArray(Charsets.UTF_8))
            out.fd.sync()
        }
        Files.move(
            temp.toPath(),
            file.toPath(),
            StandardCopyOption.REPLACE_EXISTING,
            StandardCopyOption.ATOMIC_MOVE,
        )
        syncDirectory(file.parentFile!!)
    }

    fun move(source: File, target: File) {
        mkdir(target.parentFile!!)
        checkBackup(!target.exists(), "RESTORE_FAILED", "Restore target already exists")
        Files.move(source.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE)
        syncDirectory(source.parentFile!!)
        syncDirectory(target.parentFile!!)
    }

    fun delete(file: File) {
        removeOwned(file)
        syncDirectory(file.parentFile!!)
    }
}

internal fun JSONObject.toChannelMap(): Map<String, Any?> =
    keys().asSequence().associateWith { key -> jsonValue(get(key)) }

private fun jsonValue(value: Any?): Any? =
    when (value) {
        JSONObject.NULL -> null
        is JSONObject -> value.toChannelMap()
        is JSONArray -> (0 until value.length()).map { jsonValue(value.get(it)) }
        else -> value
    }

internal fun JSONArray.objects(): List<JSONObject> = (0 until length()).map { getJSONObject(it) }
