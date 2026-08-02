import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/package_info.dart';
import '../../../providers/infrastructure_providers.dart';
import '../../../providers/theme_provider.dart' show sharedPreferencesProvider;
import '../../../runtime/runtime_manager.dart';
import '../../../runtime/runtime_package.dart';
import '../../../services/app_logger.dart';

/// 包管理数据访问接口。
///
/// Controller 仅依赖此抽象，生产实现 [RuntimePackageRepository] 把
/// `RuntimeManager` + `SharedPreferences` 包缓存组合为单一数据源；测试通过
/// `ProviderScope.overrides` 注入 [FakePackageRepository]，避免依赖原生桥接。
///
/// 不复制 [RuntimePackage] / [PackageInstallRequest] 等运行时模型，Repository
/// 直接转发它们，保持与现有 runtime 层模型一致。
abstract class PackageRepository {
  /// 当前运行引擎后端标识（chaquopy / linux_like）。
  String get activeBackendId;

  /// 是否支持 requirements.txt 批量安装（仅 Linux-like）。
  bool get supportsRequirementsInstall;

  /// 安装进度事件流。Repository 负责暴露原始流，Controller 持有订阅。
  Stream<PackageInstallProgress> get packageInstallProgressStream;

  /// 列出当前后端已安装的全部包。
  Future<List<RuntimePackage>> listPackages();

  /// 安装单个包。
  Future<PackageInstallResult> installPackage(PackageInstallRequest request);

  /// 修复（重装）单个包。
  Future<PackageInstallResult> repairPackage(PackageInstallRequest request);

  /// 按项目 requirements 安装依赖。
  Future<PackageInstallResult> installRequirements(
    RequirementsInstallRequest request,
  );

  /// 卸载包，返回清理详情。
  Future<PackageUninstallResult> uninstallPackage(String packageName);

  /// 读取上次缓存到磁盘的包快照（按当前后端键隔离）。
  ///
  /// 返回空列表表示无缓存。Repository 实现内部处理解码异常，保证不抛出。
  Future<List<PackageInfo>> restoreCachedPackages();

  /// 把当前包列表缓存到磁盘。失败仅记录日志，不抛出。
  Future<void> savePackageCache(List<PackageInfo> packages);

  /// 释放底层资源（如有）。默认空实现。
  void dispose() {}
}

/// 生产实现：把 [RuntimeManager] 与 `SharedPreferences` 包缓存组合为 Repository。
///
/// 包缓存键、字段和排序与迁移前的 legacy ChangeNotifier 完全一致，保证回滚后缓存
/// 仍可读取。本类不持有订阅；订阅由 Controller 负责。
class RuntimePackageRepository implements PackageRepository {
  RuntimePackageRepository({
    required RuntimeManager runtimeManager,
    required SharedPreferences preferences,
    AppLogger? logger,
  })  : _runtimeManager = runtimeManager,
        _preferences = preferences,
        _logger = logger ?? AppLogger.instance;

  final RuntimeManager _runtimeManager;
  final SharedPreferences _preferences;
  final AppLogger _logger;

  @override
  String get activeBackendId => _runtimeManager.activeBackendId;

  @override
  bool get supportsRequirementsInstall =>
      activeBackendId == RuntimeManager.linuxLikeBackendId;

  @override
  Stream<PackageInstallProgress> get packageInstallProgressStream =>
      _runtimeManager.packageInstallProgressStream;

  @override
  Future<List<RuntimePackage>> listPackages() => _runtimeManager.listPackages();

  @override
  Future<PackageInstallResult> installPackage(
    PackageInstallRequest request,
  ) =>
      _runtimeManager.installPackage(request);

  @override
  Future<PackageInstallResult> repairPackage(
    PackageInstallRequest request,
  ) =>
      _runtimeManager.repairPackage(request);

  @override
  Future<PackageInstallResult> installRequirements(
    RequirementsInstallRequest request,
  ) =>
      _runtimeManager.installRequirements(request);

  @override
  Future<PackageUninstallResult> uninstallPackage(String packageName) =>
      _runtimeManager.uninstallPackage(packageName);

  String get _cacheKey => 'package_cache_${_runtimeManager.activeBackendId}';

  @override
  Future<List<PackageInfo>> restoreCachedPackages() async {
    try {
      final raw = _preferences.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(_packageInfoFromCache)
          .where((item) => item.name.isNotEmpty)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    } catch (e) {
      _logger.warn('restore package cache error: $e', source: 'PackageRepository');
      return const [];
    }
  }

  @override
  Future<void> savePackageCache(List<PackageInfo> packages) async {
    try {
      final encoded = jsonEncode(packages
          .map((item) => {
                'name': item.name,
                'version': item.version,
                'isUserPackage': item.isUserPackage,
                'integrityStatus': item.integrityStatus,
                'integrityMessage': item.integrityMessage,
                'missingImports': item.missingImports,
              })
          .toList());
      await _preferences.setString(_cacheKey, encoded);
    } catch (e) {
      _logger.warn('save package cache error: $e', source: 'PackageRepository');
    }
  }

  @override
  void dispose() {
    // 生产实现依赖 Riverpod 管理的 RuntimeManager，这里不主动释放其内部资源；
    // 留作子类/未来扩展点。
  }

  PackageInfo _packageInfoFromCache(Map<dynamic, dynamic> item) {
    return PackageInfo(
      name: item['name']?.toString() ?? '',
      version: item['version']?.toString() ?? '',
      isUserPackage: item['isUserPackage'] == true,
      integrityStatus: item['integrityStatus']?.toString() ?? 'unknown',
      integrityMessage: item['integrityMessage']?.toString() ?? '',
      missingImports: _stringListFromCache(item['missingImports']),
    );
  }

  List<String> _stringListFromCache(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    if (value is String) {
      return value
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }
}

/// 生产用 [PackageRepository] Provider。测试通过 override 注入 fake。
final packageRepositoryProvider = Provider<PackageRepository>((ref) {
  final repository = RuntimePackageRepository(
    runtimeManager: ref.watch(runtimeManagerProvider),
    preferences: ref.watch(sharedPreferencesProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});
