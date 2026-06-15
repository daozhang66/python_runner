package com.daozhang.py

import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File

class ApkInstaller(private val context: Context) {
    fun canRequestPackageInstalls(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    fun openInstallPermissionSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:${context.packageName}")
        ).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    fun installApk(apkFile: File): String {
        if (!canRequestPackageInstalls()) {
            openInstallPermissionSettings()
            throw SecurityException("INSTALL_PERMISSION_REQUIRED")
        }

        validateApk(apkFile)
        val shareableApk = ensureShareableApk(apkFile)

        val apkUri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            shareableApk
        )
        val installIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(installIntent)
        return shareableApk.absolutePath
    }

    private fun ensureShareableApk(apkFile: File): File {
        val canonicalApk = apkFile.canonicalFile
        val shareRoots = listOf(
            context.filesDir,
            context.cacheDir,
            context.getExternalFilesDir(null)
        ).filterNotNull().map { it.canonicalFile }

        if (shareRoots.any { canonicalApk.path == it.path || canonicalApk.path.startsWith(it.path + File.separator) }) {
            return canonicalApk
        }

        val installCacheDir = File(context.cacheDir, "apk_install")
        if (!installCacheDir.exists()) installCacheDir.mkdirs()
        installCacheDir.listFiles()?.forEach { file ->
            if (file.isFile && file.name.endsWith(".apk")) file.delete()
        }

        val safeName = canonicalApk.name.takeIf { it.endsWith(".apk", ignoreCase = true) }
            ?: "app-update.apk"
        val cachedApk = File(installCacheDir, safeName)
        canonicalApk.copyTo(cachedApk, overwrite = true)
        return cachedApk
    }

    private fun validateApk(apkFile: File) {
        if (!apkFile.exists() || apkFile.length() <= 0L) {
            throw IllegalStateException("APK 文件不存在或为空")
        }

        val packageInfo = getPackageArchiveInfo(apkFile)
            ?: throw IllegalStateException("无法解析 APK 包信息")

        val archivePackageName = packageInfo.packageName ?: ""
        if (archivePackageName != context.packageName) {
            throw IllegalStateException(
                "APK 包名不匹配: $archivePackageName != ${context.packageName}"
            )
        }
    }

    @Suppress("DEPRECATION")
    private fun getPackageArchiveInfo(apkFile: File): PackageInfo? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.packageManager.getPackageArchiveInfo(
                apkFile.absolutePath,
                PackageManager.PackageInfoFlags.of(0)
            )
        } else {
            context.packageManager.getPackageArchiveInfo(apkFile.absolutePath, 0)
        }
    }
}
