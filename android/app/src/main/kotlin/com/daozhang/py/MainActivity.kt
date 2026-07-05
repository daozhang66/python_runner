package com.daozhang.py

import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import kotlinx.coroutines.*
import java.io.File
import java.util.Locale

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
    private val scriptFileStore by lazy { ScriptFileStore(filesDir) }
    private val scriptProjectStore by lazy { ScriptProjectStore(this, filesDir) }
    private val nativeFileOperations by lazy {
        NativeFileOperations(filesDir, contentResolver, scriptFileStore)
    }
    private val floatingBallController by lazy { FloatingBallController(this, mainHandler) }
    private val chaquopyPackageController by lazy {
        ChaquopyPackageController(mainHandler, ::sendInstallProgress)
    }
    private val appUpdateController by lazy {
        AppUpdateController(this) { event ->
            mainHandler.post { downloadSink?.success(event) }
        }
    }
    private val linuxLikeRuntimeManager by lazy { LinuxLikeRuntimeManager(this) }
    private val runtimeInfoController by lazy {
        RuntimeInfoController(
            filesDir,
            mainHandler,
            linuxLikeRuntimeManager
        ) { event ->
            mainHandler.post { installSink?.success(event) }
        }
    }
    private val linuxLikePackageController by lazy {
        LinuxLikePackageController(
            filesDir,
            mainHandler,
            linuxLikeRuntimeManager,
            scriptProjectStore,
            ::sendInstallProgress,
            ::sendLog
        )
    }
    private val scriptExecutionController by lazy {
        ScriptExecutionController(
            mainHandler,
            scriptFileStore,
            scriptProjectStore,
            linuxLikeRuntimeManager,
            ::sendLog,
            ::sendStatus,
            ::emitStdinRequest,
            { scriptName ->
                startForegroundServiceSafely(
                    PythonForegroundService.TASK_EXECUTE,
                    scriptName = scriptName
                )
            },
            ::stopServiceSafely,
            ::_writeScriptErrorLog,
            ::deletePythonCacheDirectories
        )
    }
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
        return scriptFileStore.scriptsDir()
    }

    private fun normalizeScriptName(name: String): String {
        return scriptFileStore.normalizeScriptName(name)
    }

    private fun safeScriptFile(name: String): File {
        return scriptFileStore.safeScriptFile(name)
    }

    private fun scriptProjectsDir(): File {
        return scriptProjectStore.scriptProjectsDir()
    }

    private fun normalizeProjectKey(projectKey: String): String {
        return scriptProjectStore.normalizeProjectKey(projectKey)
    }

    private fun normalizeProjectRelativePath(path: String): String {
        return scriptProjectStore.normalizeProjectRelativePath(path)
    }

    private fun normalizeProjectMainFilePath(path: String): String {
        return scriptProjectStore.normalizeProjectMainFilePath(path)
    }

    private fun safeProjectRoot(projectKey: String): File {
        return scriptProjectStore.safeProjectRoot(projectKey)
    }

    private fun safeProjectFile(projectKey: String, path: String): File {
        return scriptProjectStore.safeProjectFile(projectKey, path)
    }

    private fun projectRelativePath(root: File, file: File): String {
        return scriptProjectStore.projectRelativePath(root, file)
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
        RuntimeHostApi.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            object : RuntimeHostApi {
                override fun getLinuxLikeRuntimeInfo(): LinuxLikeRuntimeInfo {
                    return runtimeInfoController.getLinuxLikeRuntimeInfoForPigeon()
                }
            }
        )
        FilePickerHostApi.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            object : FilePickerHostApi {
                override fun getFilePickerRoots(): List<NativeAppFileEntry> {
                    return nativeFileOperations.getFilePickerRootsForPigeon()
                }

                override fun listFilePickerDirectory(path: String): List<NativeAppFileEntry> {
                    return nativeFileOperations.listFilePickerDirectoryForPigeon(path)
                }

                override fun readFilePickerFile(path: String): ByteArray {
                    return nativeFileOperations.readFilePickerFile(path)
                }
            }
        )

        val methodHandlers = createNativeMethodHandlers()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                val contractError = NativeBridgeContract.validate(call.method, call.arguments)
                if (contractError != null) {
                    result.error(NativeBridgeContract.ERROR_CODE, contractError, null)
                    return@setMethodCallHandler
                }
                methodHandlers[call.method]?.invoke(call, result) ?: result.notImplemented()
            }
    }

    private fun createNativeMethodHandlers(): Map<String, (MethodCall, MethodChannel.Result) -> Unit> {
        return mapOf(
            "createScript" to { call, result ->
                handleCreateScript(
                    call.argument<String>("name") ?: "",
                    call.argument<String>("content") ?: "",
                    result
                )
            },
            "deleteScript" to { call, result ->
                handleDeleteScript(call.argument<String>("name") ?: "", result)
            },
            "renameScript" to { call, result ->
                handleRenameScript(
                    call.argument<String>("oldName") ?: "",
                    call.argument<String>("newName") ?: "",
                    result
                )
            },
            "listScripts" to { _, result -> handleListScripts(result) },
            "readScript" to { call, result ->
                handleReadScript(call.argument<String>("name") ?: "", result)
            },
            "saveScript" to { call, result ->
                handleSaveScript(
                    call.argument<String>("name") ?: "",
                    call.argument<String>("content") ?: "",
                    result
                )
            },
            "createScriptProject" to { call, result ->
                handleCreateScriptProject(call.argument<String>("projectKey") ?: "", result)
            },
            "deleteScriptProject" to { call, result ->
                handleDeleteScriptProject(call.argument<String>("projectKey") ?: "", result)
            },
            "listProjectFiles" to { call, result ->
                handleListProjectFiles(call.argument<String>("projectKey") ?: "", result)
            },
            "readProjectFile" to { call, result ->
                handleReadProjectFile(
                    call.argument<String>("projectKey") ?: "",
                    call.argument<String>("path") ?: "",
                    result
                )
            },
            "saveProjectFile" to { call, result ->
                handleSaveProjectFile(
                    call.argument<String>("projectKey") ?: "",
                    call.argument<String>("path") ?: "",
                    call.argument<String>("content") ?: "",
                    result
                )
            },
            "createProjectDirectory" to { call, result ->
                handleCreateProjectDirectory(
                    call.argument<String>("projectKey") ?: "",
                    call.argument<String>("path") ?: "",
                    result
                )
            },
            "deleteProjectEntry" to { call, result ->
                handleDeleteProjectEntry(
                    call.argument<String>("projectKey") ?: "",
                    call.argument<String>("path") ?: "",
                    result
                )
            },
            "renameProjectEntry" to { call, result ->
                handleRenameProjectEntry(
                    call.argument<String>("projectKey") ?: "",
                    call.argument<String>("oldPath") ?: "",
                    call.argument<String>("newPath") ?: "",
                    result
                )
            },
            "importScriptProjectZip" to { call, result ->
                handleImportScriptProjectZip(
                    call.argument<String>("projectKey") ?: "",
                    call.argument<String>("uri") ?: "",
                    result
                )
            },
            "exportScriptProjectZip" to { call, result ->
                val destDir = call.argument<String>("destDir")
                handleExportScriptProjectZip(
                    call.argument<String>("projectKey") ?: "",
                    destDir,
                    result
                )
            },
            "executeScript" to { call, result ->
                @Suppress("UNCHECKED_CAST")
                val hookEnv = call.argument<Map<String, String>>("hookEnv")
                scriptExecutionController.executeScript(
                    call.argument<String>("name") ?: "",
                    call.argument<String>("executionId") ?: "",
                    call.argument<String>("workingDir"),
                    hookEnv,
                    call.argument<Int>("timeoutSeconds") ?: 0,
                    result
                )
            },
            "stopExecution" to { _, result -> scriptExecutionController.stopExecution(result) },
            "sendStdin" to { call, result ->
                scriptExecutionController.sendStdin(call.argument<String>("input") ?: "", result)
            },
            "installPackage" to { call, result ->
                chaquopyPackageController.installPackage(
                    call.argument<String>("packageName") ?: "",
                    call.argument<String>("version"),
                    call.argument<String>("indexUrl"),
                    result
                )
            },
            "uninstallPackage" to { call, result ->
                chaquopyPackageController.uninstallPackage(
                    call.argument<String>("packageName") ?: "",
                    result
                )
            },
            "listInstalledPackages" to { _, result ->
                chaquopyPackageController.listInstalledPackages(result)
            },
            "importScriptFromUri" to { call, result ->
                handleImportScriptFromUri(
                    call.argument<String>("uri") ?: "",
                    call.argument<String>("name") ?: "",
                    result
                )
            },
            "exportLog" to { call, result ->
                handleExportLog(
                    call.argument<String>("content") ?: "",
                    call.argument<String>("fileName") ?: "log.txt",
                    call.argument<String>("destDir"),
                    result
                )
            },
            "exportScript" to { call, result ->
                handleExportScript(
                    call.argument<String>("name") ?: "",
                    call.argument<String>("destDir"),
                    result
                )
            },
            "getFilePickerRoots" to { _, result -> handleGetFilePickerRoots(result) },
            "listFilePickerDirectory" to { call, result ->
                handleListFilePickerDirectory(call.argument<String>("path") ?: "", result)
            },
            "openFilePickerTree" to { _, result -> result.success(null) },
            "readFilePickerFile" to { call, result ->
                handleReadFilePickerFile(call.argument<String>("path") ?: "", result)
            },
            "openUrl" to { call, result ->
                appUpdateController.openUrl(call.argument<String>("url") ?: "", result)
            },
            "downloadAndInstallApk" to { call, result ->
                appUpdateController.startApkDownload(
                    call.argument<String>("url") ?: "",
                    call.argument<String>("fileName") ?: "python_runner_update.apk",
                    call.argument<String>("version") ?: "",
                    call.argument<String>("sha256") ?: "",
                    result
                )
            },
            "startApkDownload" to { call, result ->
                appUpdateController.startApkDownload(
                    call.argument<String>("url") ?: "",
                    call.argument<String>("fileName") ?: "python_runner_update.apk",
                    call.argument<String>("version") ?: "",
                    call.argument<String>("sha256") ?: "",
                    result
                )
            },
            "cancelDownload" to { call, result ->
                result.success(appUpdateController.cancelDownload(call.argument<String>("taskId") ?: ""))
            },
            "retryDownload" to { call, result ->
                result.success(appUpdateController.retryDownload(call.argument<String>("taskId") ?: ""))
            },
            "installDownloadedApk" to { call, result ->
                appUpdateController.installDownloadedApk(call.argument<String>("taskId") ?: "", result)
            },
            "installApkFile" to { call, result ->
                appUpdateController.installApkFile(call.argument<String>("filePath") ?: "", result)
            },
            "getAppInfo" to { _, result -> appUpdateController.getAppInfo(result) },
            "getPythonInfo" to { _, result -> runtimeInfoController.getPythonInfo(result) },
            "getLinuxLikeRuntimeInfo" to { _, result ->
                runtimeInfoController.getLinuxLikeRuntimeInfo(result)
            },
            "prepareLinuxLikeRuntime" to { _, result ->
                runtimeInfoController.prepareLinuxLikeRuntime(result)
            },
            "installLinuxLikeRuntime" to { call, result ->
                runtimeInfoController.installLinuxLikeRuntime(
                    call.argument<String>("manifestUrl"),
                    result
                )
            },
            "executeLinuxLikeScript" to { call, result ->
                @Suppress("UNCHECKED_CAST")
                val environment = call.argument<Map<String, String>>("environment")
                scriptExecutionController.executeLinuxLikeScript(
                    call.argument<String>("name") ?: "",
                    call.argument<String>("executionId") ?: "",
                    call.argument<String>("workingDir"),
                    environment,
                    call.argument<Int>("timeoutSeconds") ?: 0,
                    call.argument<String>("projectKey"),
                    call.argument<String>("projectMainFilePath"),
                    result
                )
            },
            "sendLinuxLikeStdin" to { call, result ->
                scriptExecutionController.sendLinuxLikeStdin(
                    call.argument<String>("input") ?: "",
                    result
                )
            },
            "stopLinuxLikeExecution" to { _, result ->
                scriptExecutionController.stopLinuxLikeExecution(result)
            },
            "installLinuxLikePackage" to { call, result ->
                linuxLikePackageController.installLinuxLikePackage(
                    call.argument<String>("packageName") ?: "",
                    call.argument<String>("version"),
                    call.argument<String>("indexUrl"),
                    result
                )
            },
            "repairLinuxLikePackage" to { call, result ->
                linuxLikePackageController.repairLinuxLikePackage(
                    call.argument<String>("packageName") ?: "",
                    call.argument<String>("version"),
                    call.argument<String>("indexUrl"),
                    result
                )
            },
            "installLinuxLikeRequirements" to { call, result ->
                linuxLikePackageController.installLinuxLikeRequirements(
                    call.argument<String>("projectKey"),
                    call.argument<String>("requirementsPath") ?: "requirements.txt",
                    call.argument<String>("content"),
                    call.argument<String>("displayName") ?: "requirements.txt",
                    call.argument<String>("indexUrl"),
                    result
                )
            },
            "uninstallLinuxLikePackage" to { call, result ->
                linuxLikePackageController.uninstallLinuxLikePackage(
                    call.argument<String>("packageName") ?: "",
                    result
                )
            },
            "listLinuxLikePackages" to { _, result ->
                linuxLikePackageController.listLinuxLikePackages(result)
            },
            "moveToBackground" to { _, result ->
                moveTaskToBack(true)
                result.success(null)
            },
            "checkOverlayPermission" to { _, result ->
                result.success(floatingBallController.canShowFloatingBall())
            },
            "requestOverlayPermission" to { _, result ->
                floatingBallController.requestOverlayPermission()
                result.success(null)
            },
            "showFloatingBall" to { call, result ->
                floatingBallController.showFloatingBall(call.argument<String>("scriptName"), result)
            },
            "hideFloatingBall" to { _, result -> floatingBallController.hideFloatingBall(result) },
            "updateFloatingBallStatus" to { call, result ->
                floatingBallController.updateFloatingBallStatus(
                    call.argument<String>("status") ?: "running",
                    result
                )
            },
            "pushFloatingBallOutput" to { call, result ->
                floatingBallController.pushFloatingBallOutput(call.argument<String>("output") ?: "", result)
            },
            "consumePendingRunScript" to { _, result ->
                result.success(consumePendingRunScript())
            }
        )
    }

    // --- Script Management ---

    private fun scriptFileErrorCode(e: Exception): String {
        val message = e.message.orEmpty()
        return if (
            message.contains("脚本已存在") ||
            message.contains("脚本不存在") ||
            message.contains("目标名称已存在")
        ) "1001" else "1002"
    }

    private fun handleCreateScript(name: String, content: String, result: MethodChannel.Result) {
        try {
            result.success(scriptFileStore.createScript(name, content))
        } catch (e: Exception) {
            result.error(scriptFileErrorCode(e), "创建脚本失败: ${e.message}", null)
        }
    }

    private fun handleDeleteScript(name: String, result: MethodChannel.Result) {
        try {
            scriptFileStore.deleteScript(name)
            result.success(true)
        } catch (e: Exception) {
            result.error(scriptFileErrorCode(e), "删除脚本失败: ${e.message}", null)
        }
    }

    private fun handleRenameScript(oldName: String, newName: String, result: MethodChannel.Result) {
        try {
            scriptFileStore.renameScript(oldName, newName)
            result.success(true)
        } catch (e: Exception) {
            result.error(scriptFileErrorCode(e), "重命名失败: ${e.message}", null)
        }
    }

    private fun handleListScripts(result: MethodChannel.Result) {
        try {
            result.success(scriptFileStore.listScripts())
        } catch (e: Exception) {
            result.error("1002", "列出脚本失败: ${e.message}", null)
        }
    }

    private fun handleReadScript(name: String, result: MethodChannel.Result) {
        try {
            result.success(scriptFileStore.readScript(name))
        } catch (e: Exception) {
            result.error(scriptFileErrorCode(e), "读取脚本失败: ${e.message}", null)
        }
    }

    private fun handleSaveScript(name: String, content: String, result: MethodChannel.Result) {
        try {
            scriptFileStore.saveScript(name, content)
            result.success(true)
        } catch (e: Exception) {
            result.error("1002", "保存脚本失败: ${e.message}", null)
        }
    }

    // --- Project File Management ---

    private fun handleCreateScriptProject(projectKey: String, result: MethodChannel.Result) {
        try {
            result.success(scriptProjectStore.createProject(projectKey))
        } catch (e: Exception) {
            result.error("1021", "创建项目失败: ${e.message}", null)
        }
    }

    private fun handleDeleteScriptProject(projectKey: String, result: MethodChannel.Result) {
        try {
            result.success(scriptProjectStore.deleteProject(projectKey))
        } catch (e: Exception) {
            result.error("1022", "删除项目失败: ${e.message}", null)
        }
    }

    private fun handleListProjectFiles(projectKey: String, result: MethodChannel.Result) {
        try {
            result.success(scriptProjectStore.listProjectFiles(projectKey))
        } catch (e: Exception) {
            result.error("1023", "列出项目文件失败: ${e.message}", null)
        }
    }

    private fun handleReadProjectFile(projectKey: String, path: String, result: MethodChannel.Result) {
        try {
            result.success(scriptProjectStore.readProjectFile(projectKey, path))
        } catch (e: Exception) {
            result.error("1024", "读取项目文件失败: ${e.message}", null)
        }
    }

    private fun handleSaveProjectFile(projectKey: String, path: String, content: String, result: MethodChannel.Result) {
        try {
            result.success(scriptProjectStore.saveProjectFile(projectKey, path, content))
        } catch (e: Exception) {
            result.error("1025", "保存项目文件失败: ${e.message}", null)
        }
    }

    private fun handleCreateProjectDirectory(projectKey: String, path: String, result: MethodChannel.Result) {
        try {
            result.success(scriptProjectStore.createProjectDirectory(projectKey, path))
        } catch (e: Exception) {
            result.error("1026", "创建项目目录失败: ${e.message}", null)
        }
    }

    private fun handleDeleteProjectEntry(projectKey: String, path: String, result: MethodChannel.Result) {
        try {
            result.success(scriptProjectStore.deleteProjectEntry(projectKey, path))
        } catch (e: Exception) {
            result.error("1027", "删除项目条目失败: ${e.message}", null)
        }
    }

    private fun handleRenameProjectEntry(projectKey: String, oldPath: String, newPath: String, result: MethodChannel.Result) {
        try {
            result.success(scriptProjectStore.renameProjectEntry(projectKey, oldPath, newPath))
        } catch (e: Exception) {
            result.error("1028", "重命名项目条目失败: ${e.message}", null)
        }
    }

    private fun handleImportScriptProjectZip(projectKey: String, uriString: String, result: MethodChannel.Result) {
        try {
            result.success(scriptProjectStore.importProjectZip(projectKey, uriString))
        } catch (e: Exception) {
            result.error("1029", "导入项目ZIP失败: ${e.message}", null)
        }
    }

    private fun handleExportScriptProjectZip(projectKey: String, destDir: String?, result: MethodChannel.Result) {
        try {
            result.success(scriptProjectStore.exportProjectZip(projectKey, destDir))
        } catch (e: Exception) {
            result.error("1030", "导出项目ZIP失败: ${e.message}", null)
        }
    }

    private fun deletePythonCacheDirectory(dir: File, rootPath: java.nio.file.Path) {
        if (!dir.isDirectory || dir.name != "__pycache__") return
        val path = try {
            dir.canonicalFile.toPath()
        } catch (_: Exception) {
            return
        }
        if (path.startsWith(rootPath)) {
            dir.deleteRecursively()
        }
    }

    private fun isBroadPythonCacheCleanupRoot(root: File): Boolean {
        val path = root.absolutePath.replace('\\', '/').trimEnd('/')
        return path == "" ||
            path == "/" ||
            path == "/storage" ||
            path == "/storage/emulated" ||
            path == "/storage/emulated/0" ||
            path == "/sdcard" ||
            path == "/mnt"
    }

    private fun deletePythonCacheDirectories(rootDir: File) {
        try {
            val root = rootDir.canonicalFile
            if (!root.isDirectory) return
            val rootPath = root.toPath()
            deletePythonCacheDirectory(File(root, "__pycache__"), rootPath)
            if (isBroadPythonCacheCleanupRoot(root)) return

            var visited = 0
            for (file in root.walkBottomUp().maxDepth(8)) {
                visited += 1
                if (visited > 5000) break
                if (file.isDirectory && file.name == "__pycache__") {
                    deletePythonCacheDirectory(file, rootPath)
                }
            }
        } catch (_: Exception) {
        }
    }

    private fun deleteProjectPycacheDirectories(projectRoot: File) {
        deletePythonCacheDirectories(projectRoot)
    }

    // --- File Operations ---

    private fun handleImportScriptFromUri(uriString: String, name: String, result: MethodChannel.Result) {
        try {
            result.success(nativeFileOperations.importScriptFromUri(uriString, name))
        } catch (e: Exception) {
            result.error("1002", "导入失败: ${e.message}", null)
        }
    }

    private fun handleExportLog(content: String, fileName: String, destDir: String?, result: MethodChannel.Result) {
        try {
            result.success(nativeFileOperations.exportLog(content, fileName, destDir))
        } catch (e: Exception) {
            result.error("1002", "导出失败: ${e.message}", null)
        }
    }

    private fun handleExportScript(name: String, destDir: String?, result: MethodChannel.Result) {
        try {
            result.success(nativeFileOperations.exportScript(name, destDir))
        } catch (e: Exception) {
            result.error("1002", "导出脚本失败: ${e.message}", null)
        }
    }

    private fun handleGetFilePickerRoots(result: MethodChannel.Result) {
        try {
            result.success(nativeFileOperations.getFilePickerRoots())
        } catch (e: Exception) {
            result.error("1032", "获取存储位置失败: ${e.message}", null)
        }
    }

    private fun handleListFilePickerDirectory(path: String, result: MethodChannel.Result) {
        try {
            result.success(nativeFileOperations.listFilePickerDirectory(path))
        } catch (e: SecurityException) {
            result.error("1033", "没有权限读取此目录: ${e.message}", null)
        } catch (e: Exception) {
            result.error("1033", "读取目录失败: ${e.message}", null)
        }
    }

    private fun handleReadFilePickerFile(path: String, result: MethodChannel.Result) {
        try {
            result.success(nativeFileOperations.readFilePickerFile(path))
        } catch (e: SecurityException) {
            result.error("1034", "没有权限读取文件: ${e.message}", null)
        } catch (e: Exception) {
            result.error("1034", "读取文件失败: ${e.message}", null)
        }
    }

    // --- Helpers ---

    private fun sendLog(type: String, message: String, executionId: String? = null) {
        mainHandler.post {
            val payload = mutableMapOf<String, Any?>(
                "type" to type,
                "content" to message,
                "timestamp" to System.currentTimeMillis()
            )
            if (!executionId.isNullOrBlank()) {
                payload["executionId"] = executionId
            }
            logSink?.success(payload)
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


