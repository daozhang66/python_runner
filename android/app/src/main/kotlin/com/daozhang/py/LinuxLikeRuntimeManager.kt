package com.daozhang.py

import android.content.Context
import android.os.Build
import org.apache.commons.compress.archivers.tar.TarArchiveEntry
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.json.JSONObject
import org.tukaani.xz.XZInputStream
import java.io.BufferedInputStream
import java.io.File
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.nio.file.Files
import java.nio.file.Paths
import java.security.MessageDigest
import java.util.Locale
import java.util.zip.GZIPInputStream

class LinuxLikeRuntimeManager(private val context: Context) {
    companion object {
        const val defaultManifestUrl =
            "https://raw.githubusercontent.com/daozhang66/python_runner/main/linux-like/debian-python-dev-aarch64.json"
        const val defaultRuntimeFlavor = "debian-python-dev-aarch64"
        const val stdinRequestSentinel = "__PYRUNNER_STDIN_REQUEST__"
        const val defaultScriptWorkingDir = "/storage/emulated/0/Download/PythonRunner"
    }

    private val runtimeDir: File = File(context.filesDir, "linux_like")
    private val binDir: File = File(runtimeDir, "bin")
    private val prootRuntimeDir: File = File(runtimeDir, "proot_runtime")
    private val legacyTermuxDir: File = File(runtimeDir, "termux")
    private val hooksDir: File = File(context.filesDir, "python_hooks")
    private val downloadDir: File = File(runtimeDir, "downloads")
    val userSitePackagesDir: File = File(runtimeDir, "user_site_packages")
    val rootfsDir: File = File(runtimeDir, "rootfs")
    private val installedMarker: File = File(runtimeDir, ".installed")
    val explicitUserPackagesFile: File = File(runtimeDir, "explicit_user_packages.json")
    private val archiveFile: File = File(downloadDir, "runtime-package.tar.xz")
    private val prootTempDir: File = File(runtimeDir, "tmp")
    private val guestNativeLibDir = "/native-libs"
    val userSitePackagesGuestPath = "/python-runner/site-packages"
    private val guestLoaderAliasPaths = listOf(
        "/usr/lib/ld-linux-aarch64.so.1",
        "/lib/ld-linux-aarch64.so.1"
    )
    private val fallbackDnsServers = listOf("1.1.1.1", "8.8.8.8")
    private val dynamicLoaderGuestPath = "/usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1"
    private val dynamicLibraryGuestPath = "/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu:/usr/lib:/lib"

    val nativeLibraryDir: String
        get() = context.applicationInfo.nativeLibraryDir ?: ""

    val nativeProotPath: String
        get() = File(nativeLibraryDir, "libproot.so").absolutePath

    val nativeLinuxLikeLoaderPath: String
        get() = File(nativeLibraryDir, "liblinuxlike_loader.so").absolutePath

    private val nativeLinuxLikeLoaderGuestPath: String
        get() = "$guestNativeLibDir/liblinuxlike_loader.so"

    private val installedProotPath: String
        get() = File(binDir, "proot").absolutePath

    private val prootSupportDir: File
        get() {
            val primaryLoader = File(prootRuntimeDir, "usr/libexec/proot/loader")
            val legacyLoader = File(legacyTermuxDir, "usr/libexec/proot/loader")
            return if (primaryLoader.isFile || !legacyLoader.isFile) {
                prootRuntimeDir
            } else {
                legacyTermuxDir
            }
        }

    private val prootLoaderPath: String
        get() = File(prootSupportDir, "usr/libexec/proot/loader").absolutePath

    private val prootLoader32Path: String
        get() = File(prootSupportDir, "usr/libexec/proot/loader32").absolutePath

    val prootPath: String
        get() {
            val nativeProot = File(nativeProotPath)
            return if (nativeProot.isFile && nativeProot.canExecute()) {
                nativeProot.absolutePath
            } else {
                installedProotPath
            }
        }

    val pythonPath: String
        get() = File(rootfsDir, "usr/bin/python3").absolutePath

    private val pipPath: String
        get() = File(rootfsDir, "usr/bin/pip3").absolutePath

    private val pythonGuestPath: String
        get() {
            val pythonBinDir = File(rootfsDir, "usr/bin")
            val versionedPython = pythonBinDir.listFiles()
                ?.filter { it.isFile && Regex("""python3\.\d+""").matches(it.name) }
                ?.maxByOrNull { it.name.substringAfter("python3.").toIntOrNull() ?: 0 }
            return if (versionedPython != null) {
                "/usr/bin/${versionedPython.name}"
            } else {
                "/usr/bin/python3"
            }
        }

