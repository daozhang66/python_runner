import 'dart:async';

import '../models/execution_state.dart';
import '../services/native_bridge.dart';
import 'runtime_backend.dart';
import 'runtime_health.dart';
import 'runtime_output.dart';
import 'runtime_package.dart';
import 'runtime_request.dart';
import 'runtime_session.dart';
import 'runtime_stdin_request.dart';

class LinuxLikeBackend implements RuntimeBackend {
  static const backendId = 'linux_like';
  static const unavailableMessage = 'Linux-like 运行环境未安装，当前执行仍会回退到 Chaquopy';

  final NativeBridge? _bridge;

  LinuxLikeBackend({NativeBridge? bridge}) : _bridge = bridge;

  @override
  String get id => backendId;

  @override
  String get name => 'Linux-like';

  @override
  late final Stream<RuntimeOutput> outputStream = _bridge == null
      ? const Stream<RuntimeOutput>.empty().asBroadcastStream()
      : _bridge.logStream.map(RuntimeOutput.fromMap).asBroadcastStream();

  @override
  late final Stream<ExecutionState> stateStream = _bridge == null
      ? const Stream<ExecutionState>.empty().asBroadcastStream()
      : _bridge.executionStatusStream
          .map(ExecutionState.fromMap)
          .asBroadcastStream();

  @override
  late final Stream<RuntimeStdinRequest> stdinRequestStream = _bridge == null
      ? const Stream<RuntimeStdinRequest>.empty().asBroadcastStream()
      : _bridge.stdinRequestStream
          .map(RuntimeStdinRequest.fromMap)
          .asBroadcastStream();

  @override
  late final Stream<PackageInstallProgress> packageInstallProgressStream =
      _bridge == null
          ? const Stream<PackageInstallProgress>.empty().asBroadcastStream()
          : _bridge.installProgressStream
              .map(PackageInstallProgress.fromMap)
              .asBroadcastStream();

  @override
  Future<RuntimeSession> startScript(RuntimeRequest request) async {
    final bridge = _bridge;
    if (bridge == null) {
      throw StateError(unavailableMessage);
    }
    final health = await checkHealth();
    if (!health.ok) {
      throw StateError(health.message);
    }
    final session = LinuxLikeRuntimeSession(
      backend: this,
      request: request,
    );
    await bridge.executeLinuxLikeScript(
      request.scriptName,
      request.executionId,
      workingDir: request.workingDirectory,
      environment: request.environment.isEmpty ? null : request.environment,
      timeoutSeconds: request.timeout?.inSeconds,
      projectKey: request.projectKey,
      projectMainFilePath: request.projectMainFilePath,
    );
    return session;
  }

  @override
  Future<void> sendStdin(String input) async {
    final bridge = _bridge;
    if (bridge == null) return;
    await bridge.sendLinuxLikeStdin(input);
  }

  @override
  Future<void> stopExecution() async {
    final bridge = _bridge;
    if (bridge == null) return;
    await bridge.stopLinuxLikeExecution();
  }

  @override
  Future<PackageInstallResult> installPackage(
    PackageInstallRequest request,
  ) async {
    final bridge = _bridge;
    if (bridge == null) {
      return const PackageInstallResult(
        success: false,
        message: unavailableMessage,
      );
    }
    await bridge.installLinuxLikePackage(
      request.packageName,
      version: request.version,
      indexUrl: request.indexUrl,
    );
    return PackageInstallResult(
      success: true,
      message: '安装成功: ${request.packageName}',
    );
  }

  @override
  Future<PackageInstallResult> repairPackage(
    PackageInstallRequest request,
  ) async {
    final bridge = _bridge;
    if (bridge == null) {
      return const PackageInstallResult(
        success: false,
        message: unavailableMessage,
      );
    }
    await bridge.repairLinuxLikePackage(
      request.packageName,
      version: request.version,
      indexUrl: request.indexUrl,
    );
    return PackageInstallResult(
      success: true,
      message: '修复成功: ${request.packageName}',
    );
  }

