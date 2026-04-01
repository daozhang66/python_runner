enum LogType { stdout, stderr, info, error }

class LogEntry {
  final LogType type;
  final String content;
  final DateTime timestamp;

  LogEntry({
    required this.type,
    required this.content,
    required this.timestamp,
  });

  factory LogEntry.fromMap(Map<dynamic, dynamic> map) {
    final typeStr = map['type'] as String? ?? 'info';
    final type = LogType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => LogType.info,
    );
    return LogEntry(
      type: type,
      content: map['content'] as String? ?? '',
      timestamp: map['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int)
          : DateTime.now(),
    );
  }
}
