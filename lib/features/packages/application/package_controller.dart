import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/package_info.dart';
import '../../../runtime/runtime_package.dart';
import '../../../services/app_logger.dart';
import 'package_repository.dart';
import 'package_state.dart';

/// 包管理业务 Controller（单一状态所有者）。
///
/// 行为与迁移前的 legacy ChangeNotifier 完全对齐：
/// - 首次空数据加载用全屏 loading，已有缓存时仅后台刷新。
/// - `ensureLoaded` 在同一后端下只触发一次真实加载。
/// - 加载/安装使用 generation 防止旧请求覆盖新状态。
/// - 安装进度流订阅由本 Controller 持有，`ref.onDispose` 释放。
/// - 安装日志在成功/失败 5 秒后自动清空。
///
/// 页面通过 `ref.watch(packageControllerProvider.select(...))` 局部监听列表、
/// 安装状态或日志；命令方法返回 Future，供调用方显示 SnackBar。
final packageControllerProvider =
    NotifierProvider<PackageController, PackageState>(PackageController.new);

final _packageControllerRetentionProvider =
    Provider<_PackageControllerRetention>((ref) {
  final retention = _PackageControllerRetention();
  ref.onDispose(retention.dispose);
  return retention;
});

class _PackageControllerRetention {
  PackageState? state;
  String? backendId;
  bool hasLoadedOnce = false;
  int loadGeneration = 0;
  int backendGeneration = 0;
  Timer? installLogClearTimer;
  void Function()? clearInstallLog;

  void dispose() {
    installLogClearTimer?.cancel();
  }
}

class PackageController extends Notifier<PackageState> {
  PackageController();

  late PackageRepository _repository;
  late _PackageControllerRetention _retention;
  StreamSubscription<PackageInstallProgress>? _installProgressSub;
  Future<void>? _inFlightLoad;

  /// 安装日志自动清空延迟，与迁移前 legacy ChangeNotifier 一致。
  static const installLogClearDelay = Duration(seconds: 5);

  @override
  PackageState build() {
    final repository = ref.watch(packageRepositoryProvider);
    final backendId = repository.activeBackendId;
    final retention = ref.read(_packageControllerRetentionProvider);
    final backendChanged =
        retention.backendId != null && retention.backendId != backendId;

    _installProgressSub?.cancel();
    if (backendChanged) {
      retention.loadGeneration++;
      _inFlightLoad = null;
      retention.installLogClearTimer?.cancel();
      retention.backendGeneration++;
      retention.hasLoadedOnce = false;
      retention.state = null;
    }

    _repository = repository;
    _retention = retention;
    retention.backendId = backendId;
    _listenInstallProgress(backendId);

    final nextState = !backendChanged && retention.state != null
        ? retention.state!.copyWith(
            activeBackendId: backendId,
            supportsRequirementsInstall: repository.supportsRequirementsInstall,
          )
        : PackageState(
            activeBackendId: backendId,
            supportsRequirementsInstall: repository.supportsRequirementsInstall,
          );
    retention.state = nextState;
    retention.clearInstallLog = _clearInstallLogFromTimer;
    ref.onDispose(_cleanup);
    if (backendChanged) {
      _scheduleBackendLoad(backendId, retention.backendGeneration);
    }
    return nextState;
  }

  void _setState(PackageState nextState) {
    _retention.state = nextState;
    state = nextState;
  }

  void _clearInstallLogFromTimer() {
    _setState(state.copyWith(installLog: const []));
  }

  void _cleanup() {
    _installProgressSub?.cancel();
  }

  void _listenInstallProgress(String backendId) {
    _installProgressSub?.cancel();
    _installProgressSub = _repository.packageInstallProgressStream.listen(
      (data) {
        if (_retention.backendId == backendId) {
          _onInstallProgress(data);
        }
      },
      onError: (Object e) {
        if (_retention.backendId == backendId) {
          AppLogger.instance
              .warn('installProgress error: $e', source: 'PackageController');
        }
      },
    );
  }

  void _scheduleBackendLoad(String backendId, int backendGeneration) {
    scheduleMicrotask(() {
      if (_retention.backendId != backendId ||
          _retention.backendGeneration != backendGeneration) {
        return;
      }
      unawaited(ensureLoaded());
    });
  }

  void _onInstallProgress(PackageInstallProgress data) {
    final status = data.status;
    final message = data.message;
    if (message.isNotEmpty) {
      _setState(state.copyWith(installLog: [...state.installLog, message]));
    }

    if (status == 'success') {
      _setState(state.copyWith(isInstalling: false));
      unawaited(refresh());
      _scheduleInstallLogClear();
    } else if (status == 'error') {
      _setState(state.copyWith(isInstalling: false));
      _scheduleInstallLogClear();
    }
  }

