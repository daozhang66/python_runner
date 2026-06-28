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

class ChaquopyBackend implements RuntimeBackend {
  final NativeBridge _bridge;

  ChaquopyBackend(this._bridge);

  @override
  String get id => 'chaquopy';

  @override
  String get name => 'Chaquopy';

  @override
  late final Stream<RuntimeOutput> outputStream =
      _bridge.logStream.map(RuntimeOutput.fromMap).asBroadcastStream();

  @override
  late final Stream<ExecutionState> stateStream = _bridge.executionStatusStream
      .map(ExecutionState.fromMap)
      .asBroadcastStream();

  @override
  late final Stream<RuntimeStdinRequest> stdinRequestStream = _bridge
      .stdinRequestStream
      .map(RuntimeStdinRequest.fromMap)
      .asBroadcastStream();

  @override
  late final Stream<PackageInstallProgress> packageInstallProgressStream =
      _bridge.installProgressStream
          .map(PackageInstallProgress.fromMap)
          .asBroadcastStream();

  @override
  Future<RuntimeSession> startScript(RuntimeRequest request) async {
    if (request.isProject) {
      throw StateError('项目型脚本组仅支持 Linux-like 引擎');
    }
    final session = ChaquopyRuntimeSession(
      backend: this,
      request: request,
    );
    await _bridge.executeScript(
      request.scriptName,
      request.executionId,
      workingDir: request.workingDirectory,
      hookEnv: request.environment.isEmpty ? null : request.environment,
      timeoutSeconds: request.timeout?.inSeconds,
    );
    return session;
  }

  @override
  Future<void> sendStdin(String input) {
    return _bridge.sendStdin(input);
  }

  @override
  Future<void> stopExecution() {
    return _bridge.stopExecution();
  }

  @override
  Future<PackageInstallResult> installPackage(
    PackageInstallRequest request,
  ) async {
    await _bridge.installPackage(
      request.packageName,
      version: request.version,
      indexUrl: request.indexUrl,
    );
    return const PackageInstallResult(success: true);
  }

  @override
  Future<PackageInstallResult> repairPackage(
    PackageInstallRequest request,
  ) async {
    return const PackageInstallResult(
      success: false,
      message: '修复仅支持 Linux-like 用户包',
    );
  }

  @override
  Future<PackageInstallResult> installRequirements(
    RequirementsInstallRequest request,
  ) async {
    return const PackageInstallResult(
      success: false,
      message: 'requirements.txt 仅支持 Linux-like 运行环境',
    );
  }

  @override
  Future<PackageUninstallResult> uninstallPackage(String packageName) async {
    final result = await _bridge.uninstallPackage(packageName);
    return PackageUninstallResult.fromMap(result);
  }

  @override
  Future<List<RuntimePackage>> listPackages() async {
    final packages = await _bridge.listInstalledPackages();
    return packages
        .map((item) => RuntimePackage.fromMap(item))
        .where((item) => item.name.isNotEmpty)
        .toList();
  }

  @override
  Future<RuntimeHealth> checkHealth() async {
    try {
      final info = await _bridge.getPythonInfo();
      return RuntimeHealth(ok: true, details: info);
    } catch (e) {
      return RuntimeHealth(ok: false, message: e.toString());
    }
  }
}

class ChaquopyRuntimeSession implements RuntimeSession {
  final ChaquopyBackend backend;

  @override
  final RuntimeRequest request;

  final Completer<int?> _exitCompleter = Completer<int?>();
  StreamSubscription<ExecutionState>? _stateSub;

  ChaquopyRuntimeSession({
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
