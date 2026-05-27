package com.daozhang.py

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.app.Service
import android.content.Intent
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.OvershootInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import java.io.File
import kotlin.math.abs

class FloatingBallService : Service() {

    companion object {
        const val ACTION_SHOW = "com.daozhang.py.FLOATING_BALL_SHOW"
        const val ACTION_HIDE = "com.daozhang.py.FLOATING_BALL_HIDE"
        const val ACTION_UPDATE_STATUS = "com.daozhang.py.FLOATING_BALL_UPDATE_STATUS"
        const val ACTION_PUSH_OUTPUT = "com.daozhang.py.FLOATING_BALL_PUSH_OUTPUT"

        const val EXTRA_STATUS = "status"
        const val EXTRA_OUTPUT = "output"
        const val EXTRA_SCRIPT_NAME = "script_name"

        const val STATUS_IDLE = "idle"
        const val STATUS_RUNNING = "running"
        const val STATUS_ERROR = "error"
        const val STATUS_WAITING_INPUT = "waiting_input"

        private const val PREFS_NAME = "floating_ball_prefs"
        private const val KEY_RECENT_SCRIPTS = "recent_scripts"
        private const val MAX_RECENT = 5
    }

    // ── Views ──
    private var ballView: View? = null
    private var ballIconView: ImageView? = null
    private var ballBg: GradientDrawable? = null
    private var panelView: View? = null
    private var panelTimeText: TextView? = null

    private var windowManager: WindowManager? = null
    private var ballParams: WindowManager.LayoutParams? = null
    private var panelParams: WindowManager.LayoutParams? = null

    // ── State ──
    private var currentStatus = STATUS_IDLE
    private var scriptName = ""
    private var startTime = 0L
    private var isCollapsed = true
    private var isOnLeftEdge = false

    // ── Touch tracking ──
    private var initialX = 0
    private var initialY = 0
    private var initialTouchX = 0f
    private var initialTouchY = 0f
    private var isDragging = false
    private var isPanelVisible = false
    private var isLongPress = false
    private var isInTrashZone = false
    private val longPressHandler = Handler(Looper.getMainLooper())
    private var longPressRunnable: Runnable? = null

    // ── Animations / Timers ──
    private var currentAnimator: Animator? = null
    private val timerHandler = Handler(Looper.getMainLooper())
    private var timerRunnable: Runnable? = null
    private var panelAutoDismissRunnable: Runnable? = null
    private var collapseRunnable: Runnable? = null

    // ── Dimensions ──
    private val density by lazy { resources.displayMetrics.density }
    private val ballSizePx by lazy { (48 * density).toInt() }
    private val collapsedVisiblePx by lazy { (16 * density).toInt() }
    private val screenWidth: Int get() = resources.displayMetrics.widthPixels
    private val screenHeight: Int get() = resources.displayMetrics.heightPixels
    private val touchSlop by lazy { (10 * density).toInt() }
    private val panelWidthPx by lazy { (260 * density).toInt() }

