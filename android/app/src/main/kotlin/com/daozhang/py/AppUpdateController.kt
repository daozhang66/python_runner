package com.daozhang.py

import android.content.Context
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.MethodChannel
import java.io.File

class AppUpdateController(
    private val context: Context,
    private val emitDownloadEvent: (Map<String, Any?>) -> Unit
) {
    private val apkInstaller by lazy { ApkInstaller(context) }
    private val downloadManager by lazy {
        DownloadManager(context, emitDownloadEvent)
    }

    fun getAppInfo(result: MethodChannel.Result) {
        try {
            result.success(loadAppInfo().toMethodChannelMap())
        } catch (e: Exception) {
            result.error("1009", "获取应用信息失败: ${e.message}", null)
        }
    }

    fun getAppInfoForPigeon(): NativeAppInfo {
        return try {
            loadAppInfo()
        } catch (e: Exception) {
            throw FlutterError("1009", "获取应用信息失败: ${e.message}", null)
        }
    }

    fun openUrl(url: String, result: MethodChannel.Result) {
        try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("1010", "打开链接失败: ${e.message}", null)
        }
    }

    fun startApkDownload(
        url: String,
        fileName: String,
        version: String,
        sha256: String,
        result: MethodChannel.Result
    ) {
        try {
            if (!apkInstaller.canRequestPackageInstalls()) {
                apkInstaller.openInstallPermissionSettings()
                emitDownloadEvent(
                    mapOf(
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
                    )
                )
                result.error("1011", "请先允许此应用安装APK，然后再重试更新", null)
                return
            }
            val taskId = downloadManager.startApkDownload(url, fileName, version, sha256)
            result.success(taskId)
        } catch (e: Exception) {
            result.error("1012", "启动下载失败: ${e.message}", null)
        }
    }

    fun cancelDownload(taskId: String): Boolean {
        return downloadManager.cancelDownload(taskId)
    }

    fun retryDownload(taskId: String): Boolean {
        return downloadManager.retryDownload(taskId)
    }

    fun installDownloadedApk(taskId: String, result: MethodChannel.Result) {
        try {
            val apkFile = downloadManager.completedFile(taskId)
                ?: throw IllegalStateException("下载任务未完成或文件不存在")
            val path = apkInstaller.installApk(apkFile)
            // ApkInstaller has copied the external update APK into private,
            // durable app storage before launching the package installer.
            downloadManager.discardCompletedTask(taskId)
            result.success(path)
        } catch (e: SecurityException) {
            result.error("1011", "请先允许此应用安装APK，然后再重试更新", null)
        } catch (e: Exception) {
            result.error("1012", "打开安装器失败: ${e.message}", null)
        }
    }

    fun installApkFile(filePath: String, result: MethodChannel.Result) {
        try {
            val apkFile = File(filePath)
            if (!apkFile.exists()) {
                throw IllegalStateException("APK 文件不存在: $filePath")
            }
            val path = apkInstaller.installApk(apkFile)
            result.success(path)
        } catch (e: SecurityException) {
            result.error("1011", "请先允许此应用安装APK，然后再重试更新", null)
        } catch (e: Exception) {
            result.error("1012", "打开安装器失败: ${e.message}", null)
        }
    }

    private fun loadAppInfo(): NativeAppInfo {
        val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
        val appName =
            context.packageManager.getApplicationLabel(context.applicationInfo)?.toString()
                ?: context.packageName
        val versionName = packageInfo.versionName ?: ""
        val buildNumber = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
            packageInfo.longVersionCode.toString()
        } else {
            @Suppress("DEPRECATION")
            packageInfo.versionCode.toString()
        }
        return NativeAppInfo(
            appName = appName,
            packageName = context.packageName,
            version = versionName,
            buildNumber = buildNumber
        )
    }
}

private fun NativeAppInfo.toMethodChannelMap(): Map<String, String> {
    return mapOf(
        "appName" to appName,
        "packageName" to packageName,
        "version" to version,
        "buildNumber" to buildNumber
    )
}
