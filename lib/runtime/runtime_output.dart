import '../models/log_entry.dart';

enum RuntimeOutputType { stdout, stderr, info, error }

class RuntimeOutput {
  final RuntimeOutputType type;
  final String content;
  final DateTime timestamp;

  const RuntimeOutput({
    required this.type,
    required this.content,
    required this.timestamp,
  });

  factory RuntimeOutput.fromMap(Map<dynamic, dynamic> map) {
    return RuntimeOutput.fromLogEntry(LogEntry.fromMap(map));
  }

  factory RuntimeOutput.fromLogEntry(LogEntry entry) {
    return RuntimeOutput(
      type: RuntimeOutputType.values.firstWhere(
        (type) => type.name == entry.type.name,
        orElse: () => RuntimeOutputType.info,
      ),
      content: entry.content,
      timestamp: entry.timestamp,
    );
  }

  LogEntry toLogEntry() {
    return LogEntry(
      type: LogType.values.firstWhere(
        (type) => type.name == this.type.name,
        orElse: () => LogType.info,
      ),
      content: content,
      timestamp: timestamp,
    );
  }
}
