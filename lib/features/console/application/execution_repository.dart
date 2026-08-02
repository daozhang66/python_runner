import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/execution_state.dart';
import '../../../providers/infrastructure_providers.dart';
import '../../../providers/theme_provider.dart' show sharedPreferencesProvider;
import '../../../runtime/runtime_health.dart';
import '../../../runtime/runtime_manager.dart';
import '../../../runtime/runtime_output.dart';
import '../../../runtime/runtime_request.dart';
import '../../../runtime/runtime_session.dart';
import '../../../runtime/runtime_stdin_request.dart';
import '../../../services/native_bridge.dart';

/// 执行与终端数据访问接口（Level 0 交付物）。
///
/// 封装迁移前 `ExecutionProvider` 内部对 `RuntimeManager`（事件流与运行命令）
/// 和执行偏好读取的全部调用。
/// 作为 Level 3 [ExecutionController] 的唯一依赖入口。
///
/// Controller 持有事件流订阅，`ref.onDispose` 负责释放；本接口只暴露原始流，
/// 不做节流（节流由 Controller 内部的 100ms 批量通知负责）。
abstract class ExecutionRepository {
  // --- 运行引擎事件流（由 Controller 订阅） ---

  Stream<RuntimeOutput> get outputStream;

  Stream<ExecutionState> get stateStream;

  Stream<RuntimeStdinRequest> get stdinRequestStream;

  // --- 运行引擎命令 ---

  /// 当前后端标识。
  String get activeBackendId;

  /// 启动一次脚本/项目运行。返回当前运行会话，保留与 RuntimeManager 一致的
  /// 返回类型，供 Controller 在需要时直接操作会话（如定向 stdin/terminate）。
  Future<RuntimeSession> startScript(RuntimeRequest request);

  /// 向当前运行发送标准输入。
  Future<void> sendStdin(String input);

  /// 停止当前运行。
  Future<void> stopExecution();

  /// 健康检查（用于 Linux-like 后端可用性探测）。
  Future<RuntimeHealth> checkHealth();

  /// Linux-like 后端的运行时信息（available 标记等）。
  Future<Map<String, String>> getLinuxLikeRuntimeInfo();

  // --- 执行偏好（SharedPreferences） ---

  /// 读取执行偏好快照。[includeWorkingDir] 为 false 时返回的 workingDir 恒为
  /// null，对应迁移前项目执行路径 `_loadExecutionPreferences(includeWorkingDir: false)`。
  Future<ExecutionPreferences> loadExecutionPreferences({
    bool includeWorkingDir = true,
  });

}

/// 执行偏好快照（不可变）。对应迁移前 `ExecutionProvider._ExecutionPreferences`。
class ExecutionPreferences {
  const ExecutionPreferences({
    required this.workingDir,
    required this.timeoutSeconds,
    required this.preferredRuntimeBackendId,
  });

  final String? workingDir;
  final int? timeoutSeconds;
  final String preferredRuntimeBackendId;

  ExecutionPreferences copyWith({
    String? workingDir,
    bool clearWorkingDir = false,
    int? timeoutSeconds,
    String? preferredRuntimeBackendId,
  }) {
    return ExecutionPreferences(
      workingDir:
          clearWorkingDir ? null : (workingDir ?? this.workingDir),
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      preferredRuntimeBackendId:
          preferredRuntimeBackendId ?? this.preferredRuntimeBackendId,
    );
  }
}

/// 生产实现：组合 [RuntimeManager]、[NativeBridge] 与 [SharedPreferences]。
///
/// 后端切换经 `runtimeManagerProvider` 失效自动重建本 Repository 及下游
/// Controller；本类不在构造时读 prefs 解析后端，避免与 Riverpod 失效链冲突。
class RuntimeExecutionRepository implements ExecutionRepository {
  RuntimeExecutionRepository({
    required RuntimeManager runtimeManager,
    required NativeBridge bridge,
    required SharedPreferences preferences,
  })  : _runtimeManager = runtimeManager,
        _bridge = bridge,
        _preferences = preferences;

  final RuntimeManager _runtimeManager;
  final NativeBridge _bridge;
  final SharedPreferences _preferences;

  @override
  Stream<RuntimeOutput> get outputStream => _runtimeManager.outputStream;

  @override
  Stream<ExecutionState> get stateStream => _runtimeManager.stateStream;

  @override
  Stream<RuntimeStdinRequest> get stdinRequestStream =>
      _runtimeManager.stdinRequestStream;

  @override
  String get activeBackendId => _runtimeManager.activeBackendId;

  @override
  Future<RuntimeSession> startScript(RuntimeRequest request) =>
      _runtimeManager.startScript(request);

  @override
  Future<void> sendStdin(String input) => _runtimeManager.sendStdin(input);

  @override
  Future<void> stopExecution() => _runtimeManager.stopExecution();

  @override
  Future<RuntimeHealth> checkHealth() {
    // 健康检查始终针对 Linux-like 后端构造（与迁移前 _resolveExecutableBackendId 一致）。
    return RuntimeManager.linuxLike(_bridge).checkHealth();
  }

  @override
  Future<Map<String, String>> getLinuxLikeRuntimeInfo() =>
      _bridge.getLinuxLikeRuntimeInfo();

  @override
  Future<ExecutionPreferences> loadExecutionPreferences({
    bool includeWorkingDir = true,
  }) async {
    return ExecutionPreferences(
      workingDir:
          includeWorkingDir ? _preferences.getString('working_dir') : null,
      timeoutSeconds: _preferences.getInt('execution_timeout'),
      preferredRuntimeBackendId: RuntimeManager.normalizePreferredBackendId(
        _preferences.getString(RuntimeManager.prefsKey),
      ),
    );
  }

}

/// 执行 Repository Provider。测试通过 override 注入 fake。
final executionRepositoryProvider = Provider<ExecutionRepository>((ref) {
  return RuntimeExecutionRepository(
    runtimeManager: ref.watch(runtimeManagerProvider),
    bridge: ref.watch(nativeBridgeProvider),
    preferences: ref.watch(sharedPreferencesProvider),
  );
});
