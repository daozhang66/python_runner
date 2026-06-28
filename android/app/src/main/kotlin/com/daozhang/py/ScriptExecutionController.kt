package com.daozhang.py

import android.os.Handler
import com.chaquo.python.Python
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.util.concurrent.TimeUnit

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
        private const val LINUX_LIKE_GRACEFUL_STOP_MS = 300L
    }

    private val executionStateLock = Any()
    private var currentExecutionThread: Thread? = null
    private var currentExecutionProcess: Process? = null
    private var currentExecutionId: String? = null
    @Volatile private var currentExecutionStopRequested = false

    // --- Script Execution ---

    fun executeScript(name: String, executionId: String, workingDir: String?, hookEnv: Map<String, String>?, timeoutSeconds: Int, result: MethodChannel.Result) {
        // If a previous execution is still running, force-stop it first
        val oldThread = synchronized(executionStateLock) { currentExecutionThread }
        if (oldThread != null && oldThread.isAlive) {
            try {
                val py = Python.getInstance()
                val runner = py.getModule("script_runner")
                runner.callAttr("stop_running")
            } catch (_: Exception) {}
            // Send completion status for the old execution
            val oldId = synchronized(executionStateLock) { currentExecutionId }
            if (oldId != null) {
                sendStatus(oldId, "stopped", 0)
            }
            // Wait briefly for the old thread to actually terminate
            // so it doesn't interfere with the new execution
            try {
                oldThread.join(2000)
            } catch (_: Exception) {}
            synchronized(executionStateLock) {
                currentExecutionThread = null
                currentExecutionId = null
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

        synchronized(executionStateLock) {
            currentExecutionId = executionId
        }

        // Start foreground service to keep alive in background
        startForegroundExecution(name)

        sendStatus(executionId, "running", null)
        result.success(mapOf("executionId" to executionId, "status" to "started"))

        val code = file.readText()
        val scriptFilePath = file.absolutePath
        val scriptDone = java.util.concurrent.atomic.AtomicBoolean(false)

        // Serialize hookEnv to JSON string for passing to Python
        val hookEnvJson = if (hookEnv != null && hookEnv.isNotEmpty()) {
            try {
                val jsonObj = JSONObject()
                for ((k, v) in hookEnv) {
                    jsonObj.put(k, v)
                }
                jsonObj.toString()
            } catch (_: Exception) { "" }
        } else { "" }

        // Polling thread: reads output from Python's queue and forwards to Flutter
        Thread {
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
                } catch (e: Exception) {
                    // Don't silently die 鈥?check if script is still running
                    if (scriptDone.get()) break
                    Thread.sleep(200)
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
            } catch (_: Exception) {}
        }.also { it.name = "output-poll"; it.isDaemon = true; it.start() }

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
                    synchronized(executionStateLock) { currentExecutionStopRequested } -> "stopped"
                    exitCode == 0 -> "completed"
                    else -> "error"
                }
                sendStatus(
                    executionId,
                    finalStatus,
                    if (finalStatus == "stopped") 0 else exitCode
                )
                synchronized(executionStateLock) {
                    currentExecutionId = null
                    currentExecutionThread = null
                }
                // Stop foreground service
                stopForegroundService()
            }
        }.also { it.name = "python-exec" }
        synchronized(executionStateLock) {
            currentExecutionThread = executionThread
        }
        executionThread.start()

        // Watchdog thread: kill script if it exceeds the timeout
        if (timeoutSeconds > 0) {
            Thread {
                try {
                    val timeoutMs = timeoutSeconds * 1000L
                    Thread.sleep(timeoutMs)
                    if (!scriptDone.get()) {
                        // Script is still running 鈥?kill it
                        try {
                            val py = Python.getInstance()
                            val runner = py.getModule("script_runner")
                            runner.callAttr("stop_running")
                        } catch (_: Exception) {}
                        // Wait for exec thread to finish
                        synchronized(executionStateLock) { currentExecutionThread }?.join(3000)
                        if (!scriptDone.get()) {
                            scriptDone.set(true)
                            sendLog(
                                "stderr",
                                "脚本执行超时（${timeoutSeconds}秒），已强制停止",
                                executionId
                            )
                            sendStatus(executionId, "timeout", 1)
                            synchronized(executionStateLock) {
                                currentExecutionId = null
                                currentExecutionThread = null
                            }
                            stopForegroundService()
                        }
                    }
                } catch (_: InterruptedException) {}
            }.also { it.name = "timeout-watchdog"; it.isDaemon = true; it.start() }
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
            try {
                val py = Python.getInstance()
                val runner = py.getModule("script_runner")
                runner.callAttr("stop_running")
            } catch (_: Exception) {}
            // Send "stopping" status so Flutter UI updates immediately
            val execId = synchronized(executionStateLock) { currentExecutionId }
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
        val info = linuxLikeRuntimeManager.getInfo()
        if (info["available"] != "true") {
            result.error("1017", info["message"] ?: "Linux-like runtime unavailable", null)
            return
        }

        val oldProcess = synchronized(executionStateLock) { currentExecutionProcess }
        if (oldProcess != null && oldProcess.isAlive) {
            synchronized(executionStateLock) {
                currentExecutionStopRequested = true
            }
            stopProcessTree(oldProcess)
            try {
                oldProcess.waitFor(LINUX_LIKE_GRACEFUL_STOP_MS, TimeUnit.MILLISECONDS)
            } catch (_: Exception) {}
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
            currentExecutionStopRequested = false
        }
        startForegroundExecution(executionTarget.displayName)

        sendStatus(executionId, "running", null)
        result.success(mapOf("executionId" to executionId, "status" to "started"))

        val executionEnvironment = environment?.toMutableMap() ?: mutableMapOf()
        val resolvedWorkingDir = executionTarget.workingDir
        executionEnvironment["HOME"] = resolvedWorkingDir
        executionTarget.pycacheCleanupRoots.forEach { deletePythonCacheDirectories(it) }
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
            val stdout = StringBuilder()
            val stderr = StringBuilder()
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

                val stdoutThread =
                    collectProcessOutput(process.inputStream, "stdout", stdout, true, executionId)
                val stderrThread =
                    collectProcessOutput(process.errorStream, "stderr", stderr, true, executionId)

                if (timeoutSeconds > 0) {
                    Thread {
                        try {
                            Thread.sleep(timeoutSeconds * 1000L)
                            if (process.isAlive) {
                                timedOut.set(true)
                                synchronized(executionStateLock) {
                                    currentExecutionStopRequested = true
                                }
                                sendLog(
                                    "stderr",
                                    "脚本执行超时（${timeoutSeconds}秒），已强制停止",
                                    executionId
                                )
                                stopProcessTree(process)
                            }
                        } catch (_: InterruptedException) {}
                    }.also { it.name = "linux-like-timeout-watchdog"; it.isDaemon = true; it.start() }
                }

                exitCode = process.waitFor()
                stdoutThread.join(500)
                stderrThread.join(500)
                status = when {
                    timedOut.get() -> "timeout"
                    synchronized(executionStateLock) { currentExecutionStopRequested } -> "stopped"
                    exitCode == 0 -> "completed"
                    else -> "error"
                }
                if (status == "error" || status == "timeout") {
                    writeScriptErrorLog(
                        executionTarget.displayName,
                        "Linux-like process exited with code $exitCode",
                        "stdout:\n${stdout.takeLast(4000)}\n\nstderr:\n${stderr.takeLast(4000)}"
                    )
                }
            } catch (e: Throwable) {
                sendLog("stderr", "Linux-like执行错误: ${e.message}", executionId)
                status = if (synchronized(executionStateLock) { currentExecutionStopRequested }) "stopped" else "error"
                exitCode = 1
                writeScriptErrorLog(executionTarget.displayName, e.message ?: "Unknown error", e.stackTrace.joinToString("\n"))
            } finally {
                executionTarget.pycacheCleanupRoots.forEach { deletePythonCacheDirectories(it) }
                synchronized(executionStateLock) {
                    currentExecutionProcess = null
                    currentExecutionThread = null
                    currentExecutionId = null
                }
                linuxLikeRuntimeManager.cleanupExecutionTempDir(executionTempDir)
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
                currentExecutionStopRequested = true
                currentExecutionId
            }
            if (execId != null) sendStatus(execId, "stopping", null)
            process.destroy()
            Thread {
                try {
                    Thread.sleep(LINUX_LIKE_GRACEFUL_STOP_MS)
                    if (process.isAlive) stopProcessTree(process, forceOnly = true)
                } catch (_: InterruptedException) {}
            }.also { it.name = "linux-like-stop"; it.isDaemon = true; it.start() }
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

    private fun stopProcessTree(process: Process, forceOnly: Boolean = false) {
        val pid = processPid(process)
        if (!forceOnly) {
            process.destroy()
            pid?.let { killProcessTree(it, force = false) }
            Thread.sleep(LINUX_LIKE_GRACEFUL_STOP_MS)
        }
        pid?.let { killProcessTree(it, force = true) }
        if (process.isAlive) process.destroyForcibly()
    }

    private fun processPid(process: Process): Int? {
        return try {
            val field = process.javaClass.getDeclaredField("pid")
            field.isAccessible = true
            field.getInt(process)
        } catch (_: Throwable) {
            null
        }
    }

    private fun killProcessTree(rootPid: Int, force: Boolean) {
        val pids = collectDescendantPids(rootPid).asReversed() + rootPid
        pids.forEach { pid ->
            try {
                android.os.Process.sendSignal(pid, if (force) 9 else 15)
            } catch (_: Throwable) {
                if (force) {
                    try {
                        android.os.Process.killProcess(pid)
                    } catch (_: Throwable) {
                    }
                }
            }
        }
    }

    private fun collectDescendantPids(rootPid: Int): List<Int> {
        val result = linkedSetOf<Int>()
        val queue = ArrayDeque<Int>()
        queue.add(rootPid)
        while (queue.isNotEmpty()) {
            val pid = queue.removeFirst()
            readDirectChildPids(pid).forEach { child ->
                if (result.add(child)) queue.add(child)
            }
        }
        return result.toList()
    }

    private fun readDirectChildPids(pid: Int): List<Int> {
        val fromTaskChildren = try {
            File("/proc/$pid/task").listFiles()
                ?.flatMap { task ->
                    File(task, "children").takeIf { it.isFile }
                        ?.readText()
                        ?.split(Regex("\\s+"))
                        ?.mapNotNull { it.toIntOrNull() }
                        ?: emptyList()
                }
                ?.distinct()
                ?: emptyList()
        } catch (_: Exception) {
            emptyList()
        }
        if (fromTaskChildren.isNotEmpty()) return fromTaskChildren

        return try {
            File("/proc").listFiles()
                ?.mapNotNull { entry ->
                    val childPid = entry.name.toIntOrNull() ?: return@mapNotNull null
                    val status = File(entry, "status")
                    if (!status.isFile) return@mapNotNull null
                    val parentPid = status.useLines { lines ->
                        lines.firstOrNull { it.startsWith("PPid:") }
                            ?.substringAfter(':')
                            ?.trim()
                            ?.toIntOrNull()
                    }
                    if (parentPid == pid) childPid else null
                }
                ?: emptyList()
        } catch (_: Exception) {
            emptyList()
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
        val stdout = StringBuilder()
        val stderr = StringBuilder()
        val stdoutThread = collectProcessOutput(process.inputStream, "stdout", stdout, emitLogs)
        val stderrThread = collectProcessOutput(process.errorStream, "stderr", stderr, emitLogs)
        return try {
            val exitCode = process.waitFor()
            stdoutThread.join(500)
            stderrThread.join(500)
            LinuxLikeCommandResult(
                exitCode = exitCode,
                stdout = stdout.toString(),
                stderr = stderr.toString()
            )
        } finally {
            linuxLikeRuntimeManager.cleanupExecutionTempDir(executionTempDir)
        }
    }

    private fun collectProcessOutput(
        inputStream: java.io.InputStream,
        type: String,
        buffer: StringBuilder,
        emitLogs: Boolean,
        executionId: String? = null
    ): Thread {
        return Thread {
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
                        buffer.append(line).append('\n')
                        if (emitLogs) sendLog(type, line, executionId)
                    }
                }
            } catch (_: Exception) {}
        }.also { it.name = "linux-like-capture-$type"; it.isDaemon = true; it.start() }
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
