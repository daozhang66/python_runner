enum ExecutionStatus { idle, running, stopping, completed, error, stopped, timeout }

class ExecutionState {
  final String? executionId;
  final ExecutionStatus status;
  final int? exitCode;

  const ExecutionState({
    this.executionId,
    this.status = ExecutionStatus.idle,
    this.exitCode,
  });

  ExecutionState copyWith({
    String? executionId,
    ExecutionStatus? status,
    int? exitCode,
  }) {
    return ExecutionState(
      executionId: executionId ?? this.executionId,
      status: status ?? this.status,
      exitCode: exitCode,
    );
  }

  factory ExecutionState.fromMap(Map<dynamic, dynamic> map) {
    final statusStr = map['status'] as String? ?? 'idle';
    final status = ExecutionStatus.values.firstWhere(
      (e) => e.name == statusStr,
      orElse: () => ExecutionStatus.idle,
    );
    return ExecutionState(
      executionId: map['executionId'] as String?,
      status: status,
      exitCode: map['exitCode'] as int?,
    );
  }
}