  @override
  Future<PackageInstallResult> installRequirements(
    RequirementsInstallRequest request,
  ) async {
    final bridge = _bridge;
    if (bridge == null) {
      return const PackageInstallResult(
        success: false,
        message: unavailableMessage,
      );
    }
    await bridge.installLinuxLikeRequirements(
      projectKey: request.projectKey,
      requirementsPath: request.requirementsPath,
      content: request.content,
      displayName: request.displayName,
      indexUrl: request.indexUrl,
    );
    return PackageInstallResult(
      success: true,
      message: '${request.displayName} 安装成功',
    );
  }

  @override
  Future<PackageUninstallResult> uninstallPackage(String packageName) async {
    final bridge = _bridge;
    if (bridge == null) {
      return const PackageUninstallResult(
        success: false,
        message: unavailableMessage,
      );
    }
    final result = await bridge.uninstallLinuxLikePackage(packageName);
    return PackageUninstallResult.fromMap(result);
  }

  Future<RuntimeHealth> installRuntime({String? manifestUrl}) async {
    final bridge = _bridge;
    if (bridge == null) {
      return const RuntimeHealth(
        ok: false,
        message: unavailableMessage,
        details: {
          'backend': backendId,
          'available': 'false',
          'stage': 'scaffold',
        },
      );
    }
    try {
      final info =
          await bridge.installLinuxLikeRuntime(manifestUrl: manifestUrl);
      return RuntimeHealth(
        ok: info['available'] == 'true',
        message: info['message'] ?? 'Linux-like runtime installed',
        details: info,
      );
    } catch (e) {
      return RuntimeHealth(
        ok: false,
        message: 'Linux-like运行环境安装失败: $e',
        details: const {
          'backend': backendId,
          'available': 'false',
          'stage': 'install',
        },
      );
    }
  }

  @override
  Future<List<RuntimePackage>> listPackages() async {
    final bridge = _bridge;
    if (bridge == null) return const [];
    final packages = await bridge.listLinuxLikePackages();
    return packages
        .map((item) => RuntimePackage.fromMap({
              ...item,
              'source': item['source'] ?? 'user',
            }))
        .where((item) => item.name.isNotEmpty)
        .toList();
  }

  @override
  Future<RuntimeHealth> checkHealth() async {
    final bridge = _bridge;
    if (bridge != null) {
      try {
        final info = await bridge.getLinuxLikeRuntimeInfo();
        final available = info['available'] == 'true';
        return RuntimeHealth(
          ok: available,
          message: info['message'] ?? unavailableMessage,
          details: info,
        );
      } catch (e) {
        return RuntimeHealth(
          ok: false,
          message: '$unavailableMessage: $e',
          details: const {
            'backend': backendId,
            'available': 'false',
            'stage': 'native_bridge',
          },
        );
      }
    }
    return const RuntimeHealth(
      ok: false,
      message: unavailableMessage,
      details: {
        'backend': backendId,
        'available': 'false',
        'stage': 'scaffold',
      },
    );
  }
}

class LinuxLikeRuntimeSession implements RuntimeSession {
  final LinuxLikeBackend backend;

  @override
  final RuntimeRequest request;

  final Completer<int?> _exitCompleter = Completer<int?>();
  StreamSubscription<ExecutionState>? _stateSub;

  LinuxLikeRuntimeSession({
    required this.backend,
    required this.request,
  }) {
    _stateSub = backend.stateStream.listen((state) {
      if (state.executionId != null &&
          state.executionId != request.executionId) {
        return;
      }
      if (isTerminalRuntimeState(state.status) && !_exitCompleter.isCompleted) {
        _exitCompleter.complete(state.exitCode);
        _stateSub?.cancel();
      }
    });
  }

  @override
  String get id => request.executionId;

  @override
  String get backendId => backend.id;

  @override
  Stream<RuntimeOutput> get stdout => backend.outputStream
      .where((output) => output.type == RuntimeOutputType.stdout);

  @override
  Stream<RuntimeOutput> get stderr => backend.outputStream
      .where((output) => output.type == RuntimeOutputType.stderr);

  @override
  Stream<ExecutionState> get stateStream => backend.stateStream;

  @override
  Future<void> writeStdin(String data) {
    return backend.sendStdin(data);
  }

  @override
  Future<void> interrupt() {
    return terminate();
  }

  @override
  Future<void> terminate() {
    return backend.stopExecution();
  }

  @override
  Future<int?> waitExit() {
    return _exitCompleter.future;
  }
}
