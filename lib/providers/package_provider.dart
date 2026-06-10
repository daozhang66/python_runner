import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/package_info.dart';
import '../runtime/runtime_manager.dart';
import '../runtime/runtime_package.dart';
import '../services/native_bridge.dart';

class PackageProvider extends ChangeNotifier {
  final NativeBridge _bridge;
  RuntimeManager _runtimeManager;
  final bool _runtimeManagerLocked;

  List<PackageInfo> _packages = [];
  bool _installing = false;
  bool _loadingPackages = false;
  int _loadGeneration = 0;
  final List<String> _installLog = [];
  StreamSubscription<PackageInstallProgress>? _installSub;

  List<PackageInfo> get packages => _packages;
  bool get installing => _installing;
  bool get loadingPackages => _loadingPackages;
  List<String> get installLog => List.unmodifiable(_installLog);
  String get activeBackendId => _runtimeManager.activeBackendId;
  bool get supportsRequirementsInstall =>
      activeBackendId == RuntimeManager.linuxLikeBackendId;

  PackageProvider(NativeBridge bridge, {RuntimeManager? runtimeManager})
      : _bridge = bridge,
        _runtimeManager = runtimeManager ??
            RuntimeManager.fromPreferredBackend(
              bridge,
              RuntimeManager.chaquopyBackendId,
            ),
        _runtimeManagerLocked = runtimeManager != null {
    _listenInstallProgress();
  }

  void _listenInstallProgress() {
    _installSub?.cancel();
    _installSub = _runtimeManager.packageInstallProgressStream.listen((data) {
      final status = data.status;
      final message = data.message;
      if (message.isNotEmpty) {
        _installLog.add(message);
      }

      if (status == 'success') {
        _installing = false;
        loadPackages();
        _scheduleInstallLogClear();
      } else if (status == 'error') {
        _installing = false;
        _scheduleInstallLogClear();
      }

      notifyListeners();
    }, onError: (e) {
      debugPrint('installProgress error: $e');
    });
  }

  Future<void> _syncRuntimeManagerFromSettings() async {
    if (_runtimeManagerLocked) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final backendId = RuntimeManager.resolveBackendId(
        RuntimeManager.normalizePreferredBackendId(
          prefs.getString(RuntimeManager.prefsKey),
        ),
      );
      if (backendId == _runtimeManager.activeBackendId) return;
      _runtimeManager = RuntimeManager.fromPreferredBackend(_bridge, backendId);
      _packages = [];
      _listenInstallProgress();
      notifyListeners();
    } catch (e) {
      debugPrint('sync package runtime backend error: $e');
    }
  }

  String get _cacheKey => 'package_cache_${_runtimeManager.activeBackendId}';

  Future<void> _restoreCachedPackagesIfNeeded() async {
    if (_packages.isNotEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _packages = decoded
          .whereType<Map>()
          .map((item) => PackageInfo(
                name: item['name']?.toString() ?? '',
                version: item['version']?.toString() ?? '',
                isUserPackage: item['isUserPackage'] == true,
              ))
          .where((item) => item.name.isNotEmpty)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      if (_packages.isNotEmpty) {
        notifyListeners();
      }
    } catch (e) {
      debugPrint('restore package cache error: $e');
    }
  }

  Future<void> _savePackageCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_packages
          .map((item) => {
                'name': item.name,
                'version': item.version,
                'isUserPackage': item.isUserPackage,
              })
          .toList());
      await prefs.setString(_cacheKey, encoded);
    } catch (e) {
      debugPrint('save package cache error: $e');
    }
  }

  Future<void> loadPackages({bool forceRefresh = false}) async {
    final generation = ++_loadGeneration;
    try {
      await _syncRuntimeManagerFromSettings();
      if (!forceRefresh) {
        await _restoreCachedPackagesIfNeeded();
      }
      if (generation != _loadGeneration) return;
      _loadingPackages = true;
      notifyListeners();
      final result = await _runtimeManager.listPackages();
      if (generation != _loadGeneration) return;
      _packages = result
          .map((item) => PackageInfo(
                name: item.name,
                version: item.version,
                isUserPackage: item.isUserPackage,
              ))
          .toList();
      _packages.sort((a, b) => a.name.compareTo(b.name));
      await _savePackageCache();
      _loadingPackages = false;
      notifyListeners();
    } catch (e) {
      if (generation == _loadGeneration) {
        _loadingPackages = false;
        notifyListeners();
      }
      debugPrint('loadPackages error: $e');
    }
  }

  Future<void> installPackage(
    String name, {
    String? version,
    String? indexUrl,
  }) async {
    await _syncRuntimeManagerFromSettings();
    _installing = true;
    _installLog.clear();
    _installLog
        .add('Installing $name${version != null ? "==$version" : ""}...');
    notifyListeners();

    try {
      final result = await _runtimeManager.installPackage(
        PackageInstallRequest(
          packageName: name,
          version: version,
          indexUrl: indexUrl,
        ),
      );
      if (_installing) {
        _installing = false;
        _installLog.add(
          result.message.isNotEmpty
              ? result.message
              : result.success
                  ? '安装成功: $name'
                  : '安装失败: $name',
        );
        if (result.success) {
          await loadPackages();
        }
        _scheduleInstallLogClear();
        notifyListeners();
      }
    } catch (e) {
      _installing = false;
      _installLog.add('Error: $e');
      notifyListeners();
    }
  }

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

  Future<void> _installRequirements(
    RequirementsInstallRequest request,
  ) async {
    await _syncRuntimeManagerFromSettings();
    final label = request.displayName.trim().isEmpty
        ? 'requirements.txt'
        : request.displayName.trim();
    if (_installing) {
      _installLog.add('已有安装任务进行中，请稍后再试');
      notifyListeners();
      return;
    }
    _installing = true;
    _installLog.clear();
    _installLog.add('Installing $label...');
    notifyListeners();

    try {
      final result = await _runtimeManager.installRequirements(request);
      if (_installing) {
        _installing = false;
        _installLog.add(
          result.message.isNotEmpty
              ? result.message
              : result.success
                  ? '$label 安装成功'
                  : '$label 安装失败',
        );
        if (result.success) {
          await loadPackages();
        }
        _scheduleInstallLogClear();
        notifyListeners();
      }
    } catch (e) {
      _installing = false;
      _installLog.add('Error: $e');
      notifyListeners();
    }
  }

  Future<PackageUninstallResult> uninstallPackage(String name) async {
    await _syncRuntimeManagerFromSettings();
    // Immediately remove from local list for responsive UI
    _packages.removeWhere((p) => p.name == name);
    notifyListeners();

    try {
      final result = await _runtimeManager.uninstallPackage(name);
      if (!result.success) {
        await loadPackages();
        return result;
      }
      // Native uninstall done, no need to reload — already removed from list
      await loadPackages();
      return result;
    } catch (e) {
      debugPrint('uninstallPackage error: $e');
      // Restore actual state on error
      await loadPackages();
      return PackageUninstallResult(
        success: false,
        message: e.toString(),
      );
    }
  }

  Timer? _installLogClearTimer;
  bool _disposed = false;

  void clearInstallLog() {
    _installLog.clear();
    notifyListeners();
  }

  void _scheduleInstallLogClear() {
    _installLogClearTimer?.cancel();
    _installLogClearTimer = Timer(const Duration(seconds: 5), () {
      if (!_disposed) clearInstallLog();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _installLogClearTimer?.cancel();
    _installSub?.cancel();
    super.dispose();
  }
}
