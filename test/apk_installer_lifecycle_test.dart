import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('downloaded APK is copied before its completed task is discarded', () {
    final installer = File(
      'android/app/src/main/kotlin/com/daozhang/py/ApkInstaller.kt',
    ).readAsStringSync();
    final controller = File(
      'android/app/src/main/kotlin/com/daozhang/py/AppUpdateController.kt',
    ).readAsStringSync();

    expect(installer, contains('File(context.filesDir, "apk_install")'));
    expect(installer, contains('canonicalApk.copyTo(temporaryApk'));
    expect(installer, contains('temporaryApk.renameTo(privateApk)'));
    expect(installer, contains('ClipData.newRawUri'));
    expect(installer, isNot(contains('context.getExternalFilesDir(null)')));

    final installIndex = controller.indexOf('apkInstaller.installApk(apkFile)');
    final discardIndex = controller.indexOf('downloadManager.discardCompletedTask(taskId)');
    expect(installIndex, greaterThanOrEqualTo(0));
    expect(discardIndex, greaterThan(installIndex));
  });
}
