import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release manifest keeps MT data provider and removes high-risk flags',
      () {
    final releaseOverlay = File(
      'android/app/src/release/AndroidManifest.xml',
    ).readAsStringSync();
    final buildGradle = File('android/app/build.gradle').readAsStringSync();

    expect(releaseOverlay, contains('android:usesCleartextTraffic="false"'));
    expect(
        releaseOverlay, contains('android.permission.MANAGE_EXTERNAL_STORAGE'));
    expect(releaseOverlay, contains('android.permission.SYSTEM_ALERT_WINDOW'));
    expect(releaseOverlay, contains('tools:node="remove"'));
    expect(
      releaseOverlay,
      isNot(contains('bin.mt.file.content.MTDataFilesProvider')),
    );
    expect(
      releaseOverlay,
      isNot(contains('bin.mt.file.content.MTDataFilesWakeUpActivity')),
    );

    expect(buildGradle, contains('verifyReleaseManifestPolicy'));
    expect(buildGradle, contains('android:usesCleartextTraffic'));
    expect(buildGradle, contains('true'));
    expect(buildGradle, contains('MTDataFilesProvider'));
    expect(buildGradle, contains('MTDataFilesWakeUpActivity'));
    expect(buildGradle, contains('MANAGE_DOCUMENTS'));
    expect(buildGradle, contains('REQUEST_INSTALL_PACKAGES missing'));
  });
}
