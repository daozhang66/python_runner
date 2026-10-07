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
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BackupSafInstrumentationTest {
    @Test
    fun deviceCreatesArchiveFromChannelMetadataAndRestoresItsContents() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val root = File(context.filesDir, "backup_create_test_${UUID.randomUUID()}")
        val script = File(root, "scripts/hello.py")
        script.parentFile!!.mkdirs()
        script.writeText("print('你好')")
        try {
            val metadata =
                JSONObject(
                    mapOf(
                        "format" to "python_runner_backup",
                        "version" to 1,
                        "createdAt" to 1710000000123L,
                        "scripts" to
                            listOf(
                                mapOf(
                                    "name" to "hello.py",
                                    "createdAt" to 1700000000000L,
                                    "modifiedAt" to 1700000001000L,
                                    "runCount" to 0,
                                    "isPinned" to false,
                                    "sortOrder" to 0,
                                    "groupId" to null,
                                    "homeSortOrder" to null,
                                )
                            ),
                        "groups" to emptyList<Any>(),
                    )
                )
            val archive = BackupArchive(root)
            val created = archive.create("export", metadata, AtomicBoolean(false))
            val file = archive.knownArchive("export", created.getString("path"))
            val restored =
                archive.stage("restore", file.inputStream(), file.name, AtomicBoolean(false))
            assertFalse(restored.getBoolean("legacy"))
            assertEquals(
                "print('你好')",
                File(archive.payload("restore"), "scripts/hello.py").readText(),
            )
            script.delete()
            try {
                archive.create("missing", metadata, AtomicBoolean(false))
                fail("Stale metadata must not produce a silently incomplete archive")
            } catch (e: BackupException) {
                assertEquals("SOURCE_MISSING", e.code)
            }
        } finally {
            root.deleteRecursively()
        }
    }

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
