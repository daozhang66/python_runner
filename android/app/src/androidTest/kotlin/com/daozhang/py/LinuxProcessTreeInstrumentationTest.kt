package com.daozhang.py

import android.os.Handler
import android.os.Looper
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.LargeTest
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
@LargeTest
class LinuxProcessTreeInstrumentationTest {
    @Test
    fun stopTerminatesRootAndReparentableChild() {
        val process = ProcessBuilder(
            "/system/bin/sh",
            "-c",
            "sleep 30 & child=\$!; echo \$child; wait \$child"
        ).start()
        val childPid = BufferedReader(InputStreamReader(process.inputStream))
            .readLine()
            .trim()
            .toInt()

        LinuxProcessTree.stop(process)

        assertTrue("root process did not exit", process.waitFor(5, TimeUnit.SECONDS))
        assertTrue("child process $childPid remained after root termination", waitUntilGone(childPid))
    }

    @Test
    fun forceOnlyTerminatesRootAndChildWithoutGracefulWait() {
        val process = ProcessBuilder(
            "/system/bin/sh",
            "-c",
            "sleep 30 & child=\$!; echo \$child; wait \$child"
        ).start()
        val childPid = BufferedReader(InputStreamReader(process.inputStream))
            .readLine()
            .trim()
            .toInt()

        LinuxProcessTree.stop(process, forceOnly = true)

        assertTrue("root process did not exit", process.waitFor(5, TimeUnit.SECONDS))
        assertTrue("child process $childPid remained after force stop", waitUntilGone(childPid))
    }

    @Test
    fun linuxLikeStdinTimeoutOutputCapAndShutdownReachTerminalStates() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val runtime = LinuxLikeRuntimeManager(context)
        assumeTrue("Linux-like runtime must be installed on the target device", runtime.getInfo()["available"] == "true")

