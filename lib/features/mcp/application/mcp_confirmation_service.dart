import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/mcp_error_codes.dart';

/// 用户确认决策（计划 §8.3）。
enum McpConfirmationDecision { pending, allow, allowSession, deny, timeout }

/// 一条待确认的 MCP 操作。
///
/// 展示层（设置页 / 全局确认弹窗）通过 [decision] Future 感知结果；
/// 摘要文本不得包含完整密钥、Cookie 或超长代码正文。
class McpPendingConfirmation {
  McpPendingConfirmation({
    required this.id,
    required this.toolName,
    required this.summary,
    required this.clientLabel,
    required this.createdAt,
    required this.timeoutAt,
  }) {
    _completer = Completer<McpConfirmationDecision>();
  }

  final String id;
  final String toolName;
  final String summary;
  final String clientLabel;
  final DateTime createdAt;
  final DateTime timeoutAt;

  late final Completer<McpConfirmationDecision> _completer;
  McpConfirmationDecision _decision = McpConfirmationDecision.pending;

  McpConfirmationDecision get decision => _decision;
  Future<McpConfirmationDecision> get future => _completer.future;
  bool get isResolved => _completer.isCompleted;

  bool resolve(McpConfirmationDecision value) {
    if (_completer.isCompleted) return false;
    _decision = value;
    _completer.complete(value);
    return true;
  }

  /// 超时自动拒绝（不抛异常，返回 timeout 决策）。
  McpConfirmationDecision resolveTimeout() {
    if (_completer.isCompleted) return _decision;
    _decision = McpConfirmationDecision.timeout;
    _completer.complete(McpConfirmationDecision.timeout);
    return McpConfirmationDecision.timeout;
  }
}

/// 用户确认服务：MCP 工具的写操作在执行前必须获得用户允许（计划 §8.3）。
///
/// - 超过 60 秒未处理自动拒绝；
/// - 「本次会话内允许」记录在会话的 allowedTools，后续同类调用免确认；
/// - 服务停止时未决请求立即按拒绝结束。
class McpConfirmationService extends ChangeNotifier {
  static const Duration defaultTimeout = Duration(seconds: 60);

  final Duration timeout;
  final Map<String, McpPendingConfirmation> _pending = {};
  int _seq = 0;

  McpConfirmationService({this.timeout = defaultTimeout});

  List<McpPendingConfirmation> get pending =>
      List.unmodifiable(_pending.values);

  /// 请求用户确认；返回最终决策。
  Future<McpConfirmationDecision> request({
    required String toolName,
    required String summary,
    required String clientLabel,
  }) {
    final item = McpPendingConfirmation(
      id: 'confirm_${DateTime.now().microsecondsSinceEpoch}_${_seq++}',
      toolName: toolName,
      summary: summary,
      clientLabel: clientLabel,
      createdAt: DateTime.now(),
      timeoutAt: DateTime.now().add(timeout),
    );
    _pending[item.id] = item;
    notifyListeners();

    Future<void>.delayed(timeout, () {
      if (_pending.remove(item.id) != null && !item.isResolved) {
        item.resolveTimeout();
        notifyListeners();
      }
    });

    return item.future;
  }

  bool resolve(String id, McpConfirmationDecision decision) {
    final item = _pending[id];
    if (item == null) return false;
    final removed = _pending.remove(id) != null;
    final resolved = item.resolve(decision);
    if (removed || resolved) notifyListeners();
    return resolved;
  }

  /// 服务停止：未决请求全部拒绝。
  void denyAll() {
    if (_pending.isEmpty) return;
    for (final item in _pending.values) {
      item.resolve(McpConfirmationDecision.deny);
    }
    _pending.clear();
    notifyListeners();
  }

  /// 把决策映射为工具异常（allow/allowSession 之外的路径）。
  static McpToolException? toException(McpConfirmationDecision decision) {
    switch (decision) {
      case McpConfirmationDecision.allow:
      case McpConfirmationDecision.allowSession:
        return null;
      case McpConfirmationDecision.pending:
      case McpConfirmationDecision.deny:
        return McpToolException(
          McpErrorCodes.mcpForbidden,
          'The user denied this operation',
          false,
        );
      case McpConfirmationDecision.timeout:
        return McpToolException(
          McpErrorCodes.userConfirmationTimeout,
          'User confirmation timed out after 60 seconds; the operation was denied automatically',
          true,
        );
    }
  }
}
