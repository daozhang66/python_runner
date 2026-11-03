import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/services/update_service.dart';

ReleaseAssetInfo _asset(String name) => ReleaseAssetInfo(
      name: name,
      downloadUrl: 'https://example.invalid/$name',
      size: 1,
      contentType: 'application/octet-stream',
    );

void main() {
  test('picks the APK built for the running Python version', () {
    final assets = [
      _asset('PythonRunner-v1.7.0-py3.10.apk'),
      _asset('PythonRunner-v1.7.0-py3.11.apk'),
    ];
    expect(
      pickApkAsset(assets, pythonVersion: '3.11')?.name,
      'PythonRunner-v1.7.0-py3.11.apk',
    );
    expect(
      pickApkAsset(assets, pythonVersion: '3.10')?.name,
      'PythonRunner-v1.7.0-py3.10.apk',
    );
  });

  test('never falls back to an APK of another Python version', () {
    final assets = [_asset('PythonRunner-v1.7.0-py3.10.apk')];
    expect(pickApkAsset(assets, pythonVersion: '3.11'), isNull);
  });

  test('older releases with one unmarked APK keep working', () {
    final assets = [_asset('notes.txt'), _asset('app-release.apk')];
    expect(
      pickApkAsset(assets, pythonVersion: '3.10')?.name,
      'app-release.apk',
    );
  });

  test('latest release parsing attaches the checksum of the picked APK', () {
    final body = jsonEncode({
      'tag_name': 'v1.7.0',
      'assets': [
        {
          'name': 'PythonRunner-v1.7.0-py3.10.apk',
          'browser_download_url': 'https://example.invalid/py310.apk',
        },
        {
          'name': 'PythonRunner-v1.7.0-py3.11.apk',
          'browser_download_url': 'https://example.invalid/py311.apk',
        },
        {
          'name': 'PythonRunner-v1.7.0-py3.11.apk.sha256',
          'browser_download_url': 'https://example.invalid/py311.sha256',
        },
      ],
    });
    final info = UpdateService.parseLatestReleaseResponse(
      body: body,
      currentVersion: '1.6.4',
    );
    expect(info.apkAsset?.name, contains('py$appPythonVariant'));
    if (appPythonVariant == '3.11') {
      expect(
        info.apkAsset?.checksumDownloadUrl,
        'https://example.invalid/py311.sha256',
      );
    }
  });
}
