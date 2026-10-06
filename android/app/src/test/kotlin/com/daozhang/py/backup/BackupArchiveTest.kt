package com.daozhang.py.backup

import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import org.apache.commons.compress.archivers.zip.ZipArchiveEntry
import org.apache.commons.compress.archivers.zip.ZipArchiveOutputStream
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class BackupArchiveTest {
    @Test
    fun realFutureVersionBackupHasDistinctErrorAndCurrentVersionStillStages() {
        val fixture =
            javaClass.getResourceAsStream("/backup/future-version.zip")!!.use { it.readBytes() }
        try {
            core()
                .stage("future", fixture.inputStream(), "future-version.zip", AtomicBoolean(false))
            fail("A future version must not stage or fall back to legacy")
        } catch (e: BackupException) {
            assertEquals("UNSUPPORTED_VERSION", e.code)
        }
        val entries = fixtureEntries(fixture)
        val current =
            entries
                .map { (name, bytes) ->
                    name to
                        if (name == BackupArchive.MARKER) {
                            JSONObject(String(bytes, Charsets.UTF_8))
                                .put("version", 1)
                                .toString()
                                .toByteArray()
                        } else bytes
                }
                .toTypedArray()
        val staged =
            core()
                .stage("current", zip(*current).inputStream(), "current.zip", AtomicBoolean(false))
        assertFalse(staged.getBoolean("legacy"))
        assertEquals(1, staged.getJSONObject("manifest").getInt("version"))
        assertEquals(
            "print(\"future fixture\")\n",
            File(core().payload("current"), "scripts/hello.py").readText(),
        )
    }

    @Test
    fun wrongFormatAndMalformedVersionsRemainInvalidArchives() {
        val fixture =
            javaClass.getResourceAsStream("/backup/future-version.zip")!!.use { it.readBytes() }
        val entries = fixtureEntries(fixture)
        val original =
            String(entries.first { it.first == BackupArchive.MARKER }.second, Charsets.UTF_8)
        val invalid =
            listOf("null", "\"2\"", "2.0", "2.5", "-1", "9007199254740992").map {
                original.replace("\"version\":2", "\"version\":$it")
            } + original.replace("\"python_runner_backup\"", "\"other\"")
        invalid.forEachIndexed { index, marker ->
            val malformed =
                entries
                    .map { (name, bytes) ->
                        name to if (name == BackupArchive.MARKER) marker.toByteArray() else bytes
                    }
                    .toTypedArray()
            try {
                core()
                    .stage(
                        "invalidVersion$index",
                        zip(*malformed).inputStream(),
                        "invalid.zip",
                        AtomicBoolean(false),
                    )
                fail("Must reject malformed version or wrong format")
            } catch (e: BackupException) {
                assertTrue(e.code == "INVALID_ARCHIVE" || e.code == "INVALID_MANIFEST")
            }
        }
    }

    private fun fixtureEntries(bytes: ByteArray): List<Pair<String, ByteArray>> {
        val entries = mutableListOf<Pair<String, ByteArray>>()
        java.util.zip.ZipInputStream(bytes.inputStream()).use { input ->
            while (true) {
                val entry = input.nextEntry ?: break
                entries.add(entry.name to input.readBytes())
            }
        }
        return entries
    }

    @Test
    fun exportedZipIncludingMetadataMustFitInputByteLimit() {
        source()
        val limited = BackupArchive(temp.root, maxBytes = 128)
        expectFailure { limited.create("inputLimit", metadata(), AtomicBoolean(false)) }
        assertFalse(limited.operationDir("inputLimit").walkTopDown().any { it.extension == "zip" })
    }

    @Test
    fun exportAndRestoreEnforceSameStructuralBudget() {
        source()
        val limited = BackupArchive(temp.root, maxStructuralBytes = 100)
        expectFailure { limited.create("exportLimit", metadata(), AtomicBoolean(false)) }
        assertFalse(limited.operationDir("exportLimit").walkTopDown().any { it.extension == "zip" })
        expectFailure {
            limited.stage(
                "restoreLimit",
                zip("main.py" to byteArrayOf(1)).inputStream(),
                "a.zip",
                AtomicBoolean(false),
            )
        }
    }

    @Test
    fun abandonedCleanupPreservesEveryJournalAndRemovesStaleTransfers() {
        val backend = core()
        backend.transferFile("stale").writeBytes(byteArrayOf(1, 2, 3))
        val pending = backend.operationDir("pending").apply { mkdirs() }
        File(pending, "journal.json").writeText("broken journals must also survive")
        File(pending, "rollback").mkdirs()
        File(pending, "rollback/original").writeText("old")
        backend.cleanupAbandoned()
        assertFalse(backend.operationDir("stale").exists())
        assertTrue(File(pending, "journal.json").exists())
        assertEquals("old", File(pending, "rollback/original").readText())
        backend.cleanupAbandoned()
        assertTrue(File(pending, "journal.json").exists())
    }

    @get:Rule val temp = TemporaryFolder()

    private fun core() = BackupArchive(temp.root)

    private fun metadata() =
        JSONObject(
            """{"format":"python_runner_backup","version":1,"createdAt":1,"scripts":[{"name":"hello.py","createdAt":1,"modifiedAt":1,"runCount":3,"isPinned":true,"sortOrder":0,"groupId":null,"homeSortOrder":0}],"groups":[{"id":1,"name":"项目","createdAt":1,"modifiedAt":1,"sortOrder":0,"isProject":true,"projectKey":"key","mainFilePath":"main.py","homeSortOrder":1}]}"""
        )

    private fun source() {
        File(temp.root, "scripts").mkdirs()
        File(temp.root, "scripts/hello.py").writeText("print('你好')")
        File(temp.root, "script_projects/key/empty").mkdirs()
        File(temp.root, "script_projects/key/main.py").writeText("print(1)")
        File(temp.root, "script_projects/key/.hidden").writeBytes(byteArrayOf(0, -1, 42))
        File(temp.root, "script_projects/key/__pycache__").mkdirs()
        File(temp.root, "script_projects/key/__pycache__/cache").writeText("excluded")
        File(temp.root, "script_projects/key/.git").mkdirs()
        File(temp.root, "script_projects/key/.git/keep").writeText("included")
    }

    private fun zip(vararg entries: Pair<String, ByteArray>, symlink: Boolean = false): File {
        val f = File(temp.root, "input.zip")
        ZipArchiveOutputStream(f).use { out ->
            entries.forEach { (name, bytes) ->
                val e = ZipArchiveEntry(name)
                if (symlink) e.unixMode = 40960 + 511
                out.putArchiveEntry(e)
                out.write(bytes)
                out.closeArchiveEntry()
            }
        }
        return f
    }

    private fun rawZip(path: String): File {
        val f = File(temp.root, "raw.zip")
        java.util.zip.ZipOutputStream(f.outputStream()).use { out ->
            out.putNextEntry(java.util.zip.ZipEntry(path))
            out.write(1)
            out.closeEntry()
        }
        return f
    }

    @Test
    fun binaryUnicodeHiddenEmptyRoundTripAndExactExclusions() {
        source()
        val archive = core().create("export", metadata(), AtomicBoolean(false))
        val stage =
            core()
                .stage(
                    "restore",
                    File(archive.getString("path")).inputStream(),
                    "backup.zip",
                    AtomicBoolean(false),
                )
        assertFalse(stage.getBoolean("legacy"))
        val files = stage.getJSONObject("manifest").getJSONArray("files")
        val paths = (0 until files.length()).map { files.getJSONObject(it).getString("path") }
        assertTrue(paths.contains("projects/key/empty"))
        assertTrue(paths.contains("projects/key/.git/keep"))
        assertFalse(paths.any { it.contains("__pycache__") })
        assertArrayEquals(
            byteArrayOf(0, -1, 42),
            File(core().payload("restore"), "projects/key/.hidden").readBytes(),
        )
    }

    @Test
    fun legacyZipPreservesPathsAndHasNoInventedEntrypoint() {
        val stage =
            core()
                .stage(
                    "legacy",
                    zip(
                            "nested/main.py" to "print(1)".toByteArray(),
                            "empty/" to byteArrayOf(),
                            ".hidden" to byteArrayOf(0),
                            "__MACOSX/no" to byteArrayOf(),
                        )
                        .inputStream(),
                    "Example.zip",
                    AtomicBoolean(false),
                )
        assertTrue(stage.getBoolean("legacy"))
        val m = stage.getJSONObject("manifest")
        assertEquals("Example", m.getJSONArray("groups").getJSONObject(0).getString("name"))
        assertTrue(m.getJSONArray("groups").getJSONObject(0).isNull("mainFilePath"))
        assertTrue(File(core().payload("legacy"), "projects/legacy_legacy/nested/main.py").isFile)
        assertTrue(File(core().payload("legacy"), "projects/legacy_legacy/empty").isDirectory)
    }

    @Test
    fun dangerousAndAmbiguousEntriesReject() {
        val invalid = listOf("../outside", "/absolute", "a\\b", "a/../b", "a:b", "a\u0000b")
        invalid.forEachIndexed { i, path ->
            expectFailure("Path: $path") {
                core().stage("bad$i", rawZip(path).inputStream(), "bad.zip", AtomicBoolean(false))
            }
        }
        expectFailure {
            core()
                .stage(
                    "dup",
                    zip("a" to byteArrayOf(1), "a" to byteArrayOf(2)).inputStream(),
                    "bad.zip",
                    AtomicBoolean(false),
                )
        }
        expectFailure {
            core()
                .stage(
                    "collision",
                    zip("a" to byteArrayOf(1), "a/b" to byteArrayOf(2)).inputStream(),
                    "bad.zip",
                    AtomicBoolean(false),
                )
        }
        expectFailure {
            core()
                .stage(
                    "sym",
                    zip("link" to "target".toByteArray(), symlink = true).inputStream(),
                    "bad.zip",
                    AtomicBoolean(false),
                )
        }
        assertFalse(File(temp.root, "outside").exists())
    }

    @Test
    fun malformedMarkerNeverFallsBackToLegacy() {
        listOf(
                "{",
                "{\"format\":\"other\",\"version\":1}",
                metadata().put("files", org.json.JSONArray()).toString(),
            )
            .forEachIndexed { i, json ->
                expectFailure {
                    core()
                        .stage(
                            "marker$i",
                            zip(BackupArchive.MARKER to json.toByteArray()).inputStream(),
                            "bad.zip",
                            AtomicBoolean(false),
                        )
                }
            }
    }

    @Test
    fun excessivelyNestedOrTrailingMarkerRejects() {
        val valid =
            """{"format":"python_runner_backup","version":1,"createdAt":1,"scripts":[],"groups":[],"files":[]}"""
        val nested =
            valid.dropLast(1) + ",\"extra\":" + "[".repeat(200) + "0" + "]".repeat(200) + "}"
        listOf(nested, valid + "garbage").forEachIndexed { index, contents ->
            expectFailure {
                core()
                    .stage(
                        "json$index",
                        zip(BackupArchive.MARKER to contents.toByteArray()).inputStream(),
                        "bad.zip",
                        AtomicBoolean(false),
                    )
            }
        }
    }

    @Test
    fun cancellationAndMissingSourceRemovePartialArchive() {
        source()
        expectFailure { core().create("cancel", metadata(), AtomicBoolean(true)) }
        File(temp.root, "scripts/hello.py").delete()
        expectFailure { core().create("missing", metadata(), AtomicBoolean(false)) }
        assertFalse(core().operationDir("cancel").walkTopDown().any { it.extension == "zip" })
    }

    @Test
    fun changedHashMissingAndUnlistedPayloadRejectBeforeLiveMutation() {
        source()
        val created = core().create("export", metadata(), AtomicBoolean(false))
        val original = File(created.getString("path"))
        val entries =
            java.util.zip.ZipFile(original).use { z ->
                z.entries()
                    .asSequence()
                    .map { it.name to z.getInputStream(it).readBytes() }
                    .toList()
            }
        val badHash =
            entries.map { (name, bytes) ->
                if (name == "scripts/hello.py")
                    name to bytes.copyOf().apply { this[0] = (this[0] + 1).toByte() }
                else name to bytes
            }
        expectFailure {
            core()
                .stage(
                    "hash",
                    zip(*badHash.toTypedArray()).inputStream(),
                    "bad.zip",
                    AtomicBoolean(false),
                )
        }
        expectFailure {
            core()
                .stage(
                    "missingPayload",
                    zip(*entries.filter { it.first != "scripts/hello.py" }.toTypedArray())
                        .inputStream(),
                    "bad.zip",
                    AtomicBoolean(false),
                )
        }
        expectFailure {
            core()
                .stage(
                    "extra",
                    zip(*(entries + Pair("unknown", byteArrayOf(1))).toTypedArray()).inputStream(),
                    "bad.zip",
                    AtomicBoolean(false),
                )
        }
        assertEquals("print('你好')", File(temp.root, "scripts/hello.py").readText())
    }

    @Test
    fun storedZipWithBadCrcRejects() {
        val file = File(temp.root, "crc.zip")
        java.util.zip.ZipOutputStream(file.outputStream()).use { out ->
            val data = "abcd".toByteArray()
            val crc = java.util.zip.CRC32().apply { update(data) }.value
            val e =
                java.util.zip.ZipEntry("main.py").apply {
                    method = java.util.zip.ZipEntry.STORED
                    size = 4
                    compressedSize = 4
                    this.crc = crc
                }
            out.putNextEntry(e)
            out.write(data)
            out.closeEntry()
        }
        val bytes = file.readBytes()
        val offset = 30 + "main.py".length
        bytes[offset] = 'z'.code.toByte()
        file.writeBytes(bytes)
        expectFailure { core().stage("crc", file.inputStream(), "crc.zip", AtomicBoolean(false)) }
    }

    @Test
    fun downloadTransferCanStageWithinSameOperationAndCannotBeDiscardedWithJournal() {
        val backend = core()
        val transfer = backend.transferFile("download")
        transfer.writeBytes(zip("main.py" to "print(1)".toByteArray()).readBytes())
        backend.stage(
            "download",
            backend.knownArchive("download", transfer.absolutePath).inputStream(),
            "project.zip",
            AtomicBoolean(false),
        )
        assertTrue(File(backend.payload("download"), "projects/legacy_download/main.py").exists())
        File(backend.operationDir("download"), "journal.json").writeText("{}")
        expectFailure { backend.discard("download") }
        assertTrue(transfer.exists())
    }

    @Test
    fun sizeLimitsAndCancelledStageRemoveStagingFiles() {
        val small = BackupArchive(temp.root, maxBytes = 128)
        expectFailure {
            small.stage(
                "limit",
                zip("huge" to ByteArray(1024)).inputStream(),
                "large.zip",
                AtomicBoolean(false),
            )
        }
        expectFailure {
            core()
                .stage(
                    "cancelStage",
                    zip("a" to byteArrayOf(1)).inputStream(),
                    "a.zip",
                    AtomicBoolean(true),
                )
        }
        assertFalse(File(core().operationDir("cancelStage"), "input.zip").exists())
    }

    @Test
    fun cancellationDuringStreamingAndSourceMutationAreDetected() {
        source()
        val cancel = AtomicBoolean(false)
        val cancelling =
            BackupArchive(
                temp.root,
                progress = { _, stage, _, _ -> if (stage == "compressing") cancel.set(true) },
            )
        expectFailure { cancelling.create("midCancel", metadata(), cancel) }
        assertFalse(
            cancelling.operationDir("midCancel").walkTopDown().any { it.extension == "zip" }
        )
        val changing =
            BackupArchive(
                temp.root,
                progress = { _, stage, _, _ ->
                    if (stage == "compressing")
                        File(temp.root, "scripts/hello.py").setLastModified(123456789)
                },
            )
        expectFailure { changing.create("changed", metadata(), AtomicBoolean(false)) }
    }

    private fun expectFailure(label: String = "archive", action: () -> Unit) {
        try {
            action()
            fail("Must reject $label")
        } catch (_: BackupException) {}
    }
}