  /// 首次进入页面或切到库管理 Tab 时调用。同一后端下只加载一次。
  Future<void> ensureLoaded() async {
    if (state.isRefreshing || state.isInitialLoading) return;
    if (_retention.hasLoadedOnce) return;
    await _load(forceRefresh: false);
  }

  /// 强制重新拉取包列表，忽略缓存。
  Future<void> refresh() => _load(forceRefresh: true);

  Future<void> _load({required bool forceRefresh}) {
    final existing = _inFlightLoad;
    if (existing != null) return existing;

    late final Future<void> load;
    load = _performLoad(forceRefresh: forceRefresh).whenComplete(() {
      if (identical(_inFlightLoad, load)) {
        _inFlightLoad = null;
      }
    });
    _inFlightLoad = load;
    return load;
  }

  Future<void> _performLoad({required bool forceRefresh}) async {
    final repository = _repository;
    final backendId = _retention.backendId;
    final generation = ++_retention.loadGeneration;
    try {
      // 先尝试恢复缓存，给出可操作内容。
      if (!forceRefresh && state.packages.isEmpty) {
        final cached = await repository.restoreCachedPackages();
        if (!_isCurrentLoad(generation, backendId)) return;
        if (cached.isNotEmpty) {
          _setState(state.copyWith(
            packages: cached,
            clearLoadError: true,
            isInitialLoading: false,
          ));
        }
      }

      final isFirstLoad = !_retention.hasLoadedOnce && state.packages.isEmpty;
      _setState(state.copyWith(
        isInitialLoading: isFirstLoad,
        isRefreshing: !isFirstLoad,
        clearLoadError: true,
      ));

      final result = await repository.listPackages();
      if (!_isCurrentLoad(generation, backendId)) return;
      final packages = result.map(_packageInfoFromRuntime).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      _retention.hasLoadedOnce = true;
      _setState(state.copyWith(
        packages: packages,
        isInitialLoading: false,
        isRefreshing: false,
        clearLoadError: true,
      ));
      // 缓存写入不阻塞 UI，且失败仅记录日志。
      unawaited(repository.savePackageCache(packages));
    } catch (e) {
      if (!_isCurrentLoad(generation, backendId)) return;
      _setState(state.copyWith(
        isInitialLoading: false,
        isRefreshing: false,
        loadError: e.toString(),
      ));
      AppLogger.instance
          .warn('loadPackages error: $e', source: 'PackageController');
    }
  }

  bool _isCurrentLoad(int generation, String? backendId) {
    return generation == _retention.loadGeneration &&
        backendId == _retention.backendId;
  }

  /// 安装单个包。
  ///
  /// 与 legacy ChangeNotifier 的差异：此处新增了入口并发守卫，拒绝在已有
  /// 安装进行中再次调用后端（legacy 仅在 repair/requirements 有此守卫，install
  /// 没有）。这是有意的健壮性改进，[package_controller_test] 的"并发安装拒绝"
  /// 用例锁定此行为。
  Future<void> install(
    String name, {
    String? version,
    String? indexUrl,
  }) async {
    if (state.isInstalling) {
      _appendInstallLog('已有安装任务进行中，请稍后再试');
      return;
    }
    _setState(state.copyWith(
      isInstalling: true,
      installLog: [
        'Installing $name${version != null ? "==$version" : ""}...',
      ],
    ));

    try {
      final result = await _repository.installPackage(
        PackageInstallRequest(
          packageName: name,
          version: version,
          indexUrl: indexUrl,
        ),
      );
      await _handleInstallResult(
        result,
        successMessage: '安装成功: $name',
        failureMessage: '安装失败: $name',
      );
    } catch (e) {
      _failInstall('Error: $e');
    }
  }

  /// 修复（重装）单个包。
  Future<void> repair(
    String name, {
    String? version,
    String? indexUrl,
  }) async {
    if (state.isInstalling) {
      _appendInstallLog('已有安装任务进行中，请稍后再试');
      return;
    }
    final fixedVersion = version?.trim();
    _setState(state.copyWith(
      isInstalling: true,
      installLog: [
        'Repairing $name'
            '${fixedVersion == null || fixedVersion.isEmpty ? "" : "==$fixedVersion"}...',
      ],
    ));

    try {
      final result = await _repository.repairPackage(
        PackageInstallRequest(
          packageName: name,
          version: fixedVersion == null ||
                  fixedVersion.isEmpty ||
                  fixedVersion.toLowerCase() == 'unknown'
              ? null
              : fixedVersion,
          indexUrl: indexUrl,
        ),
      );
      await _handleInstallResult(
        result,
        successMessage: '修复成功: $name',
        failureMessage: '修复失败: $name',
        forceRefresh: true,
      );
    } catch (e) {
      _failInstall('Error: $e');
    }
  }

