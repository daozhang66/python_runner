import 'package:flutter/foundation.dart';

/// 审计事件类型。
enum McpAuditKind { server, connect, disconnect, toolCall }

/// 一条审计记录（计划 §8.4）。
///
/// 只记录参数摘要（截断）、令牌指纹与结果状态；
/// 禁止记录令牌明文、完整 Cookie、Authorization、完整请求体或完整脚本正文。
class McpAuditEntry {
  const McpAuditEntry({
    required this.timestamp,
    required this.kind,
    required this.status,
    this.sessionId,
    this.clientLabel,
    this.tool,
    this.argsSummary,
    this.permissionDecision = '',
    this.confirmationRequired = false,
    this.errorCode,
    this.durationMs,
    this.tokenFingerprint,
  });

  final DateTime timestamp;
  final McpAuditKind kind;
  final String status; // ok / error / rejected / started / stopped
  final String? sessionId;
  final String? clientLabel;
  final String? tool;
  final String? argsSummary;
  final String permissionDecision;
  final bool confirmationRequired;
  final String? errorCode;
  final int? durationMs;
  final String? tokenFingerprint;

  Map<String, dynamic> toMap() => {
        'timestamp': timestamp.toUtc().toIso8601String(),
        'kind': kind.name,
        'status': status,
        if (sessionId != null) 'session_id': sessionId,
        if (clientLabel != null) 'client': clientLabel,
        if (tool != null) 'tool': tool,
        if (argsSummary != null) 'args': argsSummary,
        if (permissionDecision.isNotEmpty)
          'permission_decision': permissionDecision,
        if (confirmationRequired) 'confirmation_required': true,
        if (errorCode != null) 'error_code': errorCode,
        if (durationMs != null) 'duration_ms': durationMs,
        if (tokenFingerprint != null) 'token_fp': tokenFingerprint,
      };
}

/// 内存环形审计日志（默认保留最近 200 条），供设置页展示与清空。
class McpAuditLog extends ChangeNotifier {
  static const int capacity = 200;
  static const int maxSummaryLength = 300;

  final List<McpAuditEntry> _entries = [];

  List<McpAuditEntry> get entries => List.unmodifiable(_entries);

  void recordServer(String status, {String? detail}) {
    _add(McpAuditEntry(
      timestamp: DateTime.now(),
      kind: McpAuditKind.server,
      status: status,
      argsSummary: detail != null ? _summarize(detail) : null,
    ));
  }

  void recordConnect({
    required String sessionId,
    required String clientLabel,
    required String tokenFingerprint,
  }) {
    _add(McpAuditEntry(
      timestamp: DateTime.now(),
      kind: McpAuditKind.connect,
      status: 'ok',
      sessionId: sessionId,
      clientLabel: clientLabel,
      tokenFingerprint: tokenFingerprint,
    ));
  }

  void recordDisconnect({
    required String sessionId,
    required String clientLabel,
    String reason = 'client',
  }) {
    _add(McpAuditEntry(
      timestamp: DateTime.now(),
      kind: McpAuditKind.disconnect,
      status: 'ok',
      sessionId: sessionId,
      clientLabel: clientLabel,
      argsSummary: reason,
    ));
  }

  void recordToolCall({
    required String sessionId,
    required String clientLabel,
    required String tool,
    String? argsSummary,
    required String permissionDecision,
    required bool confirmationRequired,
    required bool ok,
    String? errorCode,
    required int durationMs,
  }) {
    _add(McpAuditEntry(
      timestamp: DateTime.now(),
      kind: McpAuditKind.toolCall,
      status: ok ? 'ok' : 'error',
      sessionId: sessionId,
      clientLabel: clientLabel,
      tool: tool,
      argsSummary: argsSummary == null ? null : _summarize(argsSummary),
      permissionDecision: permissionDecision,
      confirmationRequired: confirmationRequired,
      errorCode: errorCode,
      durationMs: durationMs,
    ));
  }

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }

  void _add(McpAuditEntry entry) {
    _entries.add(entry);
    if (_entries.length > capacity) {
      _entries.removeRange(0, _entries.length - capacity);
    }
    notifyListeners();
  }

  String _summarize(String value) {
    if (value.length <= maxSummaryLength) return value;
    return '${value.substring(0, maxSummaryLength)}…(${value.length})';
  }
}
