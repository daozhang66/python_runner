package com.daozhang.py

import android.content.ContentResolver
import android.net.Uri
import android.os.Environment
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader

class NativeFileOperations(
    private val filesDir: File,
    private val contentResolver: ContentResolver,
    private val scriptFileStore: ScriptFileStore,
    private val externalFilesDir: File? = null,
    private val obbDir: File? = null
) {
    private val protectedSystemPrefixes = listOf(
        "/system",
        "/proc",
        "/sys",
        "/dev",
    )

    fun importScriptFromUri(uriString: String, name: String): Map<String, Any> {
        val uri = Uri.parse(uriString)
        val inputStream = contentResolver.openInputStream(uri)
            ?: throw IllegalArgumentException("无法读取文件")
        val content = BufferedReader(InputStreamReader(inputStream)).use { it.readText() }
        val targetFile = scriptFileStore.safeScriptFile(name)
        targetFile.writeText(content)
        return mapOf("name" to name, "path" to targetFile.absolutePath)
    }

    fun exportLog(content: String, fileName: String, destDir: String?): String {
        return try {
            val appDir = if (!destDir.isNullOrBlank()) {
                File(destDir)
            } else {
                val downloadsDir =
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                File(downloadsDir, "PythonRunner")
            }
            if (!appDir.exists()) appDir.mkdirs()
            val safeName = if (fileName.isBlank()) "log.txt" else fileName
            val file = File(appDir, safeName)
            file.writeText(content)
            file.absolutePath
        } catch (_: Exception) {
            val logsDir = File(filesDir, "logs")
            if (!logsDir.exists()) logsDir.mkdirs()
            val file = File(logsDir, fileName)
            file.writeText(content)
            file.absolutePath
        }
    }

    fun exportScript(name: String, destDir: String?): String {
        val srcFile = scriptFileStore.safeScriptFile(name)
        require(srcFile.exists()) { "脚本不存在 $name" }
        val targetDir = if (!destDir.isNullOrBlank()) {
            File(destDir)
        } else {
            File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                "PythonRunner"
            )
        }
        if (!targetDir.exists()) targetDir.mkdirs()
        val destFile = File(targetDir, name)
        srcFile.copyTo(destFile, overwrite = true)
        return destFile.absolutePath
    }

    fun getFilePickerRoots(): List<Map<String, Any>> {
        val roots = linkedMapOf<String, Map<String, Any>>()
        fun addRoot(name: String, file: File?) {
            if (file == null) return
            val path = try {
                file.canonicalPath
            } catch (_: Exception) {
                file.absolutePath
            }
            if (path.isBlank() || !file.exists()) return
            roots[path] = appFileEntryMap(file, name)
        }

        val externalRoot = Environment.getExternalStorageDirectory()
        addRoot("内部存储", externalRoot)
        addRoot(
            "下载",
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        )
        addRoot(
            "文档",
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS)
        )

        val storageRoot = File("/storage")
        storageRoot.listFiles()
            ?.filter { it.isDirectory && it.canRead() && it.name != "self" && it.name != "emulated" }
            ?.forEach { addRoot(it.name, it) }

        addRoot("文件系统", File("/"))
        return roots.values.toList()
    }

    fun getFilePickerRootsForPigeon(): List<NativeAppFileEntry> {
        return getFilePickerRoots().map { it.toNativeAppFileEntry() }
    }

    fun listFilePickerDirectory(path: String): List<Map<String, Any>> {
        if (path.isBlank()) return getFilePickerRoots()
        val dir = File(path)
        require(dir.exists()) { "目录不存在: $path" }
        require(dir.isDirectory) { "不是目录: $path" }
        return dir.listFiles()?.map { appFileEntryMap(it) } ?: emptyList()
    }

    fun listFilePickerDirectoryForPigeon(path: String): List<NativeAppFileEntry> {
        return listFilePickerDirectory(path).map { it.toNativeAppFileEntry() }
    }

    /// App-private data roots mirroring the MTDataFilesProvider mapping:
    /// data, user_de_data, android_data, android_obb. Surfaced by the file
    /// manager in root mode so the user can browse the same tree MT sees.
    fun getAppDataRoots(): List<Map<String, Any>> {
        val roots = linkedMapOf<String, Map<String, Any>>()
        fun addRoot(name: String, file: File?) {
            if (file == null) return
            val path = try {
                file.canonicalPath
            } catch (_: Exception) {
                file.absolutePath
            }
            if (path.isBlank()) return
            roots[path] = appFileEntryMap(file, name)
        }

        val dataDir = filesDir.parentFile
        addRoot("data", dataDir)
        if (dataDir?.path?.startsWith("/data/user/") == true) {
            addRoot("user_de_data", File("/data/user_de/${dataDir.path.substring(11)}"))
        }
        addRoot("android_data", externalFilesDir?.parentFile)
        addRoot("android_obb", obbDir)
        return roots.values.toList()
    }

    fun readFilePickerFile(path: String): ByteArray {
        require(path.isNotBlank()) { "文件路径为空" }
        return if (path.startsWith("content://")) {
            val uri = Uri.parse(path)
            contentResolver.openInputStream(uri)?.use { it.readBytes() }
                ?: throw IllegalArgumentException("无法读取文件")
        } else {
            val file = File(path)
            require(file.isFile) { "文件不存在: $path" }
            file.readBytes()
        }
    }

    fun createFileManagerDirectory(path: String, name: String) {
        val parent = mutableTarget(path)
        require(name.isNotBlank()) { "目录名为空" }
        require(!name.contains('/') && !name.contains('\\')) { "目录名不能包含路径分隔符" }
        val target = File(parent, name)
        require(!target.exists()) { "目录已存在: ${target.name}" }
        require(parent.isDirectory && parent.canWrite()) { "父目录不可写" }
        if (!target.mkdir()) {
            throw IllegalStateException("创建目录失败: ${target.name}")
        }
    }

    fun renameFileManagerEntry(path: String, newName: String) {
        val target = mutableTarget(path)
        require(newName.isNotBlank()) { "新名称为空" }
        require(!newName.contains('/') && !newName.contains('\\')) { "新名称不能包含路径分隔符" }
        require(target.exists()) { "文件或目录不存在: $path" }
        val renamed = File(target.parentFile, newName)
        require(!renamed.exists()) { "目标名称已存在: $newName" }
        require(target.parentFile?.canWrite() == true) { "父目录不可写" }
        if (!target.renameTo(renamed)) {
            throw IllegalStateException("重命名失败: ${target.name}")
        }
    }

    fun deleteFileManagerEntry(path: String) {
        val target = mutableTarget(path)
        require(target.exists()) { "文件或目录不存在: $path" }
        if (target.isDirectory) {
            val children = target.listFiles()
            require(children == null || children.isEmpty()) { "目录非空，不能删除: ${target.name}" }
        }
        if (!target.delete()) {
            throw IllegalStateException("删除失败: ${target.name}")
        }
    }

    fun writeFileManagerFile(path: String, content: String) {
        val target = mutableTarget(path)
        require(target.exists()) { "文件不存在: $path" }
        require(target.isFile) { "只能写入普通文件" }
        target.writeText(content)
    }

    /// Creates [path] and missing parents (like `mkdir -p`). Accepts a
    /// non-existent target, but still rejects protected prefixes so the
    /// auto-create of the default working directory cannot escape storage.
    fun ensureFileManagerDirectory(path: String) {
        require(path.isNotBlank()) { "路径为空" }
        require(!path.startsWith("content://")) { "不允许通过 URI 创建目录" }
        require(path.startsWith("/") && !path.contains("\\")) { "路径必须是绝对路径" }
        require(!path.contains("\u0000")) { "路径包含非法字符" }
        val canonical = try {
            File(path).canonicalPath
        } catch (_: Exception) {
            throw IllegalArgumentException("无法解析路径: $path")
        }
        require(canonical != "/") { "不允许创建文件系统根目录" }
        require(!protectedSystemPrefixes.any { prefix ->
            canonical == prefix || canonical.startsWith("$prefix/")
        }) { "不允许在系统目录下创建: $canonical" }
        val target = File(canonical)
        if (target.isDirectory) return
        require(!target.exists()) { "路径已存在且不是目录: $canonical" }
        if (!target.mkdirs()) {
            throw IllegalStateException("创建目录失败: $canonical")
        }
    }

    /// Resolves a mutation target from an absolute host path and rejects
    /// anything the file manager must never touch: URIs, the filesystem
    /// root, and protected system prefixes.
    private fun mutableTarget(path: String): File {
        require(path.isNotBlank()) { "路径为空" }
        require(!path.startsWith("content://")) { "不允许通过 URI 修改文件" }
        require(path.startsWith("/") && !path.contains("\\")) { "路径必须是绝对路径" }
        require(!path.contains("\u0000")) { "路径包含非法字符" }
        val canonical = try {
            File(path).canonicalPath
        } catch (_: Exception) {
            throw IllegalArgumentException("无法解析路径: $path")
        }
        require(canonical == "/" || !protectedSystemPrefixes.any { prefix ->
            canonical == prefix || canonical.startsWith("$prefix/")
        }) { "不允许修改系统目录: $canonical" }
        require(canonical != "/") { "不允许修改文件系统根目录" }
        return File(canonical)
    }

    private fun appFileEntryMap(file: File, displayName: String? = null): Map<String, Any> {
        val path = try {
            file.canonicalPath
        } catch (_: Exception) {
            file.absolutePath
        }
        val name = displayName ?: file.name.ifBlank { path }
        return mapOf(
            "path" to path,
            "name" to name,
            "isDirectory" to file.isDirectory,
            "size" to if (file.isFile) file.length() else 0L,
            "modifiedAt" to file.lastModified()
        )
    }

    private fun Map<String, Any>.toNativeAppFileEntry(): NativeAppFileEntry {
        return NativeAppFileEntry(
            path = this["path"]?.toString() ?: "",
            name = this["name"]?.toString() ?: "",
            isDirectory = this["isDirectory"] as? Boolean ?: false,
            size = (this["size"] as? Number)?.toLong() ?: 0L,
            modifiedAtMillis = (this["modifiedAt"] as? Number)?.toLong() ?: 0L
        )
    }
}
