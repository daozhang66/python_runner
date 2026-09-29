import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/mcp_error_codes.dart';
import '../domain/mcp_permission.dart';
import '../domain/mcp_tool_definition.dart';

/// MCP 策略服务（计划 §4 Policy Layer）。
///
/// 负责：
/// - 工具权限检查（用户在设置页开启的权限集合）；
/// - 每会话限流（滑动窗口）；
/// - 权限集合持久化。
///
/// 用户确认流程由 [McpConfirmationService] 承担，本服务只做静态判定。
class McpPolicyService {
  McpPolicyService({required SharedPreferences preferences})
      : _prefs = preferences {
    _enabled = _load();
  }

  static const String prefsKey = 'mcp.permissions.enabled';

  final SharedPreferences _prefs;
  late Set<McpPermission> _enabled;

  /// 每会话每分钟最大工具调用数（计划 §4 rate limit）。
  static const int perSessionRateLimit = 60;
  static const Duration rateWindow = Duration(minutes: 1);

  final Map<String, List<DateTime>> _callTimestamps = {};

  Set<McpPermission> get enabledPermissions => Set.of(_enabled);

  bool isPermissionEnabled(McpPermission permission) =>
      _enabled.contains(permission);

  Future<void> setPermissionEnabled(McpPermission permission, bool value) {
    final next = Set.of(_enabled);
    if (value) {
      next.add(permission);
    } else {
      next.remove(permission);
    }
    return updateEnabledPermissions(next);
  }

  Future<void> updateEnabledPermissions(Set<McpPermission> permissions) async {
    _enabled = Set.of(permissions);
    await _prefs.setStringList(
      prefsKey,
      permissions.map((permission) => permission.id).toList(),
    );
  }

  Set<McpPermission> _load() {
    final ids = _prefs.getStringList(prefsKey);
    if (ids == null) return McpPermission.defaults;
    // An explicitly empty or obsolete configuration must fail closed.
    return McpPermission.fromIds(ids);
  }

  /// 工具权限检查：未开启对应权限时抛 [McpToolException]（MCP_FORBIDDEN）。
  void checkToolPermission(McpToolDefinition tool) {
    if (_enabled.contains(tool.permission)) return;
    throw McpToolException(
      McpErrorCodes.mcpForbidden,
      'Permission is not enabled: ${tool.permission.displayName} (${tool.permission.id}). '
      'Enable it on the AI / MCP service page in app settings',
      false,
      {
        'permission': tool.permission.id,
        'tool': tool.name,
      },
    );
  }

  /// 滑动窗口限流：超过配额抛 RATE_LIMITED。
  void checkRateLimit(String sessionId, {DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    final window = _callTimestamps.putIfAbsent(sessionId, () => <DateTime>[]);
    window.removeWhere((item) => timestamp.difference(item) > rateWindow);
    if (window.length >= perSessionRateLimit) {
      throw McpToolException(
        McpErrorCodes.rateLimited,
        'Too many requests ($perSessionRateLimit per minute); retry later',
        true,
      );
    }
    window.add(timestamp);
  }

  /// 会话结束或服务停止时清理计数。
  void forgetSession(String sessionId) => _callTimestamps.remove(sessionId);

  void resetRateCounters() => _callTimestamps.clear();
}
