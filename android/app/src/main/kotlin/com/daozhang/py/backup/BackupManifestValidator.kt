package com.daozhang.py.backup

import java.nio.ByteBuffer
import org.json.JSONObject
import org.json.JSONTokener

/** Independent native validation: no malformed marker can become a legacy ZIP. */
internal object BackupManifestValidator {
    fun parse(bytes: ByteArray): JSONObject {
        val text = Charsets.UTF_8.newDecoder().decode(ByteBuffer.wrap(bytes)).toString()
        var depth = 0
        var quoted = false
        var escaped = false
        for (character in text) {
            if (quoted) {
                if (escaped) escaped = false
                else if (character == '\\') escaped = true else if (character == '"') quoted = false
            } else {
                when (character) {
                    '"' -> quoted = true
                    '{',
                    '[' -> {
                        depth++
                        checkBackup(
                            depth <= 64,
                            "INVALID_MANIFEST",
                            "Backup metadata is too deeply nested",
                        )
                    }
                    '}',
                    ']' -> {
                        depth--
                        checkBackup(depth >= 0)
                    }
                }
            }
        }
        checkBackup(depth == 0 && !quoted, "INVALID_MANIFEST", "Invalid backup metadata")
        val tokens = JSONTokener(text)
        val json = JSONObject(tokens)
        checkBackup(
            tokens.nextClean().code == 0,
            "INVALID_MANIFEST",
            "Invalid trailing backup metadata",
        )
        validate(json)
        return json
    }

    fun validate(json: JSONObject, withFiles: Boolean = true) {
        try {
            checkBackup(json.get("format") == "python_runner_backup")
            val version = integer(json, "version")
            checkBackup(version == 1L, "UNSUPPORTED_VERSION", "Unsupported backup version")
            date(json, "createdAt")
            val scripts = json.getJSONArray("scripts").objects()
            val groups = json.getJSONArray("groups").objects()
            checkBackup(
                scripts.size <= 10000 && groups.size <= 10000,
                "LIMIT_EXCEEDED",
                "Too many metadata records",
            )
            val ids = hashMapOf<Long, JSONObject>()
            val names = hashSetOf<String>()
            val keys = hashSetOf<String>()
            groups.forEach { group ->
                val id = integer(group, "id", 1)
                checkBackup(ids.put(id, group) == null)
                val name = string(group, "name")
                checkBackup(
                    name.isNotEmpty() &&
                        name.trim() == name &&
                        name.length <= 255 &&
                        name.none { it.code < 32 || it.code == 127 } &&
                        names.add(name)
                )
                date(group, "createdAt")
                date(group, "modifiedAt")
                integer(group, "sortOrder")
                optionalInteger(group, "homeSortOrder")
                val project = boolean(group, "isProject")
                if (project) {
                    val key = string(group, "projectKey")
                    checkBackup(
                        key.length <= 255 && Regex("^[A-Za-z0-9_-]+$").matches(key) && keys.add(key)
                    )
                    if (!group.isNull("mainFilePath")) {
                        val main = safePath(string(group, "mainFilePath"))
                        checkBackup(main.endsWith(".py", true))
                    }
                } else checkBackup(group.isNull("projectKey") && group.isNull("mainFilePath"))
            }
            val scriptNames = hashSetOf<String>()
            scripts.forEach { script ->
                val name = string(script, "name")
                safeScript(name)
                checkBackup(name.length <= 255 && scriptNames.add(name))
                date(script, "createdAt")
                date(script, "modifiedAt")
                integer(script, "runCount")
                integer(script, "sortOrder")
                optionalInteger(script, "homeSortOrder")
                boolean(script, "isPinned")
                if (!script.isNull("groupId")) {
                    val group = ids[integer(script, "groupId", 1)]
                    checkBackup(group != null && !boolean(group!!, "isProject"))
                }
                script.remove("path")
            }
            if (!withFiles) return
            val files = json.getJSONArray("files").objects()
            checkBackup(files.size <= 100000, "LIMIT_EXCEEDED", "Too many archive entries")
            val byPath = hashMapOf<String, JSONObject>()
            val populated = hashSetOf<String>()
            files.forEach { file ->
                val path = safePath(string(file, "path"))
                checkBackup(byPath.put(path, file) == null)
                val directory = boolean(file, "isDirectory")
                val size = integer(file, "size")
                date(file, "modifiedAt")
                if (directory) checkBackup(size == 0L && file.isNull("sha256"))
                else checkBackup(Regex("^[a-f0-9]{64}$").matches(string(file, "sha256")))
                if (path in setOf("scripts", "projects") && directory) return@forEach
                val parts = path.split('/')
                when (parts[0]) {
                    "scripts" ->
                        checkBackup(parts.size == 2 && !directory && parts[1] in scriptNames)
                    "projects" -> {
                        checkBackup(
                            parts.size >= 2 && parts[1] in keys && (parts.size > 2 || directory)
                        )
                        populated.add(parts[1])
                    }
                    else -> checkBackup(false)
                }
            }
            files.forEach { f ->
                var path = string(f, "path").substringBeforeLast('/', "")
                while (path.isNotEmpty()) {
                    byPath[path]?.let { checkBackup(boolean(it, "isDirectory")) }
                    path = path.substringBeforeLast('/', "")
                }
            }
            scriptNames.forEach {
                checkBackup(byPath["scripts/$it"]?.optBoolean("isDirectory", true) == false)
            }
            groups
                .filter { boolean(it, "isProject") }
                .forEach { group ->
                    val key = string(group, "projectKey")
                    checkBackup(key in populated)
                    if (!group.isNull("mainFilePath"))
                        checkBackup(
                            byPath["projects/$key/${string(group,"mainFilePath")}"]?.optBoolean(
                                "isDirectory",
                                true,
                            ) == false
                        )
                }
        } catch (e: BackupException) {
            throw e
        } catch (_: Exception) {
            throw BackupException("INVALID_MANIFEST", "Invalid backup metadata")
        }
    }

    private fun string(j: JSONObject, key: String): String {
        val v = j.get(key)
        checkBackup(v is String)
        return v as String
    }

    private fun boolean(j: JSONObject, key: String): Boolean {
        val v = j.get(key)
        checkBackup(v is Boolean)
        return v as Boolean
    }

    private fun integer(j: JSONObject, key: String, min: Long = 0): Long {
        val v = j.get(key)
        checkBackup(v is Int || v is Long)
        val n = (v as Number).toLong()
        checkBackup(n in min..9007199254740991L)
        return n
    }

    private fun optionalInteger(j: JSONObject, key: String) {
        if (!j.isNull(key)) integer(j, key)
    }

    private fun date(j: JSONObject, key: String) {
        checkBackup(integer(j, key) <= 8640000000000000L)
    }
}