  /// 按项目 requirements.txt 安装依赖。
  Future<void> installRequirementsFromProject({
    required String projectKey,
    String requirementsPath = 'requirements.txt',
    String? indexUrl,
  }) {
    return _installRequirements(
      RequirementsInstallRequest(
        projectKey: projectKey,
        requirementsPath: requirementsPath,
        displayName: requirementsPath,
        indexUrl: indexUrl,
      ),
    );
  }

  /// 按文本内容安装 requirements.txt 依赖。
  Future<void> installRequirementsFromContent({
    required String content,
    String displayName = 'requirements.txt',
    String? indexUrl,
  }) {
    return _installRequirements(
      RequirementsInstallRequest(
        content: content,
        displayName: displayName,
        indexUrl: indexUrl,
      ),
    );
  }

  Future<void> _installRequirements(RequirementsInstallRequest request) async {
    if (!state.supportsRequirementsInstall) {
      _appendInstallLog('requirements.txt 仅支持 Linux-like');
      return;
    }
    final label = request.displayName.trim().isEmpty
        ? 'requirements.txt'
        : request.displayName.trim();
    if (state.isInstalling) {
      _appendInstallLog('已有安装任务进行中，请稍后再试');
      return;
    }
    _setState(state.copyWith(
      isInstalling: true,
      installLog: ['Installing $label...'],
    ));

    try {
      final result = await _repository.installRequirements(request);
      await _handleInstallResult(
        result,
        successMessage: '$label 安装成功',
        failureMessage: '$label 安装失败',
      );
    } catch (e) {
      _failInstall('Error: $e');
    }
  }

  Future<void> _handleInstallResult(
    PackageInstallResult result, {
    required String successMessage,
    required String failureMessage,
    bool forceRefresh = false,
  }) async {
    // 与迁移前 legacy ChangeNotifier 一致：原生侧在 MethodChannel future 完成
    // 之前会先发送 success/error 进度事件，[_onInstallProgress] 据此把
    // isInstalling 置 false 并已触发刷新。此处若发现 isInstalling 已被流清掉，
    // 说明完成态已由流处理，直接返回，避免重复追加日志与重复 listPackages。
    if (!state.isInstalling) return;
    _setState(state.copyWith(
      isInstalling: false,
      installLog: [
        ...state.installLog,
        result.message.isNotEmpty
            ? result.message
            : (result.success ? successMessage : failureMessage),
      ],
    ));
    if (result.success) {
      // 与迁移前行为一致：直接安装/修复成功后等待列表刷新完成，
      // 保证调用方拿到最新包列表。流式成功事件走 [refresh] fire-and-forget。
      await _load(forceRefresh: forceRefresh);
    }
    _scheduleInstallLogClear();
  }

  void _failInstall(String message) {
    // 异常路径：流不会发送 success/error，故 isInstalling 仍为 true。
    if (!state.isInstalling) return;
    _setState(state.copyWith(
      isInstalling: false,
      installLog: [...state.installLog, message],
    ));
    _scheduleInstallLogClear();
  }

  void _appendInstallLog(String message) {
    _setState(state.copyWith(installLog: [...state.installLog, message]));
  }

  /// 卸载包。立即从本地列表移除以响应 UI，失败时回滚为真实状态。
  Future<PackageUninstallResult> uninstall(String name) async {
    final optimistic = state.packages.where((p) => p.name != name).toList();
    _setState(state.copyWith(packages: optimistic));

    try {
      final result = await _repository.uninstallPackage(name);
      // 无论成功失败都重新拉取真实状态，与迁移前行为一致。
      await _load(forceRefresh: true);
      return result;
    } catch (e) {
      AppLogger.instance
          .warn('uninstallPackage error: $e', source: 'PackageController');
      await _load(forceRefresh: true);
      return PackageUninstallResult(success: false, message: e.toString());
    }
  }

  /// 立即清空安装日志。
  void clearInstallLog() {
    _retention.installLogClearTimer?.cancel();
    _retention.installLogClearTimer = null;
    _clearInstallLogFromTimer();
  }

  void _scheduleInstallLogClear() {
    _retention.installLogClearTimer?.cancel();
    _retention.installLogClearTimer = Timer(installLogClearDelay, () {
      _retention.installLogClearTimer = null;
      _retention.clearInstallLog?.call();
    });
  }

  PackageInfo _packageInfoFromRuntime(RuntimePackage item) {
    return PackageInfo(
      name: item.name,
      version: item.version,
      isUserPackage: item.isUserPackage,
      integrityStatus: item.integrityStatus,
      integrityMessage: item.integrityMessage,
      missingImports: item.missingImports,
    );
  }
}
