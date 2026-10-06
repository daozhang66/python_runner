package com.daozhang.py

import java.io.File
import java.io.IOException
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class ScriptFileStoreTest {
    @get:Rule val temp = TemporaryFolder()

    @Test
    fun failedDeletionMustNotReportSuccessToMetadataOwner() {
        val target = File(temp.root, "scripts/blocked.py").apply { mkdirs() }
        val child = File(target, "keep.txt").apply { writeText("keep") }
        try {
            ScriptFileStore(temp.root).deleteScript("blocked.py")
            fail("A failed filesystem deletion must not allow metadata removal")
        } catch (_: IllegalStateException) {}
        assertEquals("keep", child.readText())
    }

    @Test
    fun invalidScriptsDirectoryMustNotLookLikeAnEmptyInventory() {
        File(temp.root, "scripts").writeText("not a directory")
        try {
            ScriptFileStore(temp.root).listScripts()
            fail("An unreadable inventory must abort backup instead of omitting scripts")
        } catch (_: IOException) {}
    }

    @Test
    fun newLibraryIsEmptyAndLiveInventoryReflectsFileManagerRenames() {
        val store = ScriptFileStore(temp.root)
        assertTrue(store.listScripts().isEmpty())
        store.createScript("old.py", "print(1)")
        assertTrue(File(temp.root, "scripts/old.py").renameTo(File(temp.root, "scripts/new.py")))
        File(temp.root, "scripts/notes.txt").writeText("notes")
        File(temp.root, "scripts/directory.py").mkdir()
        assertEquals(listOf("new.py"), store.listScripts().map { it["name"] })
    }
}
