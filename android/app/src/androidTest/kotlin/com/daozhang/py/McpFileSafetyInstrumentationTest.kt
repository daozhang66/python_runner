package com.daozhang.py

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class McpFileSafetyInstrumentationTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun boundedReaderRejectsOversizeAndAcceptsExactLimit() {
        val file = File.createTempFile("mcp-read-", ".txt", context.cacheDir)
        val operations = NativeFileOperations(context.filesDir, context.contentResolver, ScriptFileStore(context.filesDir))
        try {
            file.writeBytes(ByteArray(65) { 65 })
            assertThrows(FileReadLimitException::class.java) {
                operations.readFileBounded(file.path, 64)
            }
            assertEquals(65, operations.readFileBounded(file.path, 65).size)
            assertThrows(IllegalArgumentException::class.java) {
                operations.readFileBounded(file.path, 0)
            }
        } finally {
            file.delete()
        }
    }

    @Test
    fun unreadableDirectoryIsNotAnEmptyDirectory() {
        val dir = File(context.cacheDir, "mcp-directory-${System.nanoTime()}")
        assertTrue(dir.mkdir())
        val operations = NativeFileOperations(context.filesDir, context.contentResolver, ScriptFileStore(context.filesDir))
        try {
            assertTrue(operations.listFilePickerDirectory(dir.path).isEmpty())
            android.system.Os.chmod(dir.path, 0)
            assertThrows(SecurityException::class.java) {
                operations.listFilePickerDirectory(dir.path)
            }
        } finally {
            android.system.Os.chmod(dir.path, 448) // 0700
            dir.delete()
        }
    }

    @Test
    fun concurrentProjectSavesAllowOnlyOneWriterPerRevision() {
        val store = ScriptProjectStore(context, context.filesDir)
        val key = "mcp_test_${System.nanoTime()}"
        val executor = Executors.newFixedThreadPool(2)
        try {
            store.createProject(key)
            store.saveProjectFile(key, "main.py", "initial")
            val version = store.safeProjectFile(key, "main.py").lastModified()
            val start = CountDownLatch(1)
            val results = (1..2).map { number ->
                executor.submit<Boolean> {
                    start.await()
                    try {
                        store.saveProjectFile(key, "main.py", "$number", version)
                    } catch (_: ProjectWriteConflictException) {
                        false
                    }
                }
            }
            start.countDown()
            assertEquals(1, results.count { it.get(5, TimeUnit.SECONDS) })
            assertTrue(store.safeProjectFile(key, "main.py").lastModified() > version)
        } finally {
            executor.shutdownNow()
            store.deleteProject(key)
        }
    }
}
