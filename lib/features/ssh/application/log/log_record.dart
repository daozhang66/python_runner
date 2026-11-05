/// The three logs kept for terminals and AI use.
enum LogChannel {
  /// What happened in terminal sessions: commands typed and output shown.
  terminal('terminal'),

  /// Messages between the person and the AI.
  conversation('conversation'),

  /// Every operation the AI asked for, how it was approved and what came
  /// back.
  operations('operations');

  const LogChannel(this.dirName);

  final String dirName;
}

/// One log line.
///
/// Importance decides at which detail level a record is shown:
/// 0 = key events (always), 1 = normal (output summaries, results),
/// 2 = verbose (raw arguments, full results).
class LogRecord {
  const LogRecord({
    required this.t,
    required this.k,
    required this.s,
    this.sid = '',
    this.a = 'system',
    this.i = 1,
    this.d,
    this.x,
  });

  factory LogRecord.now({
    required String k,
    required String s,
    String sid = '',
    String a = 'system',
    int i = 1,
    String? d,
    Map<String, Object?>? x,
  }) {
    return LogRecord(
      t: DateTime.now().microsecondsSinceEpoch,
      k: k,
      s: s.length > 300 ? '${s.substring(0, 300)}…' : s,
      sid: sid,
      a: a,
      i: i,
      d: _cap(d),
      x: x,
    );
  }

  factory LogRecord.fromJson(Map<String, dynamic> json) {
    return LogRecord(
      t: (json['t'] as num).toInt(),
      k: json['k'] as String? ?? '',
      s: json['s'] as String? ?? '',
      sid: json['sid'] as String? ?? '',
      a: json['a'] as String? ?? 'system',
      i: (json['i'] as num?)?.toInt() ?? 1,
      d: json['d'] as String?,
      x: (json['x'] as Map?)?.cast<String, Object?>(),
    );
  }

  static const int maxDetailChars = 32000;

  static String? _cap(String? value) {
    if (value == null || value.length <= maxDetailChars) return value;
    return '${value.substring(0, maxDetailChars)}\n…(${value.length} chars, cut)';
  }

  /// Microseconds since the epoch.
  final int t;

  /// Kind: cmd, out, session, msg, ask, op, approval, result, ...
  final String k;

  /// Summary, one line.
  final String s;

  /// Session (terminal session or AI conversation) the record belongs to.
  final String sid;

  /// Who: human, ai or system.
  final String a;
  final int i;

  /// Detail text, shown at the standard and detailed levels.
  final String? d;

  /// Structured extras (host, exit code, arguments, ...).
  final Map<String, Object?>? x;

  DateTime get time => DateTime.fromMicrosecondsSinceEpoch(t);

  Map<String, Object?> toJson() => <String, Object?>{
        't': t,
        'k': k,
        's': s,
        if (sid.isNotEmpty) 'sid': sid,
        'a': a,
        'i': i,
        if (d != null) 'd': d,
        if (x != null) 'x': x,
      };
}

/// The part of [record]'s detail shown at [level]: none for the summary
/// level, 400 characters at the standard level, everything at the detailed
/// level.
String? visibleLogDetail(LogRecord record, int level) {
  final detail = record.d;
  if (level <= 0 || detail == null || detail.isEmpty) return null;
  if (level == 1 && detail.length > 400) {
    return '${detail.substring(0, 400)}… (${detail.length})';
  }
  return detail;
}

/// Plain-text form of [record] for export.
String formatLogRecord(LogRecord record, int level, {bool withDate = false}) {
  final time = record.time;
  String two(int n) => n.toString().padLeft(2, '0');
  final date =
      withDate ? '${time.year}-${two(time.month)}-${two(time.day)} ' : '';
  final stamp = '$date${two(time.hour)}:${two(time.minute)}:${two(time.second)}'
      '.${time.millisecond.toString().padLeft(3, '0')}';
  final session = record.sid.isEmpty ? '' : ' (${record.sid})';
  final head = '$stamp [${record.a}]$session ${record.s}';
  final detail = visibleLogDetail(record, level);
  if (detail == null) return head;
  final indented = detail.split('\n').map((line) => '    $line').join('\n');
  return '$head\n$indented';
}
