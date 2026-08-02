package com.daozhang.py

import android.os.Handler
import android.util.Log
import com.chaquo.python.Python
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class ScriptExecutionController(
    private val mainHandler: Handler,
    private val scriptFileStore: ScriptFileStore,
    private val scriptProjectStore: ScriptProjectStore,
    private val linuxLikeRuntimeManager: LinuxLikeRuntimeManager,
    private val sendLog: (String, String, String?) -> Unit,
    private val sendStatusEvent: (String, String, Int?) -> Unit,
    private val emitStdinRequestEvent: (String?, String) -> Unit,
    private val startForegroundExecution: (String) -> Unit,
    private val stopForegroundService: () -> Unit,
    private val writeScriptErrorLog: (String, String, String?) -> Unit,
    private val deletePythonCacheDirectories: (File) -> Unit
) {
    companion object {
        private const val TAG = "ScriptExecution"
        private const val LINUX_LIKE_GRACEFUL_STOP_MS = 300L
        private const val MAX_CAPTURED_OUTPUT_CHARS = 256 * 1024
    }

    private class BoundedOutputBuffer(private val maxChars: Int) {
        private val content = StringBuilder()
        private var truncated = false

        fun appendLine(line: String) {
            content.append(line).append('\n')
            if (content.length > maxChars) {
                content.delete(0, content.length - maxChars)
                truncated = true
            }
        }

        fun tail(limit: Int): String {
            val prefix = if (truncated) "[输出已截断]\n" else ""
            return prefix + content.takeLast(limit)
        }

        override fun toString(): String =
            (if (truncated) "[输出已截断]\n" else "") + content.toString()
    }

    private data class ProcessOutputCapture(
        val thread: Thread,
        val failed: AtomicBoolean
    )

    private val executionStateLock = Any()
    private var currentExecutionThread: Thread? = null
    private var currentExecutionProcess: Process? = null
    private var currentExecutionId: String? = null
    private var currentExecutionStopRequested: AtomicBoolean? = null
    private var currentOutputPollThread: Thread? = null
    private var currentWatchdogThread: Thread? = null

    private fun reportFailure(
        operation: String,
        error: Throwable,
        executionId: String? = null,
        notifyConsole: Boolean = true
    ) {
        val detail = "${error.javaClass.simpleName}: ${error.message ?: "unknown"}"
        val suffix = executionId?.let { " (executionId=$it)" }.orEmpty()
        Log.w(TAG, "$operation 失败$suffix: $detail", error)
        if (notifyConsole && executionId != null) {
            sendLog("stderr", "[运行时警告] $operation 失败：$detail", executionId)
        }
    }

    // --- Script Execution ---

    fun executeScript(name: String, executionId: String, workingDir: String?, hookEnv: Map<String, String>?, timeoutSeconds: Int, result: MethodChannel.Result) {
        // If a previous execution is still running, force-stop it first
        val oldThread = synchronized(executionStateLock) { currentExecutionThread }
        if (oldThread != null && oldThread.isAlive) {
            val oldExecutionId = synchronized(executionStateLock) { currentExecutionId }
            try {
                val py = Python.getInstance()
                val runner = py.getModule("script_runner")
                runner.callAttr("stop_running")
            } catch (e: Exception) {
                reportFailure("停止上一轮 Chaquopy 执行", e, oldExecutionId)
            }
            synchronized(executionStateLock) {
                currentExecutionStopRequested?.set(true)
                currentOutputPollThread?.interrupt()
                currentWatchdogThread?.interrupt()
            }
        }

        val file = try {
            scriptFileStore.safeScriptFile(name)
        } catch (e: IllegalArgumentException) {
            result.error("1001", e.message ?: "非法脚本名称", null)
            return
        }
        if (!file.exists()) {
            result.error("1001", "脚本不存在 $name", null)
            return
        }

        val hookEnvJson = if (hookEnv != null && hookEnv.isNotEmpty()) {
            try {
                JSONObject().apply {
                    hookEnv.forEach { (key, value) -> put(key, value) }
                }.toString()
            } catch (e: Exception) {
                reportFailure("序列化脚本 Hook 环境", e, executionId, notifyConsole = false)
                result.error("1002", "脚本 Hook 环境无效: ${e.message}", null)
                return
            }
        } else {
            ""
        }

        // Start foreground service to keep alive in background
        startForegroundExecution(name)

        sendStatus(executionId, "running", null)
        result.success(mapOf("executionId" to executionId, "status" to "started"))

        val code = file.readText()
        val scriptFilePath = file.absolutePath
        val scriptDone = AtomicBoolean(false)
        val stopRequested = AtomicBoolean(false)
        val timedOut = AtomicBoolean(false)
        val terminalSent = AtomicBoolean(false)
        fun finish(status: String, exitCode: Int?) {
            if (!terminalSent.compareAndSet(false, true)) return
            sendStatus(executionId, status, exitCode)
            val wasCurrent = synchronized(executionStateLock) {
                if (currentExecutionId == executionId) {
                    currentExecutionId = null
                    currentExecutionThread = null
                    currentOutputPollThread = null
                    currentWatchdogThread = null
                    currentExecutionStopRequested = null
                    true
                } else {
                    false
                }
            }
            if (wasCurrent) stopForegroundService()
        }
        synchronized(executionStateLock) {
            currentExecutionId = executionId
            currentExecutionStopRequested = stopRequested
        }

        // Polling thread: reads output from Python's queue and forwards to Flutter
        val pollThread = Thread {
            val py = Python.getInstance()
            val runner = py.getModule("script_runner")
            while (!scriptDone.get()) {
                try {
                    val items = runner.callAttr("poll_output")
                    val length = items.callAttr("__len__").toInt()
                    for (i in 0 until length) {
                        val item = items.callAttr("__getitem__", i)
                        val type = item.callAttr("__getitem__", 0).toString()
                        val content = item.callAttr("__getitem__", 1).toString()
                        if (type == "__stdin_request__") {
                            emitStdinRequest(executionId)
                        } else {
                            sendLog(type, content, executionId)
                        }
                    }
                    Thread.sleep(50)
                } catch (_: InterruptedException) {
                    break
                } catch (e: Exception) {
                    if (scriptDone.get()) break
                    reportFailure("读取 Chaquopy 输出", e, executionId)
                    try {
                        Thread.sleep(200)
                    } catch (_: InterruptedException) {
                        break
                    }
                }
            }
            // Final poll to flush remaining output
            try {
                val items = runner.callAttr("poll_output")
                val length = items.callAttr("__len__").toInt()
                for (i in 0 until length) {
                    val item = items.callAttr("__getitem__", i)
                    val type = item.callAttr("__getitem__", 0).toString()
                    val content = item.callAttr("__getitem__", 1).toString()
                    if (type != "__stdin_request__") {
                        sendLog(type, content, executionId)
                    }
                }
            } catch (e: Exception) {
                // The script has already reached a terminal path; retain that
                // result while leaving a Logcat breadcrumb for lost tail output.
                reportFailure("刷新 Chaquopy 剩余输出", e, executionId, notifyConsole = false)
            }
        }.also { it.name = "output-poll"; it.isDaemon = true }
        synchronized(executionStateLock) { currentOutputPollThread = pollThread }
        pollThread.start()

        // Execution thread
        val executionThread = Thread {
            var exitCode = 0
            try {
                val py = Python.getInstance()
                val runner = py.getModule("script_runner")
                val result2 = runner.callAttr("run_script", code, workingDir ?: "", hookEnvJson, scriptFilePath)
                exitCode = result2.callAttr("get", "exit_code").toInt()
            } catch (e: Exception) {
                sendLog("stderr", "执行错误: ${e.message}", executionId)
                exitCode = 1
                // Persist script error to log file for post-mortem debugging
                writeScriptErrorLog(name, e.message ?: "Unknown error", e.stackTrace?.toString())
            } finally {
                scriptDone.set(true)
                // Small delay to let the polling thread flush remaining output
                Thread.sleep(200)
                val finalStatus = when {
                    timedOut.get() -> "timeout"
                    stopRequested.get() -> "stopped"
                    exitCode == 0 -> "completed"
                    else -> "error"
                }
                finish(finalStatus, if (finalStatus == "stopped") 0 else exitCode)
            }
        }.also { it.name = "python-exec" }
        synchronized(executionStateLock) {
            currentExecutionThread = executionThread
        }
        executionThread.start()

        // Watchdog thread: kill script if it exceeds the timeout
        if (timeoutSeconds > 0) {
            val watchdogThread = Thread {
                try {
                    val timeoutMs = timeoutSeconds.toLong()
                        .coerceAtMost(Long.MAX_VALUE / 1000L) * 1000L
                    Thread.sleep(timeoutMs)
                    if (!scriptDone.get()) {
                        // Script is still running 鈥?kill it
                        timedOut.set(true)
                        sendLog(
                            "stderr",
                            "脚本执行超时（${timeoutSeconds}秒），正在停止",
                            executionId
                        )
                        try {
                            val py = Python.getInstance()
                            val runner = py.getModule("script_runner")
                            runner.callAttr("stop_running")
                        } catch (e: Exception) {
                            reportFailure("超时停止 Chaquopy 脚本", e, executionId)
                        }
                        // Wait for exec thread to finish
                        executionThread.join(3000)
                        if (!scriptDone.get()) {
                            scriptDone.set(true)
                            finish("timeout", 1)
                        }
                    }
                } catch (_: InterruptedException) {}
            }.also { it.name = "timeout-watchdog"; it.isDaemon = true }
            synchronized(executionStateLock) { currentWatchdogThread = watchdogThread }
            watchdogThread.start()
        }
    }

    fun sendStdin(input: String, result: MethodChannel.Result) {
        Thread {
            try {
                val py = Python.getInstance()
                val runner = py.getModule("script_runner")
                runner.callAttr("provide_stdin", input)
                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                mainHandler.post { result.error("1007", "发送输入失败: ${e.message}", null) }
            }
        }.also { it.name = "stdin-send"; it.start() }
    }

    fun stopExecution(result: MethodChannel.Result) {
        val thread = synchronized(executionStateLock) { currentExecutionThread }
        if (thread != null && thread.isAlive) {
            val executionId = synchronized(executionStateLock) { currentExecutionId }
            try {
                val py = Python.getInstance()
                val runner = py.getModule("script_runner")
                runner.callAttr("stop_running")
            } catch (e: Exception) {
                reportFailure("停止 Chaquopy 脚本", e, executionId)
            }
            // Send "stopping" status so Flutter UI updates immediately
            val execId = synchronized(executionStateLock) {
                currentExecutionStopRequested?.set(true)
                currentExecutionId
            }
            if (execId != null) {
                sendStatus(execId, "stopping", null)
            }
            result.success(true)
        } else {
            result.success(false)
        }
    }

    fun executeLinuxLikeScript(
        name: String,
        executionId: String,
        workingDir: String?,
        environment: Map<String, String>?,
        timeoutSeconds: Int,
        projectKey: String?,
        projectMainFilePath: String?,
        result: MethodChannel.Result
    ) {
        val stopRequested = AtomicBoolean(false)
        val info = linuxLikeRuntimeManager.getInfo()
        if (info["available"] != "true") {
            result.error("1017", info["message"] ?: "Linux-like runtime unavailable", null)
            return
        }

        val oldProcess = synchronized(executionStateLock) { currentExecutionProcess }
        if (oldProcess != null && oldProcess.isAlive) {
            val oldExecutionId = synchronized(executionStateLock) { currentExecutionId }
            synchronized(executionStateLock) {
                currentExecutionStopRequested?.set(true)
            }
            stopProcessTree(oldProcess, executionId = oldExecutionId)
            try {
                oldProcess.waitFor(LINUX_LIKE_GRACEFUL_STOP_MS, TimeUnit.MILLISECONDS)
            } catch (e: Exception) {
                reportFailure("等待上一轮 Linux-like 进程退出", e, oldExecutionId)
            }
        }

        val executionTarget = try {
            if (!projectKey.isNullOrBlank()) {
                val safeMainPath = scriptProjectStore.normalizeProjectMainFilePath(
                    projectMainFilePath ?: throw IllegalArgumentException("项目主程序未设置")
                )
                val projectRoot = scriptProjectStore.safeProjectRoot(projectKey)
                val mainFile = scriptProjectStore.safeProjectFile(projectKey, safeMainPath)
                if (!projectRoot.isDirectory) {
                    throw IllegalArgumentException("项目目录不存在: $projectKey")
                }
                if (!mainFile.isFile) {
                    throw IllegalArgumentException("项目主程序不存在: $safeMainPath")
                }
                LinuxLikeExecutionTarget(
                    displayName = name.trim().ifBlank { scriptProjectStore.normalizeProjectKey(projectKey) },
                    scriptFile = mainFile,
                    executionFilePath = mainFile.absolutePath,
                    workingDir = projectRoot.absolutePath,
                    pythonPathEntries = listOf(
                        projectRoot.absolutePath,
                        mainFile.parentFile?.absolutePath
                    ).filterNotNull().distinct(),
                    projectRoot = projectRoot,
                    pycacheCleanupRoots = listOf(projectRoot)
                )
            } else {
                val scriptFile = scriptFileStore.safeScriptFile(name)
                if (!scriptFile.exists()) {
                    throw IllegalArgumentException("脚本不存在 $name")
                }
                val resolvedScriptWorkingDir =
                    linuxLikeRuntimeManager.resolveScriptWorkingDir(workingDir)
                LinuxLikeExecutionTarget(
                    displayName = name,
                    scriptFile = scriptFile,
                    executionFilePath = File(
                        resolvedScriptWorkingDir,
                        scriptFile.name
                    ).absolutePath,
                    workingDir = resolvedScriptWorkingDir,
                    pythonPathEntries = emptyList(),
                    pycacheCleanupRoots = listOfNotNull(
                        File(resolvedScriptWorkingDir),
                        scriptFile.parentFile
                    ).distinctBy {
                        try {
                            it.canonicalPath
                        } catch (_: Exception) {
                            it.absolutePath
                        }
                    }
                )
            }
        } catch (e: IllegalArgumentException) {
            result.error("1001", e.message ?: "非法执行目标", null)
            return
        }

        synchronized(executionStateLock) {
            currentExecutionId = executionId
            currentExecutionStopRequested = stopRequested
        }
        startForegroundExecution(executionTarget.displayName)

        sendStatus(executionId, "running", null)
        result.success(mapOf("executionId" to executionId, "status" to "started"))

        val executionEnvironment = environment?.toMutableMap() ?: mutableMapOf()
        val resolvedWorkingDir = executionTarget.workingDir
        executionEnvironment["HOME"] = resolvedWorkingDir
        executionTarget.pycacheCleanupRoots.forEach { root ->
            try {
                deletePythonCacheDirectories(root)
            } catch (e: Exception) {
                reportFailure("执行前清理 Python 缓存", e, executionId)
            }
        }
        if (executionTarget.pythonPathEntries.isNotEmpty()) {
            val existingPythonPath = executionEnvironment["PYTHONPATH"]?.takeIf { it.isNotBlank() }
            executionEnvironment["PYTHONPATH"] =
                (executionTarget.pythonPathEntries + listOfNotNull(existingPythonPath))
                    .distinct()
                    .joinToString(":")
        }

        val command = linuxLikeRuntimeManager.buildPythonCommand(
            executionTarget.scriptFile.absolutePath,
            resolvedWorkingDir,
            executionEnvironment,
            executionTarget.executionFilePath
        )
        val timedOut = java.util.concurrent.atomic.AtomicBoolean(false)

        val linuxLikeExecutionThread = Thread {
            var exitCode = 1
            var status = "error"
            val stdout = BoundedOutputBuffer(MAX_CAPTURED_OUTPUT_CHARS)
            val stderr = BoundedOutputBuffer(MAX_CAPTURED_OUTPUT_CHARS)
            var executionTempDir: String? = null
            try {
                val processBuilder = ProcessBuilder(command)
                processBuilder.redirectErrorStream(false)
                linuxLikeRuntimeManager.applyHostEnvironment(
                    processBuilder.environment(),
                    executionEnvironment
                )
                executionTempDir = processBuilder.environment()["PROOT_TMP_DIR"]
                val process = processBuilder.start()
                synchronized(executionStateLock) {
                    currentExecutionProcess = process
                }

                val stdoutCapture =
                    collectProcessOutput(process.inputStream, "stdout", stdout, true, executionId)
                val stderrCapture =
                    collectProcessOutput(process.errorStream, "stderr", stderr, true, executionId)

                if (timeoutSeconds > 0) {
                    val watchdogThread = Thread {
                        try {
                            val timeoutMs = timeoutSeconds.toLong()
                                .coerceAtMost(Long.MAX_VALUE / 1000L) * 1000L
                            Thread.sleep(timeoutMs)
                            if (process.isAlive) {
                                timedOut.set(true)
                                stopRequested.set(true)
                                sendLog(
                                    "stderr",
                                    "脚本执行超时（${timeoutSeconds}秒），已强制停止",
                                    executionId
                                )
                                stopProcessTree(process, executionId = executionId)
                            }
                        } catch (_: InterruptedException) {}
                    }.also { it.name = "linux-like-timeout-watchdog"; it.isDaemon = true }
                    synchronized(executionStateLock) {
                        if (currentExecutionId == executionId) {
                            currentWatchdogThread = watchdogThread
                        }
                    }
                    watchdogThread.start()
                }

                exitCode = process.waitFor()
                closeProcessStdin(process, executionId)
                stdoutCapture.thread.join()
                stderrCapture.thread.join()
                status = when {
                    timedOut.get() -> "timeout"
                    stopRequested.get() -> "stopped"
                    stdoutCapture.failed.get() || stderrCapture.failed.get() -> "error"
                    exitCode == 0 -> "completed"
                    else -> "error"
                }
                if (status == "error" || status == "timeout") {
                    if (stdoutCapture.failed.get() || stderrCapture.failed.get()) {
                        sendLog("stderr", "输出捕获失败，无法确认脚本输出完整性", executionId)
                    }
                    writeScriptErrorLog(
                        executionTarget.displayName,
                        "Linux-like process exited with code $exitCode",
                        "stdout:\n${stdout.tail(4000)}\n\nstderr:\n${stderr.tail(4000)}"
                    )
                }
            } catch (e: Throwable) {
                sendLog("stderr", "Linux-like执行错误: ${e.message}", executionId)
                status = if (stopRequested.get()) "stopped" else "error"
                exitCode = 1
                writeScriptErrorLog(executionTarget.displayName, e.message ?: "Unknown error", e.stackTrace.joinToString("\n"))
            } finally {
                synchronized(executionStateLock) {
                    if (currentExecutionId == executionId) {
                        currentWatchdogThread?.interrupt()
                        currentWatchdogThread = null
                    }
                }
                executionTarget.pycacheCleanupRoots.forEach { root ->
                    try {
                        deletePythonCacheDirectories(root)
                    } catch (e: Exception) {
                        reportFailure("清理 Python 缓存", e, executionId)
                    }
                }
                synchronized(executionStateLock) {
                    currentExecutionProcess = null
                    currentExecutionThread = null
                    currentExecutionId = null
                }
                try {
                    linuxLikeRuntimeManager.cleanupExecutionTempDir(executionTempDir)
                } catch (e: Exception) {
                    reportFailure("清理 Linux-like 临时目录", e, executionId)
                }
                sendStatus(executionId, status, exitCode)
                stopForegroundService()
            }
        }.also { it.name = "linux-like-exec" }
        synchronized(executionStateLock) {
            currentExecutionThread = linuxLikeExecutionThread
        }
        linuxLikeExecutionThread.start()
    }

    fun sendLinuxLikeStdin(input: String, result: MethodChannel.Result) {
        try {
            val process = synchronized(executionStateLock) { currentExecutionProcess }
            if (process == null || !process.isAlive) {
                result.success(false)
                return
            }
            process.outputStream.write((input + "\n").toByteArray(Charsets.UTF_8))
            process.outputStream.flush()
            result.success(true)
        } catch (e: Exception) {
            result.error("1018", "发送Linux-like输入失败: ${e.message}", null)
        }
    }

    fun stopLinuxLikeExecution(result: MethodChannel.Result) {
        val process = synchronized(executionStateLock) { currentExecutionProcess }
        if (process != null && process.isAlive) {
            val execId = synchronized(executionStateLock) {
                currentExecutionStopRequested?.set(true)
                currentExecutionId
            }
            if (execId != null) sendStatus(execId, "stopping", null)
            stopProcessTree(process, executionId = execId)
            result.success(true)
        } else {
            result.success(false)
        }
    }


    private data class LinuxLikeCommandResult(
        val exitCode: Int,
        val stdout: String,
        val stderr: String
    )

    private data class LinuxLikeExecutionTarget(
        val displayName: String,
        val scriptFile: File,
        val executionFilePath: String,
        val workingDir: String,
        val pythonPathEntries: List<String>,
        val projectRoot: File? = null,
        val pycacheCleanupRoots: List<File> = emptyList()
    )

    private fun stopProcessTree(
        process: Process,
        forceOnly: Boolean = false,
        executionId: String? = null
    ) {
        LinuxProcessTree.stop(process, forceOnly) { operation, error ->
            reportFailure(operation, error, executionId)
        }
    }

    /** Releases controller-owned workers when the hosting Activity goes away. */
    fun shutdown() {
        var process: Process? = null
        synchronized(executionStateLock) {
            currentExecutionStopRequested?.set(true)
            currentOutputPollThread?.interrupt()
            currentWatchdogThread?.interrupt()
            process = currentExecutionProcess
        }
        try {
            val py = Python.getInstance()
            py.getModule("script_runner").callAttr("stop_running")
        } catch (e: Exception) {
            // The interpreter may already be unavailable during teardown.
            Log.d(TAG, "Activity 销毁时停止 Chaquopy 解释器失败: ${e.message}")
        }
        val runningProcess = process
        if (runningProcess != null && runningProcess.isAlive) {
            stopProcessTree(runningProcess, executionId = synchronized(executionStateLock) { currentExecutionId })
        }
    }

    private fun runLinuxLikeCommandBlocking(
        command: List<String>,
        environment: Map<String, String>? = null,
        emitLogs: Boolean = true
    ): LinuxLikeCommandResult {
        val processBuilder = ProcessBuilder(command)
        processBuilder.redirectErrorStream(false)
        linuxLikeRuntimeManager.applyHostEnvironment(processBuilder.environment(), environment)
        val executionTempDir = processBuilder.environment()["PROOT_TMP_DIR"]
        val process = processBuilder.start()
        val stdout = BoundedOutputBuffer(MAX_CAPTURED_OUTPUT_CHARS)
        val stderr = BoundedOutputBuffer(MAX_CAPTURED_OUTPUT_CHARS)
        val stdoutCapture = collectProcessOutput(process.inputStream, "stdout", stdout, emitLogs)
        val stderrCapture = collectProcessOutput(process.errorStream, "stderr", stderr, emitLogs)
        return try {
            val exitCode = process.waitFor()
            closeProcessStdin(process, null)
            stdoutCapture.thread.join()
            stderrCapture.thread.join()
            LinuxLikeCommandResult(
                exitCode = if (stdoutCapture.failed.get() || stderrCapture.failed.get()) 1 else exitCode,
                stdout = stdout.toString(),
                stderr = if (stdoutCapture.failed.get() || stderrCapture.failed.get()) {
                    "[输出捕获失败]\n${stderr}"
                } else {
                    stderr.toString()
                }
            )
        } finally {
            try {
                linuxLikeRuntimeManager.cleanupExecutionTempDir(executionTempDir)
            } catch (e: Exception) {
                reportFailure("清理 Linux-like 命令临时目录", e, notifyConsole = false)
            }
        }
    }

    private fun collectProcessOutput(
        inputStream: java.io.InputStream,
        type: String,
        buffer: BoundedOutputBuffer,
        emitLogs: Boolean,
        executionId: String? = null
    ): ProcessOutputCapture {
        val failed = AtomicBoolean(false)
        val thread = Thread {
            try {
                BufferedReader(InputStreamReader(inputStream)).useLines { lines ->
                    lines.forEach { line ->
                        if (line.startsWith(LinuxLikeRuntimeManager.stdinRequestSentinel)) {
                            emitStdinRequest(
                                executionId,
                                parseLinuxLikePrompt(line.removePrefix(LinuxLikeRuntimeManager.stdinRequestSentinel))
                            )
                            return@forEach
                        }
                        buffer.appendLine(line)
                        if (emitLogs) sendLog(type, line, executionId)
                    }
                }
            } catch (e: Exception) {
                failed.set(true)
                reportFailure("读取 Linux-like $type 输出", e, executionId)
            }
        }.also { it.name = "linux-like-capture-$type"; it.isDaemon = true; it.start() }
        return ProcessOutputCapture(thread, failed)
    }

    private fun closeProcessStdin(process: Process, executionId: String?) {
        try {
            process.outputStream.close()
        } catch (e: Exception) {
            reportFailure("关闭 Linux-like stdin", e, executionId)
        }
    }

    private fun parseLinuxLikePrompt(payload: String): String {
        val trimmed = payload.trim()
        if (trimmed.isEmpty()) return ""
        return try {
            JSONObject(trimmed).optString("prompt", "")
        } catch (_: Exception) {
            trimmed
        }
    }


    private fun emitStdinRequest(executionId: String?, prompt: String = "") {
        emitStdinRequestEvent(executionId, prompt)
    }

    private fun sendStatus(executionId: String, status: String, exitCode: Int?) {
        sendStatusEvent(executionId, status, exitCode)
    }
}
