package com.daozhang.py

import java.io.File

class ScriptFileStore(private val filesDir: File) {
    fun scriptsDir(): File {
        val dir = File(filesDir, "scripts")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    fun normalizeScriptName(name: String): String {
        val safeName = name.trim()
        require(safeName.isNotEmpty()) { "脚本名称不能为空" }
        require(safeName != "." && safeName != "..") { "非法脚本名称" }
        require(!safeName.contains('/') && !safeName.contains('\\')) {
            "脚本名称不能包含路径分隔符"
        }
        require(safeName.none { it.code < 32 || it.code == 127 }) {
            "脚本名称不能包含控制字符"
        }
        return safeName
    }

    fun safeScriptFile(name: String): File {
        val safeName = normalizeScriptName(name)
        val scriptsRoot = scriptsDir().canonicalFile
        val target = File(scriptsRoot, safeName).canonicalFile
        require(target.toPath().startsWith(scriptsRoot.toPath()) && target.name == safeName) {
            "脚本路径越界"
        }
        return target
    }

    fun createScript(name: String, content: String): Map<String, Any> {
        val file = safeScriptFile(name)
        require(!file.exists()) { "脚本已存在 $name" }
        file.writeText(content)
        return mapOf("name" to name, "path" to file.absolutePath)
    }

    fun deleteScript(name: String) {
        val file = safeScriptFile(name)
        require(file.exists()) { "脚本不存在 $name" }
        file.delete()
    }

    fun renameScript(oldName: String, newName: String) {
        val oldFile = safeScriptFile(oldName)
        val newFile = safeScriptFile(newName)
        require(oldFile.exists()) { "脚本不存在 $oldName" }
        require(!newFile.exists()) { "目标名称已存在 $newName" }
        require(oldFile.renameTo(newFile)) { "文件重命名失败" }
    }

    fun listScripts(): List<Map<String, Any>> {
        val files = scriptsDir().listFiles()?.filter { it.isFile && it.name.endsWith(".py") } ?: emptyList()
        return files.map { file ->
            mapOf(
                "name" to file.name,
                "path" to file.absolutePath,
                "modifiedAt" to file.lastModified(),
                "size" to file.length()
            )
        }.sortedByDescending { it["modifiedAt"] as Long }
    }

    fun readScript(name: String): String {
        val file = safeScriptFile(name)
        require(file.exists()) { "脚本不存在 $name" }
        return file.readText()
    }

    fun saveScript(name: String, content: String) {
        safeScriptFile(name).writeText(content)
    }
}
