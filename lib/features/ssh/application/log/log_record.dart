import 'dart:convert';

import '../terminal/terminal_locale.dart';

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

const int _standardLines = 10;
const int _standardChars = 600;

/// What of [record]'s detail is shown at [level]:
///
/// * 0 (summary): nothing;
/// * 1 (standard): a readable digest. Output is cut to about ten lines, and
///   an MCP call shows only what matters (arguments, error, slow or refused
///   calls) instead of its raw JSON;
/// * 2 (detailed): everything. Complete script and terminal output, and the
///   full pretty-printed JSON of MCP calls.
String? visibleLogDetail(LogRecord record, int level) {
  final detail = record.d;
  if (level <= 0 || detail == null || detail.isEmpty) return null;
  if (record.k.startsWith('mcp_')) return _mcpDetail(detail, level);
  if (level >= 2) return detail;
  return _clipForStandard(detail);
}

String _clipForStandard(String text) {
  final lines = text.split('\n');
  var out = lines.length > _standardLines
      ? lines.take(_standardLines).join('\n')
      : text;
  if (out.length > _standardChars) out = out.substring(0, _standardChars);
  if (out.length == text.length) return text;
  return '$out\n… ${tr('共 ${lines.length} 行、${text.length} 个字符，切到「详细」查看全部', '${lines.length} lines, ${text.length} characters; switch to Detailed for everything')}';
}

String? _mcpDetail(String raw, int level) {
  Object? json;
  try {
    json = jsonDecode(raw);
  } catch (_) {
    return raw;
  }
  if (json is! Map) return raw;
  if (level >= 2) return const JsonEncoder.withIndent('  ').convert(json);
  final lines = <String>[];
  final args = json['args'];
  if (args is String && args.isNotEmpty) lines.add(args);
  final code = json['error_code'];
  if (code != null) lines.add('${tr('错误', 'error')}: $code');
  final decision = json['permission_decision'];
  if (decision is String && decision.isNotEmpty && decision != 'allowed') {
    lines.add('${tr('权限', 'permission')}: $decision');
  }
  final ms = json['duration_ms'];
  if (ms != null) lines.add('$ms ms');
  return lines.isEmpty ? null : lines.join('\n');
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
