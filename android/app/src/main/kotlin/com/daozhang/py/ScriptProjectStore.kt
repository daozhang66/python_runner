package com.daozhang.py

import android.content.Context
import android.net.Uri
import android.os.Environment
import java.io.BufferedInputStream
import java.io.File
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

class ScriptProjectStore(
    private val context: Context,
    private val filesDir: File
) {
    fun scriptProjectsDir(): File {
        val dir = File(filesDir, "script_projects")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    fun normalizeProjectKey(projectKey: String): String {
        val safeKey = projectKey.trim()
        require(safeKey.isNotEmpty()) { "项目标识不能为空" }
        require(safeKey.all { it.isLetterOrDigit() || it == '_' || it == '-' }) {
            "项目标识只能包含英文、数字、下划线和短横线"
        }
        require(!safeKey.contains('/') && !safeKey.contains('\\')) {
            "项目标识不能包含路径分隔符"
        }
        require(safeKey.none { it.code < 32 || it.code == 127 }) {
            "项目标识不能包含控制字符"
        }
        return safeKey
    }

    fun normalizeProjectRelativePath(path: String): String {
        val raw = path.trim()
        require(raw.isNotEmpty()) { "项目路径不能为空" }
        require(!raw.contains('\\')) { "项目路径不能包含反斜杠" }
        require(!raw.startsWith("/") && !Regex("^[A-Za-z]:").containsMatchIn(raw)) {
            "项目路径不能是绝对路径"
        }
        val parts = raw.split('/')
        require(parts.none { it.isBlank() || it == "." || it == ".." }) {
            "项目路径包含非法段"
        }
        require(raw.none { it.code < 32 || it.code == 127 }) {
            "项目路径不能包含控制字符"
        }
        return parts.joinToString("/")
    }

    fun normalizeProjectMainFilePath(path: String): String {
        val safePath = normalizeProjectRelativePath(path)
        require(safePath.endsWith(".py")) { "项目主程序必须是 .py 文件" }
        return safePath
    }

    fun safeProjectRoot(projectKey: String): File {
        val safeKey = normalizeProjectKey(projectKey)
        val projectsRoot = scriptProjectsDir().canonicalFile
        val root = File(projectsRoot, safeKey).canonicalFile
        require(root.toPath().startsWith(projectsRoot.toPath()) && root.name == safeKey) {
            "项目目录越界"
        }
        return root
    }

    fun safeProjectFile(projectKey: String, path: String): File {
        val root = safeProjectRoot(projectKey)
        val safePath = normalizeProjectRelativePath(path)
        val target = File(root, safePath).canonicalFile
        require(target.toPath().startsWith(root.toPath())) {
            "项目文件路径越界"
        }
        return target
    }

    fun projectRelativePath(root: File, file: File): String {
        return root.canonicalFile.toPath()
            .relativize(file.canonicalFile.toPath())
            .joinToString("/")
    }

    fun createProject(projectKey: String): Map<String, Any> {
        val root = safeProjectRoot(projectKey)
        if (!root.exists()) root.mkdirs()
        return mapOf(
            "projectKey" to normalizeProjectKey(projectKey),
            "path" to root.absolutePath
        )
    }

    fun deleteProject(projectKey: String): Boolean {
        val root = safeProjectRoot(projectKey)
        if (root.exists()) root.deleteRecursively()
        return true
    }

    fun listProjectFiles(projectKey: String): List<Map<String, Any>> {
        val root = safeProjectRoot(projectKey)
        if (!root.exists()) return emptyList()
        return root.walkTopDown()
            .drop(1)
            .map { file ->
                mapOf(
                    "path" to projectRelativePath(root, file),
                    "name" to file.name,
                    "isDirectory" to file.isDirectory,
                    "size" to if (file.isFile) file.length() else 0L,
                    "modifiedAt" to file.lastModified()
                )
            }
            .sortedWith(
                compareBy<Map<String, Any>> { it["path"].toString().lowercase(Locale.US) }
                    .thenBy { it["name"].toString() }
            )
            .toList()
    }

    fun readProjectFile(projectKey: String, path: String): String {
        val file = safeProjectFile(projectKey, path)
        require(file.isFile) { "项目文件不存在: $path" }
        return file.readText()
    }

    fun saveProjectFile(projectKey: String, path: String, content: String): Boolean {
        val file = safeProjectFile(projectKey, path)
        file.parentFile?.mkdirs()
        file.writeText(content)
        return true
    }

    fun createProjectDirectory(projectKey: String, path: String): Boolean {
        val dir = safeProjectFile(projectKey, path)
        if (!dir.exists()) dir.mkdirs()
        return true
    }

    fun deleteProjectEntry(projectKey: String, path: String): Boolean {
        val root = safeProjectRoot(projectKey)
        val target = safeProjectFile(projectKey, path)
        require(target.canonicalFile != root.canonicalFile) {
            "不能通过条目删除项目根目录"
        }
        if (target.exists()) target.deleteRecursively()
        return true
    }

    fun renameProjectEntry(projectKey: String, oldPath: String, newPath: String): Boolean {
        val source = safeProjectFile(projectKey, oldPath)
        val target = safeProjectFile(projectKey, newPath)
        require(source.exists()) { "项目条目不存在: $oldPath" }
        require(!target.exists()) { "目标条目已存在: $newPath" }
        target.parentFile?.mkdirs()
        if (!source.renameTo(target)) {
            throw IllegalStateException("系统拒绝重命名")
        }
        return true
    }

    fun importProjectZip(projectKey: String, uriString: String): List<Map<String, Any>> {
        val root = safeProjectRoot(projectKey)
        if (!root.exists()) root.mkdirs()
        val input = openInputStreamFromPathOrUri(uriString)
            ?: throw IllegalArgumentException("无法读取ZIP文件")
        val importedFiles = mutableListOf<Map<String, Any>>()
        var entryCount = 0
        var totalBytes = 0L
        val maxEntries = 2000
        val maxEntryBytes = 20L * 1024L * 1024L
        val maxTotalBytes = 200L * 1024L * 1024L

        BufferedInputStream(input).use { buffered ->
            ZipInputStream(buffered).use { zip ->
                while (true) {
                    val entry = zip.nextEntry ?: break
                    entryCount++
                    if (entryCount > maxEntries) {
                        throw IllegalArgumentException("ZIP条目过多")
                    }
                    val relativePath = normalizeZipEntryPath(entry.name)
                    if (relativePath == null) {
                        zip.closeEntry()
                        continue
                    }
                    if (entry.size > maxEntryBytes) {
                        throw IllegalArgumentException("ZIP条目过大: ${entry.name}")
                    }
                    val target = safeProjectFile(projectKey, relativePath)
                    if (entry.isDirectory) {
                        target.mkdirs()
                    } else {
                        target.parentFile?.mkdirs()
                        var entryBytes = 0L
                        target.outputStream().use { output ->
                            val buffer = ByteArray(64 * 1024)
                            while (true) {
                                val bytesRead = zip.read(buffer)
                                if (bytesRead == -1) break
                                entryBytes += bytesRead
                                totalBytes += bytesRead
                                if (entryBytes > maxEntryBytes) {
                                    throw IllegalArgumentException("ZIP条目过大: ${entry.name}")
                                }
                                if (totalBytes > maxTotalBytes) {
                                    throw IllegalArgumentException("ZIP总大小过大")
                                }
                                output.write(buffer, 0, bytesRead)
                            }
                        }
                        importedFiles.add(
                            mapOf(
                                "path" to projectRelativePath(root, target),
                                "name" to target.name,
                                "isDirectory" to false,
                                "size" to target.length(),
                                "modifiedAt" to target.lastModified()
                            )
                        )
                    }
                    zip.closeEntry()
                }
            }
        }
        return importedFiles.sortedBy { it["path"].toString().lowercase(Locale.US) }
    }

    fun exportProjectZip(projectKey: String, destDir: String?): String {
        val root = safeProjectRoot(projectKey)
        require(root.isDirectory) { "项目目录不存在" }
        val targetDir = if (!destDir.isNullOrBlank()) {
            File(destDir)
        } else {
            File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                "PythonRunner"
            )
        }
        if (!targetDir.exists()) targetDir.mkdirs()
        val zipFile = File(targetDir, "${normalizeProjectKey(projectKey)}.zip")
        ZipOutputStream(zipFile.outputStream()).use { zip ->
            root.walkTopDown()
                .drop(1)
                .filter { file ->
                    file.isFile && !shouldSkipProjectZipEntry(projectRelativePath(root, file))
                }
                .forEach { file ->
                    val relativePath = projectRelativePath(root, file)
                    zip.putNextEntry(ZipEntry(relativePath))
                    file.inputStream().use { input -> input.copyTo(zip) }
                    zip.closeEntry()
                }
        }
        return zipFile.absolutePath
    }

    private fun openInputStreamFromPathOrUri(value: String): java.io.InputStream? {
        val text = value.trim()
        if (text.isEmpty()) return null
        if (text.startsWith("content://") || text.startsWith("file://")) {
            return context.contentResolver.openInputStream(Uri.parse(text))
        }
        val file = File(text)
        if (file.isFile) return file.inputStream()
        return try {
            context.contentResolver.openInputStream(Uri.parse(text))
        } catch (_: Exception) {
            null
        }
    }

    private fun normalizeZipEntryPath(entryName: String): String? {
        val raw = entryName.trim().removePrefix("./")
        if (raw.isBlank()) return null
        if (raw.startsWith("__MACOSX/") || raw.endsWith(".DS_Store")) return null
        if (raw.contains('\\')) {
            throw IllegalArgumentException("ZIP路径不能包含反斜杠: $entryName")
        }
        val directoryTrimmed = raw.trimEnd('/')
        if (directoryTrimmed.isBlank()) return null
        return normalizeProjectRelativePath(directoryTrimmed)
    }

    private fun shouldSkipProjectZipEntry(relativePath: String): Boolean {
        val parts = relativePath.split('/')
        return parts.any {
            it == "__pycache__" ||
                it == ".pytest_cache" ||
                it == ".python_runner_sync" ||
                it == ".python_runner_linux_like"
        }
    }
}
