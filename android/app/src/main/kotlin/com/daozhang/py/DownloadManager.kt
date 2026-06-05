package com.daozhang.py

import android.content.Context
import android.os.Environment
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.io.File
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.max

private const val HTTP_REQUESTED_RANGE_NOT_SATISFIABLE = 416

class DownloadManager(
    private val context: Context,
    private val emitEvent: (Map<String, Any?>) -> Unit
) {
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val jobs = ConcurrentHashMap<String, Job>()
    private val tasks = ConcurrentHashMap<String, DownloadTask>()
    private val retryDelaysMs = longArrayOf(2_000L, 4_000L, 8_000L)

    private val updatesDir: File
        get() {
            val dir = File(
                context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: context.filesDir,
                "updates"
            )
            if (!dir.exists()) dir.mkdirs()
            return dir
        }

    fun startApkDownload(
        url: String,
        fileName: String,
        version: String,
        sha256: String
    ): String {
        val task = loadOrCreateTask(url, fileName, version, sha256)
        launchDownload(task.copy(status = DownloadStatus.PENDING, lastErrorCode = "", lastErrorMessage = ""))
        return task.taskId
    }

    fun retryDownload(taskId: String): Boolean {
        val task = tasks[taskId] ?: loadTask(taskId) ?: return false
        launchDownload(
            task.copy(
                status = DownloadStatus.PENDING,
                retryCount = 0,
                lastErrorCode = "",
                lastErrorMessage = "",
                updatedAt = System.currentTimeMillis()
            )
        )
        return true
    }

    fun cancelDownload(taskId: String): Boolean {
        jobs.remove(taskId)?.cancel()
        val task = tasks[taskId] ?: loadTask(taskId)
        if (task != null) {
            File(task.tempFilePath).delete()
            File(task.finalFilePath).delete()
            File(task.stateFilePath).delete()
            val cancelled = task.withStatus(DownloadStatus.CANCELLED)
            tasks[taskId] = cancelled
            emit(cancelled)
        }
        return task != null
    }

    fun completedFile(taskId: String): File? {
        val task = tasks[taskId] ?: loadTask(taskId) ?: return null
        val file = File(task.finalFilePath)
        return if (file.exists() && file.length() > 0L) file else null
    }

    private fun launchDownload(task: DownloadTask) {
        jobs.remove(task.taskId)?.cancel()
        tasks[task.taskId] = task
        jobs[task.taskId] = scope.launch {
            try {
                runWithRetry(task)
            } catch (_: CancellationException) {
                // cancelDownload emits the terminal event and removes files.
            } finally {
                jobs.remove(task.taskId)
            }
        }
    }

    private suspend fun runWithRetry(initialTask: DownloadTask) {
        var task = initialTask
        var attempt = 0
        while (true) {
            try {
                performDownload(task.copy(retryCount = attempt))
                return
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val downloaded = File(task.tempFilePath).takeIf { it.exists() }?.length() ?: 0L
                if (attempt >= retryDelaysMs.size) {
                    val failed = task.withStatus(
                        DownloadStatus.FAILED,
                        downloaded = downloaded,
                        nextRetryCount = attempt,
                        errorCode = "DOWNLOAD_FAILED",
                        errorMessage = e.message ?: e.javaClass.simpleName
                    )
                    tasks[task.taskId] = failed
                    writeState(failed)
                    emit(failed)
                    return
                }

                val retrying = task.withStatus(
                    DownloadStatus.RETRYING,
                    downloaded = downloaded,
                    nextRetryCount = attempt + 1,
                    errorCode = "NETWORK_RETRY",
                    errorMessage = e.message ?: e.javaClass.simpleName
                )
                tasks[task.taskId] = retrying
                writeState(retrying)
                emit(retrying)
                delay(retryDelaysMs[attempt])
                task = retrying.copy(status = DownloadStatus.PENDING)
                attempt += 1
            }
        }
    }

    private suspend fun performDownload(inputTask: DownloadTask) {
        var task = inputTask.withStatus(DownloadStatus.CHECKING)
        tasks[task.taskId] = task
        writeState(task)
        emit(task)

        val remote = probeRemote(task.url)
        val partFile = File(task.tempFilePath)
        val finalFile = File(task.finalFilePath)

        if (remoteChanged(task, remote)) {
            partFile.delete()
            finalFile.delete()
            task = task.copy(downloadedBytes = 0L)
        }

        task = task.withRemoteInfo(remote.totalBytes, remote.etag, remote.lastModified)
        tasks[task.taskId] = task
        writeState(task)

        var downloaded = if (partFile.exists()) partFile.length() else 0L
        var connection = openGetConnection(task.url, downloaded)
        var responseCode = connection.responseCode

        if (downloaded > 0L && responseCode == HttpURLConnection.HTTP_OK) {
            connection.disconnect()
            partFile.delete()
            downloaded = 0L
            connection = openGetConnection(task.url, 0L)
            responseCode = connection.responseCode
        }

        if (downloaded > 0L && responseCode == HTTP_REQUESTED_RANGE_NOT_SATISFIABLE) {
            connection.disconnect()
            if (remote.totalBytes > 0L && partFile.length() == remote.totalBytes) {
                completeDownload(task, partFile, finalFile, remote.totalBytes)
                return
            }
            partFile.delete()
            performDownload(task.copy(downloadedBytes = 0L))
            return
        }

        if (responseCode != HttpURLConnection.HTTP_OK &&
            responseCode != HttpURLConnection.HTTP_PARTIAL
        ) {
            val message = connection.errorStream?.bufferedReader()?.use { it.readText() }
            connection.disconnect()
            throw IllegalStateException("HTTP $responseCode ${message.orEmpty()}".trim())
        }

        val totalBytes = resolveTotalBytes(connection, responseCode, remote.totalBytes)
        task = task.withStatus(
            DownloadStatus.DOWNLOADING,
            downloaded = downloaded,
            total = totalBytes
        ).withRemoteInfo(totalBytes, remote.etag, remote.lastModified)
        tasks[task.taskId] = task
        writeState(task)
        emit(task)

        val startedAt = System.currentTimeMillis()
        val startedBytes = downloaded
        var lastEmitAt = 0L
        var lastStateBytes = downloaded
        val buffer = ByteArray(64 * 1024)

        connection.inputStream.use { input ->
            RandomAccessFile(partFile, "rw").use { output ->
                if (downloaded > 0L) {
                    output.seek(downloaded)
                } else {
                    output.setLength(0L)
                }

                while (true) {
                    currentCoroutineContext().ensureActive()
                    val bytesRead = input.read(buffer)
                    if (bytesRead == -1) break
                    output.write(buffer, 0, bytesRead)
                    downloaded += bytesRead.toLong()

                    val now = System.currentTimeMillis()
                    val shouldEmit = now - lastEmitAt >= 500L
                    val shouldPersist = downloaded - lastStateBytes >= 256L * 1024L
                    if (shouldEmit || shouldPersist) {
                        task = task.withStatus(
                            DownloadStatus.DOWNLOADING,
                            downloaded = downloaded,
                            total = totalBytes
                        )
                        tasks[task.taskId] = task
                        if (shouldPersist) {
                            writeState(task)
                            lastStateBytes = downloaded
                        }
                        if (shouldEmit) {
                            emit(task, speedBytesPerSecond(startedBytes, downloaded, startedAt, now))
                            lastEmitAt = now
                        }
                    }
                }
            }
        }
        connection.disconnect()

        task = task.withStatus(DownloadStatus.DOWNLOADING, downloaded = downloaded, total = totalBytes)
        writeState(task)
        completeDownload(task, partFile, finalFile, totalBytes)
    }

    private fun completeDownload(
        task: DownloadTask,
        partFile: File,
        finalFile: File,
        totalBytes: Long
    ) {
        if (totalBytes > 0L && partFile.length() != totalBytes) {
            throw IllegalStateException("文件大小不一致: ${partFile.length()} != $totalBytes")
        }

        if (finalFile.exists()) finalFile.delete()
        if (!partFile.renameTo(finalFile)) {
            partFile.copyTo(finalFile, overwrite = true)
            partFile.delete()
        }

        if (task.sha256.isNotBlank()) {
            val actual = sha256(finalFile)
            if (!actual.equals(task.sha256, ignoreCase = true)) {
                finalFile.delete()
                throw IllegalStateException("SHA256 校验失败")
            }
        }

        val completed = task.withStatus(
            DownloadStatus.COMPLETED,
            downloaded = finalFile.length(),
            total = if (totalBytes > 0L) totalBytes else finalFile.length()
        )
        tasks[task.taskId] = completed
        writeState(completed)
        emit(completed)
    }

    private fun loadOrCreateTask(
        url: String,
        fileName: String,
        version: String,
        sha256: String
    ): DownloadTask {
        val safeFileName = safeApkFileName(fileName)
        val taskId = taskIdFor(safeFileName, version)
        val stateFile = stateFileFor(taskId)
        val existing = readTask(stateFile)
        if (existing != null && existing.url == url) {
            tasks[taskId] = existing
            return existing
        }

        val finalFile = File(updatesDir, safeFileName)
        val partFile = File(updatesDir, "$safeFileName.part")
        val task = DownloadTask(
            taskId = taskId,
            type = DownloadTaskType.APK_UPDATE,
            url = url,
            fileName = safeFileName,
            version = version,
            tempFilePath = partFile.absolutePath,
            finalFilePath = finalFile.absolutePath,
            stateFilePath = stateFile.absolutePath,
            sha256 = sha256
        )
        tasks[taskId] = task
        writeState(task)
        return task
    }

    private fun loadTask(taskId: String): DownloadTask? {
        return readTask(stateFileFor(taskId))?.also { tasks[taskId] = it }
    }

    private fun readTask(file: File): DownloadTask? {
        if (!file.exists()) return null
        return try {
            DownloadTask.fromJson(JSONObject(file.readText()))
        } catch (_: Exception) {
            file.delete()
            null
        }
    }

    private fun writeState(task: DownloadTask) {
        val stateFile = File(task.stateFilePath)
        val tmpFile = File("${task.stateFilePath}.tmp")
        if (!stateFile.parentFile.exists()) stateFile.parentFile.mkdirs()
        tmpFile.writeText(task.toJson().toString())
        if (stateFile.exists()) stateFile.delete()
        if (!tmpFile.renameTo(stateFile)) {
            throw IllegalStateException("无法写入下载状态文件")
        }
    }

    private fun emit(task: DownloadTask, speed: Long = 0L) {
        val etaSeconds = if (speed > 0L && task.totalBytes > task.downloadedBytes) {
            ((task.totalBytes - task.downloadedBytes) / speed).coerceAtLeast(0L)
        } else {
            -1L
        }
        val progress = if (task.totalBytes > 0L) {
            (task.downloadedBytes * 100L / task.totalBytes).toInt().coerceIn(0, 100)
        } else {
            -1
        }
        emitEvent(
            mapOf(
                "taskId" to task.taskId,
                "type" to "apk_update",
                "status" to task.status.name.lowercase(Locale.US),
                "downloadedBytes" to task.downloadedBytes,
                "totalBytes" to task.totalBytes,
                "progress" to progress,
                "speedBytesPerSecond" to speed,
                "etaSeconds" to etaSeconds,
                "retryCount" to task.retryCount,
                "filePath" to if (task.status == DownloadStatus.COMPLETED) task.finalFilePath else "",
                "errorCode" to task.lastErrorCode,
                "errorMessage" to task.lastErrorMessage
            )
        )
    }

    private fun speedBytesPerSecond(
        startedBytes: Long,
        downloadedBytes: Long,
        startedAt: Long,
        now: Long
    ): Long {
        val elapsed = max(1L, now - startedAt)
        return ((downloadedBytes - startedBytes) * 1000L / elapsed).coerceAtLeast(0L)
    }

    private fun openGetConnection(url: String, downloaded: Long): HttpURLConnection {
        return (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 15_000
            readTimeout = 60_000
            setRequestProperty("Accept", "application/octet-stream")
            setRequestProperty("User-Agent", "python_runner-updater")
            if (downloaded > 0L) {
                setRequestProperty("Range", "bytes=$downloaded-")
            }
            instanceFollowRedirects = true
            connect()
        }
    }

    private fun probeRemote(url: String): RemoteInfo {
        return try {
            val connection = (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = "HEAD"
                connectTimeout = 15_000
                readTimeout = 30_000
                setRequestProperty("User-Agent", "python_runner-updater")
                instanceFollowRedirects = true
                connect()
            }
            val code = connection.responseCode
            if (code !in 200..399) {
                connection.disconnect()
                probeRemoteWithRange(url)
            } else {
                RemoteInfo(
                    totalBytes = connection.getHeaderFieldLong("Content-Length", -1L),
                    etag = connection.getHeaderField("ETag") ?: "",
                    lastModified = connection.getHeaderField("Last-Modified") ?: ""
                ).also {
                    connection.disconnect()
                }
            }
        } catch (_: Exception) {
            probeRemoteWithRange(url)
        }
    }

    private fun probeRemoteWithRange(url: String): RemoteInfo {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 15_000
            readTimeout = 30_000
            setRequestProperty("User-Agent", "python_runner-updater")
            setRequestProperty("Range", "bytes=0-0")
            instanceFollowRedirects = true
            connect()
        }
        val total = parseContentRangeTotal(connection.getHeaderField("Content-Range"))
            ?: connection.getHeaderFieldLong("Content-Length", -1L)
        return RemoteInfo(
            totalBytes = total,
            etag = connection.getHeaderField("ETag") ?: "",
            lastModified = connection.getHeaderField("Last-Modified") ?: ""
        ).also {
            connection.inputStream.close()
            connection.disconnect()
        }
    }

    private fun resolveTotalBytes(
        connection: HttpURLConnection,
        responseCode: Int,
        probedTotal: Long
    ): Long {
        if (probedTotal > 0L) return probedTotal
        if (responseCode == HttpURLConnection.HTTP_PARTIAL) {
            parseContentRangeTotal(connection.getHeaderField("Content-Range"))?.let { return it }
        }
        return connection.getHeaderFieldLong("Content-Length", -1L)
    }

    private fun parseContentRangeTotal(contentRange: String?): Long? {
        if (contentRange.isNullOrBlank()) return null
        val slashIndex = contentRange.lastIndexOf('/')
        if (slashIndex < 0 || slashIndex == contentRange.lastIndex) return null
        return contentRange.substring(slashIndex + 1).toLongOrNull()
    }

    private fun remoteChanged(task: DownloadTask, remote: RemoteInfo): Boolean {
        if (task.etag.isNotBlank() && remote.etag.isNotBlank() && task.etag != remote.etag) {
            return true
        }
        if (task.lastModified.isNotBlank() &&
            remote.lastModified.isNotBlank() &&
            task.lastModified != remote.lastModified
        ) {
            return true
        }
        return false
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(64 * 1024)
        file.inputStream().use { input ->
            while (true) {
                val read = input.read(buffer)
                if (read == -1) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun taskIdFor(fileName: String, version: String): String {
        val base = if (version.isBlank()) fileName else "$version-$fileName"
        return "apk-update-${sanitize(base)}"
    }

    private fun stateFileFor(taskId: String): File = File(updatesDir, "$taskId.task_state.json")

    private fun safeApkFileName(fileName: String): String {
        val clean = fileName.substringAfterLast('/').substringAfterLast('\\')
        return if (clean.lowercase(Locale.US).endsWith(".apk")) clean else "$clean.apk"
    }

    private fun sanitize(value: String): String {
        return value.lowercase(Locale.US)
            .replace(Regex("[^a-z0-9._-]+"), "-")
            .trim('-')
            .ifBlank { "download" }
    }

    private data class RemoteInfo(
        val totalBytes: Long,
        val etag: String,
        val lastModified: String
    )
}