    // ── Colors ──
    private val COLOR_IDLE = 0xFF9E9E9E.toInt()
    private val COLOR_RUNNING = 0xFF4CAF50.toInt()
    private val COLOR_ERROR = 0xFFF44336.toInt()
    private val COLOR_WAITING = 0xFFFF9800.toInt()
    private val COLOR_TRASH = 0xFFD32F2F.toInt()

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW -> {
                val name = intent.getStringExtra(EXTRA_SCRIPT_NAME) ?: ""
                if (name.isNotEmpty()) {
                    scriptName = name
                    startTime = System.currentTimeMillis()
                    addRecentScript(name)
                    if (ballView == null) {
                        showBall()
                    }
                    updateStatus(STATUS_RUNNING)
                } else {
                    if (ballView == null) {
                        showBall()
                        updateStatus(STATUS_IDLE)
                    }
                }
            }
            ACTION_HIDE -> {
                hideAll()
                stopSelf()
            }
            ACTION_UPDATE_STATUS -> {
                val status = intent.getStringExtra(EXTRA_STATUS) ?: STATUS_IDLE
                updateStatus(status)
            }
            ACTION_PUSH_OUTPUT -> {
                // Script output stays in the in-app terminal; the overlay is only a launcher/status control.
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        hideAll()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ═══════════════════════════════════════════════════════════
    // Show / Hide
    // ═══════════════════════════════════════════════════════════

    private fun showBall() {
        if (ballView != null) return

        ballView = createBallView()
        ballParams = WindowManager.LayoutParams(
            ballSizePx, ballSizePx,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = maxBallX()
            y = (screenHeight / 2 - ballSizePx / 2).coerceIn(0, maxBallY())
        }

        try {
            windowManager?.addView(ballView, ballParams)
            timerHandler.postDelayed({ snapToEdge() }, 100)
        } catch (_: Exception) {
            ballView = null
            ballParams = null
        }
    }

    private fun hideAll() {
        removePanel()
        removeBall()
        stopAllAnimations()
        stopTimeUpdates()
        cancelCollapse()
    }

    private fun removeBall() {
        ballView?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
        ballView = null
        ballParams = null
        ballBg = null
        ballIconView = null
    }

    // ═══════════════════════════════════════════════════════════
    // Ball View
    // ═══════════════════════════════════════════════════════════

    private fun createBallView(): View {
        val container = FrameLayout(this).apply {
            elevation = 8 * density
        }

        ballBg = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(COLOR_IDLE)
            setStroke((1.5f * density).toInt(), 0x30FFFFFF.toInt())
        }
        container.background = ballBg

        val iconSize = (ballSizePx * 0.55).toInt()
        ballIconView = ImageView(this).apply {
            setImageResource(R.drawable.ic_floating_ball_idle)
            setColorFilter(0xFFFFFFFF.toInt())
            scaleType = ImageView.ScaleType.FIT_CENTER
            // Inner shadow/glow effect via elevation
            elevation = 2 * density
        }
        container.addView(ballIconView, FrameLayout.LayoutParams(iconSize, iconSize).apply {
            gravity = Gravity.CENTER
        })
        container.setOnTouchListener { _, event -> handleBallTouch(event) }
        return container
    }

    // ═══════════════════════════════════════════════════════════
    // Status / Output
    // ═══════════════════════════════════════════════════════════

