import 'dart:convert';
import 'dart:io';

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

    test('parseLatestReleaseResponse links checksum asset without fake hash',
        () {
      const checksumUrl = 'https://example.com/python_runner-v1.3.4.apk.sha256';
      const body = '''
{
  "tag_name": "v1.3.4",
  "name": "1.3.4",
  "body": "",
  "html_url": "https://github.com/daozhang66/python_runner/releases/tag/v1.3.4",
  "published_at": "2026-05-03T08:30:00Z",
  "assets": [
    {
      "name": "python_runner-v1.3.4.apk",
      "browser_download_url": "https://example.com/python_runner-v1.3.4.apk",
      "size": 123456,
      "content_type": "application/vnd.android.package-archive"
    },
    {
      "name": "python_runner-v1.3.4.apk.sha256",
      "browser_download_url": "$checksumUrl",
      "size": 96,
      "content_type": "text/plain"
    }
  ]
}
''';

      final updateInfo = UpdateService.parseLatestReleaseResponse(
        body: body,
        currentVersion: '1.3.3',
      );

      expect(updateInfo.apkAsset, isNotNull);
      expect(updateInfo.apkAsset!.sha256, isNull);
      expect(updateInfo.apkAsset!.checksumDownloadUrl, checksumUrl);
    });

    test('extractSha256Checksum accepts sha256sum and digest formats', () {
      const hash =
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

      expect(
        UpdateService.extractSha256Checksum('$hash  app-release.apk'),
        hash,
      );
      expect(
        UpdateService.extractSha256Checksum('sha256:$hash'),
        hash,
      );
      expect(UpdateService.extractSha256Checksum('not a checksum'), isNull);
    });

    test('parseReleaseLogsResponse extracts release history entries', () {
      const body = '''
[
  {
    "tag_name": "v1.4.4",
    "name": "1.4.4 更新日志",
    "body": "- 新增更新日志页面\\n- 优化设置入口",
    "html_url": "https://github.com/daozhang66/python_runner/releases/tag/v1.4.4",
    "published_at": "2026-06-05T12:00:00Z",
    "prerelease": false,
    "assets": [
      {
        "name": "python_runner-v1.4.4.apk",
        "browser_download_url": "https://example.com/python_runner-v1.4.4.apk",
        "size": 456789,
        "content_type": "application/vnd.android.package-archive"
      }
    ]
  },
  {
    "tag_name": "v1.4.3",
    "name": "",
    "body": "修复更新检查",
    "html_url": "https://github.com/daozhang66/python_runner/releases/tag/v1.4.3",
    "published_at": "2026-06-04T10:00:00Z",
    "prerelease": true,
    "assets": []
  }
]
''';

      final entries = UpdateService.parseReleaseLogsResponse(
        body: body,
        limit: 1,
      );

      expect(entries, hasLength(1));
      expect(entries.first.tagName, 'v1.4.4');
      expect(entries.first.version, '1.4.4');
      expect(entries.first.releaseName, '1.4.4 更新日志');
      expect(entries.first.releaseNotes, contains('新增更新日志页面'));
      expect(entries.first.htmlUrl, contains('/releases/tag/v1.4.4'));
      expect(entries.first.publishedAt, DateTime.parse('2026-06-05T12:00:00Z'));
      expect(entries.first.isPrerelease, isFalse);
      expect(entries.first.apkAsset, isNotNull);
      expect(entries.first.apkAsset!.name, 'python_runner-v1.4.4.apk');
    });

    test('extractApiErrorMessage returns GitHub message when present', () {
      const body = '{"message":"API rate limit exceeded"}';
      expect(
        UpdateService.extractApiErrorMessage(body),
        'API rate limit exceeded',
      );
    });

    test('bounds successful and error update API responses', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var mode = 'latest-success-large';
      server.listen((request) async {
        if (request.uri.path == '/checksum') {
          request.response
            ..statusCode = HttpStatus.internalServerError
            ..write('e' * (64 * 1024 + 1));
          await request.response.close();
          return;
        }
        if (mode == 'latest-error-large') {
          request.response
            ..statusCode = HttpStatus.internalServerError
            ..write('e' * (64 * 1024 + 1));
          await request.response.close();
          return;
        }
        if (mode == 'latest-success-large' || mode == 'logs-success-large') {
          request.response
            ..statusCode = HttpStatus.ok
            ..write('x' * (1024 * 1024 + 1));
          await request.response.close();
          return;
        }
        final checksumUrl =
            'http://${server.address.address}:${server.port}/checksum';
        request.response
          ..statusCode = HttpStatus.ok
          ..write(jsonEncode({
            'tag_name': 'v1.2.0',
            'assets': [
              {
                'name': 'app.apk',
                'browser_download_url': checksumUrl,
                'size': 1,
                'content_type': 'application/vnd.android.package-archive',
              },
              {
                'name': 'app.apk.sha256',
                'browser_download_url': checksumUrl,
                'size': 1,
                'content_type': 'text/plain',
              },
            ],
          }));
        await request.response.close();
      });
      final service = UpdateService(
        apiBaseUri:
            Uri.parse('http://${server.address.address}:${server.port}'),
      );
      try {
        await expectLater(
          service.fetchLatestRelease(currentVersion: '1.0.0'),
          throwsA(isA<HttpException>()),
        );

        mode = 'logs-success-large';
        await expectLater(
            service.fetchReleaseLogs(), throwsA(isA<HttpException>()));

        mode = 'latest-error-large';
        await expectLater(
          service.fetchLatestRelease(currentVersion: '1.0.0'),
          throwsA(isA<HttpException>()),
        );

        mode = 'checksum-release';
        final update =
            await service.fetchLatestRelease(currentVersion: '1.0.0');
        expect(update.apkAsset!.sha256, isNull);
        expect(update.apkAsset!.checksumError, isNotNull);
      } finally {
        await server.close(force: true);
      }
    });
  });
}