    fun getInfo(): Map<String, String> {
        repairCriticalExecutablePermissions()
        ensureGuestLoaderAliases()
        configureDnsResolver()
        val sysNativeLibDir = context.applicationInfo.nativeLibraryDir ?: ""
        val prootFile = File(prootPath)
        val pythonFile = File(pythonPath)
        val pythonBinaryFile = rootfsFile(pythonGuestPath)
        val pipFile = File(pipPath)
        val prootLoaderFile = File(prootLoaderPath)
        val prootLoader32File = File(prootLoader32Path)
        val dynamicLoaderFile = rootfsFile(dynamicLoaderGuestPath)
        val guestLoaderAliasFile = rootfsFile("/lib/ld-linux-aarch64.so.1")
        val marker = readInstalledMarker()

        // Diagnostic: list files in system nativeLibraryDir
        val nativeLibDirListing = try {
            File(sysNativeLibDir).listFiles()?.joinToString("; ") {
                "${it.name}:exists=${it.exists()},canExec=${it.canExecute()},canRead=${it.canRead()},size=${it.length()}"
            } ?: "directory empty or not found"
        } catch (e: Exception) {
            "error: ${e.message}"
        }

        // Diagnostic: check Os.access for X_OK
        val prootOsAccess = try {
            android.system.Os.access(nativeProotPath, android.system.OsConstants.X_OK).toString()
        } catch (e: Exception) {
            "error: ${e.message}"
        }

        android.util.Log.i("LinuxLike", "=== DIAGNOSTIC ===")
        android.util.Log.i("LinuxLike", "sysNativeLibDir: $sysNativeLibDir")
        android.util.Log.i("LinuxLike", "nativeLibDirListing: $nativeLibDirListing")
        android.util.Log.i("LinuxLike", "prootOsAccess(X_OK): $prootOsAccess")
        android.util.Log.i("LinuxLike", "prootPath: ${prootFile.absolutePath} exists=${prootFile.exists()} canExec=${prootFile.canExecute()}")
        android.util.Log.i("LinuxLike", "prootLoaderPath: ${prootLoaderFile.absolutePath} exists=${prootLoaderFile.exists()} canExec=${prootLoaderFile.canExecute()} size=${prootLoaderFile.length()}")
        android.util.Log.i("LinuxLike", "guestLoaderAliasPath: ${guestLoaderAliasFile.absolutePath} exists=${guestLoaderAliasFile.exists()} canExec=${guestLoaderAliasFile.canExecute()} size=${guestLoaderAliasFile.length()}")
        android.util.Log.i("LinuxLike", "=== END DIAGNOSTIC ===")
        val installed = installedMarker.exists() &&
            rootfsDir.exists() &&
            pythonFile.exists() &&
            pythonBinaryFile.exists() &&
            pipFile.exists() &&
            prootLoaderFile.exists() &&
            dynamicLoaderFile.exists() &&
            guestLoaderAliasFile.exists() &&
            prootFile.exists()
        val available = installed &&
            prootFile.exists() &&
            prootFile.canExecute() &&
            prootLoaderFile.canExecute() &&
            pythonBinaryFile.canExecute() &&
            dynamicLoaderFile.canExecute() &&
            guestLoaderAliasFile.canExecute()
        val message = when {
            available -> "Linux-like runtime ready"
            !prootFile.exists() -> "Linux-like proot missing"
            !prootFile.canExecute() -> "Linux-like proot is not executable"
            !prootLoaderFile.exists() -> "Linux-like proot loader missing"
            !prootLoaderFile.canExecute() -> "Linux-like proot loader is not executable"
            !dynamicLoaderFile.exists() -> "Linux-like dynamic loader missing"
            !dynamicLoaderFile.canExecute() -> "Linux-like dynamic loader is not executable"
            !guestLoaderAliasFile.exists() -> "Linux-like guest loader alias missing"
            !guestLoaderAliasFile.canExecute() -> "Linux-like guest loader alias is not executable"
            !pythonBinaryFile.exists() -> "Linux-like python binary missing"
            !pythonBinaryFile.canExecute() -> "Linux-like python binary is not executable"
            !installed -> "Linux-like runtime not installed"
            else -> "Linux-like runtime incomplete"
        }

        return mutableMapOf(
            "backend" to "linux_like",
            "runtimeFlavor" to (marker["runtimeFlavor"] ?: defaultRuntimeFlavor),
            "available" to available.toString(),
            "installed" to installed.toString(),
            "message" to message,
            "runtimeDir" to runtimeDir.absolutePath,
            "binDir" to binDir.absolutePath,
            "downloadDir" to downloadDir.absolutePath,
            "userSitePackagesDir" to userSitePackagesDir.absolutePath,
            "userSitePackagesGuestPath" to userSitePackagesGuestPath,
            "rootfsDir" to rootfsDir.absolutePath,
            "prootRuntimeDir" to prootRuntimeDir.absolutePath,
            "legacyTermuxDir" to legacyTermuxDir.absolutePath,
            "prootPath" to prootPath,
            "prootLoaderPath" to prootLoaderPath,
            "prootLoader32Path" to prootLoader32Path,
            "installedProotPath" to installedProotPath,
            "nativeProotPath" to nativeProotPath,
            "nativeLibraryDir" to nativeLibraryDir,
            "guestNativeLibDir" to guestNativeLibDir,
            "nativeLinuxLikeLoaderPath" to nativeLinuxLikeLoaderPath,
            "nativeLinuxLikeLoaderGuestPath" to nativeLinuxLikeLoaderGuestPath,
            "prootSource" to if (prootPath == nativeProotPath) "apk_native" else "runtime_package",
            "pythonPath" to pythonPath,
            "pipPath" to pipPath,
            "archivePath" to archiveFile.absolutePath,
            "prootTempDir" to prootTempDir.absolutePath,
            "dynamicLoaderPath" to dynamicLoaderFile.absolutePath,
            "dynamicLoaderGuestPath" to dynamicLoaderGuestPath,
            "guestLoaderAliasPath" to guestLoaderAliasFile.absolutePath,
            "diag_nativeLibDirListing" to nativeLibDirListing,
            "diag_prootOsAccessX" to prootOsAccess,
            "pythonGuestPath" to pythonGuestPath,
            "prootLoaderExecutable" to prootLoaderFile.canExecute().toString(),
            "prootLoader32Executable" to prootLoader32File.canExecute().toString(),
            "guestLoaderAliasExecutable" to guestLoaderAliasFile.canExecute().toString(),
            "pythonBinaryExecutable" to pythonBinaryFile.canExecute().toString(),
            "dynamicLoaderExecutable" to dynamicLoaderFile.canExecute().toString(),
            "defaultManifestUrl" to defaultManifestUrl,
            "architecture" to (Build.SUPPORTED_ABIS.firstOrNull() ?: Build.CPU_ABI ?: "unknown")
        ).apply {
            putAll(marker)
        }
    }

