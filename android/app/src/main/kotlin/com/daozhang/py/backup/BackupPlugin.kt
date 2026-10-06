package com.daozhang.py.backup

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.system.Os
import android.system.OsConstants
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import org.json.JSONArray
import org.json.JSONObject

class BackupPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    PluginRegistry.ActivityResultListener {
    var executionActive: () -> Boolean = { false }
    lateinit var gate: BackupWorkspaceGate
        private set

    private lateinit var context: Context
    private lateinit var archive: BackupArchive
    private lateinit var journal: BackupJournal
    private lateinit var channel: MethodChannel
    private lateinit var events: EventChannel
    private val main = Handler(Looper.getMainLooper())
    private val worker =
        Executors.newSingleThreadExecutor { task -> Thread(task, "backup-storage") }
    private var binding: ActivityPluginBinding? = null
    private var sink: EventChannel.EventSink? = null
    private var picker: MethodChannel.Result? = null
    private var pickerRequest = 0
    private var pickerTree = false
    private var reserved: String? = null
    private var busy = false
    private var committing = false
    private var cancelled = AtomicBoolean(false)
    private var lastStage = ""
    private var lastProgress = 0L

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        journal = BackupJournal(context.filesDir, ::syncDirectory)
        archive = BackupArchive(context.filesDir, ::progress)
        gate = BackupWorkspaceGate({ executionActive() }, { journal.pending().isNotEmpty() })
        channel = MethodChannel(binding.binaryMessenger, "com.daozhang.py/backup")
        channel.setMethodCallHandler(this)
        events = EventChannel(binding.binaryMessenger, "com.daozhang.py/backup_progress")
        events.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        events.setStreamHandler(null)
        sink = null
        detachActivity()
        if (!committing) cancelled.set(true)
        worker.shutdown()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.binding = binding
        binding.addActivityResultListener(this)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = detachActivity()

    override fun onDetachedFromActivity() = detachActivity()

