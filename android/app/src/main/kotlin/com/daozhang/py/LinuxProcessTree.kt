package com.daozhang.py

import android.os.Process
import android.util.Log
import java.io.File

/** Process-tree cleanup shared by Linux-like execution and device tests. */
internal object LinuxProcessTree {
    private const val TAG = "LinuxProcessTree"
    private const val GRACEFUL_STOP_MS = 300L

    internal data class ChildPidLookup(
        val pids: List<Int>,
        val failed: Boolean
    )

    fun stop(
        process: java.lang.Process,
        forceOnly: Boolean = false,
        onFailure: (String, Throwable) -> Unit = { operation, error ->
            Log.w(TAG, "$operation failed: ${error.message}", error)
        }
    ) {
        val pid = processPid(process, onFailure)
        // Descendants must be discovered before proot exits and re-parents them.
        val lookup = pid?.let { collectDescendantPids(it, onFailure) }
        val descendants = lookup?.pids?.asReversed() ?: emptyList()
        if (lookup?.failed == true) {
            Log.w(TAG, "Child process enumeration was incomplete; terminating known PIDs")
        }
        if (!forceOnly) {
            signalPids(descendants, force = false, onFailure)
            try {
                process.destroy()
            } catch (error: Exception) {
                onFailure("Terminate Linux-like root process", error)
            }
            Thread.sleep(GRACEFUL_STOP_MS)
        }
        signalPids(descendants, force = true, onFailure)
        pid?.let { signalPids(listOf(it), force = true, onFailure) }
        if (process.isAlive) {
            try {
                process.destroyForcibly()
            } catch (error: Exception) {
                onFailure("Force terminate Linux-like root process", error)
            }
        }
    }

    private fun processPid(
        process: java.lang.Process,
        onFailure: (String, Throwable) -> Unit
    ): Int? = try {
        (process.javaClass.getMethod("pid").invoke(process) as Number).toInt()
    } catch (_: Throwable) {
        try {
            val field = process.javaClass.getDeclaredField("pid")
            field.isAccessible = true
            field.getInt(process)
        } catch (error: Throwable) {
            onFailure("Read Linux-like process PID", error)
            null
        }
    }

    private fun signalPids(
        pids: List<Int>,
        force: Boolean,
        onFailure: (String, Throwable) -> Unit
    ) {
        pids.forEach { pid ->
            try {
                Process.sendSignal(pid, if (force) 9 else 15)
            } catch (error: Throwable) {
                onFailure("Send ${if (force) "SIGKILL" else "SIGTERM"} to process $pid", error)
                if (force) {
                    try {
                        Process.killProcess(pid)
                    } catch (fallbackError: Throwable) {
                        onFailure("Force terminate process $pid", fallbackError)
                    }
                }
            }
        }
    }

    private fun collectDescendantPids(
        rootPid: Int,
        onFailure: (String, Throwable) -> Unit
    ): ChildPidLookup {
        val result = linkedSetOf<Int>()
        val queue = ArrayDeque<Int>()
        var failed = false
        queue.add(rootPid)
        while (queue.isNotEmpty()) {
            val pid = queue.removeFirst()
            val lookup = readDirectChildPids(pid, onFailure)
            failed = failed || lookup.failed
            lookup.pids.forEach { child -> if (result.add(child)) queue.add(child) }
        }
        return ChildPidLookup(result.toList(), failed)
    }

    private fun readDirectChildPids(
        pid: Int,
        onFailure: (String, Throwable) -> Unit
    ): ChildPidLookup {
        var failed = false
        val fromTaskChildren = try {
            File("/proc/$pid/task").listFiles()
                ?.flatMap { task ->
                    File(task, "children").takeIf { it.isFile }
                        ?.readText()
                        ?.split(Regex("\\s+"))
                        ?.mapNotNull { it.toIntOrNull() }
                        ?: emptyList()
                }
                ?.distinct()
                ?: emptyList()
        } catch (error: Exception) {
            failed = true
            onFailure("Read /proc/$pid/task/children", error)
            emptyList()
        }
        if (fromTaskChildren.isNotEmpty()) return ChildPidLookup(fromTaskChildren, failed)

        val fromProcScan = try {
            File("/proc").listFiles()
                ?.mapNotNull { entry ->
                    val childPid = entry.name.toIntOrNull() ?: return@mapNotNull null
                    val status = File(entry, "status")
                    if (!status.isFile) return@mapNotNull null
                    val parentPid = status.useLines { lines ->
                        lines.firstOrNull { it.startsWith("PPid:") }
                            ?.substringAfter(':')
                            ?.trim()
                            ?.toIntOrNull()
                    }
                    if (parentPid == pid) childPid else null
                }
                ?: emptyList()
        } catch (error: Exception) {
            failed = true
            onFailure("Scan /proc for children of $pid", error)
            emptyList()
        }
        return ChildPidLookup(fromProcScan, failed)
    }
}