    fun prepare(): Map<String, String> {
        ensureDirectories()
        repairCriticalExecutablePermissions()
        return getInfo().toMutableMap().apply {
            this["prepared"] = "true"
        }
    }

    fun installFromManifest(
        manifestUrl: String?,
        progress: ((String, String) -> Unit)? = null
    ): Map<String, String> {
        ensureDirectories()
        val selectedManifestUrl = manifestUrl?.takeIf { it.isNotBlank() } ?: defaultManifestUrl
        progress?.invoke("manifest", "读取 Debian 开发版运行环境配置...")
        val manifest = fetchManifest(selectedManifestUrl)

        val mirrorPrefix = context
            .getSharedPreferences("FlutterSharedPreferences", android.content.Context.MODE_PRIVATE)
            .getString("flutter.github_mirror_prefix", "") ?: ""
        val downloadUrl = if (mirrorPrefix.isNotBlank()) {
            mirrorPrefix.trimEnd('/') + "/" + manifest.url
        } else {
            manifest.url
        }

        progress?.invoke("downloading", "下载 ${manifest.runtimeFlavor}...")
        downloadFile(downloadUrl, archiveFile, manifest.sizeBytes, progress)

        progress?.invoke("verifying", "校验运行环境包 SHA-256...")
        verifySha256(archiveFile, manifest.sha256)

        progress?.invoke("extracting", "解压 Debian 开发版运行环境...")
        extractRuntimeArchive(archiveFile)

        progress?.invoke("finalizing", "写入运行环境安装标记...")
        repairCriticalExecutablePermissions()
        ensureGuestLoaderAliases()
        configureDnsResolver()
        validateRuntimePackage(manifest)
        writeInstalledMarker(manifest, selectedManifestUrl)
        cleanupDownloadedArchive()

        return getInfo().toMutableMap().apply {
            this["installedFrom"] = selectedManifestUrl
            this["message"] = this["message"] ?: "Linux-like runtime installed"
        }
    }

    fun buildPythonCommand(
        scriptPath: String,
        workingDir: String? = null,
        environment: Map<String, String>? = null,
        executionFilePath: String? = null
    ): List<String> {
        return buildBaseCommand(
            resolveScriptWorkingDir(workingDir),
            ensureWorkingDirExists = true
        ).apply {
            addPythonLauncherWithHook(scriptPath, executionFilePath)
        }
    }

    fun buildPythonModuleCommand(
        moduleName: String,
        args: List<String> = emptyList(),
        workingDir: String? = null,
        environment: Map<String, String>? = null
    ): List<String> {
        return buildBaseCommand(workingDir).apply {
            addPythonLauncher()
            add("-m")
            add(moduleName)
            addAll(args)
        }
    }

