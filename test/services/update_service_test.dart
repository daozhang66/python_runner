import 'package:flutter_test/flutter_test.dart';

import 'package:python_runner/services/update_service.dart';

void main() {
  group('UpdateService', () {
    test('normalizeVersion strips prefixes and build metadata', () {
      expect(UpdateService.normalizeVersion(' v1.3.4+8 '), '1.3.4');
      expect(UpdateService.normalizeVersion('release-2.0.1-beta'), '2.0.1');
      expect(UpdateService.normalizeVersion(''), '0.0.0');
    });

    test('compareVersions compares semantic segments', () {
      expect(UpdateService.compareVersions('1.3.4', '1.3.3'), greaterThan(0));
      expect(UpdateService.compareVersions('1.3.4', '1.3.4+8'), 0);
      expect(UpdateService.compareVersions('1.3.4', '1.10.0'), lessThan(0));
    });

    test('parseLatestReleaseResponse extracts the first apk asset', () {
      const body = '''
{
  "tag_name": "v1.3.4",
  "name": "1.3.4",
  "body": "- fix updater\\n- improve terminal",
  "html_url": "https://github.com/daozhang66/python_runner/releases/tag/v1.3.4",
  "published_at": "2026-05-03T08:30:00Z",
  "assets": [
    {
      "name": "release-notes.txt",
      "browser_download_url": "https://example.com/release-notes.txt",
      "size": 100,
      "content_type": "text/plain"
    },
    {
      "name": "python_runner-v1.3.4.apk",
      "browser_download_url": "https://example.com/python_runner-v1.3.4.apk",
      "size": 123456,
      "content_type": "application/vnd.android.package-archive"
    }
  ]
}
''';

      final updateInfo = UpdateService.parseLatestReleaseResponse(
        body: body,
        currentVersion: '1.3.3+7',
      );

      expect(updateInfo.currentVersion, '1.3.3');
      expect(updateInfo.latestVersion, '1.3.4');
      expect(updateInfo.hasUpdate, isTrue);
      expect(updateInfo.apkAsset, isNotNull);
      expect(updateInfo.apkAsset!.name, 'python_runner-v1.3.4.apk');
      expect(
        updateInfo.apkAsset!.downloadUrl,
        'https://example.com/python_runner-v1.3.4.apk',
      );
    });

    test('extractApiErrorMessage returns GitHub message when present', () {
      const body = '{"message":"API rate limit exceeded"}';
      expect(
        UpdateService.extractApiErrorMessage(body),
        'API rate limit exceeded',
      );
    });
  });
}
