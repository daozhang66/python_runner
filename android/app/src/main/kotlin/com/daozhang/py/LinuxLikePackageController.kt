package com.daozhang.py

import android.os.Handler
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.util.Locale

class LinuxLikePackageController(
    private val filesDir: File,
    private val mainHandler: Handler,
    private val linuxLikeRuntimeManager: LinuxLikeRuntimeManager,
    private val scriptProjectStore: ScriptProjectStore,
    private val sendInstallProgress: (String, String, String) -> Unit,
    private val sendLog: (String, String, String?) -> Unit
) {
    private val linuxLikeBootstrapPackages = setOf("pip", "setuptools", "wheel")

    private data class LinuxLikeRequirementsTarget(
        val file: File,
        val pipPath: String,
        val workingDir: String?,
        val temporary: Boolean
    )

    fun installLinuxLikeRequirements(
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
                    val requestedPackages = readLinuxLikeRequirementPackageNames(target.file)
                    recordLinuxLikeExplicitPackages(requestedPackages)
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
        val safeRequirementsPath = scriptProjectStore.normalizeProjectRelativePath(requirementsPath)
        require(safeRequirementsPath == "requirements.txt") {
            "只支持项目根目录 requirements.txt"
        }
        if (!projectKey.isNullOrBlank()) {
            val projectRoot = scriptProjectStore.safeProjectRoot(projectKey)
            val requirementsFile = scriptProjectStore.safeProjectFile(projectKey, safeRequirementsPath)
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
            emptyMap()
        )
    }

    fun installLinuxLikePackage(
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

    fun repairLinuxLikePackage(
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
                val fixedVersion = version
                    ?.trim()
                    ?.takeIf { it.isNotBlank() && !it.equals("unknown", ignoreCase = true) }
                val packageSpec = if (fixedVersion != null) "$packageName==$fixedVersion" else packageName
                val args = mutableListOf(
                    "--disable-pip-version-check",
                    "install",
                    "--target",
                    linuxLikeRuntimeManager.userSitePackagesGuestPath,
                    "--upgrade",
                    "--force-reinstall"
                )
                if (!indexUrl.isNullOrBlank()) {
                    args.add("-i")
                    args.add(indexUrl)
                }
                args.add(packageSpec)
                sendInstallProgress(packageName, "repairing", "开始修复 $packageSpec...")
                val command = linuxLikeRuntimeManager.buildPythonModuleCommand("pip", args)
                val commandResult = runLinuxLikeCommandBlocking(command)
                if (commandResult.exitCode == 0) {
                    sendInstallProgress(packageName, "repairing", "正在校验 $packageName 是否已恢复...")
                    val verifyResult = verifyLinuxLikePackageInstalled(packageName)
                    if (verifyResult.exitCode == 0 && verifyResult.stdout.isNotBlank()) {
                        recordLinuxLikeExplicitPackage(packageName, fixedVersion)
                        refreshLinuxLikeExplicitPackageMetadata()
                        sendInstallProgress(packageName, "success", "$packageSpec 修复成功")
                        mainHandler.post { result.success(true) }
                    } else {
                        val verifyMessage = listOf(verifyResult.stderr, verifyResult.stdout)
                            .firstOrNull { it.isNotBlank() }
                            ?.trim()
                            ?: "pip show did not find $packageName after repair"
                        sendInstallProgress(packageName, "error", "$packageSpec 修复后校验失败")
                        mainHandler.post {
                            result.error("1019", "Linux-like修复包校验失败: $verifyMessage", null)
                        }
                    }
                } else {
                    val errorMessage = commandResult.stderr.ifBlank { commandResult.stdout }
                        .trim()
                        .ifBlank { "pip 退出码 ${commandResult.exitCode}" }
                    sendInstallProgress(packageName, "error", "$packageSpec 修复失败")
                    mainHandler.post {
                        result.error("1019", "Linux-like修复包失败: $errorMessage", null)
                    }
                }
            } catch (e: Exception) {
                sendInstallProgress(packageName, "error", "修复失败: ${e.message}")
                mainHandler.post {
                    result.error("1019", "Linux-like修复包失败: ${e.message}", null)
                }
            }
        }.also { it.name = "linux-like-pip-repair"; it.start() }
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

    private fun normalizeRequirementPackageName(packageSpec: String): String {
        val trimmed = packageSpec.trim()
        if (trimmed.isBlank()) return ""
        val eggName = Regex("[#&]egg=([A-Za-z0-9_.-]+)")
            .find(trimmed)
            ?.groupValues
            ?.getOrNull(1)
        if (!eggName.isNullOrBlank()) {
            return normalizePythonPackageName(eggName)
        }
        val withoutMarker = trimmed.substringBefore(";").trim()
        val beforeDirectReference = withoutMarker.substringBefore("@").trim()
        val match = Regex("[A-Za-z0-9_.-]+").find(beforeDirectReference)
            ?: return ""
        return normalizePythonPackageName(match.value)
    }

    private fun readLinuxLikeRequirementPackageNames(requirementsFile: File): List<String> {
        if (!requirementsFile.isFile) return emptyList()
        return try {
            requirementsFile.readLines()
                .map { line ->
                    line.substringBefore(" #")
                        .substringBefore("\t#")
                        .trim()
                }
                .filter { it.isNotBlank() && !it.startsWith("#") }
                .filter { line ->
                    !line.startsWith("-") ||
                        line.startsWith("-e ") ||
                        line.startsWith("--editable")
                }
                .mapNotNull { line ->
                    val candidate = if (line.startsWith("-e ")) {
                        line.removePrefix("-e").trim()
                    } else if (line.startsWith("--editable")) {
                        line.removePrefix("--editable").trim()
                    } else {
                        line
                    }
                    normalizeRequirementPackageName(candidate)
                        .takeIf { it.isNotBlank() }
                }
                .distinct()
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun uninstallLinuxLikePackage(packageName: String, result: MethodChannel.Result) {
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
        val normalizedName = normalizeRequirementPackageName(packageName)
        if (normalizedName.isBlank()) return
        val distributions = linuxLikeDistributions()
        markLinuxLikeExplicitDistributions(setOf(normalizedName), distributions)
        val packages = loadLinuxLikeExplicitPackages()
        packages[normalizedName] = version?.trim().orEmpty()
        mergeLinuxLikeExplicitPackageVersions(packages, distributions)
        saveLinuxLikeExplicitPackages(packages)
    }

    private fun recordLinuxLikeExplicitPackages(packageNames: Collection<String>) {
        if (packageNames.isEmpty()) return
        val distributions = linuxLikeDistributions()
        val packages = loadLinuxLikeExplicitPackages()
        val normalizedNames = packageNames
            .map(::normalizeRequirementPackageName)
            .filter { it.isNotBlank() && !linuxLikeBootstrapPackages.contains(it) }
            .toSet()
        markLinuxLikeExplicitDistributions(normalizedNames, distributions)
        normalizedNames.forEach { normalizedName ->
            packages[normalizedName] = packages[normalizedName].orEmpty()
        }
        mergeLinuxLikeExplicitPackageVersions(packages, distributions)
        saveLinuxLikeExplicitPackages(packages)
    }

    private fun markLinuxLikeExplicitDistributions(
        packageNames: Set<String>,
        distributions: List<LinuxLikeDistribution>
    ) {
        if (packageNames.isEmpty()) return
        distributions
            .filter { distribution ->
                packageNames.contains(distribution.normalizedName) &&
                    distribution.metadataDir.isDirectory &&
                    (
                        distribution.metadataDir.name.endsWith(".dist-info") ||
                            distribution.metadataDir.name.endsWith(".egg-info")
                    )
            }
            .forEach { distribution ->
                try {
                    distribution.metadataDir.resolve("PYTHON_RUNNER_REQUESTED").writeText("")
                } catch (_: Exception) {
                }
            }
    }

    private fun mergeLinuxLikeExplicitPackageVersions(
        packages: MutableMap<String, String>,
        distributions: List<LinuxLikeDistribution>
    ) {
        if (packages.isEmpty() || distributions.isEmpty()) return
        val installed = distributions.associateBy { it.normalizedName }
        packages.keys.toList().forEach { normalizedName ->
            val installedVersion = installed[normalizedName]?.version.orEmpty()
            if (installedVersion.isNotBlank()) {
                packages[normalizedName] = installedVersion
            }
        }
    }

    private fun pruneLinuxLikeImplicitExplicitPackages(
        packages: MutableMap<String, String>,
        distributions: List<LinuxLikeDistribution>
    ): MutableMap<String, String> {
        if (packages.isEmpty() || distributions.isEmpty()) {
            return packages
        }
        val installed = distributions.associateBy { it.normalizedName }
        val pruned = linkedMapOf<String, String>()
        packages.toSortedMap().forEach { (name, version) ->
            val distribution = installed[name] ?: return@forEach
            val metadataBacked = distribution.metadataDir.name.endsWith(".dist-info") ||
                distribution.metadataDir.name.endsWith(".egg-info")
            if (!metadataBacked || distribution.isDirectRequest) {
                pruned[name] = version
            }
        }
        return pruned
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
        val requires: List<String>,
        val integrity: LinuxLikeIntegrity
    )

    private data class LinuxLikeIntegrity(
        val status: String,
        val message: String,
        val missingImports: List<String>
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
                val topLevelEntries = metadataDir.resolve("top_level.txt")
                    .takeIf { it.isFile }
                    ?.readLines()
                    ?.map { it.trim() }
                    ?.filter { it.isNotBlank() }
                    ?: emptyList()
                val recordEntries = metadataDir.resolve("RECORD")
                    .takeIf { it.isFile }
                    ?.readLines()
                    ?.mapNotNull(::recordPathFromCsvLine)
                    ?: emptyList()
                val requires = metadata["Requires-Dist"]
                    ?.mapNotNull(::requirementName)
                    ?: emptyList()
                LinuxLikeDistribution(
                    name = name,
                    version = metadata["Version"]?.firstOrNull().orEmpty(),
                    normalizedName = normalizePythonPackageName(name),
                    metadataDir = metadataDir,
                    isDirectRequest = metadataDir.resolve("REQUESTED").isFile ||
                        metadataDir.resolve("PYTHON_RUNNER_REQUESTED").isFile,
                    topLevelEntries = topLevelEntries,
                    recordEntries = recordEntries,
                    requires = requires,
                    integrity = resolveLinuxLikeIntegrity(
                        siteDir,
                        metadataDir,
                        topLevelEntries,
                        recordEntries
                    )
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
                    (
                        File(file, "__init__.py").isFile ||
                            file.listFiles()?.any { child ->
                                child.isFile && child.name.endsWith(".py")
                            } == true
                    ) &&
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
                    requires = emptyList(),
                    integrity = LinuxLikeIntegrity("ok", "", emptyList())
                )
            }
            ?: emptyList()
        val singleFileDistributions = siteDir.listFiles()
            ?.filter { file ->
                file.isFile &&
                    file.name.endsWith(".py") &&
                    !file.name.startsWith(".") &&
                    !knownNames.contains(normalizePythonPackageName(file.name.dropLast(3))) &&
                    !metadataOwnedTopLevels.contains(normalizePythonPackageName(file.name.dropLast(3)))
            }
            ?.map { file ->
                val name = file.name.dropLast(3)
                LinuxLikeDistribution(
                    name = name,
                    version = "",
                    normalizedName = normalizePythonPackageName(name),
                    metadataDir = file,
                    isDirectRequest = false,
                    topLevelEntries = listOf(name),
                    recordEntries = listOf(file.name),
                    requires = emptyList(),
                    integrity = LinuxLikeIntegrity("ok", "", emptyList())
                )
            }
            ?: emptyList()
        return (metadataDistributions + importPackageDistributions + singleFileDistributions)
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

    private fun resolveLinuxLikeIntegrity(
        siteDir: File,
        metadataDir: File,
        topLevelEntries: List<String>,
        recordEntries: List<String>
    ): LinuxLikeIntegrity {
        val metadataBacked = metadataDir.name.endsWith(".dist-info") ||
            metadataDir.name.endsWith(".egg-info")
        if (!metadataBacked) {
            return LinuxLikeIntegrity("ok", "", emptyList())
        }
        val importRoots = inferLinuxLikeImportRoots(
            metadataDir.name,
            topLevelEntries,
            recordEntries
        )
        if (importRoots.isEmpty()) {
            return LinuxLikeIntegrity("unknown", "", emptyList())
        }
        val missingImports = importRoots
            .filterNot { linuxLikeImportRootExists(siteDir, it) }
            .distinct()
            .sorted()
        if (missingImports.isEmpty()) {
            return LinuxLikeIntegrity("ok", "", emptyList())
        }
        return LinuxLikeIntegrity(
            "broken",
            "缺少 ${missingImports.joinToString("、")}",
            missingImports
        )
    }

    private fun inferLinuxLikeImportRoots(
        metadataDirName: String,
        topLevelEntries: List<String>,
        recordEntries: List<String>
    ): List<String> {
        val declaredRoots = topLevelEntries
            .mapNotNull(::normalizePythonImportRoot)
            .distinct()
        if (declaredRoots.isNotEmpty()) {
            return declaredRoots
        }
        return recordEntries
            .mapNotNull { recordPath -> importRootFromRecordPath(recordPath, metadataDirName) }
            .distinct()
    }

    private fun normalizePythonImportRoot(value: String): String? {
        val normalizedPath = value
            .trim()
            .replace('\\', '/')
            .trim('/')
        if (normalizedPath.isBlank() || normalizedPath.contains("..")) {
            return null
        }
        val root = normalizedPath
            .substringBefore('/')
            .substringBefore('.')
            .trim()
        return root.takeIf { it.matches(Regex("[A-Za-z_][A-Za-z0-9_]*")) }
    }

    private fun importRootFromRecordPath(recordPath: String, metadataDirName: String): String? {
        val normalizedPath = recordPath
            .trim()
            .replace('\\', '/')
            .trim('/')
        if (normalizedPath.isBlank() || normalizedPath.contains("..")) {
            return null
        }
        val firstSegment = normalizedPath.substringBefore('/').trim()
        if (firstSegment.isBlank() ||
            firstSegment == metadataDirName ||
            firstSegment.endsWith(".dist-info") ||
            firstSegment.endsWith(".egg-info") ||
            firstSegment.endsWith(".data")
        ) {
            return null
        }
        if (!normalizedPath.contains('/')) {
            if (!firstSegment.endsWith(".py")) {
                return null
            }
            return normalizePythonImportRoot(firstSegment.dropLast(3))
        }
        return normalizePythonImportRoot(firstSegment)
    }

    private fun linuxLikeImportRootExists(siteDir: File, importRoot: String): Boolean {
        val root = normalizePythonImportRoot(importRoot) ?: return false
        if (File(siteDir, root).exists() || File(siteDir, "$root.py").isFile) {
            return true
        }
        return siteDir.listFiles()?.any { file ->
            file.isFile && file.name.startsWith("$root.")
        } == true
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

    private fun queryLinuxLikeInstalledPackageVersions(): MutableMap<String, String> {
        return try {
            val command = linuxLikeRuntimeManager.buildPythonModuleCommand(
                "pip",
                listOf(
                    "--disable-pip-version-check",
                    "list",
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
                packages[normalizePythonPackageName(packageName)] = item.optString("version")
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
        val loadedExplicitPackages = loadLinuxLikeExplicitPackages()
        if (distributions.isEmpty()) {
            return loadedExplicitPackages
        }
        val explicitPackages =
            pruneLinuxLikeImplicitExplicitPackages(loadedExplicitPackages, distributions)
        if (explicitPackages != loadedExplicitPackages) {
            saveLinuxLikeExplicitPackages(explicitPackages)
        }
        mergeLinuxLikeExplicitPackageVersions(explicitPackages, distributions)

        val requestedPackages = linkedMapOf<String, String>()
        distributions
            .filter { it.isDirectRequest && !linuxLikeBootstrapPackages.contains(it.normalizedName) }
            .sortedBy { it.name.lowercase(Locale.US) }
            .forEach { distribution ->
                requestedPackages[distribution.normalizedName] = distribution.version
            }
        if (requestedPackages.isNotEmpty()) {
            val mergedPackages = linkedMapOf<String, String>()
            explicitPackages.toSortedMap().forEach { (name, version) ->
                mergedPackages[name] = version
            }
            requestedPackages.toSortedMap().forEach { (name, version) ->
                mergedPackages[name] = version.ifBlank { mergedPackages[name].orEmpty() }
            }
            mergeLinuxLikeExplicitPackageVersions(mergedPackages, distributions)
            if (mergedPackages != explicitPackages) {
                saveLinuxLikeExplicitPackages(mergedPackages)
            }
            return mergedPackages.toMutableMap()
        }

        if (explicitPackages.isEmpty() && topLevelPackages.isNotEmpty()) {
            val resolvedPackages = linkedMapOf<String, String>()
            topLevelPackages.toSortedMap().forEach { (name, version) ->
                resolvedPackages[name] = version
            }
            mergeLinuxLikeExplicitPackageVersions(resolvedPackages, distributions)
            if (resolvedPackages != explicitPackages) {
                saveLinuxLikeExplicitPackages(resolvedPackages)
            }
            return resolvedPackages.toMutableMap()
        }

        if (explicitPackages.isNotEmpty()) {
            saveLinuxLikeExplicitPackages(explicitPackages)
        }
        return explicitPackages
    }

    private fun cleanupLinuxLikeOrphanDependencies(): List<String> {
        val removedDependencies = linkedSetOf<String>()
        while (true) {
            val distributions = linuxLikeDistributions()
            val explicitPackages = resolveLinuxLikeExplicitPackages(
                distributions,
                emptyMap()
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

    fun listLinuxLikePackages(result: MethodChannel.Result) {
        Thread {
            try {
                val info = linuxLikeRuntimeManager.getInfo()
                if (info["available"] != "true") {
                    mainHandler.post { result.success(emptyList<Map<String, Any>>()) }
                    return@Thread
                }
                val hostDistributions = linuxLikeDistributions()
                val installedPackageVersions = queryLinuxLikeInstalledPackageVersions()
                val explicitPackages =
                    resolveLinuxLikeExplicitPackages(hostDistributions, emptyMap()).keys
                val packages = mutableListOf<Map<String, Any>>()
                val installedPackageNames =
                    hostDistributions.mapTo(mutableSetOf()) { it.normalizedName }
                val listedPackageNames = mutableSetOf<String>()

                hostDistributions
                    .sortedBy { it.name.lowercase(Locale.US) }
                    .forEach { distribution ->
                        val normalizedPackageName = distribution.normalizedName
                        val isBootstrapPackage =
                            linuxLikeBootstrapPackages.contains(normalizedPackageName)
                        val isExplicitUserPackage =
                            explicitPackages.contains(normalizedPackageName)
                        if (!isBootstrapPackage && !isExplicitUserPackage) {
                            return@forEach
                        }
                        if (listedPackageNames.contains(normalizedPackageName)) {
                            return@forEach
                        }
                        listedPackageNames.add(normalizedPackageName)
                        val packageMap = mutableMapOf<String, Any>(
                            "name" to distribution.name,
                            "version" to distribution.version
                                .ifBlank { installedPackageVersions[normalizedPackageName].orEmpty() }
                                .ifBlank { "unknown" },
                            "source" to if (isExplicitUserPackage) "user" else "runtime",
                            "integrityStatus" to distribution.integrity.status,
                            "integrityMessage" to distribution.integrity.message,
                            "missingImports" to distribution.integrity.missingImports
                        )
                        packages.add(packageMap)
                    }
                linuxLikeBootstrapPackages
                    .filter { !listedPackageNames.contains(it) }
                    .sorted()
                    .forEach { name ->
                        listedPackageNames.add(name)
                        packages.add(
                            mapOf<String, Any>(
                                "name" to name,
                                "version" to installedPackageVersions[name].orEmpty()
                                    .ifBlank { "unknown" },
                                "source" to "runtime",
                                "integrityStatus" to "unknown",
                                "integrityMessage" to "",
                                "missingImports" to emptyList<String>()
                            )
                        )
                    }
                removeMissingLinuxLikeExplicitPackages(installedPackageNames)
                mainHandler.post {
                    result.success(
                        packages.sortedBy { it["name"]?.toString()?.lowercase(Locale.US) ?: "" }
                    )
                }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("1025", "Linux-like列出包失败: ${e.message}", null)
                }
            }
        }.also { it.name = "linux-like-package-list"; it.start() }
    }


    private data class LinuxLikeCommandResult(
        val exitCode: Int,
        val stdout: String,
        val stderr: String
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
        emitLogs: Boolean
    ): Thread {
        return Thread {
            try {
                BufferedReader(InputStreamReader(inputStream)).useLines { lines ->
                    lines.forEach { line ->
                        buffer.append(line).append('\n')
                        if (emitLogs) sendLog(type, line, null)
                    }
                }
            } catch (_: Exception) {
            }
        }.also { it.name = "linux-like-package-"; it.isDaemon = true; it.start() }
    }
}