    fun buildPythonInlineCommand(
        code: String,
        workingDir: String? = null
    ): List<String> {
        return buildBaseCommand(workingDir).apply {
            addPythonLauncher()
            add("-c")
            add(code)
        }
    }

    fun resolveScriptWorkingDir(workingDir: String?): String {
        val candidate = workingDir?.trim().orEmpty()
        return if (candidate.isNotEmpty()) candidate else defaultScriptWorkingDir
    }

    private fun buildBaseCommand(
        workingDir: String? = null,
        ensureWorkingDirExists: Boolean = false
    ): MutableList<String> {
        ensureDirectories()
        repairCriticalExecutablePermissions()
        ensureGuestLoaderAliases()
        configureDnsResolver()
        prepareHooksDir()
        val resolvedWorkingDir = workingDir?.takeIf { it.isNotBlank() } ?: "/root"
        val command = mutableListOf(
            prootPath,
            "--link2symlink",
            "-0",
            "-r",
            rootfsDir.absolutePath
        )
        addBind(command, context.filesDir.absolutePath)
        context.getExternalFilesDir(null)?.absolutePath?.let { addBind(command, it) }
        addBind(command, userSitePackagesDir.absolutePath, userSitePackagesGuestPath)
        if (hooksDir.isDirectory) addBind(command, hooksDir.absolutePath)
        listOf("/sdcard", "/storage", "/mnt").forEach { path ->
            if (File(path).exists()) addBind(command, path)
        }
        if (resolvedWorkingDir.startsWith("/")) {
            val hostWorkingDir = File(resolvedWorkingDir)
            if (ensureWorkingDirExists && !hostWorkingDir.exists()) {
                hostWorkingDir.mkdirs()
            }
            if (hostWorkingDir.exists()) {
                addBind(command, hostWorkingDir.absolutePath)
            }
        }
        command.add("-w")
        command.add(resolvedWorkingDir)
        return command
    }

    private fun MutableList<String>.addPythonLauncher() {
        add(pythonGuestPath)
        add("-B")
    }

    private fun MutableList<String>.addPythonLauncherWithHook(
        scriptPath: String,
        executionFilePath: String? = null
    ) {
        add(pythonGuestPath)
        add("-B")
        add("-c")
        val hooksDirLiteral = toPythonStringLiteral(hooksDir.absolutePath)
        val scriptPathLiteral = toPythonStringLiteral(scriptPath)
        val executionFilePathLiteral =
            toPythonStringLiteral(executionFilePath?.takeIf { it.isNotBlank() } ?: scriptPath)
        val stdinRequestSentinelLiteral = toPythonStringLiteral(stdinRequestSentinel)
        val code = buildString {
            appendLine("import builtins, json, os, sys")
            appendLine("sys.dont_write_bytecode = True")
            appendLine("hooks_dir = $hooksDirLiteral")
            appendLine("script_path = $scriptPathLiteral")
            appendLine("execution_file_path = $executionFilePathLiteral")
            appendLine("stdin_request_sentinel = $stdinRequestSentinelLiteral")
            appendLine("_original_stdin = sys.stdin")
            appendLine("_stdin_request_from_input = False")
            appendLine("def _emit_stdin_request(prompt=''):")
            appendLine("    payload = json.dumps({'prompt': prompt}, ensure_ascii=False)")
            appendLine("    sys.__stdout__.write(stdin_request_sentinel + payload + '\\n')")
            appendLine("    sys.__stdout__.flush()")
            appendLine("class _PythonRunnerStdin:")
            appendLine("    def readline(self, *args, **kwargs):")
            appendLine("        global _stdin_request_from_input")
            appendLine("        if not _stdin_request_from_input:")
            appendLine("            _emit_stdin_request()")
            appendLine("        return _original_stdin.readline(*args, **kwargs)")
            appendLine("    def __getattr__(self, name):")
            appendLine("        return getattr(_original_stdin, name)")
            appendLine("sys.stdin = _PythonRunnerStdin()")
            appendLine("def _patched_input(prompt=''):")
            appendLine("    global _stdin_request_from_input")
            appendLine("    _emit_stdin_request(str(prompt) if prompt is not None else '')")
            appendLine("    _stdin_request_from_input = True")
            appendLine("    try:")
            appendLine("        return sys.stdin.readline().rstrip('\\n')")
            appendLine("    finally:")
            appendLine("        _stdin_request_from_input = False")
            appendLine("builtins.input = _patched_input")
            appendLine("sys.path.insert(0, hooks_dir)")
            appendLine("if os.environ.get('PYRUNNER_HTTP_HOOK_CONFIG'):")
            appendLine("    try:")
            appendLine("        import http_debug_hook")
            appendLine("    except Exception:")
            appendLine("        pass")
            appendLine("script_dir = os.path.dirname(os.path.abspath(script_path))")
            appendLine("if script_dir and script_dir not in sys.path:")
            appendLine("    sys.path.insert(0, script_dir)")
            appendLine("sys.argv[0] = os.path.abspath(execution_file_path)")
            appendLine("with open(script_path, 'rb') as _source_file:")
            appendLine("    _source = _source_file.read()")
            appendLine("_code = compile(_source, execution_file_path, 'exec')")
            appendLine("_globals = {")
            appendLine("    '__name__': '__main__',")
            appendLine("    '__file__': execution_file_path,")
            appendLine("    '__package__': None,")
            appendLine("    '__cached__': None,")
            appendLine("    '__builtins__': builtins,")
            appendLine("}")
            appendLine("exec(_code, _globals)")
        }
        add(code)
    }

