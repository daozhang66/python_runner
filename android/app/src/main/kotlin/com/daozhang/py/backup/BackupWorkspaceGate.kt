package com.daozhang.py.backup

import java.io.Closeable
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Short control methods run on the platform thread. Leases cover asynchronous legacy mutations
 * through their MethodChannel result, not just dispatch.
 */
class BackupWorkspaceGate(
    private val executionActive: () -> Boolean,
    private val recoveryPending: () -> Boolean,
) {
    private var owner: String? = null
    private var legacyLeases = 0
    private var committing = false

    @Synchronized
    fun requireIdle() {
        checkBackup(
            owner == null && legacyLeases == 0 && !committing,
            "WORKSPACE_BUSY",
            "Workspace is busy",
        )
    }

    @Synchronized
    fun acquire(id: String) {
        checkBackup(
            owner == null && legacyLeases == 0 && !executionActive(),
            "WORKSPACE_BUSY",
            "Workspace is busy",
        )
        owner = id
    }

    @Synchronized
    fun requireOwner(id: String) {
        checkBackup(owner == id, "WORKSPACE_NOT_LOCKED", "Workspace lock is required")
    }

    @Synchronized
    fun release(id: String) {
        requireOwner(id)
        checkBackup(!committing, "WORKSPACE_BUSY", "Restore commit is in progress")
        owner = null
    }

    @Synchronized
    fun beginCommit(id: String) {
        requireOwner(id)
        checkBackup(legacyLeases == 0, "WORKSPACE_BUSY", "Workspace is busy")
        committing = true
    }

    @Synchronized
    fun beginRecovery(id: String) {
        checkBackup(
            (owner == null || owner == id) && legacyLeases == 0 && !executionActive(),
            "WORKSPACE_BUSY",
            "Workspace is busy",
        )
        committing = true
    }

    @Synchronized
    fun endCommit() {
        committing = false
    }

    @Synchronized
    fun enterLegacy(method: String): Closeable {
        val mutation = method in mutations
        val read = method in reads
        if (mutation || read)
            checkBackup(
                !recoveryPending() && !committing && (!mutation || owner == null),
                "WORKSPACE_BUSY",
                "Backup or recovery is in progress",
            )
        if (mutation || read) legacyLeases++
        val closed = AtomicBoolean(false)
        return Closeable {
            if ((mutation || read) && closed.compareAndSet(false, true))
                synchronized(this) { legacyLeases-- }
        }
    }

    companion object {
        private val mutations =
            setOf(
                "createScript",
                "deleteScript",
                "renameScript",
                "saveScript",
                "createScriptProject",
                "deleteScriptProject",
                "saveProjectFile",
                "createProjectDirectory",
                "deleteProjectEntry",
                "renameProjectEntry",
                "importScriptProjectZip",
                "createFileManagerDirectory",
                "transferFileManagerEntry",
                "renameFileManagerEntry",
                "deleteFileManagerEntry",
                "writeFileManagerFile",
                "ensureFileManagerDirectory",
                "executeScript",
                "executeLinuxLikeScript",
                "importScriptFromUri",
                "exportScript",
                "exportScriptProjectZip",
                "exportLog",
                "installLinuxLikeRequirements",
                "installLinuxLikePackage",
                "repairLinuxLikePackage",
                "uninstallLinuxLikePackage",
            )
        private val reads =
            setOf(
                "listScripts",
                "readScript",
                "listProjectFiles",
                "readProjectFile",
                "readFileBounded",
                "getFileManagerAppDataRoots",
                "getFilePickerRoots",
                "listFilePickerDirectory",
                "readFilePickerFile",
            )
    }
}
