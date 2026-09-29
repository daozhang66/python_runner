import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../providers/infrastructure_providers.dart';
import '../../../providers/execution_provider.dart';
import '../../../providers/theme_provider.dart' show sharedPreferencesProvider;
import '../../../services/app_logger.dart';
import '../../network/application/network_inspector_repository.dart';
import '../../packages/application/package_repository.dart';
import '../../scripts/application/script_repository.dart';
import '../../scripts/application/script_workspace_controller.dart';
import '../domain/mcp_facade_models.dart';
import '../infrastructure/mcp_audit_log.dart';
import '../infrastructure/mcp_http_transport.dart';
import '../infrastructure/mcp_server_adapter.dart';
import '../infrastructure/mcp_session_store.dart';
import '../infrastructure/mcp_token_store.dart';
import '../infrastructure/mcp_tool_registry.dart';
import 'mcp_application_facade.dart';
import 'mcp_execution_service.dart';
import 'mcp_confirmation_service.dart';
import 'mcp_facade_impl.dart';
import 'mcp_operation_registry.dart';
import 'mcp_policy_service.dart';

/// MCP 服务运行状态（计划 §11：已停止、启动中、运行中、错误）。
enum McpServerStatus { stopped, starting, running, error }

enum McpServerNotice {
  startFailed,
  overlayPermissionRequired,
  keepAliveUnavailable,
  hideOverlayFailed,
}

class McpServerState {
  const McpServerState({
    required this.status,
    required this.port,
    required this.requireToken,
    this.notice,
    this.noticeDetail,
    this.startedAt,
  });

  final McpServerStatus status;
  final int port;
  final bool requireToken;
  final McpServerNotice? notice;
  final Object? noticeDetail;
  final DateTime? startedAt;

  McpServerState copyWith({
    McpServerStatus? status,
    int? port,
    bool? requireToken,
    McpServerNotice? notice,
    Object? noticeDetail,
    bool clearNotice = false,
    DateTime? startedAt,
  }) {
    return McpServerState(
      status: status ?? this.status,
      port: port ?? this.port,
      requireToken: requireToken ?? this.requireToken,
      notice: clearNotice ? null : (notice ?? this.notice),
      noticeDetail: clearNotice ? null : (noticeDetail ?? this.noticeDetail),
      startedAt: startedAt ?? this.startedAt,
    );
  }
}

/// Facade 读取的实时服务信息（避免 Facade 依赖控制器产生循环）。
class McpServiceInfo {
  bool running = false;
  int port = 0;
}

// ── 基础服务 Provider ──

final mcpAuditLogProvider = Provider<McpAuditLog>((ref) => McpAuditLog());

final mcpSessionStoreProvider = Provider<McpSessionStore>((ref) {
  return McpSessionStore();
});

final mcpConfirmationServiceProvider = Provider<McpConfirmationService>((ref) {
  return McpConfirmationService();
});

final mcpOperationRegistryProvider = Provider<McpOperationRegistry>((ref) {
  return McpOperationRegistry();
});

final mcpTokenStoreProvider = Provider<McpTokenStore>((ref) {
  return McpTokenStore(preferences: ref.watch(sharedPreferencesProvider));
});

final mcpPolicyProvider = Provider<McpPolicyService>((ref) {
  return McpPolicyService(preferences: ref.watch(sharedPreferencesProvider));
});

final mcpServiceInfoProvider = Provider<McpServiceInfo>((ref) {
  return McpServiceInfo();
});

final mcpExecutionOwnerProvider = Provider<ExecutionProvider>((ref) {
  throw StateError('App execution provider is not attached');
});

final mcpExecutionServiceProvider = Provider<McpExecutionService>((ref) {
  return McpExecutionService(
    execution: () => ref.read(mcpExecutionOwnerProvider),
    scripts: ref.watch(scriptRepositoryProvider),
    recordRun: (name) async {
      final workspace = ref.read(scriptWorkspaceControllerProvider.notifier);
      await workspace.load();
      await workspace.incrementRunCount(name);
    },
    recordProjectRun: (group) async {
      final workspace = ref.read(scriptWorkspaceControllerProvider.notifier);
      await workspace.load();
      await workspace.markProjectGroupUsed(group);
    },
  );
});

