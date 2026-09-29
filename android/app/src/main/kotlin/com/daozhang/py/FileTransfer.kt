package com.daozhang.py

import java.io.File
import java.io.IOException
import java.nio.file.FileVisitResult
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.Path
import java.nio.file.SimpleFileVisitor
import java.nio.file.attribute.BasicFileAttributes

/** Copy to a private staging directory; publish without replacing user data. */
internal object FileTransfer {
    fun transfer(source: File, parent: File, move: Boolean): String {
        val src = source.toPath()
        val destination = parent.toPath().resolve(source.name)
        require(Files.isDirectory(parent.toPath(), NOFOLLOW_LINKS)) { "目标不是目录" }
        require(!Files.isSymbolicLink(src)) { "不支持复制或移动符号链接" }
        require(Files.exists(src, NOFOLLOW_LINKS)) { "源文件不存在" }
        require(!Files.exists(destination, NOFOLLOW_LINKS)) { "目标已存在，请先重命名或选择其他目录" }
        require(!destination.startsWith(src)) { "不能复制或移动到自身及其子目录" }
        if (move) {
            // No copy/delete fallback: failed cross-filesystem moves retain source.
            require(android.system.Os.stat(source.path).st_dev ==
                android.system.Os.stat(parent.path).st_dev) {
                "不支持跨存储剪切，请复制并确认后再删除源文件"
            }
            Files.move(src, destination)
            return destination.toString()
        }
        val staging = Files.createTempDirectory(parent.toPath(), ".pyrunner-copy-")
        val payload = staging.resolve("content")
        try {
            var count = 0
            Files.walkFileTree(src, object : SimpleFileVisitor<Path>() {
                override fun preVisitDirectory(dir: Path, attrs: BasicFileAttributes): FileVisitResult {
                    if (++count > 100000) throw IOException("目录条目过多")
                    Files.createDirectory(payload.resolve(src.relativize(dir)))
                    return FileVisitResult.CONTINUE
                }
                override fun visitFile(file: Path, attrs: BasicFileAttributes): FileVisitResult {
                    if (++count > 100000) throw IOException("目录条目过多")
                    if (!attrs.isRegularFile || attrs.isSymbolicLink) throw IOException("不支持复制符号链接或特殊文件")
                    Files.copy(file, payload.resolve(src.relativize(file)), NOFOLLOW_LINKS)
                    return FileVisitResult.CONTINUE
                }
            })
            Files.move(payload, destination)
            return destination.toString()
        } finally {
            // Only remove our randomly created staging tree; never the destination.
            Files.walkFileTree(staging, object : SimpleFileVisitor<Path>() {
                override fun visitFile(file: Path, attrs: BasicFileAttributes): FileVisitResult {
                    Files.delete(file)
                    return FileVisitResult.CONTINUE
                }
                override fun postVisitDirectory(dir: Path, exc: IOException?): FileVisitResult {
                    Files.delete(dir)
                    return FileVisitResult.CONTINUE
                }
            })
        }
    }
}
