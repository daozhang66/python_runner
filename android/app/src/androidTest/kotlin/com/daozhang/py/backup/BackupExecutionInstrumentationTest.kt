package com.daozhang.py.backup

import android.os.Handler
import android.os.Looper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import com.daozhang.py.LinuxLikeRuntimeManager
import com.daozhang.py.ScriptExecutionController
import com.daozhang.py.ScriptFileStore
import com.daozhang.py.ScriptProjectStore
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BackupExecutionInstrumentationTest {
    @Test
    fun timedOutPythonWorkerStillBlocksWorkspaceUntilItsLateWriteCompletes() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        if (!Python.isStarted()) Python.start(AndroidPlatform(context))
        val root =
            File(context.filesDir, "backup_execution_test_${UUID.randomUUID()}").apply { mkdirs() }
        val marker = File(root, "scripts/late.txt")
        val timedOut = CountDownLatch(1)
        val events = java.util.concurrent.ConcurrentLinkedQueue<String>()
        val controller =
            ScriptExecutionController(
                Handler(Looper.getMainLooper()),
                ScriptFileStore(root),
                ScriptProjectStore(context, root),
                LinuxLikeRuntimeManager(context),
                { _, text, _ -> events.add(text) },
                { _, status, _ ->
                    events.add(status)
                    if (status == "timeout") timedOut.countDown()
                },
                { _, _ -> },
                {},
                {},
                { _, _, _ -> },
                {},
            )
        val script =
            """
            import time
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline:
                pass
            with open(r'${marker.absolutePath}', 'w') as output:
                output.write('late write')
        """
                .trimIndent()
        ScriptFileStore(root).createScript("timeout.py", script)
        try {
            instrumentation.runOnMainSync {
                controller.executeScript(
                    "timeout.py",
                    "timeout_guard",
                    root.absolutePath,
                    null,
                    1,
                    object : MethodChannel.Result {
                        override fun success(result: Any?) {}

                        override fun error(code: String, message: String?, details: Any?) {
                            throw AssertionError(code)
                        }

                        override fun notImplemented() {
                            throw AssertionError("execution missing")
                        }
                    },
                )
            }
            assertTrue("watchdog must report timeout: $events", timedOut.await(7, TimeUnit.SECONDS))
            assertFalse("worker has not performed late write yet", marker.exists())
            assertTrue(
                "timeout status must retain the live-worker lease",
                controller.hasActiveExecution(),
            )
            val gate = BackupWorkspaceGate(controller::hasActiveExecution, { false })
            try {
                gate.acquire("restore")
                fail("Live timed-out worker must block restore")
            } catch (e: BackupException) {
                assertEquals("WORKSPACE_BUSY", e.code)
            }
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10)
            while (controller.hasActiveExecution() && System.nanoTime() < deadline) Thread.sleep(20)
            assertEquals("late write", marker.readText())
            gate.acquire("restore")
            gate.release("restore")
        } finally {
            // The red regression clears current state early: wait for its actual
            // file write as well before deleting this test-owned directory.
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(12)
            while (
                (!marker.exists() || controller.hasActiveExecution()) &&
                    System.nanoTime() < deadline
            ) Thread.sleep(20)
            controller.shutdown()
            root.deleteRecursively()
        }
    }
}