        val store = ScriptFileStore(context.filesDir)
        val inputScript = "instrumentation_input_${System.nanoTime()}.py"
        val timeoutScript = "instrumentation_timeout_${System.nanoTime()}.py"
        val outputScript = "instrumentation_output_${System.nanoTime()}.py"
        val shutdownScript = "instrumentation_shutdown_${System.nanoTime()}.py"
        val files = listOf(inputScript, timeoutScript, outputScript, shutdownScript)
            .map { store.safeScriptFile(it) }
        try {
            store.safeScriptFile(inputScript).writeText("value = input('device prompt: '); print('received:' + value)")
            store.safeScriptFile(timeoutScript).writeText("import time; time.sleep(30)")
            store.safeScriptFile(outputScript).writeText(
                "for _ in range(320): print('x' * 1024)\nraise RuntimeError('expected instrumentation failure')"
            )
            store.safeScriptFile(shutdownScript).writeText("import time; time.sleep(30)")

            val inputProbe = ExecutionProbe()
            val inputController = controller(context, runtime, inputProbe)
            inputController.executeLinuxLikeScript(
                inputScript, "stdin-${System.nanoTime()}", null, null, 10, null, null, ResultProbe()
            )
            assertTrue("stdin request was not emitted", inputProbe.stdin.await(15, TimeUnit.SECONDS))
            inputController.sendLinuxLikeStdin("answer", ResultProbe())
            assertEquals("completed", inputProbe.awaitTerminal())
            assertTrue("stdin value was not written to stdout", inputProbe.logs.any { it.contains("received:answer") })

            val timeoutProbe = ExecutionProbe()
            controller(context, runtime, timeoutProbe).executeLinuxLikeScript(
                timeoutScript, "timeout-${System.nanoTime()}", null, null, 1, null, null, ResultProbe()
            )
            assertEquals("timeout", timeoutProbe.awaitTerminal())

            val outputProbe = ExecutionProbe()
            controller(context, runtime, outputProbe).executeLinuxLikeScript(
                outputScript, "output-${System.nanoTime()}", null, null, 15, null, null, ResultProbe()
            )
            assertEquals("error", outputProbe.awaitTerminal())
            assertTrue("bounded output marker was not persisted", outputProbe.errors.any { it.contains("[输出已截断]") })

            val shutdownProbe = ExecutionProbe()
            val shutdownController = controller(context, runtime, shutdownProbe)
            shutdownController.executeLinuxLikeScript(
                shutdownScript, "shutdown-${System.nanoTime()}", null, null, 15, null, null, ResultProbe()
            )
            Thread.sleep(500)
            shutdownController.shutdown()
            assertEquals("stopped", shutdownProbe.awaitTerminal())
        } finally {
            files.forEach { it.delete() }
        }
    }

    @Test
    fun chaquopyTimeoutThenRestartEmitsExactlyOneTerminalStatePerExecution() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        if (!Python.isStarted()) Python.start(AndroidPlatform(context))
        val store = ScriptFileStore(context.filesDir)
        val timeoutScript = "instrumentation_chaquopy_timeout_${System.nanoTime()}.py"
        val completedScript = "instrumentation_chaquopy_completed_${System.nanoTime()}.py"
        try {
            store.safeScriptFile(timeoutScript).writeText("import time\nwhile True: time.sleep(0.05)")
            store.safeScriptFile(completedScript).writeText("print('chaquopy restarted')")

            val timeoutProbe = ExecutionProbe()
            controller(context, LinuxLikeRuntimeManager(context), timeoutProbe).executeScript(
                timeoutScript, "chaquopy-timeout-${System.nanoTime()}", null, null, 1, ResultProbe()
            )
            assertEquals("timeout", timeoutProbe.awaitTerminal())
            assertEquals("a Chaquopy timeout must emit one terminal status", 1, timeoutProbe.terminalStatuses.size)

            val restartProbe = ExecutionProbe()
            controller(context, LinuxLikeRuntimeManager(context), restartProbe).executeScript(
                completedScript, "chaquopy-restart-${System.nanoTime()}", null, null, 10, ResultProbe()
            )
            assertEquals("completed", restartProbe.awaitTerminal())
            assertEquals("a restarted Chaquopy run must emit one terminal status", 1, restartProbe.terminalStatuses.size)
        } finally {
            store.safeScriptFile(timeoutScript).delete()
            store.safeScriptFile(completedScript).delete()
        }
    }

    private fun controller(
        context: android.content.Context,
        runtime: LinuxLikeRuntimeManager,
        probe: ExecutionProbe
    ): ScriptExecutionController = ScriptExecutionController(
        Handler(Looper.getMainLooper()),
        ScriptFileStore(context.filesDir),
        ScriptProjectStore(context, context.filesDir),
        runtime,
        { _, content, _ -> probe.logs.add(content) },
        { _, status, _ -> probe.recordStatus(status) },
        { _, _ -> probe.stdin.countDown() },
        {},
        {},
        { _, _, detail -> probe.errors.add(detail.orEmpty()) },
        {}
    )

    private fun waitUntilGone(pid: Int): Boolean {
        repeat(100) {
            if (!File("/proc/$pid").exists()) return true
            Thread.sleep(50)
        }
        return !File("/proc/$pid").exists()
    }

    private class ExecutionProbe {
        val stdin = CountDownLatch(1)
        private val terminal = CountDownLatch(1)
        val terminalStatuses = Collections.synchronizedList(mutableListOf<String>())
        val logs = Collections.synchronizedList(mutableListOf<String>())
        val errors = Collections.synchronizedList(mutableListOf<String>())

        fun recordStatus(status: String) {
            if (status in setOf("completed", "error", "stopped", "timeout")) {
                terminalStatuses.add(status)
                terminal.countDown()
            }
        }

        fun awaitTerminal(): String {
            assertTrue("execution did not reach a terminal state", terminal.await(20, TimeUnit.SECONDS))
            return terminalStatuses.singleOrNull().also { assertNotNull("multiple or missing terminal states", it) }!!
        }
    }

    private class ResultProbe : MethodChannel.Result {
        override fun success(result: Any?) = Unit
        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            throw AssertionError("native call failed: $errorCode $errorMessage")
        }
        override fun notImplemented() {
            throw AssertionError("native call was not implemented")
        }
    }
}
