/// 长任务操作状态（计划 §10.2：包安装等不能无限等待）。
enum McpOperationStatus { pending, running, succeeded, failed, cancelled }

/// 应用级长任务跟踪：operation id、状态、进度与最大执行时间。
///
/// 首期用于 `package.install`；当前选用的传输层不支持 MCP 标准
/// progress/cancellation 通知，取消能力暂不可用（见开发记录）。
class McpOperation {
  McpOperation({
    required this.id,
    required this.kind,
    required this.description,
    required this.maxDuration,
    DateTime? startedAt,
  })  : status = McpOperationStatus.pending,
        startedAt = startedAt ?? DateTime.now(),
        progressMessages = <String>[];

  final String id;
  final String kind;
  final String description;
  final DateTime startedAt;
  final Duration maxDuration;
  final List<String> progressMessages;

  McpOperationStatus status;
  String? failureReason;
  Map<String, dynamic>? result;
  DateTime? finishedAt;

  bool get isFinished =>
      status == McpOperationStatus.succeeded ||
      status == McpOperationStatus.failed ||
      status == McpOperationStatus.cancelled;

  bool get isExpired =>
      !isFinished && DateTime.now().isAfter(startedAt.add(maxDuration));

  void markRunning() => status = McpOperationStatus.running;

  void markSucceeded() {
    status = McpOperationStatus.succeeded;
    finishedAt = DateTime.now();
  }

  void markFailed(String reason) {
    status = McpOperationStatus.failed;
    failureReason = reason;
    finishedAt = DateTime.now();
  }

  void markCancelled(String reason) {
    status = McpOperationStatus.cancelled;
    failureReason = reason;
    finishedAt = DateTime.now();
  }

  void appendProgress(String message) {
    progressMessages.add(message);
    if (progressMessages.length > 50) {
      progressMessages.removeRange(0, progressMessages.length - 50);
    }
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'kind': kind,
        'description': description,
        'status': status.name,
        'started_at': startedAt.toUtc().toIso8601String(),
        'max_duration_ms': maxDuration.inMilliseconds,
        if (progressMessages.isNotEmpty) 'last_progress': progressMessages.last,
        if (failureReason != null) 'failure_reason': failureReason,
        if (result != null) 'result': result,
        if (finishedAt != null)
          'finished_at': finishedAt!.toUtc().toIso8601String(),
      };
}
