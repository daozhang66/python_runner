package com.daozhang.py.backup

import org.junit.Assert.*
import org.junit.Test

class BackupWorkspaceGateTest {
    @Test
    fun activeExecutionAndLegacyLeasePreventSnapshotAndStaleUnlockFails() {
        var active = true
        val gate = BackupWorkspaceGate({ active }, { false })
        fails { gate.acquire("op") }
        active = false
        val lease = gate.enterLegacy("transferFileManagerEntry")
        fails { gate.acquire("op") }
        lease.close()
        gate.acquire("op")
        fails { gate.release("stale") }
        fails { gate.requireIdle() }
        fails { gate.enterLegacy("executeScript") }
        gate.release("op")
        gate.enterLegacy("saveScript").close()
        gate.requireIdle()
    }

    @Test
    fun pendingJournalBlocksWritesAndReadsUntilRecovered() {
        var pending = true
        val gate = BackupWorkspaceGate({ false }, { pending })
        fails { gate.enterLegacy("readScript") }
        fails { gate.enterLegacy("saveScript") }
        pending = false
        gate.acquire("op")
        gate.enterLegacy("readScript").close()
        gate.beginCommit("op")
        fails { gate.enterLegacy("readScript") }
        gate.endCommit()
        gate.release("op")
    }

    private fun fails(action: () -> Unit) {
        try {
            action()
            fail("Must be blocked")
        } catch (_: BackupException) {}
    }
}
