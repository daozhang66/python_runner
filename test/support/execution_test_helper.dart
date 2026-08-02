import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:python_runner/features/console/application/execution_repository.dart';
import 'package:python_runner/models/execution_state.dart';
import 'package:python_runner/runtime/runtime_health.dart';
import 'package:python_runner/runtime/runtime_output.dart';
import 'package:python_runner/runtime/runtime_request.dart';
import 'package:python_runner/runtime/runtime_session.dart';
import 'package:python_runner/runtime/runtime_stdin_request.dart';

/// 构建一个绑定到 [FakeExecutionRepository] 的 [ProviderContainer]，供 Level 3
/// 执行/终端 Controller 单测使用。调用方负责 `container.dispose()`。
ProviderContainer buildExecutionContainer({
  FakeExecutionRepository? repository,
  List<Override> overrides = const [],
}) {
  final repo = repository ?? FakeExecutionRepository();
  return ProviderContainer(
    overrides: [
      ...overrides,
      executionRepositoryProvider.overrideWithValue(repo),
    ],
  );
}

/// 测试用 [ExecutionRepository]。
///
/// 用三个 `StreamController` 模拟 runtime 事件流（output/state/stdin），命令方法
/// 暴露计数器与最近请求；执行偏好可在外部预设。Level 3 Controller
/// 单测通过本类注入流事件，验证订阅释放与 generation 隔离。
class FakeExecutionRepository implements ExecutionRepository {
  FakeExecutionRepository({
    this.activeBackendId = 'chaquopy',
    ExecutionPreferences? preferences,
    this.health = const RuntimeHealth(ok: true),
    this.linuxLikeRuntimeInfo = const {'available': 'false'},
  }) : _preferences = preferences ??
            const ExecutionPreferences(
              workingDir: null,
              timeoutSeconds: null,
              preferredRuntimeBackendId: 'chaquopy',
            );

  @override
  final String activeBackendId;

  ExecutionPreferences _preferences;
  RuntimeHealth health;
  Map<String, String> linuxLikeRuntimeInfo;

  final StreamController<RuntimeOutput> _outputController =
      StreamController<RuntimeOutput>.broadcast();
  final StreamController<ExecutionState> _stateController =
      StreamController<ExecutionState>.broadcast();
  final StreamController<RuntimeStdinRequest> _stdinController =
      StreamController<RuntimeStdinRequest>.broadcast();

  // 可观测计数器与最近请求。
  int startScriptCount = 0;
  int sendStdinCount = 0;
  int stopExecutionCount = 0;
  int checkHealthCount = 0;
  int loadPreferencesCount = 0;

  RuntimeRequest? lastStartRequest;
  String? lastStdinInput;

  @override
  Stream<RuntimeOutput> get outputStream => _outputController.stream;

  @override
  Stream<ExecutionState> get stateStream => _stateController.stream;

  @override
  Stream<RuntimeStdinRequest> get stdinRequestStream => _stdinController.stream;

  void emitOutput(RuntimeOutput output) => _outputController.add(output);
  void emitState(ExecutionState state) => _stateController.add(state);
  void emitStdinRequest(RuntimeStdinRequest request) =>
      _stdinController.add(request);

  @override
  Future<RuntimeSession> startScript(RuntimeRequest request) async {
    startScriptCount++;
    lastStartRequest = request;
    return _StubRuntimeSession(request);
  }

  @override
  Future<void> sendStdin(String input) async {
    sendStdinCount++;
    lastStdinInput = input;
  }

  @override
  Future<void> stopExecution() async {
    stopExecutionCount++;
  }

  @override
  Future<RuntimeHealth> checkHealth() async {
    checkHealthCount++;
    return health;
  }

  @override
  Future<Map<String, String>> getLinuxLikeRuntimeInfo() async =>
      linuxLikeRuntimeInfo;

  @override
  Future<ExecutionPreferences> loadExecutionPreferences({
    bool includeWorkingDir = true,
  }) async {
    loadPreferencesCount++;
    if (includeWorkingDir) return _preferences;
    // 项目执行路径：workingDir 强制为 null。
    return _preferences.copyWith(clearWorkingDir: true);
  }

  /// 在测试中覆盖偏好快照。
  void setPreferences(ExecutionPreferences preferences) =>
      _preferences = preferences;

  /// 关闭内部流控制器，释放资源。
  void dispose() {
    _outputController.close();
    _stateController.close();
    _stdinController.close();
  }
}

/// 最小 [RuntimeSession] 桩实现，供 [FakeExecutionRepository.startScript] 返回。
class _StubRuntimeSession implements RuntimeSession {
  _StubRuntimeSession(this._request);

  final RuntimeRequest _request;

  @override
  String get id => 'stub-session';

  @override
  String get backendId => 'stub';

  @override
  RuntimeRequest get request => _request;

  @override
  Stream<RuntimeOutput> get stdout => const Stream<RuntimeOutput>.empty();

  @override
  Stream<RuntimeOutput> get stderr => const Stream<RuntimeOutput>.empty();

  @override
  Stream<ExecutionState> get stateStream => const Stream<ExecutionState>.empty();

  @override
  Future<void> writeStdin(String data) async {}

  @override
  Future<void> interrupt() async {}

  @override
  Future<void> terminate() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<int?> waitExit() async => 0;
}
