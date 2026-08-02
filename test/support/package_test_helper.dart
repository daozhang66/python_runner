import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:python_runner/features/packages/application/package_repository.dart';
import 'package:python_runner/models/package_info.dart';
import 'package:python_runner/runtime/runtime_package.dart';

/// 构建一个绑定到 [FakePackageRepository] 的 [ProviderContainer]，用于包管理
/// Controller 单元测试。
///
/// 默认使用空的 `SharedPreferences`；传入 [preferences] 可固定缓存内容或运行
/// 引擎偏好。调用方负责 [ProviderContainer.dispose]（通常通过 `tearDown` 或
/// `addTearDown(container.dispose)`）。
ProviderContainer buildPackageContainer({
  FakePackageRepository? repository,
  List<Override> overrides = const [],
}) {
  final repo = repository ?? FakePackageRepository();
  return ProviderContainer(
    overrides: [
      ...overrides,
      // 直接用 fake repository 屏蔽底层 RuntimeManager / SharedPreferences 依赖，
      // 因此 Controller 测试不需要真实原生桥接。
      packageRepositoryProvider.overrideWithValue(repo),
    ],
  );
}

/// 测试用 [PackageRepository]。
///
/// 通过 `StreamController` 模拟安装进度事件，通过可变列表模拟已安装包；每个
/// 命令方法都暴露计数器和最近请求，便于断言调用参数、并发覆盖与异常转换。
class FakePackageRepository implements PackageRepository {
  FakePackageRepository({
    List<RuntimePackage> packages = const [],
    this.activeBackendId = 'fake',
    this.supportsRequirementsInstall = false,
    this.listPackagesError,
    PackageInstallResult? installResult,
    PackageInstallResult? repairResult,
    PackageInstallResult? requirementsResult,
    PackageUninstallResult? uninstallResult,
    this.listPackagesCompleter,
    List<RuntimePackage> packagesAfterInstall = const [],
    List<RuntimePackage> packagesAfterRepair = const [],
    List<RuntimePackage> packagesAfterRequirements = const [],
    Map<String, PackageInfo>? cachedPackages,
  })  : _packages = List<RuntimePackage>.from(packages),
        _installResult = installResult,
        _repairResult = repairResult,
        _requirementsResult = requirementsResult,
        _uninstallResult = uninstallResult,
        _packagesAfterInstall = List<RuntimePackage>.from(packagesAfterInstall),
        _packagesAfterRepair = List<RuntimePackage>.from(packagesAfterRepair),
        _packagesAfterRequirements =
            List<RuntimePackage>.from(packagesAfterRequirements),
        _cachedPackages = Map<String, PackageInfo>.from(cachedPackages ?? {});

  final List<RuntimePackage> _packages;
  PackageInstallResult? _installResult;
  PackageInstallResult? _repairResult;
  PackageInstallResult? _requirementsResult;
  PackageUninstallResult? _uninstallResult;
  final List<RuntimePackage> _packagesAfterInstall;
  final List<RuntimePackage> _packagesAfterRepair;
  final List<RuntimePackage> _packagesAfterRequirements;
  final Map<String, PackageInfo> _cachedPackages;

  @override
  final String activeBackendId;

  @override
  final bool supportsRequirementsInstall;

  Object? listPackagesError;
  Completer<List<RuntimePackage>>? listPackagesCompleter;

  // Observability counters for assertions.
  int listPackagesCallCount = 0;
  int installCallCount = 0;
  int repairCallCount = 0;
  int requirementsInstallCount = 0;
  int uninstallCallCount = 0;
  PackageInstallRequest? lastInstallRequest;
  PackageInstallRequest? lastRepairRequest;
  RequirementsInstallRequest? lastRequirementsRequest;
  String? lastUninstallName;

  // Backing fields for cached packages exposed to the controller.
  List<PackageInfo> savedCache = const [];

  final StreamController<PackageInstallProgress> _progressController =
      StreamController<PackageInstallProgress>.broadcast();

  @override
  Stream<PackageInstallProgress> get packageInstallProgressStream =>
      _progressController.stream;

  /// 推送一条安装进度事件（测试驱动用）。
  void emitProgress(PackageInstallProgress event) =>
      _progressController.add(event);

  void setInstallResult(PackageInstallResult result) => _installResult = result;
  void setRepairResult(PackageInstallResult result) => _repairResult = result;
  void setRequirementsResult(PackageInstallResult result) =>
      _requirementsResult = result;
  void setUninstallResult(PackageUninstallResult result) =>
      _uninstallResult = result;

  @override
  Future<List<RuntimePackage>> listPackages() async {
    listPackagesCallCount++;
    final error = listPackagesError;
    if (error != null) throw error;
    return listPackagesCompleter?.future ??
        List<RuntimePackage>.from(_packages);
  }

  @override
  Future<PackageInstallResult> installPackage(
    PackageInstallRequest request,
  ) async {
    lastInstallRequest = request;
    installCallCount++;
    _packages
      ..clear()
      ..addAll(_packagesAfterInstall);
    return _installResult ??
        PackageInstallResult(
          success: true,
          message: '安装成功: ${request.packageName}',
        );
  }

  @override
  Future<PackageInstallResult> repairPackage(
    PackageInstallRequest request,
  ) async {
    lastRepairRequest = request;
    repairCallCount++;
    _packages
      ..clear()
      ..addAll(_packagesAfterRepair);
    return _repairResult ??
        PackageInstallResult(
          success: true,
          message: '修复成功: ${request.packageName}',
        );
  }

  @override
  Future<PackageInstallResult> installRequirements(
    RequirementsInstallRequest request,
  ) async {
    lastRequirementsRequest = request;
    requirementsInstallCount++;
    _packages
      ..clear()
      ..addAll(_packagesAfterRequirements);
    return _requirementsResult ??
        const PackageInstallResult(
          success: true,
          message: 'requirements.txt 安装成功',
        );
  }

  @override
  Future<PackageUninstallResult> uninstallPackage(String packageName) async {
    lastUninstallName = packageName;
    uninstallCallCount++;
    final result = _uninstallResult ??
        const PackageUninstallResult(success: true, message: '卸载成功');
    _packages.removeWhere((item) => item.name == packageName);
    // 与 RuntimeBackend 行为一致：后端清理的依赖也一并从列表移除。
    for (final dependency in result.removedDependencies) {
      _packages.removeWhere((item) => item.name == dependency);
    }
    return result;
  }

  @override
  Future<List<PackageInfo>> restoreCachedPackages() async {
    return List<PackageInfo>.from(_cachedPackages.values)
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Future<void> savePackageCache(List<PackageInfo> packages) async {
    savedCache = List<PackageInfo>.from(packages);
  }

  @override
  void dispose() {
    _progressController.close();
  }
}
