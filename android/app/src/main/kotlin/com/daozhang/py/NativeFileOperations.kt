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
    private val scriptFileStore: ScriptFileStore
) {
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
