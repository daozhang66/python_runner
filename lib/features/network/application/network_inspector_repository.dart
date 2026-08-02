import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/infrastructure_providers.dart';
import '../../../services/http_inspector_store.dart';

/// 网络检查器数据访问接口（Level 0 交付物）。
///
/// 计划 §4.5：底层文件持久化、导出与已有 [HttpInspectorStore] 单例暂时保留，
/// 本接口作为展示态外观，供 Level 4 的 Controller（`networkInspectorControllerProvider`）
/// 与页面通过 Riverpod 访问。本接口**不复制**记录或持久化逻辑，仅委托单例。
///
/// 变更通知沿用 [ChangeNotifier] 语义（addListener/removeListener），Level 4
/// Controller 通过 `ref.onDispose` 解绑并把通知映射为状态快照。
abstract interface class NetworkInspectorRepository implements Listenable {
  // --- 记录与统计 ---

  List<HttpRecord> get records;

  int get count;

  Map<String, dynamic> get stats;

  Map<String, dynamic> get visibleStats;

  List<MapEntry<String, int>> get domainStats;

  int get hiddenNoiseCount;

  bool get isLoaded;

  Object? get lastStorageError;

  // --- 过滤（内存态，不持久化） ---

  List<HttpRecord> get filteredRecords;

  String get filterDomain;

  String get filterMethod;

  int? get filterStatus;

  bool get hideNoiseMethods;

  void setFilterDomain(String value);

  void setFilterMethod(String value);

  void setFilterStatus(int? value);

  void setHideNoiseMethods(bool value);

  void clearFilters();

  // --- 写入 / 生命周期 ---

  void addFromJson(Map<String, dynamic> json);

  void clear();

  Future<void> ensureLoaded();

  Future<void> loadDisplayPreferences();

  Future<void> flush();

  // --- 导出 ---

  String exportAll();

  String exportFiltered();

  String exportHar({bool filteredOnly = false});
}

/// 生产实现：薄包装 [HttpInspectorStore] 单例。
///
/// 所有方法直接转发到 store；不引入额外状态。计划允许单例本体保留，因此
/// 本类不重建持久化或统计聚合逻辑。
class HttpInspectorRepository implements NetworkInspectorRepository {
  HttpInspectorRepository(this._store);

  final HttpInspectorStore _store;

  @override
  void addListener(VoidCallback listener) => _store.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _store.removeListener(listener);

  @override
  List<HttpRecord> get records => _store.records;

  @override
  int get count => _store.count;

  @override
  Map<String, dynamic> get stats => _store.stats;

  @override
  Map<String, dynamic> get visibleStats => _store.visibleStats;

  @override
  List<MapEntry<String, int>> get domainStats => _store.domainStats;

  @override
  int get hiddenNoiseCount => _store.hiddenNoiseCount;

  @override
  bool get isLoaded => _store.isLoaded;

  @override
  Object? get lastStorageError => _store.lastStorageError;

  @override
  List<HttpRecord> get filteredRecords => _store.filteredRecords;

  @override
  String get filterDomain => _store.filterDomain;

  @override
  String get filterMethod => _store.filterMethod;

  @override
  int? get filterStatus => _store.filterStatus;

  @override
  bool get hideNoiseMethods => _store.hideNoiseMethods;

  @override
  void setFilterDomain(String value) => _store.setFilterDomain(value);

  @override
  void setFilterMethod(String value) => _store.setFilterMethod(value);

  @override
  void setFilterStatus(int? value) => _store.setFilterStatus(value);

  @override
  void setHideNoiseMethods(bool value) => _store.setHideNoiseMethods(value);

  @override
  void clearFilters() => _store.clearFilters();

  @override
  void addFromJson(Map<String, dynamic> json) => _store.addFromJson(json);

  @override
  void clear() => _store.clear();

  @override
  Future<void> ensureLoaded() => _store.ensureLoaded();

  @override
  Future<void> loadDisplayPreferences() => _store.loadDisplayPreferences();

  @override
  Future<void> flush() => _store.flush();

  @override
  String exportAll() => _store.exportAll();

  @override
  String exportFiltered() => _store.exportFiltered();

  @override
  String exportHar({bool filteredOnly = false}) =>
      _store.exportHar(filteredOnly: filteredOnly);
}

/// 网络检查器 Repository Provider。包装单例；测试通过 override 注入 fake。
final networkInspectorRepositoryProvider =
    Provider<NetworkInspectorRepository>((ref) {
  return HttpInspectorRepository(ref.watch(httpInspectorStoreProvider));
});
