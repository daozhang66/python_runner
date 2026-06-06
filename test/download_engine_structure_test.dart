import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'download engine uses task based native bridge and dedicated progress stream',
      () {
    final nativeBridge =
        File('lib/services/native_bridge.dart').readAsStringSync();
    final updateManager =
        File('lib/services/app_update_manager.dart').readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt',
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

    expect(nativeBridge, contains('com.daozhang.py/download_progress'));
    expect(nativeBridge, contains('downloadProgressStream'));
    expect(nativeBridge, contains('Future<String> startApkDownload'));
    expect(nativeBridge, contains('Future<bool> cancelDownload'));
    expect(nativeBridge, contains('Future<bool> retryDownload'));
    expect(nativeBridge, contains('Future<String> installDownloadedApk'));

    expect(mainActivity, contains('DOWNLOAD_PROGRESS_CHANNEL'));
    expect(mainActivity, contains('downloadSink'));
    expect(mainActivity, contains('DownloadManager('));
    expect(mainActivity, contains('ApkInstaller('));
    expect(mainActivity, contains('"startApkDownload"'));
    expect(mainActivity, contains('"cancelDownload"'));
    expect(mainActivity, contains('"retryDownload"'));
    expect(mainActivity, contains('"installDownloadedApk"'));
    expect(mainActivity,
        isNot(contains('private fun handleDownloadAndInstallApk(')));
    expect(mainActivity, isNot(contains('ByteArray(8192)')));

    expect(updateManager, contains('downloadProgressStream'));
    expect(updateManager, contains('startApkDownload'));
    expect(updateManager, contains('cancelDownload'));
    expect(updateManager, contains('retryDownload'));
    expect(updateManager, contains('installDownloadedApk'));
    expect(updateManager, contains('下载失败'));
    expect(updateManager, contains('重试'));
    expect(updateManager, contains('取消'));
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

    expect(installerSource, contains('canRequestPackageInstalls'));
    expect(installerSource, contains('FileProvider.getUriForFile'));
    expect(installerSource, contains('ACTION_VIEW'));
    expect(installerSource, contains('packageName'));
    expect(installerSource, contains('getPackageArchiveInfo'));
  });
}
