package com.daozhang.py

import android.os.Handler
import com.chaquo.python.Python
import io.flutter.plugin.common.MethodChannel

class ChaquopyPackageController(
    private val mainHandler: Handler,
    private val sendInstallProgress: (String, String, String) -> Unit
) {
    fun installPackage(
        packageName: String,
        version: String?,
        indexUrl: String?,
        result: MethodChannel.Result
    ) {
        Thread {
            try {
                mainHandler.post {
                    sendInstallProgress(packageName, "installing", "开始安装 $packageName...")
                }

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
                        sendInstallProgress(
                            packageName,
                            "$packageName 安装失败: pip 退出码 $pipResult",
                            "安装失败: pip 退出码 $pipResult"
                        )
                        result.error("1004", "安装失败: pip 退出码 $pipResult", null)
                    }
                    return@Thread
                }

                val verifyResult = runner.callAttr("verify_package", packageName)
                val verifySuccess = verifyResult.callAttr("get", "success").toBoolean()
                val verifyMessage = verifyResult.callAttr("get", "message").toString()

                if (verifySuccess) {
                    mainHandler.post {
                        sendInstallProgress(
                            packageName,
                            "$packageName 安装成功 - $verifyMessage",
                            "$packageName 安装成功 - $verifyMessage"
                        )
                        result.success(true)
                    }
                } else {
                    mainHandler.post {
                        sendInstallProgress(
                            packageName,
                            "$packageName 安装后无法导入: $verifyMessage",
                            "$packageName 安装后无法导入: $verifyMessage"
                        )
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

    fun uninstallPackage(packageName: String, result: MethodChannel.Result) {
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

    fun listInstalledPackages(result: MethodChannel.Result) {
        Thread {
            try {
                val py = Python.getInstance()
                val runner = py.getModule("script_runner")
                val pyPackages = runner.callAttr("list_packages")
                val packages = mutableListOf<Map<String, String>>()

                val length = pyPackages.callAttr("__len__").toInt()
                for (i in 0 until length) {
                    val item = pyPackages.callAttr("__getitem__", i)
                    packages.add(
                        mapOf(
                            "name" to item.callAttr("get", "name").toString(),
                            "version" to item.callAttr("get", "version").toString(),
                            "source" to item.callAttr("get", "source").toString()
                        )
                    )
                }

                mainHandler.post { result.success(packages) }
            } catch (e: Exception) {
                mainHandler.post { result.error("1006", "获取包列表失败: ${e.message}", null) }
            }
        }.also { it.name = "pip-list"; it.start() }
    }
}
