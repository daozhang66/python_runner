package com.daozhang.py

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import kotlinx.coroutines.*
import java.io.File
import java.io.BufferedReader
import java.io.BufferedInputStream
import java.io.InputStreamReader
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {

    companion object {
        private const val FLOATING_BALL_PREFS_NAME = "floating_ball_prefs"
        private const val KEY_PENDING_RUN_SCRIPT = "pending_run_script"
    }

    private val METHOD_CHANNEL = "com.daozhang.py/native_bridge"
    private val LOG_STREAM_CHANNEL = "com.daozhang.py/log_stream"
    private val INSTALL_PROGRESS_CHANNEL = "com.daozhang.py/install_progress"
    private val DOWNLOAD_PROGRESS_CHANNEL = "com.daozhang.py/download_progress"
    private val EXECUTION_STATUS_CHANNEL = "com.daozhang.py/execution_status"

    private val STDIN_REQUEST_CHANNEL = "com.daozhang.py/stdin_request"

    private var logSink: EventChannel.EventSink? = null
    private var installSink: EventChannel.EventSink? = null
    private var downloadSink: EventChannel.EventSink? = null
    private var statusSink: EventChannel.EventSink? = null
    private var stdinRequestSink: EventChannel.EventSink? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private val coroutineScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val apkInstaller by lazy { ApkInstaller(this) }
    private val downloadManager by lazy {
        DownloadManager(this) { event ->
            mainHandler.post { downloadSink?.success(event) }
        }
    }
    private val linuxLikeRuntimeManager by lazy { LinuxLikeRuntimeManager(this) }
    private val linuxLikeBootstrapPackages = setOf("pip", "setuptools", "wheel")
    private val linuxLikeImplicitDependencyPackages = setOf(
        "certifi",
        "charset_normalizer",
        "idna",
        "urllib3",
        "typing_extensions",
        "six",
        "pycparser"
    )
    private var currentExecutionJob: Job? = null
    private var currentExecutionThread: Thread? = null
    private var currentExecutionProcess: Process? = null
    private var currentExecutionId: String? = null
    @Volatile private var currentExecutionStopRequested = false
    private var batteryOptRequested = false

    private var pendingRunScript: String? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleRunScriptIntent(intent)
    }

    private fun handleRunScriptIntent(intent: Intent?) {
        val name = intent?.getStringExtra("run_script")
        if (!name.isNullOrBlank()) {
            val safeName = try {
                normalizeScriptName(name)
            } catch (_: IllegalArgumentException) {
                intent.removeExtra("run_script")
                return
            }
            pendingRunScript = safeName
            getSharedPreferences(FLOATING_BALL_PREFS_NAME, MODE_PRIVATE)
                .edit()
                .putString(KEY_PENDING_RUN_SCRIPT, safeName)
                .apply()
            intent.removeExtra("run_script")
        }
    }

    fun consumePendingRunScript(): String? {
        val prefs = getSharedPreferences(FLOATING_BALL_PREFS_NAME, MODE_PRIVATE)
        val name = pendingRunScript ?: prefs.getString(KEY_PENDING_RUN_SCRIPT, null)
        pendingRunScript = null
        prefs.edit().remove(KEY_PENDING_RUN_SCRIPT).apply()
        return name
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        // Register native crash handler ASAP 鈥?before Flutter engine init
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
        WindowCompat.setDecorFitsSystemWindows(window, false)
        handleRunScriptIntent(intent)
    }

    private fun scriptsDir(): File {
        val dir = File(filesDir, "scripts")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    private fun normalizeScriptName(name: String): String {
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

    private fun safeScriptFile(name: String): File {
        val safeName = normalizeScriptName(name)
        val scriptsRoot = scriptsDir().canonicalFile
        val target = File(scriptsRoot, safeName).canonicalFile
        require(target.toPath().startsWith(scriptsRoot.toPath()) && target.name == safeName) {
            "脚本路径越界"
        }
        return target
    }

    private fun scriptProjectsDir(): File {
        val dir = File(filesDir, "script_projects")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    private fun normalizeProjectKey(projectKey: String): String {
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

    private fun normalizeProjectRelativePath(path: String): String {
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

    private fun normalizeProjectMainFilePath(path: String): String {
        val safePath = normalizeProjectRelativePath(path)
        require(safePath.endsWith(".py")) { "项目主程序必须是 .py 文件" }
        return safePath
    }

    private fun safeProjectRoot(projectKey: String): File {
        val safeKey = normalizeProjectKey(projectKey)
        val projectsRoot = scriptProjectsDir().canonicalFile
        val root = File(projectsRoot, safeKey).canonicalFile
        require(root.toPath().startsWith(projectsRoot.toPath()) && root.name == safeKey) {
            "项目目录越界"
        }
        return root
    }

    private fun safeProjectFile(projectKey: String, path: String): File {
        val root = safeProjectRoot(projectKey)
        val safePath = normalizeProjectRelativePath(path)
        val target = File(root, safePath).canonicalFile
        require(target.toPath().startsWith(root.toPath())) {
            "项目文件路径越界"
        }
        return target
    }

    private fun projectRelativePath(root: File, file: File): String {
        return root.canonicalFile.toPath()
            .relativize(file.canonicalFile.toPath())
            .joinToString("/")
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

        // EventChannel: download_progress
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, DOWNLOAD_PROGRESS_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    downloadSink = events
                }
                override fun onCancel(arguments: Any?) {
                    downloadSink = null
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
                    "createScriptProject" -> {
                        val projectKey = call.argument<String>("projectKey") ?: ""
                        handleCreateScriptProject(projectKey, result)
                    }
                    "deleteScriptProject" -> {
                        val projectKey = call.argument<String>("projectKey") ?: ""
                        handleDeleteScriptProject(projectKey, result)
                    }
                    "listProjectFiles" -> {
                        val projectKey = call.argument<String>("projectKey") ?: ""
                        handleListProjectFiles(projectKey, result)
                    }
                    "readProjectFile" -> {
                        val projectKey = call.argument<String>("projectKey") ?: ""
                        val path = call.argument<String>("path") ?: ""
                        handleReadProjectFile(projectKey, path, result)
                    }
                    "saveProjectFile" -> {
                        val projectKey = call.argument<String>("projectKey") ?: ""
                        val path = call.argument<String>("path") ?: ""
                        val content = call.argument<String>("content") ?: ""
                        handleSaveProjectFile(projectKey, path, content, result)
                    }
                    "createProjectDirectory" -> {
                        val projectKey = call.argument<String>("projectKey") ?: ""
                        val path = call.argument<String>("path") ?: ""
                        handleCreateProjectDirectory(projectKey, path, result)
                    }
                    "deleteProjectEntry" -> {
                        val projectKey = call.argument<String>("projectKey") ?: ""
                        val path = call.argument<String>("path") ?: ""
                        handleDeleteProjectEntry(projectKey, path, result)
                    }
                    "renameProjectEntry" -> {
                        val projectKey = call.argument<String>("projectKey") ?: ""
                        val oldPath = call.argument<String>("oldPath") ?: ""
                        val newPath = call.argument<String>("newPath") ?: ""
                        handleRenameProjectEntry(projectKey, oldPath, newPath, result)
                    }
                    "importScriptProjectZip" -> {
                        val projectKey = call.argument<String>("projectKey") ?: ""
                        val uri = call.argument<String>("uri") ?: ""
                        handleImportScriptProjectZip(projectKey, uri, result)
                    }
                    "exportScriptProjectZip" -> {
                        val projectKey = call.argument<String>("projectKey") ?: ""
                        val destDir = call.argument<String>("destDir")
                        handleExportScriptProjectZip(projectKey, destDir, result)
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
                        val destDir = call.argument<String>("destDir")
                        handleExportLog(content, fileName, destDir, result)
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
                        handleStartApkDownload(url, fileName, "", "", result)
                    }
                    "startApkDownload" -> {
                        val url = call.argument<String>("url") ?: ""
                        val fileName = call.argument<String>("fileName") ?: "python_runner_update.apk"
                        val version = call.argument<String>("version") ?: ""
                        val sha256 = call.argument<String>("sha256") ?: ""
                        handleStartApkDownload(url, fileName, version, sha256, result)
                    }
                    "cancelDownload" -> {
                        val taskId = call.argument<String>("taskId") ?: ""
                        result.success(downloadManager.cancelDownload(taskId))
                    }
                    "retryDownload" -> {
                        val taskId = call.argument<String>("taskId") ?: ""
                        result.success(downloadManager.retryDownload(taskId))
                    }
                    "installDownloadedApk" -> {
                        val taskId = call.argument<String>("taskId") ?: ""
                        handleInstallDownloadedApk(taskId, result)
                    }
                    "getAppInfo" -> handleGetAppInfo(result)
                    "getPythonInfo" -> handleGetPythonInfo(result)
                    "getLinuxLikeRuntimeInfo" -> handleGetLinuxLikeRuntimeInfo(result)
                    "prepareLinuxLikeRuntime" -> handlePrepareLinuxLikeRuntime(result)
                    "installLinuxLikeRuntime" -> {
                        val manifestUrl = call.argument<String>("manifestUrl")
                        handleInstallLinuxLikeRuntime(manifestUrl, result)
                    }
                    "executeLinuxLikeScript" -> {
                        val name = call.argument<String>("name") ?: ""
                        val executionId = call.argument<String>("executionId") ?: ""
                        val workingDir = call.argument<String>("workingDir")
                        val timeoutSeconds = call.argument<Int>("timeoutSeconds") ?: 0
                        val projectKey = call.argument<String>("projectKey")
                        val projectMainFilePath = call.argument<String>("projectMainFilePath")
                        @Suppress("UNCHECKED_CAST")
                        val environment = call.argument<Map<String, String>>("environment")
                        handleExecuteLinuxLikeScript(
                            name,
                            executionId,
                            workingDir,
                            environment,
                            timeoutSeconds,
                            projectKey,
                            projectMainFilePath,
                            result
                        )
                    }
                    "sendLinuxLikeStdin" -> {
                        val input = call.argument<String>("input") ?: ""
                        handleSendLinuxLikeStdin(input, result)
                    }
                    "stopLinuxLikeExecution" -> handleStopLinuxLikeExecution(result)
                    "installLinuxLikePackage" -> {
                        val packageName = call.argument<String>("packageName") ?: ""
                        val version = call.argument<String>("version")
                        val indexUrl = call.argument<String>("indexUrl")
                        handleInstallLinuxLikePackage(packageName, version, indexUrl, result)
                    }
                    "installLinuxLikeRequirements" -> {
                        val projectKey = call.argument<String>("projectKey")
                        val requirementsPath =
                            call.argument<String>("requirementsPath") ?: "requirements.txt"
                        val content = call.argument<String>("content")
                        val displayName =
                            call.argument<String>("displayName") ?: "requirements.txt"
                        val indexUrl = call.argument<String>("indexUrl")
                        handleInstallLinuxLikeRequirements(
                            projectKey,
                            requirementsPath,
                            content,
                            displayName,
                            indexUrl,
                            result
                        )
                    }
                    "uninstallLinuxLikePackage" -> {
                        val packageName = call.argument<String>("packageName") ?: ""
                        handleUninstallLinuxLikePackage(packageName, result)
                    }
                    "listLinuxLikePackages" -> handleListLinuxLikePackages(result)
                    "moveToBackground" -> {
                        moveTaskToBack(true)
                        result.success(null)
                    }
                    "checkOverlayPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            result.success(android.provider.Settings.canDrawOverlays(this))
                        } else {
                            result.success(true)
                        }
                    }
                    "requestOverlayPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            if (!android.provider.Settings.canDrawOverlays(this)) {
                                startActivity(
                                    android.content.Intent(
                                        android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                        android.net.Uri.parse("package:$packageName")
                                    ).apply { addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK) }
                                )
                            }
                        }
                        result.success(null)
                    }
                    "showFloatingBall" -> handleShowFloatingBall(call.argument<String>("scriptName"), result)
                    "hideFloatingBall" -> handleHideFloatingBall(result)
                    "updateFloatingBallStatus" -> {
                        val status = call.argument<String>("status") ?: "running"
                        handleUpdateFloatingBallStatus(status, result)
                    }
                    "pushFloatingBallOutput" -> {
                        val output = call.argument<String>("output") ?: ""
                        handlePushFloatingBallOutput(output, result)
                    }
                    "consumePendingRunScript" -> {
                        result.success(consumePendingRunScript())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // --- Script Management ---

    private fun handleCreateScript(name: String, content: String, result: MethodChannel.Result) {
        try {
            val file = safeScriptFile(name)
            if (file.exists()) {
                result.error("1001", "脚本已存在 $name", null)
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
            val file = safeScriptFile(name)
            if (!file.exists()) {
                result.error("1001", "脚本不存在 $name", null)
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
            val oldFile = safeScriptFile(oldName)
            val newFile = safeScriptFile(newName)
            if (!oldFile.exists()) {
                result.error("1001", "脚本不存在 $oldName", null)
                return
            }
            if (newFile.exists()) {
                result.error("1001", "目标名称已存在 $newName", null)
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
            val file = safeScriptFile(name)
            if (!file.exists()) {
                result.error("1001", "脚本不存在 $name", null)
                return
            }
            result.success(file.readText())
        } catch (e: Exception) {
            result.error("1002", "读取脚本失败: ${e.message}", null)
        }
    }

    private fun handleSaveScript(name: String, content: String, result: MethodChannel.Result) {
        try {
            val file = safeScriptFile(name)
            file.writeText(content)
            result.success(true)
        } catch (e: Exception) {
            result.error("1002", "保存脚本失败: ${e.message}", null)
        }
    }

    // --- Project File Management ---

    private fun handleCreateScriptProject(projectKey: String, result: MethodChannel.Result) {
        try {
            val root = safeProjectRoot(projectKey)
            if (!root.exists()) root.mkdirs()
            result.success(mapOf("projectKey" to normalizeProjectKey(projectKey), "path" to root.absolutePath))
        } catch (e: Exception) {
            result.error("1021", "创建项目失败: ${e.message}", null)
        }
    }

    private fun handleDeleteScriptProject(projectKey: String, result: MethodChannel.Result) {
        try {
            val root = safeProjectRoot(projectKey)
            if (root.exists()) root.deleteRecursively()
            result.success(true)
        } catch (e: Exception) {
            result.error("1022", "删除项目失败: ${e.message}", null)
        }
    }

    private fun handleListProjectFiles(projectKey: String, result: MethodChannel.Result) {
        try {
            val root = safeProjectRoot(projectKey)
            if (!root.exists()) {
                result.success(emptyList<Map<String, Any>>())
                return
            }
            val files = root.walkTopDown()
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
                .sortedWith(compareBy<Map<String, Any>> { it["path"].toString().lowercase(Locale.US) }
                    .thenBy { it["name"].toString() })
                .toList()
            result.success(files)
        } catch (e: Exception) {
            result.error("1023", "列出项目文件失败: ${e.message}", null)
        }
    }

    private fun handleReadProjectFile(projectKey: String, path: String, result: MethodChannel.Result) {
        try {
            val file = safeProjectFile(projectKey, path)
            if (!file.isFile) {
                result.error("1024", "项目文件不存在: $path", null)
                return
            }
            result.success(file.readText())
        } catch (e: Exception) {
            result.error("1024", "读取项目文件失败: ${e.message}", null)
        }
    }

    private fun handleSaveProjectFile(projectKey: String, path: String, content: String, result: MethodChannel.Result) {
        try {
            val file = safeProjectFile(projectKey, path)
            file.parentFile?.mkdirs()
            file.writeText(content)
            result.success(true)
        } catch (e: Exception) {
            result.error("1025", "保存项目文件失败: ${e.message}", null)
        }
    }

    private fun handleCreateProjectDirectory(projectKey: String, path: String, result: MethodChannel.Result) {
        try {
            val dir = safeProjectFile(projectKey, path)
            if (!dir.exists()) dir.mkdirs()
            result.success(true)
        } catch (e: Exception) {
            result.error("1026", "创建项目目录失败: ${e.message}", null)
        }
    }

    private fun handleDeleteProjectEntry(projectKey: String, path: String, result: MethodChannel.Result) {
        try {
            val root = safeProjectRoot(projectKey)
            val target = safeProjectFile(projectKey, path)
            if (target.canonicalFile == root.canonicalFile) {
                result.error("1027", "不能通过条目删除项目根目录", null)
                return
            }
            if (target.exists()) target.deleteRecursively()
            result.success(true)
        } catch (e: Exception) {
            result.error("1027", "删除项目条目失败: ${e.message}", null)
        }
    }

    private fun handleRenameProjectEntry(projectKey: String, oldPath: String, newPath: String, result: MethodChannel.Result) {
        try {
            val source = safeProjectFile(projectKey, oldPath)
            val target = safeProjectFile(projectKey, newPath)
            if (!source.exists()) {
                result.error("1028", "项目条目不存在: $oldPath", null)
                return
            }
            if (target.exists()) {
                result.error("1028", "目标条目已存在: $newPath", null)
                return
            }
            target.parentFile?.mkdirs()
            if (!source.renameTo(target)) {
                throw IllegalStateException("系统拒绝重命名")
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("1028", "重命名项目条目失败: ${e.message}", null)
        }
    }

    private fun handleImportScriptProjectZip(projectKey: String, uriString: String, result: MethodChannel.Result) {
        try {
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
            result.success(importedFiles.sortedBy { it["path"].toString().lowercase(Locale.US) })
        } catch (e: Exception) {
            result.error("1029", "导入项目ZIP失败: ${e.message}", null)
        }
    }

    private fun handleExportScriptProjectZip(projectKey: String, destDir: String?, result: MethodChannel.Result) {
        try {
            val root = safeProjectRoot(projectKey)
            if (!root.isDirectory) {
                result.error("1030", "项目目录不存在", null)
                return
            }
            val targetDir = if (!destDir.isNullOrBlank()) {
                File(destDir)
            } else {
                File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "PythonRunner")
            }
            if (!targetDir.exists()) targetDir.mkdirs()
            val zipFile = File(targetDir, "${normalizeProjectKey(projectKey)}.zip")
            ZipOutputStream(zipFile.outputStream()).use { zip ->
                root.walkTopDown()
                    .drop(1)
                    .filter { file -> file.isFile && !shouldSkipProjectZipEntry(projectRelativePath(root, file)) }
                    .forEach { file ->
                        val relativePath = projectRelativePath(root, file)
                        zip.putNextEntry(ZipEntry(relativePath))
                        file.inputStream().use { input -> input.copyTo(zip) }
                        zip.closeEntry()
                    }
            }
            result.success(zipFile.absolutePath)
        } catch (e: Exception) {
            result.error("1030", "导出项目ZIP失败: ${e.message}", null)
        }
    }

    private fun openInputStreamFromPathOrUri(value: String): java.io.InputStream? {
        val text = value.trim()
        if (text.isEmpty()) return null
        if (text.startsWith("content://") || text.startsWith("file://")) {
            return contentResolver.openInputStream(Uri.parse(text))
        }
        val file = File(text)
        if (file.isFile) return file.inputStream()
        return try {
            contentResolver.openInputStream(Uri.parse(text))
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

    private fun deleteProjectPycacheDirectories(projectRoot: File) {
        try {
            val root = projectRoot.canonicalFile
            val rootPath = root.toPath()
            root.walkBottomUp().forEach { file ->
                if (file.isDirectory && file.name == "__pycache__") {
                    val path = file.canonicalFile.toPath()
                    if (path.startsWith(rootPath)) {
                        file.deleteRecursively()
                    }
                }
            }
        } catch (_: Exception) {
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

        val file = try {
            safeScriptFile(name)
        } catch (e: IllegalArgumentException) {
            result.error("1001", e.message ?: "非法脚本名称", null)
            return
        }
        if (!file.exists()) {
            result.error("1001", "脚本不存在 $name", null)
            return
        }

        currentExecutionId = executionId

        // Start foreground service to keep alive in background
        startForegroundServiceSafely(PythonForegroundService.TASK_EXECUTE, scriptName = name)

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
                            sendLog(type, content)
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
                val result2 = runner.callAttr("run_script", code, workingDir ?: "", hookEnvJson, scriptFilePath)
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
                        // Script is still running 鈥?kill it
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

    private fun handleExecuteLinuxLikeScript(
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

        val oldProcess = currentExecutionProcess
        if (oldProcess != null && oldProcess.isAlive) {
            currentExecutionStopRequested = true
            oldProcess.destroy()
            try {
                oldProcess.waitFor()
            } catch (_: Exception) {}
        }

        val executionTarget = try {
            if (!projectKey.isNullOrBlank()) {
                val safeMainPath = normalizeProjectMainFilePath(
                    projectMainFilePath ?: throw IllegalArgumentException("项目主程序未设置")
                )
                val projectRoot = safeProjectRoot(projectKey)
                val mainFile = safeProjectFile(projectKey, safeMainPath)
                if (!projectRoot.isDirectory) {
                    throw IllegalArgumentException("项目目录不存在: $projectKey")
                }
                if (!mainFile.isFile) {
                    throw IllegalArgumentException("项目主程序不存在: $safeMainPath")
                }
                LinuxLikeExecutionTarget(
                    displayName = name.trim().ifBlank { normalizeProjectKey(projectKey) },
                    scriptFile = mainFile,
                    workingDir = projectRoot.absolutePath,
                    pythonPathEntries = listOf(
                        projectRoot.absolutePath,
                        mainFile.parentFile?.absolutePath
                    ).filterNotNull().distinct(),
                    projectRoot = projectRoot
                )
            } else {
                val scriptFile = safeScriptFile(name)
                if (!scriptFile.exists()) {
                    throw IllegalArgumentException("脚本不存在 $name")
                }
                LinuxLikeExecutionTarget(
                    displayName = name,
                    scriptFile = scriptFile,
                    workingDir = linuxLikeRuntimeManager.resolveScriptWorkingDir(workingDir),
                    pythonPathEntries = emptyList()
                )
            }
        } catch (e: IllegalArgumentException) {
            result.error("1001", e.message ?: "非法执行目标", null)
            return
        }

        currentExecutionId = executionId
        currentExecutionStopRequested = false
        startForegroundServiceSafely(PythonForegroundService.TASK_EXECUTE, scriptName = executionTarget.displayName)

        sendStatus(executionId, "running", null)
        result.success(mapOf("executionId" to executionId, "status" to "started"))

        val executionEnvironment = environment?.toMutableMap() ?: mutableMapOf()
        val resolvedWorkingDir = executionTarget.workingDir
        executionEnvironment["HOME"] = resolvedWorkingDir
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
            executionEnvironment
        )
        val timedOut = java.util.concurrent.atomic.AtomicBoolean(false)

        currentExecutionThread = Thread {
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
                currentExecutionProcess = process

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
                                currentExecutionStopRequested = true
                                sendLog("stderr", "脚本执行超时（${timeoutSeconds}秒），已强制停止")
                                process.destroy()
                                Thread.sleep(1000)
                                if (process.isAlive) process.destroyForcibly()
                            }
                        } catch (_: InterruptedException) {}
                    }.also { it.name = "linux-like-timeout-watchdog"; it.isDaemon = true; it.start() }
                }

                exitCode = process.waitFor()
                stdoutThread.join(500)
                stderrThread.join(500)
                status = when {
                    timedOut.get() -> "timeout"
                    currentExecutionStopRequested -> "stopped"
                    exitCode == 0 -> "completed"
                    else -> "error"
                }
                if (status == "error" || status == "timeout") {
                    _writeScriptErrorLog(
                        executionTarget.displayName,
                        "Linux-like process exited with code $exitCode",
                        "stdout:\n${stdout.takeLast(4000)}\n\nstderr:\n${stderr.takeLast(4000)}"
                    )
                }
            } catch (e: Throwable) {
                sendLog("stderr", "Linux-like执行错误: ${e.message}")
                status = if (currentExecutionStopRequested) "stopped" else "error"
                exitCode = 1
                _writeScriptErrorLog(executionTarget.displayName, e.message ?: "Unknown error", e.stackTrace.joinToString("\n"))
            } finally {
                executionTarget.projectRoot?.let { deleteProjectPycacheDirectories(it) }
                currentExecutionProcess = null
                currentExecutionThread = null
                currentExecutionId = null
                linuxLikeRuntimeManager.cleanupExecutionTempDir(executionTempDir)
                sendStatus(executionId, status, exitCode)
                stopServiceSafely()
            }
        }.also { it.name = "linux-like-exec"; it.start() }
    }

    private fun handleSendLinuxLikeStdin(input: String, result: MethodChannel.Result) {
        try {
            val process = currentExecutionProcess
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

    private fun handleStopLinuxLikeExecution(result: MethodChannel.Result) {
        val process = currentExecutionProcess
        if (process != null && process.isAlive) {
            currentExecutionStopRequested = true
            val execId = currentExecutionId
            if (execId != null) sendStatus(execId, "stopping", null)
            process.destroy()
            Thread {
                try {
                    Thread.sleep(1000)
                    if (process.isAlive) process.destroyForcibly()
                } catch (_: InterruptedException) {}
            }.also { it.name = "linux-like-stop"; it.isDaemon = true; it.start() }
            result.success(true)
        } else {
            result.success(false)
        }
    }

    private data class LinuxLikeRequirementsTarget(
        val file: File,
        val pipPath: String,
        val workingDir: String?,
        val temporary: Boolean
    )

    private fun handleInstallLinuxLikeRequirements(
        projectKey: String?,
        requirementsPath: String,
        content: String?,
        displayName: String,
        indexUrl: String?,
        result: MethodChannel.Result
    ) {
        Thread {
            var temporaryFile: File? = null
            val label = displayName.takeIf { it.isNotBlank() } ?: "requirements.txt"
            try {
                val info = linuxLikeRuntimeManager.getInfo()
                if (info["available"] != "true") {
                    throw IllegalStateException(info["message"] ?: "Linux-like runtime unavailable")
                }
                val target = resolveLinuxLikeRequirementsTarget(
                    projectKey,
                    requirementsPath,
                    content,
                    label
                )
                if (target.temporary) {
                    temporaryFile = target.file
                }
                val args = mutableListOf(
                    "--disable-pip-version-check",
                    "install",
                    "--target",
                    linuxLikeRuntimeManager.userSitePackagesGuestPath
                )
                if (!indexUrl.isNullOrBlank()) {
                    args.add("-i")
                    args.add(indexUrl)
                }
                args.add("-r")
                args.add(target.pipPath)

                sendInstallProgress("requirements.txt", "installing", "开始安装 $label...")
                val command = linuxLikeRuntimeManager.buildPythonModuleCommand(
                    "pip",
                    args,
                    workingDir = target.workingDir
                )
                val commandResult = runLinuxLikeCommandBlocking(command)
                if (commandResult.exitCode == 0) {
                    refreshLinuxLikeExplicitPackageMetadata()
                    sendInstallProgress("requirements.txt", "success", "$label 安装成功")
                    mainHandler.post { result.success(true) }
                } else {
                    val errorMessage = commandResult.stderr.ifBlank { commandResult.stdout }
                        .trim()
                        .ifBlank { "pip 退出码 ${commandResult.exitCode}" }
                    sendInstallProgress("requirements.txt", "error", "$label 安装失败")
                    mainHandler.post {
                        result.error("1031", "Linux-like安装requirements失败: $errorMessage", null)
                    }
                }
            } catch (e: Exception) {
                sendInstallProgress("requirements.txt", "error", "安装失败: ${e.message}")
                mainHandler.post {
                    result.error("1031", "Linux-like安装requirements失败: ${e.message}", null)
                }
            } finally {
                temporaryFile?.delete()
            }
        }.also { it.name = "linux-like-pip-requirements"; it.start() }
    }

    private fun resolveLinuxLikeRequirementsTarget(
        projectKey: String?,
        requirementsPath: String,
        content: String?,
        displayName: String
    ): LinuxLikeRequirementsTarget {
        require(displayName.equals("requirements.txt", ignoreCase = true)) {
            "只支持 requirements.txt"
        }
        val safeRequirementsPath = normalizeProjectRelativePath(requirementsPath)
        require(safeRequirementsPath == "requirements.txt") {
            "只支持项目根目录 requirements.txt"
        }
        if (!projectKey.isNullOrBlank()) {
            val projectRoot = safeProjectRoot(projectKey)
            val requirementsFile = safeProjectFile(projectKey, safeRequirementsPath)
            require(requirementsFile.isFile) { "requirements.txt 不存在" }
            return LinuxLikeRequirementsTarget(
                file = requirementsFile,
                pipPath = "requirements.txt",
                workingDir = projectRoot.absolutePath,
                temporary = false
            )
        }

        val body = content?.takeIf { it.isNotBlank() }
            ?: throw IllegalArgumentException("requirements.txt 为空")
        val importDir = File(filesDir, "linux_like/requirements_imports")
        if (!importDir.exists()) importDir.mkdirs()
        val requirementsFile = File(importDir, "requirements-${System.currentTimeMillis()}.txt")
        requirementsFile.writeText(body)
        return LinuxLikeRequirementsTarget(
            file = requirementsFile,
            pipPath = requirementsFile.absolutePath,
            workingDir = null,
            temporary = true
        )
    }

    private fun refreshLinuxLikeExplicitPackageMetadata() {
        resolveLinuxLikeExplicitPackages(
            linuxLikeDistributions(),
            queryLinuxLikeTopLevelPackages()
        )
    }

    private fun handleInstallLinuxLikePackage(
        packageName: String,
        version: String?,
        indexUrl: String?,
        result: MethodChannel.Result
    ) {
        Thread {
            try {
                val info = linuxLikeRuntimeManager.getInfo()
                if (info["available"] != "true") {
                    throw IllegalStateException(info["message"] ?: "Linux-like runtime unavailable")
                }
                val packageSpec = if (!version.isNullOrBlank()) "$packageName==$version" else packageName
                val args = mutableListOf(
                    "--disable-pip-version-check",
                    "install",
                    "--target",
                    linuxLikeRuntimeManager.userSitePackagesGuestPath
                )
                if (!indexUrl.isNullOrBlank()) {
                    args.add("-i")
                    args.add(indexUrl)
                }
                args.add(packageSpec)
                sendInstallProgress(packageName, "installing", "开始安装 $packageSpec...")
                val command = linuxLikeRuntimeManager.buildPythonModuleCommand("pip", args)
                val commandResult = runLinuxLikeCommandBlocking(command)
                if (commandResult.exitCode == 0) {
                    sendInstallProgress(packageName, "正在校验 $packageName 是否已安装...", "正在校验 $packageName 是否已安装...")
                    val verifyResult = verifyLinuxLikePackageInstalled(packageName)
                    if (verifyResult.exitCode == 0 && verifyResult.stdout.isNotBlank()) {
                        recordLinuxLikeExplicitPackage(packageName, version)
                        sendInstallProgress(packageName, "$packageSpec 安装成功", "安装成功")
                        mainHandler.post { result.success(true) }
                    } else {
                        val verifyMessage = listOf(verifyResult.stderr, verifyResult.stdout)
                            .firstOrNull { it.isNotBlank() }
                            ?.trim()
                            ?: "pip show did not find $packageName after install"
                        sendInstallProgress(packageName, "error", "$packageSpec 安装后校验失败")
                        mainHandler.post {
                            result.error("1019", "Linux-like安装包校验失败: $verifyMessage", null)
                        }
                    }
                } else {
                    sendInstallProgress(packageName, "error", "$packageSpec 安装失败")
                    mainHandler.post {
                        result.error("1019", "Linux-like安装包失败: ${commandResult.stderr}", null)
                    }
                }
            } catch (e: Exception) {
                sendInstallProgress(packageName, "error", "安装失败: ${e.message}")
                mainHandler.post {
                    result.error("1019", "Linux-like安装包失败: ${e.message}", null)
                }
            }
        }.also { it.name = "linux-like-pip-install"; it.start() }
    }

    private fun verifyLinuxLikePackageInstalled(packageName: String): LinuxLikeCommandResult {
        val distributionName = normalizePackageNameForPipShow(packageName)
        if (distributionName.isBlank()) {
            return LinuxLikeCommandResult(
                exitCode = 1,
                stdout = "",
                stderr = "invalid package name: $packageName"
            )
        }
        val command = linuxLikeRuntimeManager.buildPythonModuleCommand(
            "pip",
            listOf("--disable-pip-version-check", "show", distributionName)
        )
        return runLinuxLikeCommandBlocking(command, emitLogs = false)
    }

    private fun normalizePackageNameForPipShow(packageName: String): String {
        return packageName
            .trim()
            .substringBefore("[")
            .substringBefore("==")
            .substringBefore("~=")
            .substringBefore(">=")
            .substringBefore("<=")
            .substringBefore("!=")
            .substringBefore(">")
            .substringBefore("<")
            .trim()
    }

    private fun handleUninstallLinuxLikePackage(packageName: String, result: MethodChannel.Result) {
        Thread {
            try {
                val info = linuxLikeRuntimeManager.getInfo()
                if (info["available"] != "true") {
                    throw IllegalStateException(info["message"] ?: "Linux-like runtime unavailable")
                }
                sendInstallProgress(packageName, "uninstalling", "开始卸载 $packageName...")
                val removedPackages = removeLinuxLikePackagesFromOverlay(listOf(packageName))
                if (removedPackages.isNotEmpty()) {
                    removeLinuxLikeExplicitPackage(packageName)
                    val removedDependencies = cleanupLinuxLikeOrphanDependencies()
                    sendInstallProgress(packageName, "success", "$packageName 卸载成功")
                    mainHandler.post {
                        result.success(
                            mapOf(
                                "success" to true,
                                "message" to "$packageName 卸载成功",
                                "removedDependencies" to removedDependencies
                            )
                        )
                    }
                } else {
                    sendInstallProgress(packageName, "error", "$packageName 卸载失败")
                    mainHandler.post {
                        result.error("1024", "Linux-like卸载包失败: $packageName 未安装", null)
                    }
                }
            } catch (e: Exception) {
                sendInstallProgress(packageName, "error", "卸载失败: ${e.message}")
                mainHandler.post {
                    result.error("1024", "Linux-like卸载包失败: ${e.message}", null)
                }
            }
        }.also { it.name = "linux-like-pip-uninstall"; it.start() }
    }

    private fun normalizePythonPackageName(packageName: String): String {
        return packageName.trim().lowercase(Locale.US).replace(Regex("[-_.]+"), "_")
    }

    private fun loadLinuxLikeExplicitPackages(): MutableMap<String, String> {
        val file = linuxLikeRuntimeManager.explicitUserPackagesFile
        if (!file.exists()) return mutableMapOf()
        return try {
            val json = JSONObject(file.readText())
            val packages = mutableMapOf<String, String>()
            val keys = json.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                packages[normalizePythonPackageName(key)] = json.optString(key, "")
            }
            packages
        } catch (_: Exception) {
            mutableMapOf()
        }
    }

    private fun saveLinuxLikeExplicitPackages(packages: Map<String, String>) {
        val file = linuxLikeRuntimeManager.explicitUserPackagesFile
        if (packages.isEmpty()) {
            if (file.exists()) {
                file.delete()
            }
            return
        }
        file.parentFile?.mkdirs()
        val json = JSONObject()
        packages.toSortedMap().forEach { (name, version) ->
            json.put(name, version)
        }
        file.writeText(json.toString())
    }

    private fun recordLinuxLikeExplicitPackage(packageName: String, version: String?) {
        val packages = loadLinuxLikeExplicitPackages()
        packages[normalizePythonPackageName(packageName)] = version?.trim().orEmpty()
        saveLinuxLikeExplicitPackages(packages)
    }

    private fun removeLinuxLikeExplicitPackage(packageName: String) {
        val packages = loadLinuxLikeExplicitPackages()
        packages.remove(normalizePythonPackageName(packageName))
        saveLinuxLikeExplicitPackages(packages)
    }

    private fun removeMissingLinuxLikeExplicitPackages(installedPackageNames: Set<String>) {
        val packages = loadLinuxLikeExplicitPackages()
        val stalePackages = packages.keys - installedPackageNames
        if (stalePackages.isEmpty()) {
            return
        }
        stalePackages.forEach { packages.remove(it) }
        saveLinuxLikeExplicitPackages(packages)
    }

    private data class LinuxLikeDistribution(
        val name: String,
        val version: String,
        val normalizedName: String,
        val metadataDir: File,
        val isDirectRequest: Boolean,
        val topLevelEntries: List<String>,
        val recordEntries: List<String>,
        val requires: List<String>
    )

    private fun linuxLikeDistributions(): List<LinuxLikeDistribution> {
        val siteDir = linuxLikeRuntimeManager.userSitePackagesDir
        if (!siteDir.isDirectory) {
            return emptyList()
        }
        val metadataDistributions = siteDir.listFiles()
            ?.filter { it.isDirectory && (it.name.endsWith(".dist-info") || it.name.endsWith(".egg-info")) }
            ?.mapNotNull { metadataDir ->
                val metadata = readLinuxLikeMetadata(metadataDir)
                val guessedName = metadataDir.name
                    .substringBefore(".dist-info")
                    .substringBefore(".egg-info")
                    .substringBeforeLast("-")
                    .takeIf { it.isNotBlank() }
                val name = metadata["Name"]?.firstOrNull()?.takeIf { it.isNotBlank() }
                    ?: guessedName
                    ?: return@mapNotNull null
                LinuxLikeDistribution(
                    name = name,
                    version = metadata["Version"]?.firstOrNull().orEmpty(),
                    normalizedName = normalizePythonPackageName(name),
                    metadataDir = metadataDir,
                    isDirectRequest = metadataDir.resolve("REQUESTED").isFile,
                    topLevelEntries = metadataDir.resolve("top_level.txt")
                        .takeIf { it.isFile }
                        ?.readLines()
                        ?.map { it.trim() }
                        ?.filter { it.isNotBlank() }
                        ?: emptyList(),
                    recordEntries = metadataDir.resolve("RECORD")
                        .takeIf { it.isFile }
                        ?.readLines()
                        ?.mapNotNull(::recordPathFromCsvLine)
                        ?: emptyList(),
                    requires = metadata["Requires-Dist"]
                        ?.mapNotNull(::requirementName)
                        ?: emptyList()
                )
            }
            ?.distinctBy { it.normalizedName }
            ?: emptyList()
        val knownNames = metadataDistributions.map { it.normalizedName }.toSet()
        val metadataOwnedTopLevels = metadataDistributions
            .flatMap { distribution ->
                distribution.topLevelEntries.map(::normalizePythonPackageName)
            }
            .toSet()
        val importPackageDistributions = siteDir.listFiles()
            ?.filter { file ->
                file.isDirectory &&
                    !file.name.startsWith(".") &&
                    !file.name.endsWith(".dist-info") &&
                    !file.name.endsWith(".egg-info") &&
                    !file.name.endsWith(".data") &&
                    File(file, "__init__.py").isFile &&
                    !knownNames.contains(normalizePythonPackageName(file.name)) &&
                    !metadataOwnedTopLevels.contains(normalizePythonPackageName(file.name))
            }
            ?.map { packageDir ->
                val name = packageDir.name
                LinuxLikeDistribution(
                    name = name,
                    version = readPythonPackageVersion(packageDir),
                    normalizedName = normalizePythonPackageName(name),
                    metadataDir = packageDir,
                    isDirectRequest = false,
                    topLevelEntries = listOf(name),
                    recordEntries = emptyList(),
                    requires = emptyList()
                )
            }
            ?: emptyList()
        return (metadataDistributions + importPackageDistributions)
            .distinctBy { it.normalizedName }
    }

    private fun readPythonPackageVersion(packageDir: File): String {
        return try {
            val initFile = File(packageDir, "__init__.py")
            val text = initFile.takeIf { it.isFile }?.readText() ?: return ""
            Regex("""__version__\s*=\s*['"]([^'"]+)['"]""")
                .find(text)
                ?.groupValues
                ?.getOrNull(1)
                .orEmpty()
        } catch (_: Exception) {
            ""
        }
    }

    private fun readLinuxLikeMetadata(metadataDir: File): Map<String, List<String>> {
        val file = listOf("METADATA", "PKG-INFO")
            .map { metadataDir.resolve(it) }
            .firstOrNull { it.isFile }
            ?: return emptyMap()
        val result = linkedMapOf<String, MutableList<String>>()
        var activeKey: String? = null
        file.forEachLine { rawLine ->
            if (rawLine.startsWith(" ") || rawLine.startsWith("\t")) {
                activeKey?.let { key ->
                    val values = result[key]
                    if (!values.isNullOrEmpty()) {
                        values[values.lastIndex] = values.last() + "\n" + rawLine.trim()
                    }
                }
                return@forEachLine
            }
            val delimiter = rawLine.indexOf(':')
            if (delimiter <= 0) {
                activeKey = null
                return@forEachLine
            }
            val key = rawLine.substring(0, delimiter)
            val value = rawLine.substring(delimiter + 1).trim()
            result.getOrPut(key) { mutableListOf() }.add(value)
            activeKey = key
        }
        return result
    }

    private fun requirementName(requirement: String): String? {
        val head = requirement.substringBefore(";").trim()
        val match = Regex("[A-Za-z0-9_.-]+").find(head) ?: return null
        return match.value.takeIf { it.isNotBlank() }
    }

    private fun recordPathFromCsvLine(line: String): String? {
        if (line.isBlank()) return null
        if (!line.startsWith("\"")) {
            return line.substringBefore(",").trim().takeIf { it.isNotBlank() }
        }
        val builder = StringBuilder()
        var index = 1
        while (index < line.length) {
            val ch = line[index]
            if (ch == '"') {
                if (index + 1 < line.length && line[index + 1] == '"') {
                    builder.append('"')
                    index += 2
                    continue
                }
                break
            }
            builder.append(ch)
            index++
        }
        return builder.toString().takeIf { it.isNotBlank() }
    }

    private fun removeLinuxLikeDistributionFiles(distribution: LinuxLikeDistribution) {
        distribution.recordEntries.forEach { relativePath ->
            deleteLinuxLikeSitePath(relativePath)
        }
        distribution.topLevelEntries.forEach { entry ->
            deleteLinuxLikeSitePath(entry)
            deleteLinuxLikeSitePath("$entry.py")
        }
        deleteLinuxLikeSiteFile(distribution.metadataDir)

        val prefix = distribution.normalizedName
        linuxLikeRuntimeManager.userSitePackagesDir.listFiles()?.forEach { file ->
            val baseName = if (file.name.endsWith(".py")) file.name.dropLast(3) else file.name
            val normalized = normalizePythonPackageName(baseName)
            val isMetadata = file.name.endsWith(".dist-info") ||
                file.name.endsWith(".egg-info") ||
                file.name.endsWith(".data")
            if (normalized == prefix || (isMetadata && normalized.startsWith("${prefix}_"))) {
                deleteLinuxLikeSiteFile(file)
            }
        }
    }

    private fun deleteLinuxLikeSitePath(relativePath: String) {
        val siteDir = linuxLikeRuntimeManager.userSitePackagesDir
        val target = File(siteDir, relativePath)
        deleteLinuxLikeSiteFile(target)
    }

    private fun deleteLinuxLikeSiteFile(target: File) {
        try {
            val siteRoot = linuxLikeRuntimeManager.userSitePackagesDir.canonicalFile.toPath()
            val targetPath = target.canonicalFile.toPath()
            if (!targetPath.startsWith(siteRoot)) {
                return
            }
            if (target.isDirectory) {
                target.deleteRecursively()
            } else if (target.exists()) {
                target.delete()
            }
            pruneEmptyLinuxLikeSiteParents(target.parentFile)
        } catch (_: Exception) {
        }
    }

    private fun pruneEmptyLinuxLikeSiteParents(start: File?) {
        if (start == null) return
        try {
            val siteRoot = linuxLikeRuntimeManager.userSitePackagesDir.canonicalFile
            var current: File? = start.canonicalFile
            while (current != null && current != siteRoot && current.toPath().startsWith(siteRoot.toPath())) {
                if (!current.isDirectory || current.listFiles()?.isEmpty() != true) {
                    break
                }
                current.delete()
                current = current.parentFile?.canonicalFile
            }
        } catch (_: Exception) {
        }
    }

    private fun removeLinuxLikePackagesFromOverlay(packageNames: List<String>): List<String> {
        if (packageNames.isEmpty()) {
            return emptyList()
        }
        val targets = packageNames.map(::normalizePythonPackageName).toSet()
        val removed = linkedSetOf<String>()
        linuxLikeDistributions().forEach { distribution ->
            if (!targets.contains(distribution.normalizedName)) {
                return@forEach
            }
            removeLinuxLikeDistributionFiles(distribution)
            removed.add(distribution.name)
        }
        val remainingTargets = targets - removed.map(::normalizePythonPackageName).toSet()
        if (remainingTargets.isNotEmpty()) {
            linuxLikeRuntimeManager.userSitePackagesDir.listFiles()?.forEach { file ->
                val baseName = if (file.name.endsWith(".py")) file.name.dropLast(3) else file.name
                val normalized = normalizePythonPackageName(baseName)
                val metadataPrefix = remainingTargets.firstOrNull { target ->
                    normalized.startsWith("${target}_")
                }
                val directMatch = remainingTargets.firstOrNull { target -> normalized == target }
                val matchedTarget = directMatch ?: metadataPrefix
                if (matchedTarget != null) {
                    deleteLinuxLikeSiteFile(file)
                    removed.add(packageNames.firstOrNull {
                        normalizePythonPackageName(it) == matchedTarget
                    } ?: matchedTarget)
                }
            }
        }
        return removed.toList()
    }

    private fun queryLinuxLikeOrphanDependencies(explicitPackages: Set<String>): List<String> {
        val explicit = explicitPackages.map(::normalizePythonPackageName).toSet()
        val distributions = linuxLikeDistributions()
        val installed = distributions.associateBy { it.normalizedName }
        val required = distributions
            .flatMap { it.requires }
            .map(::normalizePythonPackageName)
            .toSet()
        return installed.keys
            .filter { name ->
                !linuxLikeBootstrapPackages.contains(name) &&
                    !explicit.contains(name) &&
                    !required.contains(name)
            }
            .sorted()
            .mapNotNull { installed[it]?.name }
    }

    private fun queryLinuxLikeTopLevelPackages(): MutableMap<String, String> {
        return try {
            val command = linuxLikeRuntimeManager.buildPythonModuleCommand(
                "pip",
                listOf(
                    "--disable-pip-version-check",
                    "list",
                    "--not-required",
                    "--format=json"
                )
            )
            val commandResult = runLinuxLikeCommandBlocking(command, emitLogs = false)
            if (commandResult.exitCode != 0) {
                return mutableMapOf()
            }
            val json = JSONArray(commandResult.stdout)
            val packages = linkedMapOf<String, String>()
            for (i in 0 until json.length()) {
                val item = json.getJSONObject(i)
                val packageName = item.optString("name")
                if (packageName.isBlank()) continue
                val normalizedPackageName = normalizePythonPackageName(packageName)
                if (linuxLikeBootstrapPackages.contains(normalizedPackageName)) continue
                packages[normalizedPackageName] = item.optString("version")
            }
            packages.toMutableMap()
        } catch (_: Exception) {
            mutableMapOf()
        }
    }

    private fun resolveLinuxLikeExplicitPackages(
        distributions: List<LinuxLikeDistribution>,
        topLevelPackages: Map<String, String>
    ): MutableMap<String, String> {
        val explicitPackages = loadLinuxLikeExplicitPackages()
        if (distributions.isEmpty()) {
            return explicitPackages
        }

        val requestedPackages = linkedMapOf<String, String>()
        distributions
            .filter { it.isDirectRequest && !linuxLikeBootstrapPackages.contains(it.normalizedName) }
            .sortedBy { it.name.lowercase(Locale.US) }
            .forEach { distribution ->
                requestedPackages[distribution.normalizedName] = distribution.version
            }
        if (requestedPackages.isNotEmpty()) {
            if (requestedPackages != explicitPackages) {
                saveLinuxLikeExplicitPackages(requestedPackages)
            }
            return requestedPackages.toMutableMap()
        }

        if (topLevelPackages.isNotEmpty()) {
            val resolvedPackages = linkedMapOf<String, String>()
            topLevelPackages.toSortedMap().forEach { (name, version) ->
                resolvedPackages[name] = version
            }
            if (resolvedPackages != explicitPackages) {
                saveLinuxLikeExplicitPackages(resolvedPackages)
            }
            return resolvedPackages.toMutableMap()
        }

        return explicitPackages
    }

    private fun cleanupLinuxLikeOrphanDependencies(): List<String> {
        val removedDependencies = linkedSetOf<String>()
        while (true) {
            val distributions = linuxLikeDistributions()
            val explicitPackages = resolveLinuxLikeExplicitPackages(
                distributions,
                queryLinuxLikeTopLevelPackages()
            ).keys
            val orphanDependencies = queryLinuxLikeOrphanDependencies(explicitPackages)
            if (orphanDependencies.isEmpty()) {
                break
            }
            val removedThisRound = removeLinuxLikePackagesFromOverlay(orphanDependencies)
            if (removedThisRound.isEmpty()) {
                break
            }
            removedThisRound.forEach { removedDependencies.add(it) }
        }
        return removedDependencies.toList()
    }

    private fun handleListLinuxLikePackages(result: MethodChannel.Result) {
        Thread {
            try {
                val info = linuxLikeRuntimeManager.getInfo()
                if (info["available"] != "true") {
                    mainHandler.post { result.success(emptyList<Map<String, String>>()) }
                    return@Thread
                }
                val command = linuxLikeRuntimeManager.buildPythonModuleCommand(
                    "pip",
                    listOf("--disable-pip-version-check", "list", "--format=json")
                )
                val commandResult = runLinuxLikeCommandBlocking(command, emitLogs = false)
                if (commandResult.exitCode != 0) {
                    throw IllegalStateException(commandResult.stderr)
                }
                val json = org.json.JSONArray(commandResult.stdout)
                val hostDistributions = linuxLikeDistributions()
                val topLevelPackages = queryLinuxLikeTopLevelPackages()
                val explicitPackages =
                    resolveLinuxLikeExplicitPackages(hostDistributions, topLevelPackages).keys
                val packages = mutableListOf<Map<String, String>>()
                val installedPackageNames =
                    hostDistributions.mapTo(mutableSetOf()) { it.normalizedName }
                val listedPackageNames = mutableSetOf<String>()
                val pipListedPackages = mutableListOf<Map<String, String>>()

                for (i in 0 until json.length()) {
                    val item = json.getJSONObject(i)
                    val packageName = item.optString("name")
                    val packageVersion = item.optString("version")
                    val normalizedPackageName = normalizePythonPackageName(packageName)
                    pipListedPackages.add(
                        mapOf(
                            "name" to packageName,
                            "version" to packageVersion
                        )
                    )
                    installedPackageNames.add(normalizedPackageName)
                }

                pipListedPackages
                    .sortedBy { it["name"]?.lowercase(Locale.US) ?: "" }
                    .forEach { item ->
                    val packageName = item["name"].orEmpty()
                    if (packageName.isBlank()) return@forEach
                    val packageVersion = item["version"].orEmpty()
                    val normalizedPackageName = normalizePythonPackageName(packageName)
                    val isBootstrapPackage =
                        linuxLikeBootstrapPackages.contains(normalizedPackageName)
                    val isExplicitUserPackage = explicitPackages.contains(normalizedPackageName)
                    if (!isBootstrapPackage && !isExplicitUserPackage) {
                        return@forEach
                    }
                    if (listedPackageNames.contains(normalizedPackageName)) {
                        return@forEach
                    }
                    listedPackageNames.add(normalizedPackageName)
                    packages.add(
                        mapOf(
                            "name" to packageName,
                            "version" to packageVersion.ifBlank { "unknown" },
                            "source" to if (isExplicitUserPackage) "user" else "runtime"
                        )
                    )
                }
                removeMissingLinuxLikeExplicitPackages(installedPackageNames)
                mainHandler.post { result.success(packages) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("1025", "Linux-like列出包失败: ${e.message}", null)
                }
            }
        }.also { it.name = "linux-like-pip-list"; it.start() }
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

                val pipResult = runner.callAttr("install_package", pyList).toInt()
                if (pipResult != 0) {
                    mainHandler.post {
                        sendInstallProgress(packageName, "$packageName 安装失败: pip 退出码 $pipResult", "安装失败: pip 退出码 $pipResult")
                        result.error("1004", "安装失败: pip 退出码 $pipResult", null)
                    }
                    return@Thread
                }

                // Verify the package can actually be imported
                val verifyResult = runner.callAttr("verify_package", packageName)
                val verifySuccess = verifyResult.callAttr("get", "success").toBoolean()
                val verifyMessage = verifyResult.callAttr("get", "message").toString()

                if (verifySuccess) {
                    mainHandler.post {
                        sendInstallProgress(packageName, "$packageName 安装成功 - $verifyMessage", "$packageName 安装成功 - $verifyMessage")
                        result.success(true)
                    }
                } else {
                    mainHandler.post {
                        sendInstallProgress(packageName, "$packageName 安装后无法导入: $verifyMessage", "$packageName 安装后无法导入: $verifyMessage")
                        result.error("1004", "$packageName 安装后无法导入: $verifyMessage", null)
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
                val uninstallResult = runner.callAttr("uninstall_package", packageName)
                val removedDependenciesValue = uninstallResult.callAttr("get", "removedDependencies")
                val removedDependencies = mutableListOf<String>()
                val removedCount = removedDependenciesValue.callAttr("__len__").toInt()
                for (i in 0 until removedCount) {
                    removedDependencies.add(
                        removedDependenciesValue.callAttr("__getitem__", i).toString()
                    )
                }
                mainHandler.post {
                    result.success(
                        mapOf(
                            "success" to uninstallResult.callAttr("get", "success").toBoolean(),
                            "message" to uninstallResult.callAttr("get", "message").toString(),
                            "removedDependencies" to removedDependencies
                        )
                    )
                }
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
                        "version" to item.callAttr("get", "version").toString(),
                        "source" to item.callAttr("get", "source").toString()
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
            val targetFile = safeScriptFile(name)
            targetFile.writeText(content)
            result.success(mapOf("name" to name, "path" to targetFile.absolutePath))
        } catch (e: Exception) {
            result.error("1002", "导入失败: ${e.message}", null)
        }
    }

    private fun handleExportLog(content: String, fileName: String, destDir: String?, result: MethodChannel.Result) {
        try {
            val appDir = if (!destDir.isNullOrBlank()) {
                File(destDir)
            } else {
                val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                File(downloadsDir, "PythonRunner")
            }
            if (!appDir.exists()) appDir.mkdirs()
            val safeName = if (fileName.isBlank()) "log.txt" else fileName
            val file = File(appDir, safeName)
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
            val srcFile = safeScriptFile(name)
            if (!srcFile.exists()) {
                result.error("1001", "脚本不存在 $name", null)
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
                    val value = siteModule.callAttr("getsitepackages")
                    val first = try {
                        value.callAttr("__getitem__", 0)?.toString()
                    } catch (_: Exception) {
                        null
                    }
                    first ?: value?.toString() ?: "未知"
                } catch (_: Exception) { "未知" }
                val executable = sys.get("executable")?.toString() ?: "未知"
                mainHandler.post {
                    val versionLine = version.lines().firstOrNull() ?: version
                    result.success(mapOf<String, String>(
                        "pythonVersion" to versionLine,
                        "sitePackages" to sitePackages,
                        "pythonPath" to executable,
                        "chaquopyPipDir" to File(filesDir, "chaquopy/pip").absolutePath,
                    ))
                }
            } catch (e: Exception) {
                mainHandler.post { result.error("1008", "获取Python信息失败: ${e.message}", null) }
            }
        }.also { it.name = "py-info"; it.start() }
    }

    private fun handleGetLinuxLikeRuntimeInfo(result: MethodChannel.Result) {
        try {
            result.success(linuxLikeRuntimeManager.getInfo())
        } catch (e: Exception) {
            result.error("1014", "获取Linux-like运行环境信息失败: ${e.message}", null)
        }
    }

    private fun handlePrepareLinuxLikeRuntime(result: MethodChannel.Result) {
        Thread {
            try {
                val info = linuxLikeRuntimeManager.prepare()
                mainHandler.post { result.success(info) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("1015", "准备Linux-like运行环境失败: ${e.message}", null)
                }
            }
        }.also { it.name = "linux-like-prepare"; it.start() }
    }

    private fun handleInstallLinuxLikeRuntime(manifestUrl: String?, result: MethodChannel.Result) {
        Thread {
            try {
                val info = linuxLikeRuntimeManager.installFromManifest(manifestUrl) { status, message ->
                    mainHandler.post {
                        installSink?.success(mapOf(
                            "packageName" to "linux-like-runtime",
                            "status" to status,
                            "message" to message
                        ))
                    }
                }
                mainHandler.post { result.success(info) }
            } catch (e: Exception) {
                mainHandler.post {
                    installSink?.success(mapOf(
                        "packageName" to "linux-like-runtime",
                        "status" to "error",
                        "Linux-like环境安装失败: ${e.message}" to "Linux-like环境安装失败: ${e.message}"
                    ))
                    result.error("1016", "安装Linux-like运行环境失败: ${e.message}", null)
                }
            }
        }.also { it.name = "linux-like-install"; it.start() }
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
            result.error("1009", "获取应用信息失败: ${e.message}", null)
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
            result.error("1010", "打开链接失败: ${e.message}", null)
        }
    }

    private fun handleStartApkDownload(
        url: String,
        fileName: String,
        version: String,
        sha256: String,
        result: MethodChannel.Result
    ) {
        try {
            if (!apkInstaller.canRequestPackageInstalls()) {
                apkInstaller.openInstallPermissionSettings()
                downloadSink?.success(mapOf(
                    "taskId" to "",
                    "type" to "apk_update",
                    "status" to "install_permission_required",
                    "downloadedBytes" to 0L,
                    "totalBytes" to -1L,
                    "progress" to -1,
                    "speedBytesPerSecond" to 0L,
                    "etaSeconds" to -1L,
                    "retryCount" to 0,
                    "filePath" to "",
                    "errorCode" to "INSTALL_PERMISSION_REQUIRED",
                    "errorMessage" to "请先允许此应用安装APK，然后再重试更新"
                ))
                result.error("1011", "请先允许此应用安装APK，然后再重试更新", null)
                return
            }
            val taskId = downloadManager.startApkDownload(url, fileName, version, sha256)
            result.success(taskId)
        } catch (e: Exception) {
            result.error("1012", "启动下载失败: ${e.message}", null)
        }
    }

    private fun handleInstallDownloadedApk(taskId: String, result: MethodChannel.Result) {
        try {
            val apkFile = downloadManager.completedFile(taskId)
                ?: throw IllegalStateException("下载任务未完成或文件不存在")
            val path = apkInstaller.installApk(apkFile)
            result.success(path)
        } catch (e: SecurityException) {
            result.error("1011", "请先允许此应用安装APK，然后再重试更新", null)
        } catch (e: Exception) {
            result.error("1012", "打开安装器失败: ${e.message}", null)
        }
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

    private fun pipeProcessOutput(inputStream: java.io.InputStream, type: String): Thread {
        return Thread {
            try {
                BufferedReader(InputStreamReader(inputStream)).useLines { lines ->
                    lines.forEach { line -> sendLog(type, line) }
                }
            } catch (_: Exception) {}
        }.also { it.name = "linux-like-$type"; it.isDaemon = true; it.start() }
    }

    private data class LinuxLikeCommandResult(
        val exitCode: Int,
        val stdout: String,
        val stderr: String
    )

    private data class LinuxLikeExecutionTarget(
        val displayName: String,
        val scriptFile: File,
        val workingDir: String,
        val pythonPathEntries: List<String>,
        val projectRoot: File? = null
    )

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
                        if (emitLogs) sendLog(type, line)
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
        if (executionId.isNullOrBlank()) return
        mainHandler.post {
            stdinRequestSink?.success(
                mapOf(
                    "executionId" to executionId,
                    "prompt" to prompt,
                    "timestamp" to System.currentTimeMillis()
                )
            )
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
            stopService(Intent(this, PythonForegroundService::class.java))
        } catch (_: Exception) {}
        // FloatingBallService lifecycle is managed by Flutter-side execution_provider
    }

    // --- Floating Ball ---

    private fun handleShowFloatingBall(scriptName: String?, result: MethodChannel.Result) {
        try {
            val intent = Intent(this, FloatingBallService::class.java).apply {
                action = FloatingBallService.ACTION_SHOW
                putExtra(FloatingBallService.EXTRA_SCRIPT_NAME, scriptName ?: "")
            }
            startService(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("1020", "显示悬浮球失败: ${e.message}", null)
        }
    }

    private fun handleHideFloatingBall(result: MethodChannel.Result) {
        try {
            val intent = Intent(this, FloatingBallService::class.java).apply {
                action = FloatingBallService.ACTION_HIDE
            }
            startService(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("1021", "隐藏悬浮球失败: ${e.message}", null)
        }
    }

    private fun handleUpdateFloatingBallStatus(status: String, result: MethodChannel.Result) {
        try {
            val intent = Intent(this, FloatingBallService::class.java).apply {
                action = FloatingBallService.ACTION_UPDATE_STATUS
                putExtra(FloatingBallService.EXTRA_STATUS, status)
            }
            startService(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("1022", "更新悬浮球状态失败: ${e.message}", null)
        }
    }

    private fun handlePushFloatingBallOutput(output: String, result: MethodChannel.Result) {
        try {
            val intent = Intent(this, FloatingBallService::class.java).apply {
                action = FloatingBallService.ACTION_PUSH_OUTPUT
                putExtra(FloatingBallService.EXTRA_OUTPUT, output)
            }
            startService(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("1023", "推送输出失败: ${e.message}", null)
        }
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
