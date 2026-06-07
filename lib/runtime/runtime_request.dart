class RuntimeRequest {
  final String scriptName;
  final String executionId;
  final String? scriptPath;
  final List<String> args;
  final Map<String, String> environment;
  final String? workingDirectory;
  final Duration? timeout;
  final String? projectKey;
  final String? projectMainFilePath;

  const RuntimeRequest({
    required this.scriptName,
    required this.executionId,
    this.scriptPath,
    this.args = const [],
    this.environment = const {},
    this.workingDirectory,
    this.timeout,
    this.projectKey,
    this.projectMainFilePath,
  });

  bool get isProject => projectKey != null;
}