/// 应用门面：所有 MCP 工具经此访问现有业务（计划 §5）。
final mcpApplicationFacadeProvider = Provider<McpApplicationFacade>((ref) {
  final serviceInfo = ref.watch(mcpServiceInfoProvider);
  return AppMcpApplicationFacade(
    scriptRepository: ref.watch(scriptRepositoryProvider),
    workspaceController: ref.read(scriptWorkspaceControllerProvider.notifier),
    bridge: ref.watch(nativeBridgeProvider),
    networkRepository: ref.watch(networkInspectorRepositoryProvider),
    packageRepository: ref.watch(packageRepositoryProvider),
    runtimeManager: ref.watch(runtimeManagerProvider),
    statusProbe:
        (appVersion, runtimeBackend, linuxLikeAvailable, linuxLikeInstalled) =>
            McpAppStatus(
      appVersion: appVersion,
      runtimeBackend: runtimeBackend,
      linuxLikeAvailable: linuxLikeAvailable,
      linuxLikeInstalled: linuxLikeInstalled,
      mcpRunning: serviceInfo.running,
      mcpPort: serviceInfo.port,
    ),
    operationRegistry: ref.watch(mcpOperationRegistryProvider),
  );
});

final mcpToolRegistryProvider = Provider<McpToolRegistry>((ref) {
  return McpToolRegistry(
    ref.watch(mcpApplicationFacadeProvider),
    operations: ref.watch(mcpOperationRegistryProvider),
    execution: ref.watch(mcpExecutionServiceProvider),
  );
});

final mcpServerAdapterProvider = Provider<McpServerAdapter>((ref) {
  return McpServerAdapter(
    tools: ref.watch(mcpToolRegistryProvider),
    sessions: ref.watch(mcpSessionStoreProvider),
    policy: ref.watch(mcpPolicyProvider),
    audit: ref.watch(mcpAuditLogProvider),
    serverVersion: '',
  );
});

// ── 服务控制器 ──

/// MCP 服务生命周期控制器：启动、停止、端口与令牌管理（计划 §11）。
///
/// - 服务只由用户在设置页开启，不持久化运行状态或在启动时恢复；
/// - 停止后所有新请求被拒绝、会话失效、未决确认自动拒绝（计划 §2.2）。
final mcpServerControllerProvider =
    NotifierProvider<McpServerController, McpServerState>(
  McpServerController.new,
);

class McpServerController extends Notifier<McpServerState> {
  static const String enabledPrefsKey = 'mcp.enabled';
  static const String portPrefsKey = 'mcp.port';
  static const String requireTokenPrefsKey = 'mcp.require_token';
  static const int defaultPort = McpHttpTransport.defaultPort;
  static const Duration sweepInterval = Duration(minutes: 1);

  McpHttpTransport? _transport;
  Timer? _sweepTimer;

