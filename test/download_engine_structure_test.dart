import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app update routes through the native resume engine and installs APK',
      () {
    final nativeBridge =
        File('lib/services/native_bridge.dart').readAsStringSync();
    final updateManager =
        File('lib/services/app_update_manager.dart').readAsStringSync();
    final progressModel =
        File('lib/models/download_progress.dart').readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt',
    ).readAsStringSync();
    final appUpdateController = File(
      'android/app/src/main/kotlin/com/daozhang/py/AppUpdateController.kt',
    ).readAsStringSync();
    final installerSource = File(
      'android/app/src/main/kotlin/com/daozhang/py/ApkInstaller.kt',
    ).readAsStringSync();

    final downloadTask = File(
      'android/app/src/main/kotlin/com/daozhang/py/DownloadTask.kt',
    );
    final downloadManager = File(
      'android/app/src/main/kotlin/com/daozhang/py/DownloadManager.kt',
    );
    final apkInstaller = File(
      'android/app/src/main/kotlin/com/daozhang/py/ApkInstaller.kt',
    );

    expect(downloadTask.existsSync(), isTrue);
    expect(downloadManager.existsSync(), isTrue);
    expect(apkInstaller.existsSync(), isTrue);

    // The dormant Dio DownloadService has been removed; the update flow now
    // drives the native resume engine end to end.
    expect(
      File('lib/services/download_service.dart').existsSync(),
      isFalse,
    );

    // Progress model mirrors the native DownloadManager.emit payload.
    expect(progressModel, contains('class DownloadProgress'));
    expect(progressModel, contains('enum DownloadStatus'));
    expect(progressModel, contains('install_permission_required'));

    expect(nativeBridge, contains('Future<void> installApkFile'));
    expect(nativeBridge, contains("_invoke('installApkFile'"));
    expect(nativeBridge, contains('Future<String> startApkDownload'));
    expect(nativeBridge, contains('downloadProgressStream'));
    expect(appUpdateController, contains('DownloadManager('));
    expect(appUpdateController, contains('ApkInstaller('));
    expect(mainActivity, contains('AppUpdateController(this)'));
    expect(mainActivity, contains('"installApkFile"'));
    expect(mainActivity, contains('"startApkDownload"'));
    expect(mainActivity,
        isNot(contains('private fun handleDownloadAndInstallApk(')));
    expect(mainActivity, isNot(contains('ByteArray(8192)')));

    // Update manager consumes the native engine, not Dio.
    expect(updateManager, contains('_bridge.startApkDownload'));
    expect(updateManager, contains('downloadProgressStream'));
    expect(updateManager, contains('_bridge.installDownloadedApk'));
    expect(updateManager, contains('_bridge.cancelDownload'));
    expect(updateManager, isNot(contains('DownloadService')));
    expect(updateManager, isNot(contains('package:dio/dio.dart')));
    expect(updateManager, contains('更新失败'));
    expect(updateManager, contains('取消'));
    expect(installerSource, contains('ensureShareableApk(apkFile)'));
    expect(installerSource, contains('context.cacheDir, "apk_install"'));
    expect(installerSource, contains('canonicalApk.copyTo'));
  });

  test(
      'native download manager supports resume retry validation and state files',
      () {
    final taskSource = File(
      'android/app/src/main/kotlin/com/daozhang/py/DownloadTask.kt',
    ).readAsStringSync();
    final managerSource = File(
      'android/app/src/main/kotlin/com/daozhang/py/DownloadManager.kt',
    ).readAsStringSync();
    final installerSource = File(
      'android/app/src/main/kotlin/com/daozhang/py/ApkInstaller.kt',
    ).readAsStringSync();

    expect(taskSource, contains('data class DownloadTask'));
    expect(taskSource, contains('enum class DownloadStatus'));
    expect(taskSource, contains('CHECKING'));
    expect(taskSource, contains('DOWNLOADING'));
    expect(taskSource, contains('RETRYING'));
    expect(taskSource, contains('COMPLETED'));
    expect(taskSource, contains('CANCELLED'));
    expect(taskSource, contains('FAILED'));
    expect(taskSource, contains('toJson'));
    expect(taskSource, contains('fromJson'));

    expect(managerSource, contains('.part'));
    expect(managerSource, contains('.task_state.json'));
    expect(managerSource, contains('.tmp'));
    expect(managerSource, contains('Range'));
    expect(managerSource, contains('bytes='));
    expect(managerSource, contains('HTTP_PARTIAL'));
    expect(managerSource, contains('HTTP_OK'));
    expect(managerSource, contains('HTTP_REQUESTED_RANGE_NOT_SATISFIABLE'));
    expect(managerSource, contains('ETag'));
    expect(managerSource, contains('Last-Modified'));
    expect(managerSource, contains('ByteArray(64 * 1024)'));
    expect(managerSource, contains('retryDelaysMs'));
    expect(managerSource, contains('speedBytesPerSecond'));
    expect(managerSource, contains('etaSeconds'));
    expect(managerSource, contains('cancelDownload'));
    expect(managerSource, contains('requireSha256'));
    expect(managerSource, contains('valid SHA-256 checksum'));
    expect(managerSource, isNot(contains('task.sha256.isNotBlank()')));

    expect(installerSource, contains('canRequestPackageInstalls'));
    expect(installerSource, contains('FileProvider.getUriForFile'));
    expect(installerSource, contains('ACTION_VIEW'));
    expect(installerSource, contains('packageName'));
    expect(installerSource, contains('getPackageArchiveInfo'));
  });
}
