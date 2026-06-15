import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:python_runner/pages/update_log_page.dart';
import 'package:python_runner/services/update_service.dart';

class _FakeUpdateService extends UpdateService {
  _FakeUpdateService(this.entries);

  final List<ReleaseLogEntry> entries;

  @override
  Future<List<ReleaseLogEntry>> fetchReleaseLogs({int limit = 20}) async {
    return entries.take(limit).toList();
  }
}

void main() {
  test('expanded release notes stay full width and left aligned', () {
    final source = File('lib/pages/update_log_page.dart').readAsStringSync();

    expect(source, contains('alignment: Alignment.centerLeft'));
    expect(source, contains('width: double.infinity'));
    expect(source, contains('MarkdownBody('));
  });

  testWidgets('update log page lists filters and expands release notes',
      (tester) async {
    final openedUrls = <String>[];
    final entries = [
      ReleaseLogEntry(
        tagName: 'v1.4.4',
        version: '1.4.4',
        releaseName: '更新日志',
        releaseNotes: '- 新增更新日志页面\n- 优化设置入口',
        htmlUrl:
            'https://github.com/daozhang66/python_runner/releases/tag/v1.4.4',
        publishedAt: DateTime.parse('2026-06-05T12:00:00Z'),
        isPrerelease: false,
        apkAsset: const ReleaseAssetInfo(
          name: 'python_runner-v1.4.4.apk',
          downloadUrl: 'https://example.com/python_runner-v1.4.4.apk',
          size: 456789,
          contentType: 'application/vnd.android.package-archive',
        ),
      ),
      ReleaseLogEntry(
        tagName: 'v1.4.3',
        version: '1.4.3',
        releaseName: '性能优化',
        releaseNotes: '- 优化终端性能',
        htmlUrl:
            'https://github.com/daozhang66/python_runner/releases/tag/v1.4.3',
        publishedAt: DateTime.parse('2026-06-04T10:00:00Z'),
        isPrerelease: false,
        apkAsset: null,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: UpdateLogPage(
          updateService: _FakeUpdateService(entries),
          openUrl: (url) async => openedUrls.add(url),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('更新日志'), findsNWidgets(2));
    expect(find.text('v1.4.4'), findsOneWidget);
    expect(find.text('v1.4.3'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('updateLogSearchField')),
      '新增',
    );
    await tester.pumpAndSettle();

    expect(find.text('v1.4.4'), findsOneWidget);
    expect(find.text('v1.4.3'), findsNothing);

    await tester.tap(find.text('v1.4.4'));
    await tester.pumpAndSettle();
    expect(find.textContaining('新增更新日志页面'), findsOneWidget);

    await tester.tap(find.text('发布页'));
    await tester.pumpAndSettle();
    expect(openedUrls, [
      'https://github.com/daozhang66/python_runner/releases/tag/v1.4.4',
    ]);
  });
}
