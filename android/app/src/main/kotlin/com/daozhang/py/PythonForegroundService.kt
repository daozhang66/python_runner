package com.daozhang.py

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class PythonForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "python_runner_channel"
        const val NOTIFICATION_ID = 1001
        const val ACTION_STOP = "com.daozhang.py.ACTION_STOP"
        const val EXTRA_TASK_TYPE = "task_type"
        const val EXTRA_SCRIPT_NAME = "script_name"
        const val TASK_EXECUTE = "execute"
        const val TASK_PIP_INSTALL = "pip_install"
    }

    private var scriptName: String? = null
    private var startTime: Long = 0
    private val updateHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private val updateRunnable = object : Runnable {
        override fun run() {
            updateNotificationWithDuration()
            updateHandler.postDelayed(this, 10_000)
        }
    }

    private var wakeLock: android.os.PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        try {
            val pm = getSystemService(POWER_SERVICE) as android.os.PowerManager
            wakeLock = pm.newWakeLock(android.os.PowerManager.PARTIAL_WAKE_LOCK, "PythonRunner::ScriptExecution")
            wakeLock?.acquire(4 * 60 * 60 * 1000L)
        } catch (e: Exception) {
            android.util.Log.w("PythonRunner", "WakeLock acquire failed: ${e.message}")
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Don't try to restart — just let it die gracefully
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        updateHandler.removeCallbacks(updateRunnable)
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {}
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        val taskType = intent?.getStringExtra(EXTRA_TASK_TYPE) ?: TASK_EXECUTE
        scriptName = intent?.getStringExtra(EXTRA_SCRIPT_NAME)
        startTime = System.currentTimeMillis()

        val contentText = when (taskType) {
            TASK_PIP_INSTALL -> "正在安装 Python 包..."
            else -> {
                val name = scriptName?.removeSuffix(".py") ?: "脚本"
                "$name 运行中..."
            }
        }

        try {
            val notification = buildNotification(contentText)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            android.util.Log.w("PythonRunner", "Failed to startForeground: ${e.message}")
            stopSelf()
            return START_NOT_STICKY
        }

        // Start periodic notification updates (every 10s)
        updateHandler.removeCallbacks(updateRunnable)
        updateHandler.postDelayed(updateRunnable, 10_000)

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Python Runner",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Python 脚本执行状态"
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun updateNotificationWithDuration() {
        val name = scriptName?.removeSuffix(".py") ?: "脚本"
        val elapsed = (System.currentTimeMillis() - startTime) / 1000
        val duration = when {
            elapsed < 60 -> "${elapsed}s"
            elapsed < 3600 -> "${elapsed / 60}m ${elapsed % 60}s"
            else -> "${elapsed / 3600}h ${(elapsed % 3600) / 60}m"
        }
        try {
            val notification = buildNotification("$name 已运行 $duration")
            val manager = getSystemService(NotificationManager::class.java)
            manager.notify(NOTIFICATION_ID, notification)
        } catch (_: Exception) {}
    }

    private fun buildNotification(contentText: String): Notification {
        val stopIntent = Intent(this, PythonForegroundService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 0, stopIntent, PendingIntent.FLAG_IMMUTABLE
        )

        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val launchPendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent, PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Python Runner")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_menu_manage)
            .setOngoing(true)
            .setContentIntent(launchPendingIntent)
            .addAction(android.R.drawable.ic_media_pause, "停止", stopPendingIntent)
            .build()
    }

    fun updateNotification(text: String) {
        val notification = buildNotification(text)
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, notification)
    }
}
