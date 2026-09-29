import 'package:flutter/foundation.dart';

import '../domain/mcp_operation.dart';

/// 长任务操作注册表（计划 §10.2）。
///
/// 当传输层不支持 MCP 标准 progress/cancellation 通知时，操作状态仍在此
/// 登记，供设置页展示与后续 `operation.get_status` 工具使用。
class McpOperationRegistry extends ChangeNotifier {
  static const int maxTracked = 50;

  final Map<String, McpOperation> _operations = {};
  int _seq = 0;

  List<McpOperation> get operations {
    final list = _operations.values.toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return List.unmodifiable(list);
  }

  McpOperation? find(String id) => _operations[id];

  McpOperation begin({
    required String kind,
    required String description,
    Duration maxDuration = const Duration(minutes: 15),
  }) {
    final operation = McpOperation(
      id: 'op_${DateTime.now().microsecondsSinceEpoch}_${_seq++}',
      kind: kind,
      description: description,
      maxDuration: maxDuration,
    );
    operation.markRunning();
    _prune();
    _operations[operation.id] = operation;
    notifyListeners();
    return operation;
  }

  void reportProgress(McpOperation operation, String message) {
    if (operation.isFinished) return;
    operation.appendProgress(message);
    notifyListeners();
  }

  void finish(McpOperation operation,
      {String? failureReason, Map<String, dynamic>? result}) {
    if (operation.isFinished) return;
    operation.result = result;
    if (failureReason == null) {
      operation.markSucceeded();
    } else {
      operation.markFailed(failureReason);
    }
    notifyListeners();
  }

  void clearFinished() {
    final before = _operations.length;
    _operations.removeWhere((_, op) => op.isFinished);
    if (_operations.length != before) notifyListeners();
  }

  /// 服务停止时把仍在执行的操作标记为取消。
  void cancelAllActive() {
    var changed = false;
    for (final operation in _operations.values) {
      if (!operation.isFinished) {
        operation.markCancelled('MCP service stopped');
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// 把超过最大执行时间的未完成操作标记为失败。
  void sweepExpired() {
    var changed = false;
    for (final operation in _operations.values) {
      if (operation.isExpired) {
        operation.markFailed(
            'Maximum execution time exceeded; the underlying task may still be running');
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  void _prune() {
    if (_operations.length < maxTracked) return;
    // 优先淘汰已结束的旧操作。
    final finished = _operations.values.where((op) => op.isFinished).toList()
      ..sort((a, b) =>
          (a.finishedAt ?? a.startedAt).compareTo(b.finishedAt ?? b.startedAt));
    var toRemove = _operations.length - maxTracked + 1;
    for (final op in finished) {
      if (toRemove <= 0) break;
      _operations.remove(op.id);
      toRemove--;
    }
    // 仍然超限则淘汰最旧的。
    while (_operations.length >= maxTracked) {
      final oldest = _operations.values.reduce(
        (a, b) => a.startedAt.isBefore(b.startedAt) ? a : b,
      );
      _operations.remove(oldest.id);
    }
  }
}
