package com.daozhang.py

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.nio.file.Files

@RunWith(AndroidJUnit4::class)
class FileTransferTest {
    @Test
    fun copiesAndMovesWithoutOverwritingOrFollowingLinks() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val temp = Files.createTempDirectory(context.cacheDir.toPath(), "transfer-test-").toFile()
        try {
            val source = temp.resolve("source").apply { mkdir() }
            source.resolve("nested").mkdir()
            source.resolve("nested/data.txt").writeText("hello")
            val target = temp.resolve("target").apply { mkdir() }
            FileTransfer.transfer(source, target, false)
            assertEquals("hello", target.resolve("source/nested/data.txt").readText())
            assertTrue(source.exists())
            assertThrows(IllegalArgumentException::class.java) { FileTransfer.transfer(source, target, false) }
            assertThrows(IllegalArgumentException::class.java) { FileTransfer.transfer(source, source.resolve("nested"), false) }
            val moveTarget = temp.resolve("moved").apply { mkdir() }
            FileTransfer.transfer(source, moveTarget, true)
            assertFalse(source.exists())
            assertEquals("hello", moveTarget.resolve("source/nested/data.txt").readText())
            val links = temp.resolve("links").apply { mkdir() }
            Files.createSymbolicLink(links.resolve("link").toPath(), moveTarget.toPath())
            assertThrows(java.io.IOException::class.java) { FileTransfer.transfer(links, target, false) }
            assertFalse(target.resolve("links").exists())
            assertTrue(target.listFiles()!!.none { it.name.startsWith(".pyrunner-copy-") })
            Files.delete(links.resolve("link").toPath())
        } finally {
            // This test owns the entire randomly created fixture directory.
            temp.deleteRecursively()
        }
    }

}
