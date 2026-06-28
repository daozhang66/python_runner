package com.daozhang.py

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.ResultReceiver
import io.flutter.plugin.common.MethodChannel

class FloatingBallController(
    private val activity: Activity,
    private val mainHandler: Handler
) {
    fun canShowFloatingBall(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            android.provider.Settings.canDrawOverlays(activity)
    }

    fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            !android.provider.Settings.canDrawOverlays(activity)
        ) {
            activity.startActivity(
                Intent(
                    android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:${activity.packageName}")
                ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
            )
        }
    }

    fun showFloatingBall(scriptName: String?, result: MethodChannel.Result) {
        var completed = false
        var timeoutRunnable: Runnable? = null
        try {
            if (!canShowFloatingBall()) {
                result.error("1024", "悬浮窗权限未授予", null)
                return
            }
            timeoutRunnable = Runnable {
                if (completed) return@Runnable
                completed = true
                result.error("1025", "悬浮球服务启动超时，请重新开启或检查系统悬浮窗权限", null)
            }
            val receiver = object : ResultReceiver(mainHandler) {
                override fun onReceiveResult(resultCode: Int, resultData: Bundle?) {
                    if (completed) return
                    completed = true
                    timeoutRunnable?.let { mainHandler.removeCallbacks(it) }
                    if (resultCode == FloatingBallService.RESULT_SHOW_OK) {
                        result.success(true)
                    } else {
                        val message = resultData?.getString(
                            FloatingBallService.EXTRA_RESULT_MESSAGE
                        ) ?: "显示悬浮球失败"
                        result.error("1020", message, null)
                    }
                }
            }
            val intent = Intent(activity, FloatingBallService::class.java).apply {
                action = FloatingBallService.ACTION_SHOW
                putExtra(FloatingBallService.EXTRA_SCRIPT_NAME, scriptName ?: "")
                putExtra(FloatingBallService.EXTRA_RESULT_RECEIVER, receiver)
            }
            mainHandler.postDelayed(timeoutRunnable!!, 2500L)
            startFloatingBallService(intent)
        } catch (e: Exception) {
            completed = true
            timeoutRunnable?.let { mainHandler.removeCallbacks(it) }
            result.error("1020", "显示悬浮球失败: ${e.message}", null)
        }
    }

    fun hideFloatingBall(result: MethodChannel.Result) {
        try {
            val intent = Intent(activity, FloatingBallService::class.java).apply {
                action = FloatingBallService.ACTION_HIDE
            }
            startFloatingBallService(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("1021", "隐藏悬浮球失败: ${e.message}", null)
        }
    }

    fun updateFloatingBallStatus(status: String, result: MethodChannel.Result) {
        try {
            if (!canShowFloatingBall()) {
                result.error("1024", "悬浮窗权限未授予", null)
                return
            }
            val intent = Intent(activity, FloatingBallService::class.java).apply {
                action = FloatingBallService.ACTION_UPDATE_STATUS
                putExtra(FloatingBallService.EXTRA_STATUS, status)
            }
            startFloatingBallService(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("1022", "更新悬浮球状态失败: ${e.message}", null)
        }
    }

    fun pushFloatingBallOutput(output: String, result: MethodChannel.Result) {
        try {
            if (!canShowFloatingBall()) {
                result.error("1024", "悬浮窗权限未授予", null)
                return
            }
            val intent = Intent(activity, FloatingBallService::class.java).apply {
                action = FloatingBallService.ACTION_PUSH_OUTPUT
                putExtra(FloatingBallService.EXTRA_OUTPUT, output)
            }
            startFloatingBallService(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("1023", "推送输出失败: ${e.message}", null)
        }
    }

    private fun startFloatingBallService(intent: Intent) {
        activity.startService(intent)
    }
}