    private fun updateStatus(status: String) {
        currentStatus = status
        stopAllAnimations()
        ballView?.apply { scaleX = 1f; scaleY = 1f; translationX = 0f; rotation = 0f; alpha = 1f }
        when (status) {
            STATUS_IDLE -> {
                ballBg?.setColor(COLOR_IDLE)
                ballIconView?.setImageResource(R.drawable.ic_floating_ball_idle)
            }
            STATUS_RUNNING -> {
                ballBg?.setColor(COLOR_RUNNING)
                ballIconView?.setImageResource(R.drawable.ic_floating_ball_running)
                startRotateAnimation()
                startTimeUpdates()
            }
            STATUS_ERROR -> {
                ballBg?.setColor(COLOR_ERROR)
                ballIconView?.setImageResource(R.drawable.ic_floating_ball_error)
                startShakeAnimation()
                schedulePanelAutoDismiss(5000)
            }
            STATUS_WAITING_INPUT -> {
                ballBg?.setColor(COLOR_WAITING)
                ballIconView?.setImageResource(R.drawable.ic_floating_ball_waiting)
                startBounceAnimation()
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // Touch Handling
    // ═══════════════════════════════════════════════════════════

    private fun handleBallTouch(event: MotionEvent): Boolean {
        val params = ballParams ?: return false

        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                cancelCollapse()
                initialX = params.x
                initialY = params.y
                initialTouchX = event.rawX
                initialTouchY = event.rawY
                isDragging = false
                isLongPress = false
                isInTrashZone = false

                longPressRunnable = Runnable {
                    if (isCollapsed) {
                        expandFromEdge()
                    }
                    isLongPress = true
                    if (isPanelVisible) removePanel() else showPanel()
                }
                longPressHandler.postDelayed(longPressRunnable!!, 500L)
                return true
            }

            MotionEvent.ACTION_MOVE -> {
                val dx = event.rawX - initialTouchX
                val dy = event.rawY - initialTouchY

                if (!isDragging && (abs(dx) > touchSlop || abs(dy) > touchSlop)) {
                    isDragging = true
                    longPressRunnable?.let { longPressHandler.removeCallbacks(it) }
                    if (isCollapsed) {
                        expandFromEdge()
                    }
                    removePanel()
                }

                if (isDragging) {
                    params.x = (initialX + dx.toInt()).coerceIn(0, maxBallX())
                    params.y = (initialY + dy.toInt()).coerceIn(0, maxBallY())
                    try { windowManager?.updateViewLayout(ballView, params) } catch (_: Exception) {}

                    // Trash zone — only when a script is running
                    if (currentStatus != STATUS_IDLE) {
                        val ballCenterY = params.y + ballSizePx / 2
                        val inTrash = ballCenterY > screenHeight * 0.85

                        if (inTrash != isInTrashZone) {
                            isInTrashZone = inTrash
                            if (inTrash) {
                                ballBg?.setColor(COLOR_TRASH)
                                ballIconView?.setImageResource(R.drawable.ic_floating_ball_error)
                                stopAllAnimations()
                                ballView?.animate()?.scaleX(1.3f)?.scaleY(1.3f)?.setDuration(150)?.start()
                            } else {
                                updateStatus(currentStatus)
                                ballView?.animate()?.scaleX(1.0f)?.scaleY(1.0f)?.setDuration(150)?.start()
                            }
                        }
                    }
                }
                return true
            }

            MotionEvent.ACTION_UP -> {
                longPressRunnable?.let { longPressHandler.removeCallbacks(it) }

                if (isDragging) {
                    ballView?.animate()?.scaleX(1.0f)?.scaleY(1.0f)?.setDuration(100)?.start()

                    if (isInTrashZone && currentStatus != STATUS_IDLE) {
                        stopScript()
                        scriptName = ""
                        startTime = 0
                        updateStatus(STATUS_IDLE)
                        isDragging = false
                        isInTrashZone = false
                        return true
                    }
                    isDragging = false
                    isInTrashZone = false
                    updateStatus(currentStatus)
                    snapToEdge()
                } else if (!isLongPress) {
                    if (isCollapsed) {
                        expandFromEdge()
                    } else if (isPanelVisible) {
                        removePanel()
                    } else {
                        showPanel()
                    }
                }
                return true
            }
        }
        return false
    }

    // ═══════════════════════════════════════════════════════════
    // Snap to Edge
    // ═══════════════════════════════════════════════════════════

    private fun snapToEdge() {
        val params = ballParams ?: return
        val centerX = params.x + ballSizePx / 2
        val targetX = if (centerX < screenWidth / 2) 0 else maxBallX()
        val targetY = params.y.coerceIn(0, maxBallY())
        isOnLeftEdge = targetX == 0

        if (params.x == targetX && params.y == targetY) {
            collapseToEdge()
            return
        }

        ValueAnimator.ofInt(params.x, targetX).apply {
            duration = 200
            addUpdateListener { anim ->
                params.x = anim.animatedValue as Int
                params.y = targetY
                try { windowManager?.updateViewLayout(ballView, params) } catch (_: Exception) {}
            }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: android.animation.Animator) {
                    collapseToEdge()
                }
            })
            start()
        }
    }

    private fun maxBallX(): Int = (screenWidth - ballSizePx).coerceAtLeast(0)

    private fun maxBallY(): Int = (screenHeight - ballSizePx).coerceAtLeast(0)

    private fun scheduleCollapse() {
        scheduleCollapse(1200L)
    }

    private fun scheduleCollapse(delayMs: Long) {
        cancelCollapse()
        collapseRunnable = Runnable {
            if (!isDragging && !isPanelVisible) {
                collapseToEdge()
            }
        }
        timerHandler.postDelayed(collapseRunnable!!, delayMs)
    }

    private fun cancelCollapse() {
        collapseRunnable?.let { timerHandler.removeCallbacks(it) }
        collapseRunnable = null
    }

    private fun collapseToEdge() {
        val params = ballParams ?: return
        if (panelView != null || isDragging) return

        val centerX = params.x + ballSizePx / 2
        val targetX = if (centerX < screenWidth / 2) 0 else maxBallX()
        isOnLeftEdge = targetX == 0
        params.x = targetX
        params.y = params.y.coerceIn(0, maxBallY())
        try { windowManager?.updateViewLayout(ballView, params) } catch (_: Exception) {}

        val hiddenWidth = (ballSizePx - collapsedVisiblePx).coerceAtLeast(0).toFloat()
        val targetTranslation = if (isOnLeftEdge) -hiddenWidth else hiddenWidth
        isCollapsed = true
        ballView?.animate()
            ?.translationX(targetTranslation)
            ?.setDuration(180)
            ?.start()
    }

    private fun expandFromEdge() {
        isCollapsed = false
        ballView?.animate()
            ?.translationX(0f)
            ?.setDuration(160)
            ?.start()
        scheduleCollapse(3000L)
    }

    // ═══════════════════════════════════════════════════════════
    // Panel (Long Press Expand / Auto-show during running)
    // ═══════════════════════════════════════════════════════════

    private fun showPanel() {
        if (panelView != null || ballParams == null) return
        if (isCollapsed) {
            expandFromEdge()
        }
        cancelCollapse()
        if (currentStatus == STATUS_IDLE) showIdlePanel() else showRunningPanel()
    }

    // ── Running panel: script info + stop ──

    private fun showRunningPanel() {
        val dp = density
        val container = createPanelContainer(dp)

        // Header: script name + elapsed time
        val headerRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        headerRow.addView(TextView(this).apply {
            text = scriptName.removeSuffix(".py")
            setTextColor(0xFFFFFFFF.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        })
        panelTimeText = TextView(this).apply {
            text = formatElapsed()
            setTextColor(0xB0FFFFFF.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        }
        headerRow.addView(panelTimeText)
        container.addView(headerRow)

        container.addView(createDivider(dp))

        container.addView(TextView(this).apply {
            text = "脚本正在运行，完整输出请在应用终端查看。"
            setTextColor(0xB0FFFFFF.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                bottomMargin = (8 * dp).toInt()
            }
        })

        // Stop button
        container.addView(createButton("停止脚本", COLOR_ERROR) {
            stopScript()
            removePanel()
            scriptName = ""
            startTime = 0
            updateStatus(STATUS_IDLE)
        })

        addPanelToScreen(container)
    }

    // ── Idle panel: recent scripts quick run ──

    private fun showIdlePanel() {
        val dp = density
        val container = createPanelContainer(dp)

        // Header
        container.addView(TextView(this).apply {
            text = "最近运行"
            setTextColor(0xFFFFFFFF.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
        })
        container.addView(createDivider(dp))

        // List recent scripts
        val scripts = getRecentScripts()
        if (scripts.isEmpty()) {
            container.addView(TextView(this).apply {
                text = "(暂无脚本)"
                setTextColor(0x80FFFFFF.toInt())
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                    bottomMargin = (8 * dp).toInt()
                }
            })
        } else {
            for (name in scripts) {
                container.addView(createScriptRow(name, dp))
            }
        }

        // Open app button
        container.addView(createButton("打开应用", 0xFF5C6BC0.toInt()) {
            removePanel()
            openApp()
        })

        addPanelToScreen(container)
    }

    private fun createScriptRow(name: String, dp: Float): View {
        return TextView(this).apply {
            text = "▶  ${name.removeSuffix(".py")}"
            setTextColor(0xFFFFFFFF.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setPadding(0, (4 * dp).toInt(), 0, (4 * dp).toInt())
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)

            setOnClickListener {
                removePanel()
                runScript(name)
            }
        }
    }

    // ── Recent scripts tracking ──

    private fun addRecentScript(name: String) {
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        val current = prefs.getString(KEY_RECENT_SCRIPTS, "") ?: ""
        val list = current.split(",").filter { it.isNotEmpty() && it != name }.toMutableList()
        list.add(0, name)
        prefs.edit().putString(KEY_RECENT_SCRIPTS, list.take(MAX_RECENT).joinToString(",")).apply()
    }

    private fun getRecentScripts(): List<String> {
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        val stored = prefs.getString(KEY_RECENT_SCRIPTS, "") ?: ""
        if (stored.isEmpty()) {
            // Fallback to file modification time
            val scriptsDir = File(filesDir, "scripts")
            if (!scriptsDir.exists()) return emptyList()
            return scriptsDir.listFiles()
                ?.filter { it.isFile && it.name.endsWith(".py") }
                ?.sortedByDescending { it.lastModified() }
                ?.take(3)
                ?.map { it.name }
                ?: emptyList()
        }
        return stored.split(",").filter { it.isNotEmpty() }
    }

    private fun runScript(name: String) {
        // Open app with script name as extra — Flutter will pick it up and run
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("run_script", name)
        }
        startActivity(intent)
    }

    // ── Panel helpers ──

    private fun createPanelContainer(dp: Float): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply {
                setColor(0xE02D2D2D.toInt())
                cornerRadius = 12 * dp
                setStroke((1 * dp).toInt(), 0x40FFFFFF.toInt())
            }
            elevation = 12 * dp
            setPadding((14 * dp).toInt(), (10 * dp).toInt(), (14 * dp).toInt(), (10 * dp).toInt())
        }
    }

    private fun createDivider(dp: Float): View {
        return View(this).apply {
            setBackgroundColor(0x30FFFFFF.toInt())
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, (1 * dp).toInt()).apply {
                topMargin = (6 * dp).toInt()
                bottomMargin = (6 * dp).toInt()
            }
        }
    }

    private fun createButton(text: String, color: Int, onClick: () -> Unit): TextView {
        val dp = density
        return TextView(this).apply {
            this.text = text
            setTextColor(0xFFFFFFFF.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                setColor(color)
                cornerRadius = 6 * dp
            }
            val padV = (6 * dp).toInt()
            val padH = (16 * dp).toInt()
            setPadding(padH, padV, padH, padV)
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            setOnClickListener { onClick() }
        }
    }

    private fun addPanelToScreen(panel: View) {
        panelView = panel

        val bp = ballParams!!
        val dp = density
        val belowY = bp.y + ballSizePx + (10 * dp).toInt()
        val aboveY = bp.y - panelWidthPx / 2
        val panelY = (if (belowY + panelWidthPx / 2 < screenHeight) belowY else aboveY)
            .coerceIn((8 * dp).toInt(), (screenHeight - panelWidthPx / 2).coerceAtLeast((8 * dp).toInt()))
        val maxPanelX = (screenWidth - panelWidthPx - (8 * dp).toInt()).coerceAtLeast((8 * dp).toInt())
        val panelX = bp.x.coerceIn((8 * dp).toInt(), maxPanelX)

        panelParams = WindowManager.LayoutParams(
            panelWidthPx, WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = panelX
            y = panelY
        }

        try {
            windowManager?.addView(panelView, panelParams)
            isPanelVisible = true
        } catch (_: Exception) {
            panelView = null
            panelParams = null
        }

        // Auto-dismiss: while running, stay open; otherwise dismiss after 8s
        if (currentStatus != STATUS_RUNNING) {
            schedulePanelAutoDismiss(8000)
        }
    }

    private fun schedulePanelAutoDismiss(delayMs: Long) {
        panelAutoDismissRunnable?.let { timerHandler.removeCallbacks(it) }
        panelAutoDismissRunnable = Runnable { removePanel() }
        timerHandler.postDelayed(panelAutoDismissRunnable!!, delayMs)
    }

    private fun removePanel() {
        panelAutoDismissRunnable?.let { timerHandler.removeCallbacks(it) }
        panelAutoDismissRunnable = null
        panelView?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
        panelView = null
        panelParams = null
        panelTimeText = null
        isPanelVisible = false
        if (currentStatus == STATUS_RUNNING) startTimeUpdates()
        scheduleCollapse()
    }

    // ═══════════════════════════════════════════════════════════
    // Animations
    // ═══════════════════════════════════════════════════════════

    private fun startRotateAnimation() {
        ballView?.let { view ->
            currentAnimator = ObjectAnimator.ofFloat(view, "rotation", 0f, 360f).apply {
                duration = 1500
                repeatCount = ObjectAnimator.INFINITE
                interpolator = AccelerateDecelerateInterpolator()
                start()
            }
        }
    }

    private fun startShakeAnimation() {
        ballView?.let { view ->
            val offset = 3 * density
            currentAnimator = ObjectAnimator.ofFloat(
                view, "translationX",
                0f, -offset, offset, -offset * 0.7f, offset * 0.7f, -offset * 0.3f, offset * 0.3f, 0f
            ).apply {
                duration = 800
                interpolator = AccelerateDecelerateInterpolator()
                addListener(object : AnimatorListenerAdapter() {
                    override fun onAnimationEnd(animation: Animator) {
                        view.translationX = 0f
                    }
                })
                start()
            }
        }
    }

    private fun startBounceAnimation() {
        ballView?.let { view ->
            currentAnimator = ObjectAnimator.ofFloat(view, "scaleY", 1f, 0.82f, 1f).apply {
                duration = 600
                repeatCount = ObjectAnimator.INFINITE
                interpolator = OvershootInterpolator(2f)
                start()
            }
        }
    }

    private fun stopAllAnimations() {
        currentAnimator?.cancel()
        currentAnimator = null
        ballView?.apply {
            alpha = 1.0f
            scaleX = 1f
            scaleY = 1f
            translationX = 0f
            rotation = 0f
        }
    }

    // ═══════════════════════════════════════════════════════════
    // Time Updates
    // ═══════════════════════════════════════════════════════════

    private fun startTimeUpdates() {
        stopTimeUpdates()
        timerRunnable = object : Runnable {
            override fun run() {
                panelTimeText?.text = formatElapsed()
                timerHandler.postDelayed(this, 1000)
            }
        }
        timerHandler.postDelayed(timerRunnable!!, 1000)
    }

    private fun stopTimeUpdates() {
        timerRunnable?.let { timerHandler.removeCallbacks(it) }
    }

    private fun formatElapsed(): String {
        if (startTime <= 0) return ""
        val s = (System.currentTimeMillis() - startTime) / 1000
        return when {
            s < 60 -> "${s}s"
            s < 3600 -> "${s / 60}m ${s % 60}s"
            else -> "${s / 3600}h ${(s % 3600) / 60}m"
        }
    }

    // ═══════════════════════════════════════════════════════════
    // Actions
    // ═══════════════════════════════════════════════════════════

    private fun openApp() {
        startActivity(Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
        })
    }

    private fun stopScript() {
        try {
            val runner = com.chaquo.python.Python.getInstance().getModule("script_runner")
            runner.callAttr("stop_running")
        } catch (_: Exception) {}
    }
}
