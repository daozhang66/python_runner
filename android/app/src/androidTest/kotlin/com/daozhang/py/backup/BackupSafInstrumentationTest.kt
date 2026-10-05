package com.daozhang.py.backup

import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BackupSafInstrumentationTest {
    @Test
    fun missingPersistedGrantReturnsSpecificError() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        try {
            BackupPlugin.requireWritableTree(
                context,
                Uri.parse("content://missing.documents/tree/backup"),
            )
            fail("Missing persisted grant must reject")
        } catch (e: BackupException) {
            assertEquals("PERMISSION_LOST", e.code)
        }
    }

    @Test
    fun deviceStreamingStageAtomicRenameDirectoryFsyncAndRecovery() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val root =
            File(context.filesDir, "backup_native_test_${UUID.randomUUID()}").apply { mkdirs() }
        try {
            val archive = BackupArchive(root)
            val transfer = archive.transferFile("device")
            ZipOutputStream(transfer.outputStream()).use { zip ->
                zip.putNextEntry(ZipEntry("nested/.binary"))
                zip.write(byteArrayOf(0, -1, 42))
                zip.closeEntry()
                zip.putNextEntry(ZipEntry("empty/"))
                zip.closeEntry()
            }
            val staged =
                archive.stage("device", transfer.inputStream(), "device.zip", AtomicBoolean(false))
            assertTrue(staged.getBoolean("legacy"))
            val old =
                File(root, "script_projects/local/old.txt").apply {
                    parentFile!!.mkdirs()
                    writeText("old")
                }
            val moves =
                JSONArray(
                    """[{"sourceRoot":"projects/legacy_device","targetRoot":"projects/local","overwrite":true}]"""
                )
            val journal = BackupJournal(root, { BackupPlugin.syncDirectory(it) })
            journal.commit("device", moves)
            assertArrayEquals(
                byteArrayOf(0, -1, 42),
                File(root, "script_projects/local/nested/.binary").readBytes(),
            )
            assertFalse(old.exists())
            journal.rollback("device")
            journal.rollback("device")
            assertEquals("old", old.readText())
            assertTrue(journal.pending().isEmpty())
        } finally {
            root.deleteRecursively()
        }
    }
}
