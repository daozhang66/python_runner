import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:python_runner/services/http_inspector_store.dart';

void main() {
  group('HttpInspectorStore', () {
    test('HttpRecord round-trips response body metadata', () {
      final record = HttpRecord.fromJson({
        'id': 'req-1',
        'timestamp': 1710000000000,
        'method': 'get',
        'url': 'https://example.com/data',
        'request_headers': {'Accept': 'application/json'},
        'status_code': 200,
        'response_headers': {'content-type': 'application/json'},
        'response_body_preview': '{"items":[1,2]}... (truncated)',
        'response_body_size': 4096,
        'response_body_truncated': true,
        'duration_ms': 88,
      });

      final json = record.toJson();
      expect(json['response_body_size'], 4096);
      expect(json['response_body_truncated'], isTrue);

      final restored = HttpRecord.fromJson(json);
      expect(restored.responseBodyBytes, 4096);
      expect(restored.responseBodyTruncated, isTrue);
      expect(restored.responseBodyPreview, '{"items":[1,2]}... (truncated)');
    });

    test('trimRecords keeps newest records within count and body budget', () {
      HttpRecord makeRecord(String id, int chars) => HttpRecord(
            id: id,
            timestamp: DateTime.fromMillisecondsSinceEpoch(1710000000000 + chars),
            method: 'GET',
            url: 'https://example.com/$id',
            requestHeaders: const {},
            responseBodyPreview: 'x' * chars,
            responseBodyBytes: chars,
          );

      final trimmed = HttpInspectorStore.trimRecords(
        [
          makeRecord('oldest', 4),
          makeRecord('middle', 5),
          makeRecord('newest', 6),
        ],
        maxRecords: 2,
        maxCapturedBodyBytes: 11,
      );

      expect(trimmed.map((r) => r.id).toList(), ['middle', 'newest']);
    });

    test('flush persists records and restore loads them back', () async {
      final tempDir = await Directory.systemTemp.createTemp('http_inspector_store_test_');
      try {
        final store = HttpInspectorStore.test(
          supportDirectoryProvider: () async => tempDir,
          persistDebounce: const Duration(milliseconds: 5),
        );
        await store.ensureLoaded();

        store.addFromJson({
          'id': 'req-persist',
          'timestamp': 1710000001234,
          'method': 'get',
          'url': 'https://example.com/persist',
          'request_headers': {'Accept': 'application/json'},
          'status_code': 200,
          'response_headers': {'content-type': 'application/json'},
          'response_body_preview': '{"ok":true}',
          'duration_ms': 12,
        });
        await store.flush();

        final restored = HttpInspectorStore.test(
          supportDirectoryProvider: () async => tempDir,
          persistDebounce: const Duration(milliseconds: 5),
        );
        await restored.ensureLoaded();

        expect(restored.records, hasLength(1));
        expect(restored.records.single.url, 'https://example.com/persist');
        expect(restored.records.single.responseBodyPreview, '{"ok":true}');
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });
}
