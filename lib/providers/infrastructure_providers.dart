import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/database_service.dart';
import '../services/http_inspector_store.dart';
import '../services/native_bridge.dart';

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
