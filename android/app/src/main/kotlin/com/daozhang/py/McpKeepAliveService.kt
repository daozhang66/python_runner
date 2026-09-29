package com.daozhang.py

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Rect
import android.animation.ValueAnimator
import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.content.res.Configuration
import android.os.Build
import android.view.WindowInsets
import android.view.ViewConfiguration
import android.view.animation.DecelerateInterpolator
import android.util.DisplayMetrics
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.content.res.ColorStateList
import android.graphics.Typeface
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.GestureDetector
import android.widget.FrameLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat

/** A bounded lease renewed only while the Dart MCP server is alive. */
class McpKeepAliveService : Service() {
    companion object {
        const val CHANNEL = "mcp_keep_alive"
        const val NOTIFICATION_ID = 1002
        const val SHOW = "show_overlay"
        const val HIDE = "hide_overlay"
        const val LEASE_MS = 150_000L
    }

    private val handler = Handler(Looper.getMainLooper())
    private val expire = Runnable { stopSelf() }
    private var overlay: View? = null
    private var ballView: View? = null
    private var hidden = false
    private var wakeLock: PowerManager.WakeLock? = null
    private var surface = Color.rgb(238, 241, 247)
    private var foreground = Color.rgb(25, 29, 35)
    private var primary = Color.rgb(61, 95, 133)
    private var outline = Color.rgb(195, 202, 212)
    private var labelView: TextView? = null
    private var indicator: View? = null
    private var snapAnimator: ValueAnimator? = null
    private var reposition: (() -> Unit)? = null
    private var dockGeneration = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) { stopSelf(); return START_NOT_STICKY }
        try {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(
                    CHANNEL,
                    getString(R.string.mcp_notification_channel),
                    NotificationManager.IMPORTANCE_LOW
                )
            )
            val open = PendingIntent.getActivity(this, 1002, openIntent(),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            startForeground(NOTIFICATION_ID, NotificationCompat.Builder(this, CHANNEL)
                .setSmallIcon(android.R.drawable.ic_menu_manage)
                .setContentTitle("Python Runner · MCP")
                .setContentText(getString(R.string.mcp_notification_text))
                .setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true).build())
            handler.removeCallbacks(expire)
            handler.postDelayed(expire, LEASE_MS)
            if (wakeLock == null) {
                wakeLock = getSystemService(PowerManager::class.java)
                    .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "PythonRunner:McpKeepAlive")
                    .apply { setReferenceCounted(false) }
            }
            wakeLock?.acquire(LEASE_MS)
            surface = intent.getIntExtra("surface", surface)
            foreground = intent.getIntExtra("foreground", foreground)
            primary = intent.getIntExtra("primary", primary)
            outline = intent.getIntExtra("outline", outline)
            if (intent.getBooleanExtra(HIDE, false)) {
                hidden = true
                removeOverlay()
            } else if (intent.getBooleanExtra(SHOW, false)) hidden = false
            if (!Settings.canDrawOverlays(this)) removeOverlay()
            else if (!hidden && overlay == null) showOverlay()
            applyStyle()
        } catch (e: Exception) {
            android.util.Log.w("PythonRunner", "MCP keep-alive unavailable", e)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun openIntent() = Intent(this, MainActivity::class.java)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)

    @Suppress("DEPRECATION")
    private fun dragBounds(wm: WindowManager, size: Int): Rect {
        val screen = if (Build.VERSION.SDK_INT >= 30) {
            val metrics = wm.maximumWindowMetrics
            val insets = metrics.windowInsets.getInsetsIgnoringVisibility(
                WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout())
            Rect(insets.left, insets.top,
                metrics.bounds.width() - insets.right,
                metrics.bounds.height() - insets.bottom)
        } else {
            val metrics = DisplayMetrics()
            wm.defaultDisplay.getRealMetrics(metrics)
            fun barHeight(name: String): Int {
                val id = resources.getIdentifier(name, "dimen", "android")
                return if (id == 0) 0 else resources.getDimensionPixelSize(id)
            }
            Rect(0, barHeight("status_bar_height"), metrics.widthPixels,
                metrics.heightPixels - barHeight("navigation_bar_height"))
        }
        return Rect(screen.left, screen.top,
            maxOf(screen.left, screen.right - size),
            maxOf(screen.top, screen.bottom - size))
    }

    private fun showOverlay() {
        val wm = getSystemService(WindowManager::class.java)
        val density = resources.displayMetrics.density
        fun dp(value: Int) = (value * density).toInt()
        var touchHandler: ((MotionEvent) -> Boolean)? = null
        // Own the entire gesture stream; children and ripple backgrounds must
        // never consume ACTION_UP before the window can snap.
        val layout = object : FrameLayout(this) {
            override fun dispatchTouchEvent(event: MotionEvent): Boolean =
                touchHandler?.invoke(event) ?: super.dispatchTouchEvent(event)
        }.apply {
            clipChildren = true
            clipToPadding = true
            contentDescription = getString(R.string.mcp_overlay_content_description)
            setOnClickListener { startActivity(openIntent()) }
            setOnLongClickListener { hidden = true; removeOverlay(); true }
        }
        // Keep the window on-screen and clip the translated ball inside it.
        // This also works on devices that clamp overlay window coordinates.
        val ball = FrameLayout(this).apply {
            elevation = dp(3).toFloat()
            clipToOutline = true
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        }
        ballView = ball
        layout.addView(ball, FrameLayout.LayoutParams(dp(48), dp(48)))
        val label = TextView(this).apply {
            text = "MCP"; textSize = 11f
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            letterSpacing = 0f
            includeFontPadding = false
            gravity = Gravity.CENTER
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        labelView = label
        ball.addView(label, FrameLayout.LayoutParams(dp(48), dp(48)))
        val dot = View(this)
        indicator = dot
        ball.addView(dot, FrameLayout.LayoutParams(dp(5), dp(5),
            Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).apply { bottomMargin = dp(7) })
        val params = WindowManager.LayoutParams(dp(48), dp(48),
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT).apply {
            gravity = Gravity.TOP or Gravity.LEFT
            if (Build.VERSION.SDK_INT >= 30) setFitInsetsTypes(0)
            val bounds = dragBounds(wm, dp(48))
            x = bounds.left; y = dp(160).coerceIn(bounds.top, bounds.bottom)
        }
        var downX = 0f; var downY = 0f; var x = 0; var y = 0; var dragged = false
        var revealOnly = false
        val slop = ViewConfiguration.get(this).scaledTouchSlop
        val actualPosition = IntArray(2)
        fun updatePosition() {
            try { wm.updateViewLayout(layout, params) } catch (_: Exception) { removeOverlay() }
        }
        fun cancelDocking() {
            dockGeneration++
            snapAnimator?.cancel()
            snapAnimator = null
            ball.animate().cancel()
        }
        fun placeAtEdge(destination: Int, generation: Int) {
            if (overlay !== layout || generation != dockGeneration) return
            params.x = destination
            updatePosition()
            val bounds = dragBounds(wm, dp(48))
            val translation = McpOverlayGeometry.recessedTranslation(
                destination, bounds.left, bounds.right, dp(48))
            ball.animate().translationX(translation).alpha(0.65f).setDuration(160L).start()
            // LayoutParams are requests; vendor window policy can offset them.
            // Correct against the rendered screen coordinate, at most twice.
            fun verify(attempt: Int) {
                layout.postOnAnimation {
                    if (overlay !== layout || generation != dockGeneration) return@postOnAnimation
                    layout.getLocationOnScreen(actualPosition)
                    val error = destination - actualPosition[0]
                    if (kotlin.math.abs(error) > 1 && attempt < 2) {
                        params.x = McpOverlayGeometry.correctedOffset(params.x, actualPosition[0], destination)
                        updatePosition()
                        verify(attempt + 1)
                    } else if (kotlin.math.abs(error) > 1) {
                        android.util.Log.w("PythonRunner", "MCP dock constrained: target=$destination actual=${actualPosition[0]}")
                    }
                }
            }
            verify(0)
        }
        fun snapToEdge() {
            if (overlay !== layout) return
            cancelDocking()
            val generation = dockGeneration
            val bounds = dragBounds(wm, dp(48))
            params.y = params.y.coerceIn(bounds.top, bounds.bottom)
            layout.getLocationOnScreen(actualPosition)
            val destination = McpOverlayGeometry.nearestEdge(actualPosition[0], bounds.left, bounds.right)
            val targetOffset = McpOverlayGeometry.correctedOffset(params.x, actualPosition[0], destination)
            // Always commit the final position, even when system animations are
            // disabled or an OEM suppresses animator callbacks.
            layout.postDelayed({
                if (overlay === layout && generation == dockGeneration) {
                    snapAnimator?.cancel()
                    placeAtEdge(destination, generation)
                }
            }, 240L)
            snapAnimator = ValueAnimator.ofInt(params.x, targetOffset).apply {
                duration = 180L
                interpolator = DecelerateInterpolator()
                addUpdateListener {
                    if (overlay === layout && generation == dockGeneration) {
                        params.x = it.animatedValue as Int
                        updatePosition()
                    }
                }
                addListener(object : AnimatorListenerAdapter() {
                    private var cancelled = false
                    override fun onAnimationCancel(animation: Animator) { cancelled = true }
                    override fun onAnimationEnd(animation: Animator) {
                        if (!cancelled) placeAtEdge(destination, generation)
                    }
                })
                start()
            }
        }
        reposition = {
            cancelDocking()
            val bounds = dragBounds(wm, dp(48))
            params.x = McpOverlayGeometry.nearestEdge(params.x, bounds.left, bounds.right)
            params.y = params.y.coerceIn(bounds.top, bounds.bottom)
            placeAtEdge(params.x, dockGeneration)
        }
        val gestures = GestureDetector(this, object : GestureDetector.SimpleOnGestureListener() {
            override fun onDown(event: MotionEvent): Boolean = true
            override fun onLongPress(event: MotionEvent) {
                if (!dragged && overlay != null) layout.performLongClick()
            }
            override fun onSingleTapUp(event: MotionEvent): Boolean {
                if (!dragged && !revealOnly && overlay != null) layout.performClick()
                return true
            }
        })
        // Handle the whole ball, including the status dot, as one touch target.
        touchHandler = { event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    revealOnly = ball.translationX != 0f
                    cancelDocking()
                    ball.translationX = 0f
                    ball.alpha = 1f
                    downX = event.rawX; downY = event.rawY
                    x = params.x
                    y = params.y; dragged = false
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downX; val dy = event.rawY - downY
                    if (kotlin.math.abs(dx) > slop || kotlin.math.abs(dy) > slop) dragged = true
                    if (dragged) {
                        val bounds = dragBounds(wm, dp(48))
                        params.x = (x + dx.toInt()).coerceIn(bounds.left, bounds.right)
                        params.y = (y + dy.toInt()).coerceIn(bounds.top, bounds.bottom)
                        updatePosition()
                    }
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (event.actionMasked == MotionEvent.ACTION_UP && revealOnly && !dragged) {
                        // First tap reveals the ball. Give the user time to tap
                        // again or drag; a new gesture invalidates this callback.
                        val generation = dockGeneration
                        layout.postDelayed({
                            if (overlay === layout && generation == dockGeneration) snapToEdge()
                        }, 1800L)
                    } else {
                        snapToEdge()
                    }
                }
            }
            gestures.onTouchEvent(event)
            true
        }
        wm.addView(layout, params)
        overlay = layout
        layout.post { if (overlay === layout) reposition?.invoke() }
    }

    private fun applyStyle() {
        val density = resources.displayMetrics.density
        ballView?.background = GradientDrawable().apply {
            setColor(surface)
            shape = GradientDrawable.OVAL
            setStroke(maxOf(1, density.toInt()), outline)
        }
        indicator?.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL; setColor(primary)
        }
        labelView?.setTextColor(foreground)
        labelView?.background = RippleDrawable(
            ColorStateList.valueOf((primary and 0x00ffffff) or 0x22000000),
            null, GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.WHITE) })
    }

    private fun removeOverlay() {
        dockGeneration++
        ballView?.animate()?.cancel()
        snapAnimator?.cancel()
        snapAnimator = null
        reposition = null
        overlay?.let {
            try { getSystemService(WindowManager::class.java).removeView(it) } catch (_: Exception) {}
        }
        overlay = null
        ballView = null
        labelView = null
        indicator = null
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        overlay?.post { reposition?.invoke() }
    }

    override fun onDestroy() {
        handler.removeCallbacks(expire)
        removeOverlay()
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}
