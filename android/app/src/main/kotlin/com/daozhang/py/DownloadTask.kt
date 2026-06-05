package com.daozhang.py

import org.json.JSONObject

enum class DownloadTaskType {
    APK_UPDATE
}

enum class DownloadStatus {
    PENDING,
    CHECKING,
    DOWNLOADING,
    RETRYING,
    COMPLETED,
    CANCELLED,
    FAILED
}

data class DownloadTask(
    val taskId: String,
    val type: DownloadTaskType,
    val url: String,
    val fileName: String,
    val version: String,
    val tempFilePath: String,
    val finalFilePath: String,
    val stateFilePath: String,
    val totalBytes: Long = -1L,
    val downloadedBytes: Long = 0L,
    val etag: String = "",
    val lastModified: String = "",
    val sha256: String = "",
    val status: DownloadStatus = DownloadStatus.PENDING,
    val retryCount: Int = 0,
    val lastErrorCode: String = "",
    val lastErrorMessage: String = "",
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis()
) {
    fun withStatus(
        nextStatus: DownloadStatus,
        downloaded: Long = downloadedBytes,
        total: Long = totalBytes,
        nextRetryCount: Int = retryCount,
        errorCode: String = lastErrorCode,
        errorMessage: String = lastErrorMessage
    ): DownloadTask {
        return copy(
            status = nextStatus,
            downloadedBytes = downloaded,
            totalBytes = total,
            retryCount = nextRetryCount,
            lastErrorCode = errorCode,
            lastErrorMessage = errorMessage,
            updatedAt = System.currentTimeMillis()
        )
    }

    fun withRemoteInfo(
        total: Long,
        remoteEtag: String,
        remoteLastModified: String
    ): DownloadTask {
        return copy(
            totalBytes = total,
            etag = remoteEtag,
            lastModified = remoteLastModified,
            updatedAt = System.currentTimeMillis()
        )
    }

    fun toJson(): JSONObject {
        return JSONObject()
            .put("schemaVersion", 1)
            .put("taskId", taskId)
            .put("type", type.name)
            .put("url", url)
            .put("fileName", fileName)
            .put("version", version)
            .put("tempFilePath", tempFilePath)
            .put("finalFilePath", finalFilePath)
            .put("stateFilePath", stateFilePath)
            .put("totalBytes", totalBytes)
            .put("downloadedBytes", downloadedBytes)
            .put("etag", etag)
            .put("lastModified", lastModified)
            .put("sha256", sha256)
            .put("status", status.name)
            .put("retryCount", retryCount)
            .put("lastErrorCode", lastErrorCode)
            .put("lastErrorMessage", lastErrorMessage)
            .put("createdAt", createdAt)
            .put("updatedAt", updatedAt)
    }

    companion object {
        fun fromJson(json: JSONObject): DownloadTask {
            return DownloadTask(
                taskId = json.getString("taskId"),
                type = DownloadTaskType.valueOf(json.optString("type", DownloadTaskType.APK_UPDATE.name)),
                url = json.getString("url"),
                fileName = json.getString("fileName"),
                version = json.optString("version", ""),
                tempFilePath = json.getString("tempFilePath"),
                finalFilePath = json.getString("finalFilePath"),
                stateFilePath = json.getString("stateFilePath"),
                totalBytes = json.optLong("totalBytes", -1L),
                downloadedBytes = json.optLong("downloadedBytes", 0L),
                etag = json.optString("etag", ""),
                lastModified = json.optString("lastModified", ""),
                sha256 = json.optString("sha256", ""),
                status = DownloadStatus.valueOf(json.optString("status", DownloadStatus.PENDING.name)),
                retryCount = json.optInt("retryCount", 0),
                lastErrorCode = json.optString("lastErrorCode", ""),
                lastErrorMessage = json.optString("lastErrorMessage", ""),
                createdAt = json.optLong("createdAt", System.currentTimeMillis()),
                updatedAt = json.optLong("updatedAt", System.currentTimeMillis())
            )
        }
    }
}
