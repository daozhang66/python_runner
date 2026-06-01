class RuntimeHealth {
  final bool ok;
  final String message;
  final Map<String, String> details;

  const RuntimeHealth({
    required this.ok,
    this.message = '',
    this.details = const {},
  });
}
