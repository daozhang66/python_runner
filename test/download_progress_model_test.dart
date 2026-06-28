import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/models/download_progress.dart';

void main() {
  group('DownloadProgress.fromMap', () {
    test('parses a full downloading payload', () {
      final progress = DownloadProgress.fromMap(const {
        'taskId': 'apk-update-v1.5.6',
        'type': 'apk_update',
        'status': 'downloading',
        'downloadedBytes': 1024,
        'totalBytes': 4096,
        'progress': 25,
        'speedBytesPerSecond': 512,
        'etaSeconds': 6,
        'retryCount': 0,
        'filePath': '',
        'errorCode': '',
        'errorMessage': '',
      });

      expect(progress.taskId, 'apk-update-v1.5.6');
      expect(progress.type, 'apk_update');
      expect(progress.status, DownloadStatus.downloading);
      expect(progress.downloadedBytes, 1024);
      expect(progress.totalBytes, 4096);
      expect(progress.progress, 25);
      expect(progress.speedBytesPerSecond, 512);
      expect(progress.etaSeconds, 6);
    });

    test('maps every native status name', () {
      DownloadStatus statusFor(String raw) =>
          DownloadProgress.fromMap({'status': raw}).status;

      expect(statusFor('pending'), DownloadStatus.pending);
      expect(statusFor('checking'), DownloadStatus.checking);
      expect(statusFor('downloading'), DownloadStatus.downloading);
      expect(statusFor('retrying'), DownloadStatus.retrying);
      expect(statusFor('completed'), DownloadStatus.completed);
      expect(statusFor('cancelled'), DownloadStatus.cancelled);
      expect(statusFor('failed'), DownloadStatus.failed);
      expect(
        statusFor('install_permission_required'),
        DownloadStatus.installPermissionRequired,
      );
      expect(statusFor('something_else'), DownloadStatus.unknown);
    });

    test('applies safe fallbacks for missing or unknown fields', () {
      final progress = DownloadProgress.fromMap(const {});

      expect(progress.taskId, '');
      expect(progress.type, '');
      expect(progress.status, DownloadStatus.unknown);
      expect(progress.downloadedBytes, 0);
      expect(progress.totalBytes, 0);
      // progress / eta fall back to -1 (unknown), not 0.
      expect(progress.progress, -1);
      expect(progress.etaSeconds, -1);
      expect(progress.retryCount, 0);
    });

    test('coerces numeric fields delivered as num or string', () {
      final progress = DownloadProgress.fromMap(const {
        'downloadedBytes': 2048.0,
        'totalBytes': '8192',
        'progress': 25.0,
        'speedBytesPerSecond': '1024',
        'etaSeconds': 7.0,
      });

      expect(progress.downloadedBytes, 2048);
      expect(progress.totalBytes, 8192);
      expect(progress.progress, 25);
      expect(progress.speedBytesPerSecond, 1024);
      expect(progress.etaSeconds, 7);
    });

    test('keeps the verified APK path on a completed event', () {
      final progress = DownloadProgress.fromMap(const {
        'status': 'completed',
        'filePath': '/data/updates/app.apk',
        'progress': 100,
      });

      expect(progress.status, DownloadStatus.completed);
      expect(progress.filePath, '/data/updates/app.apk');
    });

    test('carries error details on a failed event', () {
      final progress = DownloadProgress.fromMap(const {
        'status': 'failed',
        'errorCode': 'DOWNLOAD_FAILED',
        'errorMessage': '连接超时',
      });

      expect(progress.status, DownloadStatus.failed);
      expect(progress.errorCode, 'DOWNLOAD_FAILED');
      expect(progress.errorMessage, '连接超时');
    });
  });
}
