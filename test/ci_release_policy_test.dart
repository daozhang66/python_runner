import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CI builds release APK and runs release verification gates', () {
    final ci = File('.github/workflows/ci.yml').readAsStringSync();

    expect(ci, contains('flutter build apk --debug'));
    expect(ci, contains('actions/setup-python@v5'));
    expect(ci, contains("python-version: '3.11'"));
    expect(ci, contains('flutter build apk --release'));
    expect(ci, contains('verifyReleaseManifestPolicy'));
    expect(ci, contains('reportReleaseApkSize'));
    expect(ci, contains('apksigner'));
    expect(ci, contains('ZIP_STORED'));
    expect(ci, contains('build/app/reports/apk-size/release-size.txt'));
  });
}
