import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release manifest overlay removes high-risk debug/internal capabilities',
      () {
    final releaseOverlay = File(
      'android/app/src/release/AndroidManifest.xml',
    ).readAsStringSync();
    final buildGradle = File('android/app/build.gradle').readAsStringSync();

    expect(releaseOverlay, contains('android:usesCleartextTraffic="false"'));
    expect(
        releaseOverlay, contains('android.permission.MANAGE_EXTERNAL_STORAGE'));
    expect(releaseOverlay, contains('android.permission.SYSTEM_ALERT_WINDOW'));
    expect(releaseOverlay, contains('bin.mt.file.content.MTDataFilesProvider'));
    expect(releaseOverlay, contains('tools:node="remove"'));

    expect(buildGradle, contains('verifyReleaseManifestPolicy'));
    expect(buildGradle, contains('android:usesCleartextTraffic'));
    expect(buildGradle, contains('true'));
    expect(buildGradle, contains('REQUEST_INSTALL_PACKAGES missing'));
  });
}
