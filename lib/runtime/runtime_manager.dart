import 'package:shared_preferences/shared_preferences.dart';

import '../models/execution_state.dart';
import '../services/native_bridge.dart';
import 'chaquopy_backend.dart';
import 'linux_like_backend.dart';
import 'runtime_backend.dart';
import 'runtime_health.dart';
import 'runtime_output.dart';
import 'runtime_package.dart';
import 'runtime_request.dart';
import 'runtime_session.dart';
import 'runtime_stdin_request.dart';

class RuntimeManager {
  static const prefsKey = 'runtime_backend';
  static const chaquopyBackendId = 'chaquopy';
  static const linuxLikeBackendId = 'linux_like';
  static const fallbackBackendId = chaquopyBackendId;
  static const selectableBackendIds = <String>[
    chaquopyBackendId,
    linuxLikeBackendId,
  ];

  final RuntimeBackend currentBackend;
  RuntimeSession? _activeSession;

  RuntimeManager(this.currentBackend);

  factory RuntimeManager.chaquopy(NativeBridge bridge) {
    return RuntimeManager(ChaquopyBackend(bridge));
  }

  factory RuntimeManager.linuxLike([NativeBridge? bridge]) {
    return RuntimeManager(LinuxLikeBackend(bridge: bridge));
  }

  factory RuntimeManager.fromPreferredBackend(
    NativeBridge bridge,
    String? backendId,
  ) {
    final resolvedBackendId = resolveBackendId(backendId);
    switch (resolvedBackendId) {
      case linuxLikeBackendId:
        return RuntimeManager.linuxLike(bridge);
      case chaquopyBackendId:
      default:
        return RuntimeManager.chaquopy(bridge);
    }
  }

  static String backendDisplayName(String backendId) {
    switch (normalizePreferredBackendId(backendId)) {
      case linuxLikeBackendId:
        return 'Linux-like';
      case chaquopyBackendId:
      default:
        return 'Chaquopy';
    }
  }

  static String backendStatusLabel(String backendId) {
    return isBackendAvailable(backendId) ? '可用' : '未安装';
  }

  static String backendStatusMessage(String backendId) {
    switch (normalizePreferredBackendId(backendId)) {
      case linuxLikeBackendId:
        return 'Linux-like 开发版已接入；首次使用请先安装运行环境';
      case chaquopyBackendId:
      default:
        return 'Chaquopy 当前可用，适合轻量和稳定脚本执行';
    }
  }

  static bool isKnownBackendId(String? backendId) {
    return backendId != null && selectableBackendIds.contains(backendId);
  }

  static String normalizePreferredBackendId(String? backendId) {
    return isKnownBackendId(backendId) ? backendId! : chaquopyBackendId;
  }

  static bool isBackendAvailable(String backendId) {
    return selectableBackendIds.contains(backendId);
  }

  static String resolveBackendId(String? backendId) {
    final preferredBackendId = normalizePreferredBackendId(backendId);
    if (isBackendAvailable(preferredBackendId)) {
      return preferredBackendId;
    }
    return fallbackBackendId;
  }

  static Future<String> loadPreferredBackendId() async {
    final prefs = await SharedPreferences.getInstance();
    return normalizePreferredBackendId(prefs.getString(prefsKey));
  }

  static Future<void> savePreferredBackendId(String backendId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, normalizePreferredBackendId(backendId));
  }

  String get activeBackendId => currentBackend.id;

  Stream<RuntimeOutput> get outputStream => currentBackend.outputStream;
  Stream<ExecutionState> get stateStream => currentBackend.stateStream;
  Stream<RuntimeStdinRequest> get stdinRequestStream =>
      currentBackend.stdinRequestStream;
  Stream<PackageInstallProgress> get packageInstallProgressStream =>
      currentBackend.packageInstallProgressStream;

  Future<RuntimeSession> startScript(RuntimeRequest request) async {
    _activeSession = await currentBackend.startScript(request);
    return _activeSession!;
  }

  Future<void> sendStdin(String input) {
    final session = _activeSession;
    if (session != null) {
      return session.writeStdin(input);
    }
    return currentBackend.sendStdin(input);
  }

  Future<void> stopExecution() {
    final session = _activeSession;
    if (session != null) {
      return session.terminate();
    }
    return currentBackend.stopExecution();
  }

  Future<PackageInstallResult> installPackage(
    PackageInstallRequest request,
  ) {
    return currentBackend.installPackage(request);
  }

  Future<PackageUninstallResult> uninstallPackage(String packageName) {
    return currentBackend.uninstallPackage(packageName);
  }

  Future<List<RuntimePackage>> listPackages() {
    return currentBackend.listPackages();
  }

  Future<RuntimeHealth> checkHealth() {
    return currentBackend.checkHealth();
  }
}