  @override
  McpServerState build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final port = _sanitizePort(prefs.getInt(portPrefsKey)) ?? defaultPort;
    ref.onDispose(() {
      _sweepTimer?.cancel();
      _sweepTimer = null;
      final transport = _transport;
      _transport = null;
      if (transport != null) unawaited(transport.stop());
    });
    return McpServerState(
      status: McpServerStatus.stopped,
      port: port,
      requireToken: _prefs.getBool(requireTokenPrefsKey) ?? false,
    );
  }

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);
  McpTokenStore get _tokens => ref.read(mcpTokenStoreProvider);
  McpAuditLog get _audit => ref.read(mcpAuditLogProvider);
  McpServiceInfo get _serviceInfo => ref.read(mcpServiceInfoProvider);

  bool get isRunning => state.status == McpServerStatus.running;
  bool get requireToken => _prefs.getBool(requireTokenPrefsKey) ?? false;

  String get mcpUrl => 'http://127.0.0.1:${state.port}/mcp';

  Future<List<String>> get lanUrls async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    return interfaces
        .expand((item) => item.addresses)
        .where((address) => !address.isLoopback)
        .map((address) => 'http://${address.address}:${state.port}/mcp')
        .toSet()
        .toList();
  }

  /// Running state is session-only, including when upgrading from older builds.
  Future<void> setEnabled(bool enabled) async {
    await _prefs.remove(enabledPrefsKey);
    if (enabled) {
      await start(requestOverlayPermission: true);
    } else {
      await stop();
    }
  }

  Future<void> start({bool requestOverlayPermission = false}) async {
    if (state.status == McpServerStatus.running ||
        state.status == McpServerStatus.starting) {
      return;
    }
    state = state.copyWith(status: McpServerStatus.starting, clearNotice: true);
    try {
      if (requireToken && !_tokens.hasToken) {
        await _tokens.regenerate();
      }
      final adapter = ref.read(mcpServerAdapterProvider)
        ..acceptingRequests = true;
      // serverInfo 版本从原生 App 信息回填（失败不阻塞启动）。
      unawaited(_backfillServerVersion(adapter));
      final policy = ref.read(mcpPolicyProvider);
      final transport = McpHttpTransport(
        adapter: adapter,
        tokens: _tokens,
        sessions: ref.read(mcpSessionStoreProvider),
        audit: _audit,
        requireToken: requireToken,
        onSessionTerminated: policy.forgetSession,
      );
      final boundPort = await transport.start(port: state.port);
      _transport = transport;
      _serviceInfo
        ..running = true
        ..port = boundPort;
      _startSweeper();
      state = McpServerState(
        status: McpServerStatus.running,
        port: boundPort,
        requireToken: requireToken,
        startedAt: DateTime.now(),
      );
      _audit.recordServer('running', detail: mcpUrl);
      await refreshKeepAlive(
          requestPermission: requestOverlayPermission, showOverlay: true);
    } catch (e, stackTrace) {
      AppLogger.instance.error(
        'MCP 服务启动失败: $e',
        source: 'McpServer',
        detail: stackTrace.toString(),
      );
      state = state.copyWith(
        status: McpServerStatus.error,
        notice: McpServerNotice.startFailed,
        noticeDetail: e.toString(),
        clearNotice: true,
      );
    }
  }

  Future<void> stop() async {
    final transport = _transport;
    _transport = null;
    _sweepTimer?.cancel();
    _sweepTimer = null;
    _serviceInfo
      ..running = false
      ..port = 0;
    if (transport != null) {
      await transport.stop();
    }
    if (Platform.isAndroid) {
      try {
        await ref.read(nativeBridgeProvider).stopMcpKeepAlive();
      } catch (_) {}
    }
    ref.read(mcpSessionStoreProvider).clearAll();
    ref.read(mcpConfirmationServiceProvider).denyAll();
    // Stopping transport does not cancel native pip processes. Keep their
    // status queryable after the user restarts the server.
    ref.read(mcpPolicyProvider).resetRateCounters();
    state = McpServerState(
      status: McpServerStatus.stopped,
      port: state.port,
      requireToken: requireToken,
    );
  }

  Future<void> refreshKeepAlive(
      {bool requestPermission = false, bool showOverlay = false}) async {
    if (!isRunning || !Platform.isAndroid) return;
    try {
      final allowed = await ref.read(nativeBridgeProvider).startMcpKeepAlive(
          requestPermission: requestPermission, showOverlay: showOverlay);
      if (!isRunning) return;
      state = state.copyWith(
        clearNotice: true,
        notice: allowed ? null : McpServerNotice.overlayPermissionRequired,
      );
    } catch (e) {
      if (isRunning) {
        state = state.copyWith(
          notice: McpServerNotice.keepAliveUnavailable,
          noticeDetail: e.toString(),
          clearNotice: true,
        );
      }
    }
  }

  Future<void> hideOverlay() async {
    if (!isRunning || !Platform.isAndroid) return;
    try {
      await ref.read(nativeBridgeProvider).hideMcpOverlay();
      if (isRunning) state = state.copyWith(clearNotice: true);
    } catch (e) {
      if (isRunning) {
        state = state.copyWith(
          notice: McpServerNotice.hideOverlayFailed,
          noticeDetail: e.toString(),
          clearNotice: true,
        );
      }
    }
  }

  /// 修改端口（仅在停止状态下生效）。
  Future<bool> setPort(int port) async {
    final sanitized = _sanitizePort(port);
    if (sanitized == null) return false;
    await _prefs.setInt(portPrefsKey, sanitized);
    state = state.copyWith(port: sanitized);
    return true;
  }

  /// 重新生成配对令牌；旧令牌立即失效（计划 §8.2）。
  Future<String> regenerateToken() async {
    final token = await _tokens.regenerate();
    ref.read(mcpSessionStoreProvider).clearAll();
    ref.read(mcpConfirmationServiceProvider).denyAll();
    ref.read(mcpPolicyProvider).resetRateCounters();
    return token;
  }

  /// Changes local transport authentication. Restarting the service applies
  /// the new policy to every request and invalidates existing sessions.
  Future<void> setRequireToken(bool value) async {
    await _prefs.setBool(requireTokenPrefsKey, value);
    state = state.copyWith(requireToken: value);
    if (isRunning) {
      await stop();
      await start();
    }
  }

  int? _sanitizePort(int? port) {
    if (port == null || port < 1024 || port > 65535) return null;
    return port;
  }

  Future<void> _backfillServerVersion(McpServerAdapter adapter) async {
    try {
      final info = await ref.read(nativeBridgeProvider).getAppInfo();
      adapter.serverVersion = info['version'] ?? '';
    } catch (_) {
      // 保留空版本号；不影响协议功能。
    }
  }

  void _startSweeper() {
    _sweepTimer?.cancel();
    _sweepTimer = Timer.periodic(sweepInterval, (_) {
      final sessions = ref.read(mcpSessionStoreProvider);
      final swept = sessions.sweepIdle();
      if (swept > 0) {
        _audit.recordServer('sessions_swept', detail: '$swept');
      }
      ref.read(mcpOperationRegistryProvider).sweepExpired();
      unawaited(refreshKeepAlive());
    });
  }
}
