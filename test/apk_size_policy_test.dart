import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release APK size report and budgets are configured', () {
    final buildGradle = File('android/app/build.gradle').readAsStringSync();

    expect(buildGradle, contains('reportReleaseApkSize'));
    expect(buildGradle, contains('warningMb = 170.0d'));
    expect(buildGradle, contains('hardLimitMb = 190.0d'));
    expect(buildGradle, contains('native-libs'));
    expect(buildGradle, contains('chaquopy-python'));
    expect(buildGradle, contains('linux-like-assets'));
    expect(buildGradle, contains('reports/apk-size'));
    expect(buildGradle, contains('release-size.txt'));
  });
}
