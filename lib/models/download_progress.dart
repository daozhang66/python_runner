/// Status of a native download task, mirrored from Kotlin `DownloadStatus`
/// plus the synthetic `installPermissionRequired` signal emitted by
/// `AppUpdateController` when the install permission is missing.
enum DownloadStatus {
  pending,
  checking,
  downloading,
  retrying,
  completed,
  cancelled,
  failed,
  installPermissionRequired,
  unknown,
}

/// Immutable snapshot of a native download-progress event.
///
/// Parsed from the `com.daozhang.py/download_progress` EventChannel payload
/// emitted by `DownloadManager`/`AppUpdateController`. The fields mirror the
/// map keys built in `DownloadManager.emit`.
class DownloadProgress {
  final String taskId;
  final String type;
  final DownloadStatus status;
  final int downloadedBytes;
  final int totalBytes;

  /// 0-100, or -1 when the total size is unknown.
  final int progress;
  final int speedBytesPerSecond;

  /// Estimated seconds remaining, or -1 when unknown.
  final int etaSeconds;
  final int retryCount;

  /// Absolute path to the verified APK, only set when [status] is completed.
  final String filePath;
  final String errorCode;
  final String errorMessage;

  const DownloadProgress({
    required this.taskId,
    required this.type,
    required this.status,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.progress,
    required this.speedBytesPerSecond,
    required this.etaSeconds,
    required this.retryCount,
    required this.filePath,
    required this.errorCode,
    required this.errorMessage,
  });

  factory DownloadProgress.fromMap(Map<dynamic, dynamic> map) {
    return DownloadProgress(
      taskId: map['taskId']?.toString() ?? '',
      type: map['type']?.toString() ?? '',
      status: _parseStatus(map['status']?.toString() ?? ''),
      downloadedBytes: _asInt(map['downloadedBytes']),
      totalBytes: _asInt(map['totalBytes']),
      progress: _asInt(map['progress'], fallback: -1),
      speedBytesPerSecond: _asInt(map['speedBytesPerSecond']),
      etaSeconds: _asInt(map['etaSeconds'], fallback: -1),
      retryCount: _asInt(map['retryCount']),
      filePath: map['filePath']?.toString() ?? '',
      errorCode: map['errorCode']?.toString() ?? '',
      errorMessage: map['errorMessage']?.toString() ?? '',
    );
  }

  static int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static DownloadStatus _parseStatus(String raw) {
    switch (raw) {
      case 'pending':
        return DownloadStatus.pending;
      case 'checking':
        return DownloadStatus.checking;
      case 'downloading':
        return DownloadStatus.downloading;
      case 'retrying':
        return DownloadStatus.retrying;
      case 'completed':
        return DownloadStatus.completed;
      case 'cancelled':
        return DownloadStatus.cancelled;
      case 'failed':
        return DownloadStatus.failed;
      case 'install_permission_required':
        return DownloadStatus.installPermissionRequired;
      default:
        return DownloadStatus.unknown;
    }
  }
}
