import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:python_runner/services/http_inspector_store.dart';

void main() {
  group('HttpInspectorStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Map<String, dynamic> recordJson(
      String id, {
      String method = 'get',
      String? url,
      int? statusCode = 200,
      int? durationMs,
    }) =>
        {
          'id': id,
          'timestamp': 1710000000000,
          'method': method,
          'url': url ?? 'https://example.com/$id',
          'request_headers': const {},
          if (statusCode != null) 'status_code': statusCode,
          if (durationMs != null) 'duration_ms': durationMs,
        };

    Future<List<dynamic>> readPersistedRecords(Directory dir) async {
      final file = File(
        '${dir.path}${Platform.pathSeparator}http_inspector_records.json',
      );
      return jsonDecode(await file.readAsString()) as List<dynamic>;
    }

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
            timestamp:
                DateTime.fromMillisecondsSinceEpoch(1710000000000 + chars),
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

    test('trimRecords sanitizes a single record that exceeds body budget', () {
      final trimmed = HttpInspectorStore.trimRecords(
        [
          HttpRecord(
            id: 'huge-image',
            timestamp: DateTime.fromMillisecondsSinceEpoch(1710000000000),
            method: 'GET',
            url: 'https://example.com/image.png',
            requestHeaders: const {},
            responseHeaders: const {'content-type': 'image/png'},
            responseBodyPreview: 'data:image/png;base64,${'a' * 100}',
            responseBodyBytes: 75,
          ),
        ],
        maxCapturedBodyBytes: 32,
      );

      expect(trimmed, hasLength(1));
      expect(trimmed.single.id, 'huge-image');
      expect(trimmed.single.storedBodyBytes, lessThanOrEqualTo(32));
      expect(trimmed.single.responseBodyTruncated, isTrue);
    });

    test('noise methods are hidden by default and can be shown', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('http_inspector_noise_');
      try {
        final store = HttpInspectorStore.test(
          supportDirectoryProvider: () async => tempDir,
        );
        await store.loadDisplayPreferences();
        await store.ensureLoaded();

        store
          ..addFromJson(recordJson('http-get', method: 'GET', durationMs: 20))
          ..addFromJson(recordJson('dns', method: 'DNS'))
          ..addFromJson(recordJson('connect', method: 'CONNECT'))
          ..addFromJson(recordJson('process', method: 'PROCESS'))
          ..addFromJson(
              recordJson('http-post', method: 'POST', durationMs: 40));

        expect(store.hideNoiseMethods, isTrue);
        expect(store.hiddenNoiseCount, 3);
        expect(
          store.filteredRecords.map((record) => record.method).toList(),
          ['POST', 'GET'],
        );
        expect(store.visibleStats['total'], 2);
        expect(store.visibleStats['avgMs'], 30);

        store.setHideNoiseMethods(false);

        expect(store.hideNoiseMethods, isFalse);
        expect(
          store.filteredRecords.map((record) => record.method).toSet(),
          {'GET', 'DNS', 'CONNECT', 'PROCESS', 'POST'},
        );
        expect(store.visibleStats['total'], 5);
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test('noise preference is persisted across store instances', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('http_inspector_noise_prefs_');
      try {
        final store = HttpInspectorStore.test(
          supportDirectoryProvider: () async => tempDir,
        );
        await store.loadDisplayPreferences();
        expect(store.hideNoiseMethods, isTrue);

        store.setHideNoiseMethods(false);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final restored = HttpInspectorStore.test(
          supportDirectoryProvider: () async => tempDir,
        );
        await restored.loadDisplayPreferences();

        expect(restored.hideNoiseMethods, isFalse);
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test('noise filtering composes with method status and export filters',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('http_inspector_noise_export_');
      try {
        final store = HttpInspectorStore.test(
          supportDirectoryProvider: () async => tempDir,
        );
        await store.ensureLoaded();

        store
          ..addFromJson(recordJson(
            'ok',
            method: 'GET',
            url: 'https://api.example.com/ok',
            statusCode: 200,
          ))
          ..addFromJson(recordJson(
            'err',
            method: 'POST',
            url: 'https://api.example.com/error',
            statusCode: 500,
          ))
          ..addFromJson(recordJson(
            'dns',
            method: 'DNS',
            url: 'dns://api.example.com',
            statusCode: null,
          ));

        store.setFilterDomain('api.example.com');
        expect(
          store.filteredRecords.map((record) => record.id).toList(),
          ['err', 'ok'],
        );

        store.setFilterStatus(0);
        expect(
          store.filteredRecords.map((record) => record.id).toList(),
          ['err'],
        );
        expect(store.exportFiltered(), contains('POST'));
        expect(store.exportFiltered(), isNot(contains('DNS')));

        final filteredHar =
            jsonDecode(store.exportHar(filteredOnly: true)) as Map;
        expect(
          ((filteredHar['log'] as Map)['entries'] as List),
          hasLength(1),
        );

        store.clearFilters();
        expect(store.hideNoiseMethods, isTrue);
        store.setFilterMethod('DNS');

        expect(store.hideNoiseMethods, isFalse);
        expect(store.filteredRecords.single.id, 'dns');
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test('flush persists records and restore loads them back', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('http_inspector_store_test_');
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

    test('debounced persistence batches rapid records into one write',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('http_inspector_store_batch_');
      final writes = <String>[];
      try {
        final store = HttpInspectorStore.test(
          supportDirectoryProvider: () async => tempDir,
          persistDebounce: const Duration(milliseconds: 25),
          persistMaxDelay: const Duration(milliseconds: 200),
          storageWriter: (file, payload) async {
            writes.add(payload);
            await file.writeAsString(payload, flush: true);
          },
        );
        await store.ensureLoaded();

        store
          ..addFromJson(recordJson('batch-1'))
          ..addFromJson(recordJson('batch-2'))
          ..addFromJson(recordJson('batch-3'));

        await Future<void>.delayed(const Duration(milliseconds: 80));
        await store.flush();

        expect(writes, hasLength(1));
        final persisted = await readPersistedRecords(tempDir);
        expect(
          persisted.map((e) => (e as Map<String, dynamic>)['id']).toList(),
          ['batch-1', 'batch-2', 'batch-3'],
        );
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test('in-flight persistence coalesces follow-up writes', () async {
      final tempDir = await Directory.systemTemp
          .createTemp('http_inspector_store_follow_up_');
      final writes = <String>[];
      final firstWriteStarted = Completer<void>();
      final releaseFirstWrite = Completer<void>();
      try {
        final store = HttpInspectorStore.test(
          supportDirectoryProvider: () async => tempDir,
          persistDebounce: const Duration(milliseconds: 5),
          persistMaxDelay: const Duration(milliseconds: 50),
          storageWriter: (file, payload) async {
            writes.add(payload);
            if (writes.length == 1) {
              firstWriteStarted.complete();
              await releaseFirstWrite.future;
            }
            await file.writeAsString(payload, flush: true);
          },
        );
        await store.ensureLoaded();

        store.addFromJson(recordJson('slow-1'));
        await firstWriteStarted.future;

        store
          ..addFromJson(recordJson('slow-2'))
          ..addFromJson(recordJson('slow-3'));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        releaseFirstWrite.complete();
        await store.flush();

        expect(writes, hasLength(2));
        final persisted = await readPersistedRecords(tempDir);
        expect(
          persisted.map((e) => (e as Map<String, dynamic>)['id']).toList(),
          ['slow-1', 'slow-2', 'slow-3'],
        );
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test('flush cancels debounce and persists immediately', () async {
      final tempDir = await Directory.systemTemp
          .createTemp('http_inspector_store_flush_now_');
      final writes = <String>[];
      try {
        final store = HttpInspectorStore.test(
          supportDirectoryProvider: () async => tempDir,
          persistDebounce: const Duration(days: 1),
          persistMaxDelay: const Duration(days: 1),
          storageWriter: (file, payload) async {
            writes.add(payload);
            await file.writeAsString(payload, flush: true);
          },
        );
        await store.ensureLoaded();

        store.addFromJson(recordJson('flush-now'));
        expect(writes, isEmpty);

        await store.flush();

        expect(writes, hasLength(1));
        final persisted = await readPersistedRecords(tempDir);
        expect((persisted.single as Map<String, dynamic>)['id'], 'flush-now');
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test('stats are updated incrementally and cleared with records', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('http_inspector_store_stats_');
      try {
        final store = HttpInspectorStore.test(
          supportDirectoryProvider: () async => tempDir,
          persistDebounce: const Duration(milliseconds: 5),
        );
        await store.ensureLoaded();

        store.addFromJson({
          'id': 'ok-1',
          'timestamp': 1710000000000,
          'method': 'get',
          'url': 'https://example.com/success',
          'request_headers': const {},
          'status_code': 200,
          'duration_ms': 40,
        });
        store.addFromJson({
          'id': 'err-1',
          'timestamp': 1710000000100,
          'method': 'post',
          'url': 'https://example.com/error',
          'request_headers': const {},
          'status_code': 500,
          'duration_ms': 60,
        });

        expect(store.stats['total'], 2);
        expect(store.stats['success'], 1);
        expect(store.stats['error'], 1);
        expect(store.stats['avgMs'], 50);

        store.clear();
        await store.flush();

        expect(store.stats['total'], 0);
        expect(store.stats['success'], 0);
        expect(store.stats['error'], 0);
        expect(store.stats['avgMs'], isNull);

        final restored = HttpInspectorStore.test(
          supportDirectoryProvider: () async => tempDir,
        );
        await restored.ensureLoaded();
        expect(restored.records, isEmpty);
        expect(restored.stats['total'], 0);
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test('flush throws in tests when persistence fails', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('http_inspector_store_error_');
      try {
        final blocker = File('${tempDir.path}${Platform.pathSeparator}blocker');
        await blocker.writeAsString('not a directory');
        final store = HttpInspectorStore.test(
          supportDirectoryProvider: () async => Directory(blocker.path),
          persistDebounce: const Duration(milliseconds: 5),
        );
        await store.ensureLoaded();

        store.addFromJson({
          'id': 'req-fail',
          'timestamp': 1710000000000,
          'method': 'get',
          'url': 'https://example.com/fail',
          'request_headers': const {},
          'status_code': 200,
        });

        await expectLater(store.flush(), throwsA(isA<FileSystemException>()));
        expect(store.lastStorageError, isA<FileSystemException>());
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test('failed write can be retried and clears storage error', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('http_inspector_store_retry_');
      var attempts = 0;
      try {
        final store = HttpInspectorStore.test(
          supportDirectoryProvider: () async => tempDir,
          persistDebounce: const Duration(days: 1),
          persistMaxDelay: const Duration(days: 1),
          storageWriter: (file, payload) async {
            attempts++;
            if (attempts == 1) {
              throw const FileSystemException('first write failed');
            }
            await file.writeAsString(payload, flush: true);
          },
        );
        await store.ensureLoaded();
        store.addFromJson(recordJson('retry-ok'));

        await expectLater(store.flush(), throwsA(isA<FileSystemException>()));
        expect(store.lastStorageError, isA<FileSystemException>());

        await store.flush();

        expect(attempts, 2);
        expect(store.lastStorageError, isNull);
        final persisted = await readPersistedRecords(tempDir);
        expect((persisted.single as Map<String, dynamic>)['id'], 'retry-ok');
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test('app provides store and network inspector reads injection point', () {
      final mainSource = File('lib/main.dart').readAsStringSync();
      final pageSource =
          File('lib/pages/network_inspector_page.dart').readAsStringSync();

      expect(
        mainSource,
        contains('legacy_provider.ChangeNotifierProvider.value('),
      );
      expect(mainSource, contains('value: httpInspectorStore'));
      expect(pageSource, contains('context.read<HttpInspectorStore?>()'));
      expect(pageSource, contains('nextStore'));
    });
  });
}
