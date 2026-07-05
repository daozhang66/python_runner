package com.daozhang.py

import android.os.Handler
import com.chaquo.python.Python
import io.flutter.plugin.common.MethodChannel
import java.io.File

class RuntimeInfoController(
    private val filesDir: File,
    private val mainHandler: Handler,
    private val linuxLikeRuntimeManager: LinuxLikeRuntimeManager,
    private val emitInstallEvent: (Map<String, Any?>) -> Unit
) {
    fun getPythonInfo(result: MethodChannel.Result) {
        Thread {
            try {
                val info = loadPythonInfo()
                mainHandler.post {
                    result.success(info.toMethodChannelMap())
                }
            } catch (e: Exception) {
                mainHandler.post { result.error("1008", "获取Python信息失败: ${e.message}", null) }
            }
        }.also { it.name = "py-info"; it.start() }
    }

    fun getPythonInfoForPigeon(callback: (Result<NativePythonInfo>) -> Unit) {
        Thread {
            try {
                val info = loadPythonInfo()
                mainHandler.post { callback(Result.success(info)) }
            } catch (e: Exception) {
                mainHandler.post {
                    callback(
                        Result.failure(
                            FlutterError("1008", "获取Python信息失败: ${e.message}", null)
                        )
                    )
                }
            }
        }.also { it.name = "py-info-pigeon"; it.start() }
    }

    fun getLinuxLikeRuntimeInfo(result: MethodChannel.Result) {
        try {
            result.success(linuxLikeRuntimeManager.getInfo())
        } catch (e: Exception) {
            result.error("1014", "获取Linux-like运行环境信息失败: ${e.message}", null)
        }
    }

    fun getLinuxLikeRuntimeInfoForPigeon(): LinuxLikeRuntimeInfo {
        return try {
            linuxLikeRuntimeManager.getInfo().toPigeonLinuxLikeRuntimeInfo()
        } catch (e: Exception) {
            throw FlutterError("1014", "获取Linux-like运行环境信息失败: ${e.message}", null)
        }
    }

    fun prepareLinuxLikeRuntime(result: MethodChannel.Result) {
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

    fun installLinuxLikeRuntime(manifestUrl: String?, result: MethodChannel.Result) {
        Thread {
            try {
                val info = linuxLikeRuntimeManager.installFromManifest(manifestUrl) { status, message ->
                    mainHandler.post {
                        emitInstallEvent(
                            mapOf(
                                "packageName" to "linux-like-runtime",
                                "status" to status,
                                "message" to message
                            )
                        )
                    }
                }
                mainHandler.post { result.success(info) }
            } catch (e: Exception) {
                mainHandler.post {
                    emitInstallEvent(
                        mapOf(
                            "packageName" to "linux-like-runtime",
                            "status" to "error",
                            "Linux-like环境安装失败: ${e.message}" to
                                "Linux-like环境安装失败: ${e.message}"
                        )
                    )
                    result.error("1016", "安装Linux-like运行环境失败: ${e.message}", null)
                }
            }
        }.also { it.name = "linux-like-install"; it.start() }
    }

    private fun loadPythonInfo(): NativePythonInfo {
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
        } catch (_: Exception) {
            "未知"
        }
        val executable = sys.get("executable")?.toString() ?: "未知"
        val versionLine = version.lines().firstOrNull() ?: version
        return NativePythonInfo(
            pythonVersion = versionLine,
            sitePackages = sitePackages,
            pythonPath = executable,
            chaquopyPipDir = File(filesDir, "chaquopy/pip").absolutePath
        )
    }
}

private fun NativePythonInfo.toMethodChannelMap(): Map<String, String> {
    return mapOf(
        "pythonVersion" to pythonVersion,
        "sitePackages" to sitePackages,
        "pythonPath" to pythonPath,
        "chaquopyPipDir" to chaquopyPipDir
    )
}

private fun Map<String, String>.toPigeonLinuxLikeRuntimeInfo(): LinuxLikeRuntimeInfo {
    return LinuxLikeRuntimeInfo(
        available = this["available"] == "true",
        installed = this["installed"] == "true",
        message = this["message"] ?: "",
        pythonPath = this["pythonPath"] ?: "",
        pipPath = this["pipPath"] ?: "",
        rootfsDir = this["rootfsDir"] ?: ""
    )
}
