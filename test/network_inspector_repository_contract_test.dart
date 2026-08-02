import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/services/http_inspector_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/network_inspector_test_helper.dart';

/// FakeNetworkInspectorRepository 契约测试：验证记录、过滤、统计派生与通知
/// 符合 [NetworkInspectorRepository] 契约，保证 Level 4 Controller 单测可信赖本 fake。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  HttpRecord record(
    String id, {
    String method = 'GET',
    String url = 'https://example.com/api',
    int? statusCode = 200,
    int? durationMs = 100,
  }) =>
      HttpRecord(
        id: id,
        timestamp: DateTime(2026, 1, 1),
        method: method,
        url: url,
        requestHeaders: const {},
        statusCode: statusCode,
        durationMs: durationMs,
      );

  Map<String, dynamic> recordJson(
    String id, {
    String method = 'get',
    String url = 'https://example.com/api',
    int? statusCode = 200,
    int? durationMs = 100,
  }) =>
      {
        'id': id,
        'timestamp': 1710000000000,
        'method': method,
        'url': url,
        'request_headers': const {},
        if (statusCode != null) 'status_code': statusCode,
        if (durationMs != null) 'duration_ms': durationMs,
      };

  group('FakeNetworkInspectorRepository records', () {
    test('addFromJson appends a record and notifies', () async {
      final repo = FakeNetworkInspectorRepository();
      var notifications = 0;
      repo.addListener(() => notifications++);
      addTearDown(repo.dispose);

      repo.addFromJson(recordJson('req-1'));
      expect(repo.addFromJsonCount, 1);
      expect(repo.count, 1);
      expect(repo.records.single.id, 'req-1');
      expect(notifications, 1);
    });

    test('clear empties records and notifies', () {
      final repo = FakeNetworkInspectorRepository(
        records: [record('req-1')],
      );
      addTearDown(repo.dispose);
      var notifications = 0;
      repo.addListener(() => notifications++);

      repo.clear();
      expect(repo.clearCount, 1);
      expect(repo.count, 0);
      expect(notifications, 1);
    });

    test('listeners can be removed without a secondary notification channel',
        () {
      final repo = FakeNetworkInspectorRepository();
      addTearDown(repo.dispose);
      var notifications = 0;
      void listener() => notifications++;
      repo.addListener(listener);
      repo.removeListener(listener);

      repo.addFromJson(recordJson('req-1'));

      expect(notifications, 0);
    });

    test('ensureLoaded sets isLoaded flag', () async {
      final repo = FakeNetworkInspectorRepository();
      addTearDown(repo.dispose);
      expect(repo.isLoaded, isFalse);
      await repo.ensureLoaded();
      expect(repo.ensureLoadedCount, 1);
      expect(repo.isLoaded, isTrue);
    });

    test('loadDisplayPreferences applies default hide-noise preference',
        () async {
      final repo =
          FakeNetworkInspectorRepository(hideNoiseMethodsDefault: false);
      addTearDown(repo.dispose);
      await repo.loadDisplayPreferences();
      expect(repo.loadDisplayPreferencesCount, 1);
      expect(repo.hideNoiseMethods, isFalse);
    });
  });

  group('FakeNetworkInspectorRepository stats', () {
    test('stats aggregates success/error and average duration', () {
      final repo = FakeNetworkInspectorRepository(records: [
        record('a', statusCode: 200, durationMs: 100),
        record('b', statusCode: 500, durationMs: 300),
      ]);
      addTearDown(repo.dispose);

      final stats = repo.stats;
      expect(stats['total'], 2);
      expect(stats['success'], 1);
      expect(stats['error'], 1);
      expect(stats['avgMs'], 200);
    });

    test('domainStats counts by domain sorted desc', () {
      final repo = FakeNetworkInspectorRepository(records: [
        record('a', url: 'https://a.com/x'),
        record('b', url: 'https://a.com/y'),
        record('c', url: 'https://b.com/z'),
      ]);
      addTearDown(repo.dispose);

      final domains = Map.fromEntries(
        repo.domainStats.map((e) => MapEntry(e.key, e.value)),
      );
      expect(domains['a.com'], 2);
      expect(domains['b.com'], 1);
      // 排序：a.com (2) 在 b.com (1) 之前。
      expect(repo.domainStats.first.key, 'a.com');
    });
  });

  group('FakeNetworkInspectorRepository filters', () {
    test('filteredRecords applies domain and method filters', () {
      final repo = FakeNetworkInspectorRepository(records: [
        record('a', method: 'GET', url: 'https://a.com/x'),
        record('b', method: 'POST', url: 'https://b.com/y'),
      ]);
      addTearDown(repo.dispose);
      repo.setFilterDomain('a.com');
      repo.setFilterMethod('get');
      expect(repo.filteredRecords.map((r) => r.id), ['a']);
    });

    test('status filter 0 returns only errors', () {
      final repo = FakeNetworkInspectorRepository(records: [
        record('ok', statusCode: 200),
        record('err', statusCode: 500),
      ]);
      addTearDown(repo.dispose);
      repo.setFilterStatus(0);
      expect(repo.filteredRecords.single.id, 'err');
    });

    test('hideNoiseMethods hides DNS-like methods', () {
      final repo = FakeNetworkInspectorRepository(records: [
        record('dns', method: 'DNS'),
        record('get', method: 'GET'),
      ]);
      addTearDown(repo.dispose);
      repo.setHideNoiseMethods(true);
      expect(repo.filteredRecords.map((r) => r.id), ['get']);
      expect(repo.hiddenNoiseCount, 1);
    });

    test('selecting a noise method disables hide-noise preference', () {
      final repo = FakeNetworkInspectorRepository(records: [
        record('dns', method: 'DNS'),
        record('get', method: 'GET'),
      ]);
      addTearDown(repo.dispose);
      expect(repo.hideNoiseMethods, isTrue);
      repo.setFilterMethod('dns');
      expect(repo.hideNoiseMethods, isFalse, reason: '选择噪声方法时应自动关闭隐藏偏好');
      expect(repo.filteredRecords.map((r) => r.id), ['dns']);
    });

    test('clearFilters resets all filters', () {
      final repo = FakeNetworkInspectorRepository(records: [
        record('a', url: 'https://a.com/x'),
      ]);
      addTearDown(repo.dispose);
      repo.setFilterDomain('a.com');
      repo.setFilterMethod('get');
      repo.setFilterStatus(200);
      repo.clearFilters();
      expect(repo.filterDomain, isEmpty);
      expect(repo.filterMethod, isEmpty);
      expect(repo.filterStatus, isNull);
    });
  });
}
