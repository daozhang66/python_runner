import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../runtime/runtime_manager.dart';
import '../services/database_service.dart';
import '../services/http_inspector_store.dart';
import '../services/native_bridge.dart';
import 'theme_provider.dart' show sharedPreferencesProvider;

/// 基础设施 Provider（对齐 `sharedPreferencesProvider` / `themeProvider` 的注入范式）。
///
/// 把进程级单例/无依赖服务显式化，供业务 Notifier 通过 `ref.watch` 拿依赖，
/// 而非构造时硬编码 `NativeBridge.instance`。默认返回真实实例，测试可通过
/// `ProviderScope.overrides` 注入 fake。
///
/// 迁移进度（B2 PR1）：Script/Package Notifier 经此消费 bridge/db。

/// 原生桥（B3 已单例化）。全局唯一，直接复用 [NativeBridge.instance]。
final nativeBridgeProvider = Provider<NativeBridge>(
  (ref) => NativeBridge.instance,
);

/// 脚本元数据持久化（SQLite）。无状态服务。
final databaseServiceProvider = Provider<DatabaseService>(
  (ref) => DatabaseService(),
);

/// 网络抓包记录存储（自带磁盘持久化的进程级单例）。
/// 保留 [HttpInspectorStore.instance] 不动本体，仅以 Provider 包装供 UI 层 ref 访问。
final httpInspectorStoreProvider = Provider<HttpInspectorStore>(
  (ref) => HttpInspectorStore.instance,
);

/// 运行引擎后端选择失效代数。
///
/// 业务 Notifier（包管理、执行）依赖 [runtimeManagerProvider]；当用户切换运行引擎
/// 后调用 [invalidateRuntimeBackend] 使该计数器自增，从而让
/// [runtimeManagerProvider] 及其下游 Notifier 重建，避免页面读取旧引擎状态。
/// 页面禁止自行 `SharedPreferences` 后构造 RuntimeManager。
final _runtimeBackendGenerationProvider = StateProvider<int>((ref) => 0);

/// 使运行引擎后端重建。返回新的代数值。
int invalidateRuntimeBackend(Ref ref) {
  final notifier = ref.read(_runtimeBackendGenerationProvider.notifier);
  notifier.state = notifier.state + 1;
  return notifier.state;
}

int invalidateRuntimeBackendFromWidget(WidgetRef ref) {
  final notifier = ref.read(_runtimeBackendGenerationProvider.notifier);
  notifier.state = notifier.state + 1;
  return notifier.state;
}

/// 当前选中的运行引擎 [RuntimeManager]。
///
/// 根据持久化的运行引擎偏好创建；切换引擎时调用 [invalidateRuntimeBackend]
/// 使本 Provider 失效并由依赖它的包管理、执行 Controller 重建。
/// 测试可通过 `ProviderScope.overrides` 注入预构建的 RuntimeManager。
final runtimeManagerProvider = Provider<RuntimeManager>((ref) {
  // 监听代数，确保引擎切换后重建。
  ref.watch(_runtimeBackendGenerationProvider);
  final prefs = ref.watch(sharedPreferencesProvider);
  final bridge = ref.watch(nativeBridgeProvider);
  final backendId = RuntimeManager.normalizePreferredBackendId(
    prefs.getString(RuntimeManager.prefsKey),
  );
  return RuntimeManager.fromPreferredBackend(bridge, backendId);
});
