package com.daozhang.py

import com.daozhang.py.backup.BackupException
import com.daozhang.py.backup.BackupWorkspaceGate
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class LiveExecutionWorkersTest {
    @Test
    fun supersededWorkerRetainsLeaseAfterNewCurrentWorkerExits() {
        val releaseOld = CountDownLatch(1)
        val entered = CountDownLatch(1)
        val old = Thread {
            entered.countDown()
            releaseOld.await()
        }
        val current = Thread {}
        try {
            LiveExecutionWorkers.start(old)
            assertTrue(entered.await(2, TimeUnit.SECONDS))
            LiveExecutionWorkers.start(current)
            current.join()
            val gate = BackupWorkspaceGate(LiveExecutionWorkers::hasActive, { false })
            try {
                gate.acquire("snapshot")
                fail("Old worker still owns execution lease")
            } catch (e: BackupException) {
                assertEquals("WORKSPACE_BUSY", e.code)
            }
            releaseOld.countDown()
            old.join()
            gate.acquire("snapshot")
            gate.release("snapshot")
        } finally {
            releaseOld.countDown()
            old.join()
        }
    }
}
