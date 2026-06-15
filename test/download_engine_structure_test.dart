import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app update downloads with Dio and installs through FileProvider', () {
    final nativeBridge =
        File('lib/services/native_bridge.dart').readAsStringSync();
    final updateManager =
        File('lib/services/app_update_manager.dart').readAsStringSync();
    final downloadService =
        File('lib/services/download_service.dart').readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt',
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

    expect(downloadService, contains('class DownloadService'));
    expect(downloadService, contains('Dio(BaseOptions('));
    expect(downloadService,
        contains('receiveTimeout: const Duration(minutes: 30)'));
    expect(downloadService, contains('Future<void> download({'));
    expect(downloadService, contains('Future<void> downloadWithResume({'));

    expect(nativeBridge, contains('Future<void> installApkFile'));
    expect(nativeBridge, contains("_invoke('installApkFile'"));
    expect(mainActivity, contains('DownloadManager('));
    expect(mainActivity, contains('ApkInstaller('));
    expect(mainActivity, contains('"installApkFile"'));
    expect(mainActivity,
        isNot(contains('private fun handleDownloadAndInstallApk(')));
    expect(mainActivity, isNot(contains('ByteArray(8192)')));

    expect(updateManager, contains('DownloadService.instance.download'));
    expect(updateManager, contains('Directory.systemTemp'));
    expect(updateManager, contains('CancelToken'));
    expect(updateManager, contains('installApkFile(savePath)'));
    expect(updateManager, contains('下载失败'));
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