    private fun toPythonStringLiteral(value: String): String {
        return buildString {
            append('\'')
            value.forEach { ch ->
                when (ch) {
                    '\\' -> append("\\\\")
                    '\'' -> append("\\'")
                    '\n' -> append("\\n")
                    '\r' -> append("\\r")
                    '\t' -> append("\\t")
                    else -> append(ch)
                }
            }
            append('\'')
        }
    }

    fun applyHostEnvironment(
        target: MutableMap<String, String>,
        environment: Map<String, String>? = null
    ) {
        ensureDirectories()
        val executionTempDir = createProotTempDir()
        val existingLdPath = target["LD_LIBRARY_PATH"]?.takeIf { it.isNotBlank() }
        val runtimeLibDir = File(prootSupportDir, "usr/lib").absolutePath
        target["LD_LIBRARY_PATH"] = listOf(
            nativeLibraryDir.takeIf { it.isNotBlank() },
            runtimeLibDir,
            existingLdPath
        ).filterNotNull().joinToString(":")
        if (File(prootLoaderPath).isFile) {
            target["PROOT_LOADER"] = prootLoaderPath
        }
        if (File(prootLoader32Path).isFile) {
            target["PROOT_LOADER_32"] = prootLoader32Path
        }
        target["HOME"] = "/root"
        target["USER"] = "root"
        target["LOGNAME"] = "root"
        target["SHELL"] = "/bin/sh"
        target["TERM"] = "xterm-256color"
        target["PATH"] =
            "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
        target["LANG"] = "C.UTF-8"
        target["PIP_NO_INPUT"] = "1"
        target["PIP_DISABLE_PIP_VERSION_CHECK"] = "1"
        target["PIP_ROOT_USER_ACTION"] = "ignore"
        environment?.forEach { (key, value) ->
            target[key] = value
        }
        target["PYTHONDONTWRITEBYTECODE"] = "1"
        val pycacheDir = File(executionTempDir, "pycache")
        if (!pycacheDir.exists()) pycacheDir.mkdirs()
        target["PYTHONPYCACHEPREFIX"] = pycacheDir.absolutePath
        val existingPythonPath = target["PYTHONPATH"]?.takeIf { it.isNotBlank() }
        target["PYTHONPATH"] = listOf(
            userSitePackagesGuestPath,
            existingPythonPath
        ).filterNotNull().distinct().joinToString(":")
        target["PROOT_TMP_DIR"] = executionTempDir.absolutePath
        target["TMPDIR"] = executionTempDir.absolutePath
    }

    fun cleanupExecutionTempDir(path: String?) {
        if (path.isNullOrBlank()) return
        try {
            val dir = File(path)
            if (!dir.exists()) return
            val rootPath = prootTempDir.canonicalFile.toPath()
            val dirPath = dir.canonicalFile.toPath()
            if (!dirPath.startsWith(rootPath)) return
            dir.deleteRecursively()
            if (prootTempDir.exists() && prootTempDir.listFiles().isNullOrEmpty()) {
                prootTempDir.delete()
            }
        } catch (_: Exception) {
        }
    }

    private fun addBind(command: MutableList<String>, path: String, guestPath: String? = null) {
        command.add("-b")
        command.add(
            if (guestPath.isNullOrBlank()) {
                path
            } else {
                "$path:$guestPath"
            }
        )
    }

    private fun prepareHooksDir() {
        hooksDir.mkdirs()
        val hookFile = File(hooksDir, "http_debug_hook.py")
        try {
            context.assets.open("python_hooks/http_debug_hook.py").use { input ->
                hookFile.outputStream().use { output -> input.copyTo(output) }
            }
            hookFile.setReadable(true, false)
            hookFile.setWritable(true, true)
        } catch (_: Exception) { }
    }

    private fun repairCriticalExecutablePermissions() {
        ensureExecutable(File(prootPath))
        ensureExecutable(File(prootLoaderPath))
        ensureExecutable(File(prootLoader32Path))
        ensureExecutable(File(pythonPath))
        ensureExecutable(File(pipPath))
        ensureExecutable(rootfsFile(pythonGuestPath))
        ensureExecutable(rootfsFile(dynamicLoaderGuestPath))
    }