    private fun detachActivity() {
        binding?.removeActivityResultListener(this)
        binding = null
        picker?.success(null)
        picker = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    private fun progress(id: String, stage: String, completed: Long, total: Long) {
        val now = System.nanoTime()
        if (stage == lastStage && completed != total && now - lastProgress < 100_000_000) return
        lastStage = stage
        lastProgress = now
        val value =
            mapOf("operationId" to id, "stage" to stage, "completed" to completed, "total" to total)
        main.post { sink?.success(value) }
    }

    private fun reserve(id: String) {
        operationPath(context.filesDir, id)
        checkBackup(
            reserved == null || reserved == id,
            "OPERATION_BUSY",
            "Another backup operation is active",
        )
        if (reserved == null) {
            reserved = id
            cancelled = AtomicBoolean(false)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "pickBackupDirectory",
                "pickBackupArchive" -> {
                    pick(call.method == "pickBackupDirectory", result)
                    return
                }
                "cancelOperation" -> {
                    val id = arg(call, "operationId")
                    checkBackup(
                        reserved == id,
                        "STALE_OPERATION",
                        "Backup operation is no longer active",
                    )
                    if (!committing) cancelled.set(true)
                    result.success(null)
                    return
                }
                "acquireWorkspace" -> {
                    checkBackup(!busy, "OPERATION_BUSY", "Backup operation is busy")
                    val id = arg(call, "operationId")
                    operationPath(context.filesDir, id)
                    checkBackup(
                        reserved == null || reserved == id,
                        "OPERATION_BUSY",
                        "Another backup operation is active",
                    )
                    // A rejected acquisition must not reserve a previously idle
                    // operation (for example when a script is still running).
                    gate.acquire(id)
                    reserve(id)
                    result.success(null)
                    return
                }
                "releaseWorkspace" -> {
                    checkBackup(!busy, "OPERATION_BUSY", "Backup operation is busy")
                    gate.release(arg(call, "operationId"))
                    result.success(null)
                    return
                }
                "scriptsRoot" -> {
                    result.success(File(context.filesDir, "scripts").absolutePath)
                    return
                }
                "pendingRestores" -> {
                    run(result) { journal.pending() }
                    return
                }
                "cleanupAbandonedOperations" -> {
                    checkBackup(
                        !busy && reserved == null,
                        "OPERATION_BUSY",
                        "Backup operation is busy",
                    )
                    gate.requireIdle()
                    run(result) {
                        archive.cleanupAbandoned()
                        null
                    }
                    return
                }
            }
            checkBackup(!busy, "OPERATION_BUSY", "Backup operation is busy")
            val id = arg(call, "operationId")
            reserve(id)
            when (call.method) {
                "createArchive" -> {
                    gate.requireOwner(id)
                    val metadata =
                        JSONObject(
                            call.argument<Map<String, Any?>>("metadata")
                                ?: throw BackupException("INVALID_ARGUMENT", "Metadata is required")
                        )
                    run(result) { archive.create(id, metadata, cancelled).toChannelMap() }
                }
                "createTransferFile" ->
                    run(result) { mapOf("path" to archive.transferFile(id).absolutePath) }
                "saveArchiveToDirectory" ->
                    run(result) { save(id, arg(call, "archivePath"), arg(call, "treeUri")) }
                "stageArchive" ->
                    run(result) {
                        val source = arg(call, "source")
                        val input =
                            if (source.startsWith("content://"))
                                context.contentResolver.openInputStream(Uri.parse(source))
                            else archive.knownArchive(id, source).inputStream()
                        checkBackup(input != null, "IO_ERROR", "Cannot open backup archive")
                        archive
                            .stage(id, input!!, arg(call, "displayName"), cancelled)
                            .toChannelMap()
                    }
                "commitStaged" -> {
                    val moves =
                        JSONArray(
                            call.argument<List<Map<String, Any?>>>("fileMoves")
                                ?: throw BackupException(
                                    "INVALID_ARGUMENT",
                                    "Restore roots are required",
                                )
                        )
                    gate.beginCommit(id)
                    committing = true
                    run(result, commit = true) {
                        progress(id, "committing", 0, moves.length().toLong())
                        journal.commit(id, moves)
                        progress(id, "committing", moves.length().toLong(), moves.length().toLong())
                        null
                    }
                }
                "finalizeRestore",
                "rollbackRestore" -> {
                    // Recovery is permitted before Dart acquires its normal workspace lock.
                    gate.beginRecovery(id)
                    committing = true
                    run(result, commit = true, releaseReservation = true) {
                        if (call.method == "finalizeRestore") journal.finalize(id)
                        else journal.rollback(id)
                        null
                    }
                }
                "discardOperation" ->
                    run(result, releaseReservation = true) {
                        archive.discard(id)
                        null
                    }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            error(result, e)
        }
    }

    private fun run(
        result: MethodChannel.Result,
        commit: Boolean = false,
        releaseReservation: Boolean = false,
        action: () -> Any?,
    ) {
        checkBackup(!busy, "OPERATION_BUSY", "Backup operation is busy")
        busy = true
        worker.execute {
            val response =
                try {
                    Result.success(action())
                } catch (e: Exception) {
                    Result.failure(e)
                }
            main.post {
                busy = false
                if (commit) {
                    committing = false
                    gate.endCommit()
                }
                if (response.isSuccess && releaseReservation) reserved = null
                response.fold({ result.success(it) }, { error(result, it) })
            }
        }
    }

    private fun arg(call: MethodCall, key: String): String {
        val value = call.argument<String>(key)
        checkBackup(!value.isNullOrEmpty(), "INVALID_ARGUMENT", "Missing backup argument")
        return value!!
    }

    private fun error(result: MethodChannel.Result, error: Throwable) {
        val code =
            when (error) {
                is BackupException -> error.code
                is SecurityException -> "PERMISSION_LOST"
                else -> "IO_ERROR"
            }
        val message =
            if (error is BackupException) error.message
            else if (error is SecurityException) "Directory permission is no longer available"
            else "Backup storage operation failed"
        result.error(code, message, null)
    }

    private fun pick(tree: Boolean, result: MethodChannel.Result) {
        checkBackup(picker == null, "PICKER_BUSY", "A document picker is already open")
        val activity =
            binding?.activity
                ?: throw BackupException("ACTIVITY_UNAVAILABLE", "Document picker is unavailable")
        picker = result
        pickerTree = tree
        pickerRequest = nextRequest.incrementAndGet()
        val intent =
            Intent(if (tree) Intent.ACTION_OPEN_DOCUMENT_TREE else Intent.ACTION_OPEN_DOCUMENT)
        intent.addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
        )
        if (tree)
            intent.addFlags(
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
            )
        else {
            intent.addCategory(Intent.CATEGORY_OPENABLE)
            intent.type = "*/*"
            intent.putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf(
                    "application/zip",
                    "application/x-zip-compressed",
                    "application/octet-stream",
                ),
            )
        }
        try {
            activity.startActivityForResult(intent, pickerRequest)
        } catch (e: Exception) {
            picker = null
            throw e
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != pickerRequest || picker == null) return false
        val result = picker!!
        picker = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        try {
            val requested =
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    if (pickerTree) Intent.FLAG_GRANT_WRITE_URI_PERMISSION else 0
            val granted = (data.flags and requested)
            context.contentResolver.takePersistableUriPermission(uri, granted)
            if (pickerTree) requireWritableTree(context, uri)
            val name =
                if (pickerTree) DocumentFile.fromTreeUri(context, uri)?.name ?: "Backup directory"
                else documentName(uri)
            result.success(mapOf("uri" to uri.toString(), "name" to name))
        } catch (e: Exception) {
            error(result, e)
        }
        return true
    }

    private fun documentName(uri: Uri): String {
        context.contentResolver
            .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor -> if (cursor.moveToFirst()) return cursor.getString(0) ?: "backup.zip" }
        return "backup.zip"
    }

    private fun save(id: String, path: String, tree: String): Map<String, String> {
        val file = archive.knownArchive(id, path)
        checkBackup(
            file.name.startsWith("python-runner-backup-"),
            "INVALID_ARGUMENT",
            "Only generated backups can be exported",
        )
        val uri = Uri.parse(tree)
        requireWritableTree(context, uri)
        val directory =
            DocumentFile.fromTreeUri(context, uri)
                ?: throw BackupException("PERMISSION_LOST", "Backup directory is unavailable")
        checkBackup(
            directory.isDirectory && directory.canWrite(),
            "PERMISSION_LOST",
            "Backup directory is no longer writable",
        )
        checkBackup(
            directory.findFile(file.name) == null,
            "TARGET_EXISTS",
            "Backup document already exists",
        )
        val document =
            directory.createFile("application/zip", file.name)
                ?: throw BackupException("IO_ERROR", "Cannot create backup document")
        try {
            val output =
                context.contentResolver.openOutputStream(document.uri, "w")
                    ?: throw BackupException("IO_ERROR", "Cannot write backup document")
            output.use { out ->
                file.inputStream().use { input ->
                    val buffer = ByteArray(64 * 1024)
                    var completed = 0L
                    while (true) {
                        checkBackup(!cancelled.get(), "CANCELLED", "Backup operation cancelled")
                        val n = input.read(buffer)
                        if (n < 0) break
                        out.write(buffer, 0, n)
                        completed += n
                        progress(id, "copying", completed, file.length())
                    }
                    out.flush()
                }
            }
            checkBackup(!cancelled.get(), "CANCELLED", "Backup operation cancelled")
            return mapOf("uri" to document.uri.toString(), "name" to (document.name ?: file.name))
        } catch (e: Exception) {
            document.delete()
            throw e
        }
    }

    companion object {
        private val nextRequest = java.util.concurrent.atomic.AtomicInteger(28100)

        internal fun requireWritableTree(context: Context, uri: Uri) {
            checkBackup(
                uri.scheme == "content" &&
                    context.contentResolver.persistedUriPermissions.any {
                        it.uri == uri && it.isWritePermission && it.isReadPermission
                    },
                "PERMISSION_LOST",
                "Backup directory permission is no longer available",
            )
        }

        internal fun syncDirectory(directory: File) {
            val fd = Os.open(directory.absolutePath, OsConstants.O_RDONLY, 0)
            try {
                Os.fsync(fd)
            } finally {
                Os.close(fd)
            }
        }
    }
}
