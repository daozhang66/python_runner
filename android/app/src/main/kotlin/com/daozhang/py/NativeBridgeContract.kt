package com.daozhang.py

object NativeBridgeContract {
    const val ERROR_CODE = "1000"

    private val requiredStringArguments: Map<String, List<String>> = mapOf(
        "createScript" to listOf("name"),
        "deleteScript" to listOf("name"),
        "renameScript" to listOf("oldName", "newName"),
        "readScript" to listOf("name"),
        "saveScript" to listOf("name", "content"),
        "executeScript" to listOf("name", "executionId"),
        "sendStdin" to listOf("input"),
        "installPackage" to listOf("packageName"),
        "uninstallPackage" to listOf("packageName"),
        "importScriptFromUri" to listOf("uri", "name"),
        "exportLog" to listOf("content", "fileName"),
        "exportScript" to listOf("name"),
        "listFilePickerDirectory" to listOf("path"),
        "openFilePickerTree" to listOf("title"),
        "readFilePickerFile" to listOf("path"),
        "createScriptProject" to listOf("projectKey"),
        "deleteScriptProject" to listOf("projectKey"),
        "listProjectFiles" to listOf("projectKey"),
        "readProjectFile" to listOf("projectKey", "path"),
        "saveProjectFile" to listOf("projectKey", "path", "content"),
        "createProjectDirectory" to listOf("projectKey", "path"),
        "deleteProjectEntry" to listOf("projectKey", "path"),
        "renameProjectEntry" to listOf("projectKey", "oldPath", "newPath"),
        "importScriptProjectZip" to listOf("projectKey", "uri"),
        "exportScriptProjectZip" to listOf("projectKey"),
        "executeLinuxLikeScript" to listOf("name", "executionId"),
        "sendLinuxLikeStdin" to listOf("input"),
        "installLinuxLikePackage" to listOf("packageName"),
        "repairLinuxLikePackage" to listOf("packageName"),
        "installLinuxLikeRequirements" to listOf("requirementsPath", "displayName"),
        "uninstallLinuxLikePackage" to listOf("packageName"),
        "openUrl" to listOf("url"),
        "downloadAndInstallApk" to listOf("url", "fileName", "sha256"),
        "startApkDownload" to listOf("url", "fileName", "sha256"),
        "cancelDownload" to listOf("taskId"),
        "retryDownload" to listOf("taskId"),
        "installDownloadedApk" to listOf("taskId"),
    )

    private val optionalStringArguments: Map<String, List<String>> = mapOf(
        "exportLog" to listOf("destDir"),
        "exportScriptProjectZip" to listOf("destDir"),
        "executeScript" to listOf("workingDir"),
        "installPackage" to listOf("version", "indexUrl"),
        "executeLinuxLikeScript" to listOf("workingDir", "projectKey", "projectMainFilePath"),
        "installLinuxLikePackage" to listOf("version", "indexUrl"),
        "repairLinuxLikePackage" to listOf("version", "indexUrl"),
        "installLinuxLikeRequirements" to listOf("projectKey", "content", "indexUrl"),
        "downloadAndInstallApk" to listOf("version"),
        "startApkDownload" to listOf("version"),
    )

    private val sha256Pattern = Regex("^[a-fA-F0-9]{64}$")

    private val sha256StringArguments = setOf(
        "downloadAndInstallApk.sha256",
        "startApkDownload.sha256",
    )

    private val allowEmptyRequiredStrings = setOf(
        "saveScript.content",
        "exportLog.content",
        "saveProjectFile.content",
        "sendStdin.input",
        "sendLinuxLikeStdin.input",
    )

    fun validate(method: String, arguments: Any?): String? {
        val args = arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        val required = requiredStringArguments[method].orEmpty()
        for (key in required) {
            if (!args.containsKey(key)) return "Method $method requires string argument \"$key\""
            val value = args[key]
            if (value !is String) return "Method $method argument \"$key\" must be a string"
            if (!allowEmptyRequiredStrings.contains("$method.$key") && value.trim().isEmpty()) {
                return "Method $method requires non-empty string argument \"$key\""
            }
        }

        val stringKeys = required + optionalStringArguments[method].orEmpty()
        for (key in stringKeys) {
            val value = args[key]
            if (value != null && value !is String) {
                return "Method $method argument \"$key\" must be a string when provided"
            }
            if (value is String &&
                sha256StringArguments.contains("$method.$key") &&
                !sha256Pattern.matches(value.trim())
            ) {
                return "Method $method argument \"$key\" must be a valid SHA-256 checksum"
            }
        }
        return null
    }
}
