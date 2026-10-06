package com.daozhang.py.backup

import java.io.File
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class BackupJournalTest {
    @get:Rule val temp = TemporaryFolder()

    private fun prepare() {
        File(temp.root, "scripts").mkdirs()
        File(temp.root, "scripts/a.py").writeText("old")
        File(temp.root, "backup_operations/op/payload/scripts").mkdirs()
        File(temp.root, "backup_operations/op/payload/scripts/a.py").writeText("new")
    }

    private fun moves(overwrite: Boolean = true) =
        JSONArray(
            """[{"sourceRoot":"scripts/a.py","targetRoot":"scripts/a.py","overwrite":$overwrite}]"""
        )

    @Test
    fun everyDurableBoundaryCanRecoverOriginalWithoutDeletingUntouchedTarget() {
        for (crash in 1..7) {
            temp.root.listFiles()!!.forEach { it.deleteRecursively() }
            prepare()
            var step = 0
            val journal =
                BackupJournal(
                    temp.root,
                    checkpoint = { if (++step == crash) throw SimulatedDeath() },
                )
            try {
                journal.commit("op", moves())
            } catch (_: SimulatedDeath) {}
            val recovery = BackupJournal(temp.root)
            recovery.rollback("op")
            recovery.rollback("op")
            assertEquals("crash $crash", "old", File(temp.root, "scripts/a.py").readText())
            assertTrue(recovery.pending().isEmpty())
        }
    }

    @Test
    fun finalizeKeepsNewFilesAndIsIdempotent() {
        prepare()
        val journal = BackupJournal(temp.root)
        journal.commit("op", moves())
        assertEquals(listOf("op"), journal.pending())
        assertEquals("new", File(temp.root, "scripts/a.py").readText())
        journal.finalize("op")
        journal.finalize("op")
        assertEquals("new", File(temp.root, "scripts/a.py").readText())
    }

    @Test
    fun noOverwriteOrArbitraryDestinationCannotTouchOriginal() {
        prepare()
        val j = BackupJournal(temp.root)
        try {
            j.commit("op", moves(false))
            fail("must reject")
        } catch (_: BackupException) {}
        assertEquals("old", File(temp.root, "scripts/a.py").readText())
        try {
            j.commit(
                "op",
                JSONArray(
                    """[{"sourceRoot":"scripts/a.py","targetRoot":"scripts/../a","overwrite":true}]"""
                ),
            )
            fail("must reject")
        } catch (_: BackupException) {}
    }

    @Test
    fun repeatedCrashesDuringRollbackAndCleanupKeepOriginal() {
        for (crash in 1..10) {
            temp.root.listFiles()!!.forEach { it.deleteRecursively() }
            prepare()
            BackupJournal(temp.root).commit("op", moves())
            var count = 0
            try {
                BackupJournal(
                        temp.root,
                        checkpoint = { if (++count == crash) throw SimulatedDeath() },
                    )
                    .rollback("op")
            } catch (_: SimulatedDeath) {}
            BackupJournal(temp.root).rollback("op")
            assertEquals("rollback crash $crash", "old", File(temp.root, "scripts/a.py").readText())
        }
    }

    @Test
    fun repeatedCrashesDuringFinalizeKeepReplacement() {
        for (crash in 1..8) {
            temp.root.listFiles()!!.forEach { it.deleteRecursively() }
            prepare()
            BackupJournal(temp.root).commit("op", moves())
            var count = 0
            try {
                BackupJournal(
                        temp.root,
                        checkpoint = { if (++count == crash) throw SimulatedDeath() },
                    )
                    .finalize("op")
            } catch (_: SimulatedDeath) {}
            BackupJournal(temp.root).finalize("op")
            assertEquals("finalize crash $crash", "new", File(temp.root, "scripts/a.py").readText())
        }
    }

    @Test
    fun projectOverwriteFailureRestoresWholeOriginalDirectory() {
        File(temp.root, "script_projects/key/sub").mkdirs()
        File(temp.root, "script_projects/key/sub/original.bin").writeBytes(byteArrayOf(0, -1))
        File(temp.root, "backup_operations/op/payload/projects/source").mkdirs()
        File(temp.root, "backup_operations/op/payload/projects/source/new.py").writeText("new")
        val roots =
            JSONArray(
                """[{"sourceRoot":"projects/source","targetRoot":"projects/key","overwrite":true}]"""
            )
        var failed = false
        val j =
            BackupJournal(
                temp.root,
                checkpoint = {
                    if (it == "stagedMoved" && !failed) {
                        failed = true
                        throw java.io.IOException("fault")
                    }
                },
            )
        try {
            j.commit("op", roots)
            fail("Fault must propagate")
        } catch (_: BackupException) {}
        assertArrayEquals(
            byteArrayOf(0, -1),
            File(temp.root, "script_projects/key/sub/original.bin").readBytes(),
        )
        assertFalse(File(temp.root, "script_projects/key/new.py").exists())
    }

    @Test
    fun stageParentsAreDurableBeforeJournalPublication() {
        prepare()
        val synced = mutableSetOf<String>()
        var first = true
        BackupJournal(
                temp.root,
                syncDirectory = { synced.add(it.relativeTo(temp.root).invariantSeparatorsPath) },
                checkpoint = {
                    if (first) {
                        first = false
                        assertTrue(
                            "payload parent must be durable",
                            "backup_operations/op/payload" in synced,
                        )
                        assertTrue(
                            "script parent must be durable",
                            "backup_operations/op/payload/scripts" in synced,
                        )
                        assertTrue(
                            "operation ancestry must be durable",
                            "backup_operations" in synced,
                        )
                        assertTrue("filesDir must be durable", "" in synced)
                    }
                },
            )
            .commit("op", moves())
    }

    private class SimulatedDeath : Error()
}
