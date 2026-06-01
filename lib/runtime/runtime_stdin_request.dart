class RuntimeStdinRequest {
  final String? executionId;
  final String prompt;

  const RuntimeStdinRequest({
    this.executionId,
    this.prompt = '',
  });

  factory RuntimeStdinRequest.fromMap(Map<dynamic, dynamic> map) {
    return RuntimeStdinRequest(
      executionId: map['executionId'] as String?,
      prompt: map['prompt'] as String? ?? '',
    );
  }
}
