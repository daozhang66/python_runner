package com.daozhang.py

import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import kotlinx.coroutines.*
import java.io.File
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONObject

class MainActivity : FlutterActivity() {

    private val METHOD_CHANNEL = "com.daozhang.py/native_bridge"
    private val LOG_STREAM_CHANNEL = "com.daozhang.py/log_stream"
    private val INSTALL_PROGRESS_CHANNEL = "com.daozhang.py/install_progress"
    private val EXECUTION_STATUS_CHANNEL = "com.daozhang.py/execution_status"

    private val STDIN_REQUEST_CHANNEL = "com.daozhang.py/stdin_request"

    private var logSink: EventChannel.EventSink? = null
    private var installSink: EventChannel.EventSink? = null
    private var statusSink: EventChannel.EventSink? = null
    private var stdinRequestSink: EventChannel.EventSink? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private val coroutineScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var currentExecutionJob: Job? = null
    private var currentExecutionThread: Thread? = null
    private var currentExecutionId: String? = null
    private var batteryOptRequested = false

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        // Register native crash handler ASAP — before Flutter engine init
        val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                val dir = File(filesDir, "crash_logs")
                if (!dir.exists()) dir.mkdirs()
                val sdf = java.text.SimpleDateFormat("yyyy-MM-dd_HH-mm-ss", java.util.Locale.US)
                val ts = sdf.format(java.util.Date())
                val file = File(dir, "crash_$ts.txt")
                java.io.FileWriter(file).use { writer ->
                    writer.write("Time: $ts\n")
                    writer.write("Thread: ${thread.name}\n")
                    writer.write("Exception: ${throwable.javaClass.name}\n")
                    writer.write("Message: ${throwable.message}\n\n")
                    writer.write("Stack trace:\n")
                    throwable.printStackTrace(java.io.PrintWriter(writer))
                }
            } catch (_: Exception) {}
            // Pass to original handler (let Android show crash dialog)
            defaultHandler?.uncaughtException(thread, throwable)
        }

        super.onCreate(savedInstanceState)
    }

    private fun scriptsDir(): File {
        val dir = File(filesDir, "scripts")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(this))
        }

        // EventChannel: log_stream
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, LOG_STREAM_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    logSink = events
                }
                override fun onCancel(arguments: Any?) {
                    logSink = null
                }
            })

        // EventChannel: install_progress
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALL_PROGRESS_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    installSink = events
                }
                override fun onCancel(arguments: Any?) {
                    installSink = null
                }
            })

        // EventChannel: execution_status
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EXECUTION_STATUS_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    statusSink = events
                }
                override fun onCancel(arguments: Any?) {
                    statusSink = null
                }
            })

        // EventChannel: stdin_request
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, STDIN_REQUEST_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    stdinRequestSink = events
                }
                override fun onCancel(arguments: Any?) {
                    stdinRequestSink = null
                }
            })

        // MethodChannel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "createScript" -> {
                        val name = call.argument<String>("name") ?: ""
                        val content = call.argument<String>("content") ?: ""
                        handleCreateScript(name, content, result)
                    }
                    "deleteScript" -> {
                        val name = call.argument<String>("name") ?: ""
                        handleDeleteScript(name, result)
                    }
                    "renameScript" -> {
                        val oldName = call.argument<String>("oldName") ?: ""
                        val newName = call.argument<String>("newName") ?: ""
                        handleRenameScript(oldName, newName, result)
                    }
                    "listScripts" -> handleListScripts(result)
                    "readScript" -> {
                        val name = call.argument<String>("name") ?: ""
                        handleReadScript(name, result)
                    }
                    "saveScript" -> {
                        val name = call.argument<String>("name") ?: ""
                        val content = call.argument<String>("content") ?: ""
                        handleSaveScript(name, content, result)
                    }
                    "executeScript" -> {
                        val name = call.argument<String>("name") ?: ""
                        val executionId = call.argument<String>("executionId") ?: ""
                        val workingDir = call.argument<String>("workingDir")
                        val timeoutSeconds = call.argument<Int>("timeoutSeconds") ?: 0
                        @Suppress("UNCHECKED_CAST")
                        val hookEnv = call.argument<Map<String, String>>("hookEnv")
                        handleExecuteScript(name, executionId, workingDir, hookEnv, timeoutSeconds, result)
                    }
                    "stopExecution" -> handleStopExecution(result)
                    "sendStdin" -> {
                        val input = call.argument<String>("input") ?: ""
                        handleSendStdin(input, result)
                    }
                    "sendSceneTouch" -> {
                        val touchJson = call.argument<String>("touchJson") ?: ""
                        handleSendSceneTouch(touchJson, result)
                    }
                    "installPackage" -> {
                        val packageName = call.argument<String>("packageName") ?: ""
                        val version = call.argument<String>("version")
                        val indexUrl = call.argument<String>("indexUrl")
                        handleInstallPackage(packageName, version, indexUrl, result)
                    }
                    "uninstallPackage" -> {
                        val packageName = call.argument<String>("packageName") ?: ""
                        handleUninstallPackage(packageName, result)
                    }
                    "listInstalledPackages" -> handleListInstalledPackages(result)
                    "importScriptFromUri" -> {
                        val uriString = call.argument<String>("uri") ?: ""
                        val name = call.argument<String>("name") ?: ""
                        handleImportScriptFromUri(uriString, name, result)
                    }
                    "exportLog" -> {
                        val content = call.argument<String>("content") ?: ""
                        val fileName = call.argument<String>("fileName") ?: "log.txt"
                        handleExportLog(content, fileName, result)
                    }
                    "exportScript" -> {
                        val name = call.argument<String>("name") ?: ""
                        val destDir = call.argument<String>("destDir")
                        handleExportScript(name, destDir, result)
                    }
                    "openUrl" -> {
                        val url = call.argument<String>("url") ?: ""
                        handleOpenUrl(url, result)
                    }
                    "downloadAndInstallApk" -> {
                        val url = call.argument<String>("url") ?: ""
                        val fileName = call.argument<String>("fileName") ?: "python_runner_update.apk"
                        handleDownloadAndInstallApk(url, fileName, result)
                    }
                    "getAppInfo" -> handleGetAppInfo(result)
                    "getPythonInfo" -> handleGetPythonInfo(result)
                    "moveToBackground" -> {
                        moveTaskToBack(true)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // --- Script Management ---

    private fun handleCreateScript(name: String, content: String, result: MethodChannel.Result) {
        try {
            val file = File(scriptsDir(), name)
            if (file.exists()) {
                result.error("1001", "脚本已存在: $name", null)
                return
            }
            file.writeText(content)
            result.success(mapOf("name" to name, "path" to file.absolutePath))
        } catch (e: Exception) {
            result.error("1002", "创建脚本失败: ${e.message}", null)
        }
    }

    private fun handleDeleteScript(name: String, result: MethodChannel.Result) {
        try {
            val file = File(scriptsDir(), name)
            if (!file.exists()) {
                result.error("1001", "脚本不存在: $name", null)
                return
            }
            file.delete()
            result.success(true)
        } catch (e: Exception) {
            result.error("1002", "删除脚本失败: ${e.message}", null)
        }
    }

    private fun handleRenameScript(oldName: String, newName: String, result: MethodChannel.Result) {
        try {
            val oldFile = File(scriptsDir(), oldName)
            val newFile = File(scriptsDir(), newName)
            if (!oldFile.exists()) {
                result.error("1001", "脚本不存在: $oldName", null)
                return
            }
            if (newFile.exists()) {
                result.error("1001", "目标名称已存在: $newName", null)
                return
            }
            oldFile.renameTo(newFile)
            result.success(true)
        } catch (e: Exception) {
            result.error("1002", "重命名失败: ${e.message}", null)
        }
    }

    private fun handleListScripts(result: MethodChannel.Result) {
        try {
            val files = scriptsDir().listFiles()?.filter { it.isFile && it.name.endsWith(".py") } ?: emptyList()
            val scripts = files.map { file ->
                mapOf(
                    "name" to file.name,
                    "path" to file.absolutePath,
                    "modifiedAt" to file.lastModified(),
                    "size" to file.length()
                )
            }.sortedByDescending { it["modifiedAt"] as Long }
            result.success(scripts)
        } catch (e: Exception) {
            result.error("1002", "列出脚本失败: ${e.message}", null)
        }
    }

    private fun handleReadScript(name: String, result: MethodChannel.Result) {
        try {
            val file = File(scriptsDir(), name)
            if (!file.exists()) {
                result.error("1001", "脚本不存在: $name", null)
                return
            }
            result.success(file.readText())
        } catch (e: Exception) {
            result.error("1002", "读取脚本失败: ${e.message}", null)
        }
    }

    private fun handleSaveScript(name: String, content: String, result: MethodChannel.Result) {
        try {
            val file = File(scriptsDir(), name)
            file.writeText(content)
            result.success(true)
        } catch (e: Exception) {
            result.error("1002", "保存脚本失败: ${e.message}", null)
        }
    }

    // --- Script Execution ---

    private fun handleExecuteScript(name: String, executionId: String, workingDir: String?, hookEnv: Map<String, String>?, timeoutSeconds: Int, result: MethodChannel.Result) {
        // If a previous execution is still running, force-stop it first
        val oldThread = currentExecutionThread
        if (oldThread != null && oldThread.isAlive) {
            try {
                val py = Python.getInstance()
                val runner = py.getModule("script_runner")
                runner.callAttr("stop_running")
            } catch (_: Exception) {}
            // Send completion status for the old execution
            val oldId = currentExecutionId
            if (oldId != null) {
                sendStatus(oldId, "error", 1)
            }
            // Wait briefly for the old thread to actually terminate
            // so it doesn't interfere with the new execution
            try {
                oldThread.join(2000)
            } catch (_: Exception) {}
            currentExecutionThread = null
            currentExecutionId = null
        }

        val file = File(scriptsDir(), name)
        if (!file.exists()) {
            result.error("1001", "脚本不存在: $name", null)
            return
        }

        currentExecutionId = executionId

        // Start foreground service to keep alive in background
        startForegroundServiceSafely(PythonForegroundService.TASK_EXECUTE, scriptName = name)

        sendStatus(executionId, "running", null)
        result.success(mapOf("executionId" to executionId, "status" to "started"))

        val code = file.readText()
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
                            mainHandler.post {
                                stdinRequestSink?.success(mapOf(
                                    "executionId" to executionId,
                                    "timestamp" to System.currentTimeMillis()
                                ))
                            }
                        } else {
                            sendLog(type, content)
                        }
                    }
                    Thread.sleep(50)
                } catch (e: Exception) {
                    // Don't silently die — check if script is still running
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
                        sendLog(type, content)
                    }
                }
            } catch (_: Exception) {}
        }.also { it.name = "output-poll"; it.isDaemon = true; it.start() }

        // Execution thread
        currentExecutionThread = Thread {
            var exitCode = 0
            try {
                val py = Python.getInstance()
                val runner = py.getModule("script_runner")
                val result2 = runner.callAttr("run_script", code, workingDir ?: "", hookEnvJson)
                exitCode = result2.callAttr("get", "exit_code").toInt()
            } catch (e: Exception) {
                sendLog("stderr", "执行错误: ${e.message}")
                exitCode = 1
                // Persist script error to log file for post-mortem debugging
                _writeScriptErrorLog(name, e.message ?: "Unknown error", e.stackTrace?.toString())
            } finally {
                scriptDone.set(true)
                // Small delay to let the polling thread flush remaining output
                Thread.sleep(200)
                sendStatus(executionId, if (exitCode == 0) "completed" else "error", exitCode)
                currentExecutionId = null
                currentExecutionThread = null
                // Stop foreground service
                stopServiceSafely()
            }
        }.also { it.name = "python-exec"; it.start() }

        // Watchdog thread: kill script if it exceeds the timeout
        if (timeoutSeconds > 0) {
            Thread {
                try {
                    val timeoutMs = timeoutSeconds * 1000L
                    Thread.sleep(timeoutMs)
                    if (!scriptDone.get()) {
                        // Script is still running — kill it
                        try {
                            val py = Python.getInstance()
                            val runner = py.getModule("script_runner")
                            runner.callAttr("stop_running")
                        } catch (_: Exception) {}
                        // Wait for exec thread to finish
                        currentExecutionThread?.join(3000)
                        if (!scriptDone.get()) {
                            scriptDone.set(true)
                            sendLog("stderr", "脚本执行超时（${timeoutSeconds}秒），已强制停止")
                            sendStatus(executionId, "timeout", 1)
                            currentExecutionId = null
                            currentExecutionThread = null
                            stopServiceSafely()
                        }
                    }
                } catch (_: InterruptedException) {}
            }.also { it.name = "timeout-watchdog"; it.isDaemon = true; it.start() }
        }
    }

    private fun handleSendStdin(input: String, result: MethodChannel.Result) {
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

    private fun handleSendSceneTouch(touchJson: String, result: MethodChannel.Result) {
        Thread {
            try {
                val py = Python.getInstance()
                val runner = py.getModule("script_runner")
                runner.callAttr("provide_touch", touchJson)
                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                mainHandler.post { result.error("1009", "发送触摸事件失败: ${e.message}", null) }
            }
        }.also { it.name = "touch-send"; it.start() }
    }

    private fun handleStopExecution(result: MethodChannel.Result) {
        val thread = currentExecutionThread
        if (thread != null && thread.isAlive) {
            try {
                val py = Python.getInstance()
                val runner = py.getModule("script_runner")
                runner.callAttr("stop_running")
            } catch (_: Exception) {}
            // Send "stopping" status so Flutter UI updates immediately
            val execId = currentExecutionId
            if (execId != null) {
                sendStatus(execId, "stopping", null)
            }
            result.success(true)
        } else {
            result.success(false)
        }
    }

    // --- Package Management ---

    private fun handleInstallPackage(
        packageName: String, version: String?, indexUrl: String?, result: MethodChannel.Result
    ) {
        Thread {
            try {
                mainHandler.post { sendInstallProgress(packageName, "installing", "开始安装 $packageName...") }

                val py = Python.getInstance()
                val runner = py.getModule("script_runner")
                val pyList = py.getBuiltins().callAttr("list")

                pyList.callAttr("append", "install")
                if (indexUrl != null) {
                    pyList.callAttr("append", "-i")
                    pyList.callAttr("append", indexUrl)
                }
                val pkg = if (version != null) "$packageName==$version" else packageName
                pyList.callAttr("append", pkg)

                runner.callAttr("install_package", pyList)

                // Verify the package can actually be imported
                val verifyResult = runner.callAttr("verify_package", packageName)
                val verifySuccess = verifyResult.callAttr("get", "success").toBoolean()
                val verifyMessage = verifyResult.callAttr("get", "message").toString()

                if (verifySuccess) {
                    mainHandler.post {
                        sendInstallProgress(packageName, "success", "$packageName 安装成功 - $verifyMessage")
                        result.success(true)
                    }
                } else {
                    mainHandler.post {
                        sendInstallProgress(packageName, "success", "$packageName 安装完成，但: $verifyMessage")
                        result.success(true)
                    }
                }
            } catch (e: Exception) {
                mainHandler.post {
                    sendInstallProgress(packageName, "error", "安装失败: ${e.message}")
                    result.error("1004", "安装失败: ${e.message}", null)
                }
            }
        }.also { it.name = "pip-install"; it.start() }
    }

    private fun handleUninstallPackage(packageName: String, result: MethodChannel.Result) {
        Thread {
            try {
                val py = Python.getInstance()
                val runner = py.getModule("script_runner")
                runner.callAttr("uninstall_package", packageName)
                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                mainHandler.post { result.error("1005", "卸载失败: ${e.message}", null) }
            }
        }.also { it.name = "pip-uninstall"; it.start() }
    }

    private fun handleListInstalledPackages(result: MethodChannel.Result) {
        Thread {
            try {
                val py = Python.getInstance()
                val runner = py.getModule("script_runner")
                val pyPackages = runner.callAttr("list_packages")
                val packages = mutableListOf<Map<String, String>>()

                val length = pyPackages.callAttr("__len__").toInt()
                for (i in 0 until length) {
                    val item = pyPackages.callAttr("__getitem__", i)
                    packages.add(mapOf(
                        "name" to item.callAttr("get", "name").toString(),
                        "version" to item.callAttr("get", "version").toString()
                    ))
                }

                mainHandler.post { result.success(packages) }
            } catch (e: Exception) {
                mainHandler.post { result.error("1006", "获取包列表失败: ${e.message}", null) }
            }
        }.also { it.name = "pip-list"; it.start() }
    }

    // --- File Operations ---

    private fun handleImportScriptFromUri(uriString: String, name: String, result: MethodChannel.Result) {
        try {
            val uri = Uri.parse(uriString)
            val inputStream = contentResolver.openInputStream(uri)
            if (inputStream == null) {
                result.error("1002", "无法读取文件", null)
                return
            }
            val content = BufferedReader(InputStreamReader(inputStream)).use { it.readText() }
            val targetFile = File(scriptsDir(), name)
            targetFile.writeText(content)
            result.success(mapOf("name" to name, "path" to targetFile.absolutePath))
        } catch (e: Exception) {
            result.error("1002", "导入失败: ${e.message}", null)
        }
    }

    private fun handleExportLog(content: String, fileName: String, result: MethodChannel.Result) {
        try {
            // Save to public Downloads directory so user can find the file
            val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            val appDir = File(downloadsDir, "PythonRunner")
            if (!appDir.exists()) appDir.mkdirs()
            val file = File(appDir, fileName)
            file.writeText(content)
            result.success(file.absolutePath)
        } catch (e: Exception) {
            // Fallback to app-internal directory if external storage fails
            try {
                val logsDir = File(filesDir, "logs")
                if (!logsDir.exists()) logsDir.mkdirs()
                val file = File(logsDir, fileName)
                file.writeText(content)
                result.success(file.absolutePath)
            } catch (e2: Exception) {
                result.error("1002", "导出失败: ${e2.message}", null)
            }
        }
    }

    private fun handleExportScript(name: String, destDir: String?, result: MethodChannel.Result) {
        try {
            val srcFile = File(scriptsDir(), name)
            if (!srcFile.exists()) {
                result.error("1001", "脚本不存在: $name", null)
                return
            }
            val targetDir = if (!destDir.isNullOrBlank()) {
                File(destDir)
            } else {
                File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "PythonRunner")
            }
            if (!targetDir.exists()) targetDir.mkdirs()
            val destFile = File(targetDir, name)
            srcFile.copyTo(destFile, overwrite = true)
            result.success(destFile.absolutePath)
        } catch (e: Exception) {
            result.error("1002", "导出脚本失败: ${e.message}", null)
        }
    }

    private fun handleGetPythonInfo(result: MethodChannel.Result) {
        Thread {
            try {
                val py = Python.getInstance()
                val sys = py.getModule("sys")
                val version = sys.get("version")?.toString() ?: "未知"
                val siteModule = py.getModule("site")
                val sitePackages = try {
                    siteModule.callAttr("getusersitepackages")?.toString() ?: "未知"
                } catch (_: Exception) { "未知" }
                val executable = sys.get("executable")?.toString() ?: "未知"
                mainHandler.post {
                    val versionLine = version.lines().firstOrNull() ?: version
                    result.success(mapOf<String, String>(
                        "pythonVersion" to versionLine,
                        "sitePackages" to sitePackages,
                        "pythonPath" to executable
                    ))
                }
            } catch (e: Exception) {
                mainHandler.post { result.error("1008", "获取Python信息失败: ${e.message}", null) }
            }
        }.also { it.name = "py-info"; it.start() }
    }

    private fun handleGetAppInfo(result: MethodChannel.Result) {
        try {
            val packageInfo = packageManager.getPackageInfo(packageName, 0)
            val appName = packageManager.getApplicationLabel(applicationInfo)?.toString() ?: packageName
            val versionName = packageInfo.versionName ?: ""
            val buildNumber = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                packageInfo.longVersionCode.toString()
            } else {
                @Suppress("DEPRECATION")
                packageInfo.versionCode.toString()
            }
            result.success(
                mapOf<String, String>(
                    "appName" to appName,
                    "packageName" to packageName,
                    "version" to versionName,
                    "buildNumber" to buildNumber
                )
            )
        } catch (e: Exception) {
            result.error("1009", "鑾峰彇搴旂敤淇℃伅澶辫触: ${e.message}", null)
        }
    }

    private fun handleOpenUrl(url: String, result: MethodChannel.Result) {
        try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("1010", "鎵撳紑閾炬帴澶辫触: ${e.message}", null)
        }
    }

    private fun handleDownloadAndInstallApk(
        url: String,
        fileName: String,
        result: MethodChannel.Result
    ) {
        Thread {
            var connection: HttpURLConnection? = null
            try {
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O &&
                    !packageManager.canRequestPackageInstalls()
                ) {
                    val settingsIntent = Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:$packageName")
                    ).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(settingsIntent)
                    mainHandler.post {
                        result.error("1011", "璇峰厛鍏佽姝ゅ簲鐢ㄥ畨瑁匒PK锛岀劧鍚庡啀閲嶈瘯鏇存柊", null)
                    }
                    return@Thread
                }

                val targetDir = File(
                    getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: filesDir,
                    "updates"
                )
                if (!targetDir.exists()) targetDir.mkdirs()

                val safeFileName = if (fileName.lowercase().endsWith(".apk")) {
                    fileName
                } else {
                    "$fileName.apk"
                }
                val apkFile = File(targetDir, safeFileName)
                if (apkFile.exists()) apkFile.delete()

                connection = (URL(url).openConnection() as HttpURLConnection).apply {
                    requestMethod = "GET"
                    connectTimeout = 15000
                    readTimeout = 60000
                    setRequestProperty("Accept", "application/octet-stream")
                    setRequestProperty("User-Agent", "python_runner-updater")
                    instanceFollowRedirects = true
                    connect()
                }
                if (connection.responseCode !in 200..299) {
                    throw IllegalStateException("HTTP ${connection.responseCode}")
                }

                connection.inputStream.use { input ->
                    apkFile.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }

                val apkUri = FileProvider.getUriForFile(
                    this,
                    "$packageName.fileprovider",
                    apkFile
                )
                val installIntent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(apkUri, "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                startActivity(installIntent)
                mainHandler.post { result.success(apkFile.absolutePath) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("1012", "涓嬭浇鎴栧畨瑁呮洿鏂板け璐? ${e.message}", null)
                }
            } finally {
                connection?.disconnect()
            }
        }.also { it.name = "apk-update"; it.start() }
    }

    // --- Helpers ---

    private fun sendLog(type: String, message: String) {
        mainHandler.post {
            logSink?.success(mapOf(
                "type" to type,
                "content" to message,
                "timestamp" to System.currentTimeMillis()
            ))
        }
    }

    private fun sendStatus(executionId: String, status: String, exitCode: Int?) {
        mainHandler.post {
            statusSink?.success(mapOf(
                "executionId" to executionId,
                "status" to status,
                "exitCode" to exitCode
            ))
        }
    }

    private fun sendInstallProgress(packageName: String, status: String, message: String) {
        mainHandler.post {
            installSink?.success(mapOf(
                "packageName" to packageName,
                "status" to status,
                "message" to message
            ))
        }
    }

    private fun stopServiceSafely() {
        try {
            val intent = Intent(this, PythonForegroundService::class.java)
            stopService(intent)
        } catch (_: Exception) {}
    }

    private fun _writeScriptErrorLog(scriptName: String, errorMessage: String, stackTrace: String?) {
        try {
            val logDir = File(filesDir, "script_error_logs")
            if (!logDir.exists()) logDir.mkdirs()
            val sdf = java.text.SimpleDateFormat("yyyy-MM-dd_HH-mm-ss", java.util.Locale.US)
            val ts = sdf.format(java.util.Date())
            val file = File(logDir, "err_${ts}.txt")
            java.io.FileWriter(file).use { writer ->
                writer.write("Time: $ts\n")
                writer.write("Script: $scriptName\n")
                writer.write("Error: $errorMessage\n")
                if (stackTrace != null) {
                    writer.write("\nStack trace:\n$stackTrace\n")
                }
            }
        } catch (_: Exception) {}
    }

    private fun startForegroundServiceSafely(taskType: String, scriptName: String? = null) {
        try {
            val intent = Intent(this, PythonForegroundService::class.java).apply {
                putExtra(PythonForegroundService.EXTRA_TASK_TYPE, taskType)
                if (scriptName != null) {
                    putExtra(PythonForegroundService.EXTRA_SCRIPT_NAME, scriptName)
                }
            }
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: Exception) {
            android.util.Log.w("PythonRunner", "Failed to start foreground service: ${e.message}")
        }
    }

    private fun requestBatteryOptimizationExemption() {
        if (batteryOptRequested) return
        batteryOptRequested = true
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            val pm = getSystemService(POWER_SERVICE) as android.os.PowerManager
            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                try {
                    val intent = Intent(
                        android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                    ).apply { data = Uri.parse("package:$packageName") }
                    startActivity(intent)
                } catch (_: Exception) {}
            }
        }
    }

    override fun onResume() {
        super.onResume()
        requestBatteryOptimizationExemption()
    }

    override fun onDestroy() {
        coroutineScope.cancel()
        super.onDestroy()
    }
}
