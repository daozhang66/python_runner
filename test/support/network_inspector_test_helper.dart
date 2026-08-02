import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:python_runner/features/network/application/network_inspector_repository.dart';
import 'package:python_runner/services/http_inspector_store.dart';

/// 构建一个绑定到 [FakeNetworkInspectorRepository] 的 [ProviderContainer]，
/// 供 Level 4 网络检查器 Controller 单测使用。调用方负责 `container.dispose()`。
ProviderContainer buildNetworkInspectorContainer({
  FakeNetworkInspectorRepository? repository,
  List<Override> overrides = const [],
}) {
  final repo = repository ?? FakeNetworkInspectorRepository();
  return ProviderContainer(
    overrides: [
      ...overrides,
      networkInspectorRepositoryProvider.overrideWithValue(repo),
    ],
  );
}

/// 测试用 [NetworkInspectorRepository]。
///
/// 用内存列表模拟记录与统计，并复刻 [HttpInspectorStore] 的过滤/统计派生逻辑
/// （domain/method/status/noise）。继承 [ChangeNotifier] 的通知机制，Level 4
/// Controller 可通过 addListener 观察变更。
class FakeNetworkInspectorRepository extends ChangeNotifier
    implements NetworkInspectorRepository {
  FakeNetworkInspectorRepository({
    List<HttpRecord>? records,
    this.hideNoiseMethodsDefault = true,
  })  : _records = List<HttpRecord>.from(records ?? const []),
        _hideNoiseMethods = hideNoiseMethodsDefault;

  final List<HttpRecord> _records;

  String _filterDomain = '';
  String _filterMethod = '';
  int? _filterStatus;
  bool _hideNoiseMethods;

  final bool hideNoiseMethodsDefault;

  // 可观测计数器。
  int addFromJsonCount = 0;
  int clearCount = 0;
  int ensureLoadedCount = 0;
  int loadDisplayPreferencesCount = 0;
  int flushCount = 0;

  bool _isLoaded = false;

  // --- 记录与统计 ---

  @override
  List<HttpRecord> get records => List.unmodifiable(_records);

  @override
  int get count => _records.length;

  @override
  bool get isLoaded => _isLoaded;

  @override
  Object? get lastStorageError => null;

  @override
  Map<String, dynamic> get stats {
    var success = 0;
    var error = 0;
    var totalDuration = 0;
    var durationCount = 0;
    for (final r in _records) {
      if (r.isError) {
        error++;
      } else {
        success++;
      }
      if (r.durationMs != null) {
        totalDuration += r.durationMs!;
        durationCount++;
      }
    }
    return {
      'total': _records.length,
      'success': success,
      'error': error,
      'avgMs':
          durationCount > 0 ? (totalDuration / durationCount).round() : null,
    };
  }

  @override
  Map<String, dynamic> get visibleStats => _statsFor(filteredRecords);

  @override
  int get hiddenNoiseCount =>
      _hideNoiseMethods ? _records.where(_isNoiseRecord).length : 0;

  @override
  List<HttpRecord> get filteredRecords {
    var list = _recordsForCurrentNoisePreference().reversed.toList();
    if (_filterDomain.isNotEmpty) {
      final d = _filterDomain.toLowerCase();
      list = list.where((r) => r.url.toLowerCase().contains(d)).toList();
    }
    if (_filterMethod.isNotEmpty) {
      list =
          list.where((r) => r.method == _filterMethod.toUpperCase()).toList();
    }
    if (_filterStatus != null) {
      if (_filterStatus == 0) {
        list = list.where((r) => r.isError).toList();
      } else {
        final base = _filterStatus!;
        list = list
            .where((r) =>
                r.statusCode != null &&
                r.statusCode! >= base &&
                r.statusCode! < base + 100)
            .toList();
      }
    }
    return list;
  }

  @override
  List<MapEntry<String, int>> get domainStats {
    final counts = <String, int>{};
    for (final r in _recordsForCurrentNoisePreference()) {
      final d = r.domain;
      if (d.isNotEmpty) counts[d] = (counts[d] ?? 0) + 1;
    }
    return counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

  Map<String, dynamic> _statsFor(List<HttpRecord> records) {
    var success = 0;
    var error = 0;
    var totalDuration = 0;
    var durationCount = 0;
    for (final r in records) {
      if (r.isError) {
        error++;
      } else {
        success++;
      }
      if (r.durationMs != null) {
        totalDuration += r.durationMs!;
        durationCount++;
      }
    }
    return {
      'total': records.length,
      'success': success,
      'error': error,
      'avgMs':
          durationCount > 0 ? (totalDuration / durationCount).round() : null,
    };
  }

  List<HttpRecord> _recordsForCurrentNoisePreference() {
    return _hideNoiseMethods
        ? _records.where((r) => !_isNoiseRecord(r)).toList()
        : List<HttpRecord>.from(_records);
  }

  bool _isNoiseRecord(HttpRecord r) =>
      HttpInspectorStore.isNoiseMethod(r.method);

  // --- 过滤 ---

  @override
  String get filterDomain => _filterDomain;

  @override
  String get filterMethod => _filterMethod;

  @override
  int? get filterStatus => _filterStatus;

  @override
  bool get hideNoiseMethods => _hideNoiseMethods;

  @override
  void setFilterDomain(String value) {
    _filterDomain = value;
    notifyListeners();
  }

  @override
  void setFilterMethod(String value) {
    _filterMethod = value.trim().toUpperCase();
    if (_hideNoiseMethods && HttpInspectorStore.isNoiseMethod(_filterMethod)) {
      _hideNoiseMethods = false;
    }
    notifyListeners();
  }

  @override
  void setFilterStatus(int? value) {
    _filterStatus = value;
    notifyListeners();
  }

  @override
  void setHideNoiseMethods(bool value) {
    if (_hideNoiseMethods == value) return;
    _hideNoiseMethods = value;
    notifyListeners();
  }

  @override
  void clearFilters() {
    _filterDomain = '';
    _filterMethod = '';
    _filterStatus = null;
    notifyListeners();
  }

  // --- 写入 / 生命周期 ---

  @override
  void addFromJson(Map<String, dynamic> json) {
    addFromJsonCount++;
    // 复刻真实 store 的守卫：note 记录与空 URL 记录直接丢弃。
    if (json['note'] != null) return;
    final record = HttpRecord.fromJson(json);
    if (record.url.isEmpty) return;
    _records.add(record);
    notifyListeners();
  }

  @override
  void clear() {
    clearCount++;
    _records.clear();
    notifyListeners();
  }

  @override
  Future<void> ensureLoaded() async {
    ensureLoadedCount++;
    _isLoaded = true;
  }

  @override
  Future<void> loadDisplayPreferences() async {
    loadDisplayPreferencesCount++;
    _hideNoiseMethods = hideNoiseMethodsDefault;
    // 与真实 store 一致：偏好加载后通知监听者刷新。
    notifyListeners();
  }

  @override
  Future<void> flush() async {
    flushCount++;
  }

  // --- 导出 ---

  @override
  String exportAll() => _records.map(_formatRecord).join('\n');

  @override
  String exportFiltered() => filteredRecords.map(_formatRecord).join('\n');

  @override
  String exportHar({bool filteredOnly = false}) => '{"log":{"entries":[]}}';

  String _formatRecord(HttpRecord r) =>
      '${r.method} ${r.url} -> ${r.statusCode ?? r.errorType ?? '?'}';
}