    private fun ensureGuestLoaderAliases() {
        val loaderSource = rootfsFile(dynamicLoaderGuestPath)
        if (!loaderSource.isFile) return
        guestLoaderAliasPaths.forEach { guestPath ->
            val aliasFile = rootfsFile(guestPath)
            if (!aliasFile.isFile || aliasFile.length() == 0L) {
                aliasFile.parentFile?.mkdirs()
                Files.deleteIfExists(aliasFile.toPath())
                loaderSource.inputStream().use { input ->
                    aliasFile.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }
            }
            ensureExecutable(aliasFile)
        }
    }

    private fun configureDnsResolver() {
        if (!rootfsDir.exists()) return
        val dnsServers = (readAndroidDnsServers() + fallbackDnsServers)
            .map { it.substringBefore('%') }
            .filter { it.isNotBlank() && it != "0.0.0.0" && it != "::" }
            .distinct()
            .take(4)
        val resolvConf = rootfsFile("/etc/resolv.conf")
        resolvConf.parentFile?.mkdirs()
        resolvConf.writeText(buildString {
            append("# Generated by Python Runner Linux-like runtime\n")
            dnsServers.forEach { server ->
                append("nameserver ")
                append(server)
                append('\n')
            }
            append("options timeout:2 attempts:2\n")
        })
    }

