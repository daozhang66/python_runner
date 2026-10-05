package com.daozhang.py.backup

import java.io.File
import java.io.FileOutputStream
import org.json.JSONArray
import org.json.JSONObject

/**
 * File-only transaction. SQLite decides whether pending transactions are finalized or rolled back.
 * Never erase this journal on metadata failure.
 */
class BackupJournal(
    private val filesDir: File,
    private val syncDirectory: (File) -> Unit = {},
    private val checkpoint: (String) -> Unit = {},
) {
    private val durable = DurableFiles(syncDirectory)

    private fun op(id: String) = operationPath(filesDir, id)

    private fun journal(id: String) = File(op(id), "journal.json")

    fun pending(): List<String> =
        File(filesDir, "backup_operations")
            .listFiles()
            ?.filter { it.isDirectory && File(it, "journal.json").isFile }
            ?.map { it.name }
            ?.sorted() ?: emptyList()

    private fun target(root: String): File {
        safeRoot(root)
        val (kind, name) = root.split('/')
        return contained(
            File(filesDir, if (kind == "scripts") "scripts" else "script_projects"),
            name,
        )
    }

    private fun source(id: String, root: String) =
        contained(File(op(id), "payload"), safeRoot(root))

    private fun backup(id: String, index: Int) = contained(op(id), "rollback/$index")

    private fun write(id: String, value: JSONObject) {
        durable.write(journal(id), value)
        checkpoint("journal")
    }

    private fun syncTree(file: File) {
        if (file.isDirectory) {
            (file.listFiles() ?: throw BackupException("IO_ERROR", "Cannot read staged files"))
                .forEach { child ->
                    contained(file, child.name)
                    syncTree(child)
                }
            syncDirectory(file)
        } else FileOutputStream(file, true).use { it.fd.sync() }
    }

    fun commit(id: String, fileMoves: JSONArray) {
        checkBackup(!journal(id).exists(), "RECOVERY_REQUIRED", "Restore recovery required")
        checkBackup(pending().isEmpty(), "RECOVERY_REQUIRED", "Restore recovery required")
        checkBackup(fileMoves.length() <= 20000, "LIMIT_EXCEEDED", "Too many restore roots")
        val sources = hashSetOf<String>()
        val targets = hashSetOf<String>()
        val moves = JSONArray()
        fileMoves.objects().forEach { move ->
            val from = safeRoot(move.getString("sourceRoot"))
            val to = safeRoot(move.getString("targetRoot"))
            checkBackup(
                from.substringBefore('/') == to.substringBefore('/') &&
                    sources.add(from) &&
                    targets.add(to),
                "INVALID_ARGUMENT",
                "Invalid or duplicate restore root",
            )
            checkBackup(
                move.get("overwrite") is Boolean,
                "INVALID_ARGUMENT",
                "Invalid overwrite flag",
            )
            val staged = source(id, from)
            val live = target(to)
            checkBackup(
                staged.exists() &&
                    (if (from.startsWith("projects/")) staged.isDirectory else staged.isFile),
                "STAGE_MISSING",
                "Staged files are missing",
            )
            checkBackup(
                move.getBoolean("overwrite") || !live.exists(),
                "TARGET_EXISTS",
                "Restore target already exists",
            )
            moves.put(
                JSONObject()
                    .put("sourceRoot", from)
                    .put("targetRoot", to)
                    .put("originalExists", live.exists())
                    .put("phase", "prepared")
            )
        }
        // Flush all staged directory entries before publishing a journal that references them.
        syncTree(File(op(id), "payload"))
        durable.mkdir(op(id))
        durable.mkdir(File(op(id), "rollback"))
        // prepare() may have created these directories with ordinary mkdirs.
        // Persist every link from the operation back through the native root;
        // syncing a child alone does not publish its entry in its parent.
        syncDirectory(op(id))
        syncDirectory(op(id).parentFile!!)
        syncDirectory(filesDir)
        val state =
            JSONObject()
                .put("version", 1)
                .put("operationId", id)
                .put("mode", "committing")
                .put("moves", moves)
        write(id, state)
        try {
            moves.objects().forEachIndexed { index, move ->
                val live = target(move.getString("targetRoot"))
                val staged = source(id, move.getString("sourceRoot"))
                move.put("phase", "backupPending")
                write(id, state)
                if (move.getBoolean("originalExists")) {
                    durable.move(live, backup(id, index))
                    checkpoint("originalMoved")
                }
                move.put("phase", "installPending")
                write(id, state)
                durable.move(staged, live)
                checkpoint("stagedMoved")
                move.put("phase", "installed")
                write(id, state)
            }
            state.put("mode", "awaitingMetadata")
            write(id, state)
        } catch (e: Exception) {
            try {
                rollback(id)
            } catch (_: Exception) {
                throw BackupException("RECOVERY_REQUIRED", "Restore rollback requires recovery")
            }
            throw BackupException("RESTORE_FAILED", "Restore files could not be committed")
        }
    }

    private fun read(id: String): JSONObject {
        val file = journal(id)
        checkBackup(
            file.length() <= 16 * 1024 * 1024,
            "RECOVERY_REQUIRED",
            "Invalid restore journal",
        )
        try {
            val state = JSONObject(file.readText(Charsets.UTF_8))
            checkBackup(
                state.getInt("version") == 1 && state.getString("operationId") == id,
                "RECOVERY_REQUIRED",
                "Invalid restore journal",
            )
            state.getJSONArray("moves").objects().forEach {
                safeRoot(it.getString("sourceRoot"))
                safeRoot(it.getString("targetRoot"))
            }
            return state
        } catch (_: Exception) {
            throw BackupException("RECOVERY_REQUIRED", "Invalid restore journal")
        }
    }

    fun rollback(id: String) {
        if (!journal(id).exists()) return
        val state = read(id)
        when (state.getString("mode")) {
            "finalizing" -> {
                cleanup(id)
                return
            }
            "rolledBack" -> {
                cleanup(id)
                return
            }
        }
        state.put("mode", "rollingBack")
        write(id, state)
        val moves = state.getJSONArray("moves").objects()
        moves.indices.reversed().forEach { index ->
            val move = moves[index]
            val live = target(move.getString("targetRoot"))
            val staged = source(id, move.getString("sourceRoot"))
            val saved = backup(id, index)
            // A missing staged root proves its rename happened. If it is still
            // present, never delete live: that could be the untouched original.
            if (!staged.exists()) {
                checkBackup(live.exists(), "RECOVERY_REQUIRED", "Restore files need recovery")
                durable.move(live, staged)
                checkpoint("undoInstalled")
            }
            if (saved.exists()) {
                checkBackup(
                    !live.exists(),
                    "RECOVERY_REQUIRED",
                    "Restore target changed during recovery",
                )
                durable.move(saved, live)
                checkpoint("originalRestored")
            }
            if (move.getBoolean("originalExists"))
                checkBackup(
                    live.exists(),
                    "RECOVERY_REQUIRED",
                    "Original restore target is missing",
                )
            else checkBackup(!live.exists(), "RECOVERY_REQUIRED", "Unexpected restore target")
        }
        // This durable state prevents later cleanup crashes from making a
        // missing staging directory look like an installed replacement.
        state.put("mode", "rolledBack")
        write(id, state)
        cleanup(id)
    }

    fun finalize(id: String) {
        if (!journal(id).exists()) return
        val state = read(id)
        checkBackup(
            state.getString("mode") in setOf("awaitingMetadata", "finalizing"),
            "RECOVERY_REQUIRED",
            "Restore transaction is incomplete",
        )
        state.put("mode", "finalizing")
        write(id, state)
        cleanup(id)
    }

    private fun cleanup(id: String) {
        val directory = op(id)
        directory
            .listFiles()
            ?.filter { it.name != "journal.json" }
            ?.forEach {
                durable.delete(it)
                checkpoint("cleanup")
            }
        durable.delete(journal(id))
        checkpoint("journalRemoved")
        durable.delete(directory)
    }
}