    private fun readAndroidDnsServers(): List<String> {
        return try {
            val connectivity = context.getSystemService(Context.CONNECTIVITY_SERVICE)
                as? android.net.ConnectivityManager
            val network = connectivity?.activeNetwork ?: return emptyList()
            connectivity.getLinkProperties(network)?.dnsServers
                ?.mapNotNull { it.hostAddress }
                ?: emptyList()
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun ensureExecutable(file: File) {
        if (file.exists() && !file.canExecute()) {
            file.setExecutable(true, true)
        }
    }

    private fun ensureDirectories() {
        if (!context.filesDir.exists()) context.filesDir.mkdirs()
        if (!runtimeDir.exists()) runtimeDir.mkdirs()
        if (!binDir.exists()) binDir.mkdirs()
        if (!userSitePackagesDir.exists()) userSitePackagesDir.mkdirs()
        if (!rootfsDir.exists()) rootfsDir.mkdirs()
        val userSitePackagesMountPoint = rootfsFile(userSitePackagesGuestPath)
        if (!userSitePackagesMountPoint.exists()) userSitePackagesMountPoint.mkdirs()
        if (!prootTempDir.exists()) prootTempDir.mkdirs()
    }

    private fun createProotTempDir(): File {
        pruneProotTempDirs()
        val tempDir = File(
            prootTempDir,
            "run-${System.currentTimeMillis()}-${Thread.currentThread().id}"
        )
        if (!tempDir.exists()) tempDir.mkdirs()
        return tempDir
    }

    private fun pruneProotTempDirs() {
        val cutoff = System.currentTimeMillis() - 6 * 60 * 60 * 1000L
        prootTempDir.listFiles()?.forEach { file ->
            if (file.name.startsWith("run-") && file.lastModified() < cutoff) {
                file.deleteRecursively()
            }
        }
        if (prootTempDir.exists() && prootTempDir.listFiles().isNullOrEmpty()) {
            prootTempDir.delete()
        }
    }

    private fun fetchManifest(manifestUrl: String): RuntimeManifest {
        val connection = (URL(manifestUrl).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 15000
            readTimeout = 60000
            setRequestProperty("Accept", "application/json")
            setRequestProperty("User-Agent", "python-runner-linux-like")
            setRequestProperty("Cache-Control", "no-cache")
            setRequestProperty("Pragma", "no-cache")
            instanceFollowRedirects = true
            useCaches = false
            connect()
        }
        try {
            if (connection.responseCode !in 200..299) {
                throw IllegalStateException("manifest HTTP ${connection.responseCode}")
            }
            val text = connection.inputStream.bufferedReader().use { it.readText() }
            return RuntimeManifest.fromJson(JSONObject(text))
        } finally {
            connection.disconnect()
        }
    }

    private fun downloadFile(
        url: String,
        target: File,
        expectedSize: Long,
        progress: ((String, String) -> Unit)?
    ) {
        target.parentFile?.mkdirs()
        if (target.exists()) target.delete()
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 15000
            readTimeout = 120000
            setRequestProperty("Accept", "application/octet-stream")
            setRequestProperty("User-Agent", "python-runner-linux-like")
            setRequestProperty("Cache-Control", "no-cache")
            setRequestProperty("Pragma", "no-cache")
            instanceFollowRedirects = true
            useCaches = false
            connect()
        }
        try {
            if (connection.responseCode !in 200..299) {
                throw IllegalStateException("runtime HTTP ${connection.responseCode}")
            }
            val totalBytes = if (expectedSize > 0) expectedSize else connection.contentLengthLong
            var downloadedBytes = 0L
            val buffer = ByteArray(1024 * 64)
            connection.inputStream.use { input ->
                target.outputStream().use { output ->
                    while (true) {
                        val bytesRead = input.read(buffer)
                        if (bytesRead == -1) break
                        output.write(buffer, 0, bytesRead)
                        downloadedBytes += bytesRead
                        if (totalBytes > 0) {
                            val percent = (downloadedBytes * 100 / totalBytes).coerceIn(0, 100)
                            progress?.invoke("downloading", "下载中 $percent%")
                        }
                    }
                }
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun verifySha256(file: File, expectedSha256: String) {
        val expected = expectedSha256.lowercase(Locale.US)
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(1024 * 64)
            while (true) {
                val bytesRead = input.read(buffer)
                if (bytesRead == -1) break
                digest.update(buffer, 0, bytesRead)
            }
        }
        val actual = digest.digest().joinToString("") {
            "%02x".format(Locale.US, it.toInt() and 0xff)
        }
        if (actual != expected) {
            throw IllegalStateException("runtime sha256 mismatch: expected=$expected actual=$actual")
        }
    }

    private fun extractRuntimeArchive(archive: File) {
        cleanInstalledRuntime()
        if (!runtimeDir.exists()) runtimeDir.mkdirs()
        BufferedInputStream(archive.inputStream()).use { fileInput ->
            val archiveInput: InputStream = when {
                archive.name.endsWith(".tar.xz") || archive.name.endsWith(".txz") ->
                    XZInputStream(fileInput)
                archive.name.endsWith(".tar.gz") || archive.name.endsWith(".tgz") ->
                    GZIPInputStream(fileInput)
                archive.name.endsWith(".tar") -> fileInput
                else -> throw IllegalStateException("unsupported runtime archive: ${archive.name}")
            }
            archiveInput.use { extractTarStream(it) }
        }
    }

    private fun extractTarStream(input: InputStream) {
        val pendingHardLinks = mutableListOf<PendingHardLink>()
        TarArchiveInputStream(input).use { tarInput ->
            while (true) {
                val entry = tarInput.nextTarEntry ?: break
                if (!tarInput.canReadEntryData(entry)) continue
                extractTarEntry(tarInput, entry, pendingHardLinks)
            }
        }
        pendingHardLinks.forEach { link ->
            val output = resolveArchiveTarget(link.name)
            val linkTarget = resolveArchiveTarget(link.linkName)
            if (!copyHardLinkTarget(output, linkTarget, link.mode)) {
                throw IllegalStateException("unresolved runtime hard link: ${link.name} -> ${link.linkName}")
            }
        }
    }

    private fun extractTarEntry(
        tarInput: TarArchiveInputStream,
        entry: TarArchiveEntry,
        pendingHardLinks: MutableList<PendingHardLink>
    ) {
        val output = resolveArchiveTarget(entry.name)
        when {
            entry.isDirectory -> {
                if (!output.exists()) output.mkdirs()
            }
            entry.isSymbolicLink -> {
                output.parentFile?.mkdirs()
                Files.deleteIfExists(output.toPath())
                Files.createSymbolicLink(output.toPath(), Paths.get(entry.linkName))
            }
            entry.isLink -> {
                val linkTarget = resolveArchiveTarget(entry.linkName)
                if (!copyHardLinkTarget(output, linkTarget, entry.mode)) {
                    pendingHardLinks.add(PendingHardLink(entry.name, entry.linkName, entry.mode))
                }
            }
            entry.isFile -> {
                output.parentFile?.mkdirs()
                output.outputStream().use { tarInput.copyTo(it) }
                applyArchiveMode(output, entry.mode)
            }
        }
    }

    private fun copyHardLinkTarget(output: File, linkTarget: File, mode: Int): Boolean {
        if (!linkTarget.isFile) return false
        output.parentFile?.mkdirs()
        Files.deleteIfExists(output.toPath())
        linkTarget.inputStream().use { input ->
            output.outputStream().use { outputStream ->
                input.copyTo(outputStream)
            }
        }
        applyArchiveMode(output, mode)
        return true
    }

    private fun resolveArchiveTarget(entryName: String): File {
        val cleanedName = entryName.removePrefix("./")
        val target = File(runtimeDir, cleanedName)
        val rootPath = runtimeDir.canonicalFile.toPath()
        val targetPath = target.canonicalFile.toPath()
        if (!targetPath.startsWith(rootPath)) {
            throw IllegalStateException("unsafe runtime archive entry: $entryName")
        }
        return target
    }

    private fun applyArchiveMode(file: File, mode: Int) {
        file.setReadable(mode and 0b100_000_000 != 0, false)
        file.setWritable(mode and 0b010_000_000 != 0, true)
        file.setExecutable(mode and 0b001_000_000 != 0, false)
    }

    private data class PendingHardLink(
        val name: String,
        val linkName: String,
        val mode: Int
    )

    private fun cleanInstalledRuntime() {
        if (installedMarker.exists()) installedMarker.delete()
        if (rootfsDir.exists()) rootfsDir.deleteRecursively()
        if (binDir.exists()) binDir.deleteRecursively()
        if (prootRuntimeDir.exists()) prootRuntimeDir.deleteRecursively()
        if (legacyTermuxDir.exists()) legacyTermuxDir.deleteRecursively()
    }

    private fun cleanupDownloadedArchive() {
        if (archiveFile.exists()) archiveFile.delete()
        if (downloadDir.exists() && downloadDir.listFiles()?.isEmpty() != false) {
            downloadDir.delete()
        }
    }

    private fun validateRuntimePackage(manifest: RuntimeManifest) {
        val missing = mutableListOf<String>()
        if (!File(prootPath).isFile) missing.add("libproot.so or bin/proot")
        if (!File(prootLoaderPath).isFile) missing.add("proot_runtime/usr/libexec/proot/loader")
        if (!File(pythonPath).isFile) missing.add("rootfs/usr/bin/python3")
        if (!rootfsFile(pythonGuestPath).isFile) missing.add("rootfs$pythonGuestPath")
        if (!File(pipPath).isFile) missing.add("rootfs/usr/bin/pip3")
        if (!rootfsFile(dynamicLoaderGuestPath).isFile) missing.add("rootfs$dynamicLoaderGuestPath")
        if (!rootfsFile("/lib/ld-linux-aarch64.so.1").isFile) {
            missing.add("rootfs/lib/ld-linux-aarch64.so.1")
        }

        if (missing.isNotEmpty()) {
            throw IllegalStateException(
                "runtime package ${manifest.runtimeFlavor} missing: ${missing.joinToString(", ")}"
            )
        }

        val notExecutable = mutableListOf<String>()
        if (!File(prootPath).canExecute()) notExecutable.add("prootPath")
        if (!File(prootLoaderPath).canExecute()) notExecutable.add("proot_runtime/usr/libexec/proot/loader")
        if (!rootfsFile(pythonGuestPath).canExecute()) notExecutable.add(pythonGuestPath)
        if (!rootfsFile(dynamicLoaderGuestPath).canExecute()) {
            notExecutable.add(dynamicLoaderGuestPath)
        }
        if (!rootfsFile("/lib/ld-linux-aarch64.so.1").canExecute()) {
            notExecutable.add("/lib/ld-linux-aarch64.so.1")
        }

        if (notExecutable.isNotEmpty()) {
            throw IllegalStateException(
                "runtime package ${manifest.runtimeFlavor} not executable: ${notExecutable.joinToString(", ")}"
            )
        }
    }

    private fun rootfsFile(guestPath: String): File {
        return File(rootfsDir, guestPath.removePrefix("/"))
    }

    private fun writeInstalledMarker(manifest: RuntimeManifest, manifestUrl: String) {
        val json = JSONObject()
            .put("backend", "linux_like")
            .put("runtimeFlavor", manifest.runtimeFlavor)
            .put("version", manifest.version)
            .put("python", manifest.python)
            .put("pip", manifest.pip)
            .put("sha256", manifest.sha256)
            .put("manifestUrl", manifestUrl)
            .put("installedAt", System.currentTimeMillis().toString())
        installedMarker.writeText(json.toString())
    }

    private fun readInstalledMarker(): Map<String, String> {
        if (!installedMarker.exists()) return emptyMap()
        return try {
            val json = JSONObject(installedMarker.readText())
            json.keys().asSequence().associateWith { key ->
                json.optString(key, "")
            }
        } catch (_: Exception) {
            emptyMap()
        }
    }

    private data class RuntimeManifest(
        val runtimeFlavor: String,
        val version: String,
        val url: String,
        val sha256: String,
        val sizeBytes: Long,
        val python: String,
        val pip: String
    ) {
        companion object {
            fun fromJson(json: JSONObject): RuntimeManifest {
                val runtimeFlavor = json.optString("runtimeFlavor", defaultRuntimeFlavor)
                val url = json.getString("url")
                val sha256 = json.getString("sha256")
                return RuntimeManifest(
                    runtimeFlavor = runtimeFlavor,
                    version = json.optString("version", "1"),
                    url = url,
                    sha256 = sha256,
                    sizeBytes = json.optLong("size", 0L),
                    python = json.optString("python", "3"),
                    pip = json.optString("pip", "")
                )
            }
        }
    }
}
