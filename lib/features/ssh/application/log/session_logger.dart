import 'dart:async';

import 'ansi.dart';
import 'log_record.dart';

typedef LogSink = void Function(LogChannel channel, LogRecord record);

final RegExp _secretPrompt = RegExp(
  r'(pass(word|phrase|code)|口令|密码)[^\n]{0,40}[:：]\s*$',
  caseSensitive: false,
);

/// Writes what happens in one terminal session to the terminal log.
///
/// Output is collected into blocks (about a second or 4000 characters) and
/// stored without control sequences. A line typed right after a password
/// prompt is recorded as hidden, never as text.
class SessionLogger {
  SessionLogger({
    required this.sessionId,
    required this.sink,
    this.flushDelay = const Duration(seconds: 1),
  });

  final String sessionId;
  final LogSink sink;
  final Duration flushDelay;

  final StringBuffer _out = StringBuffer();
  final StringBuffer _typed = StringBuffer();
  Timer? _timer;
  bool _expectSecret = false;

  /// True while the terminal is showing a password prompt: the next typed
  /// line is recorded as hidden. Call [flushOutput] first for a fresh answer.
  bool get expectingSecret => _expectSecret;

  void _emit(LogRecord record) => sink(LogChannel.terminal, record);

  /// A key event of the session itself (opened, closed, failed, ...).
  void event(
    String kind,
    String summary, {
    int importance = 0,
    String? detail,
    String actor = 'system',
  }) {
    flushOutput();
    _emit(
      LogRecord.now(
        k: kind,
        s: summary,
        sid: sessionId,
        a: actor,
        i: importance,
        d: detail,
      ),
    );
  }

  /// A finished command line.
  void input(String line, {String actor = 'human'}) {
    flushOutput();
    final hidden = _expectSecret;
    _expectSecret = false;
    _emit(
      LogRecord.now(
        k: 'cmd',
        s: hidden ? '<hidden input>' : line,
        sid: sessionId,
        a: actor,
        i: 0,
      ),
    );
  }

  /// Raw keystrokes (SSH sessions only see these): collects them into lines.
  void feedInput(String data, {String actor = 'human'}) {
    final runes = data.runes.toList();
    var i = 0;
    while (i < runes.length) {
      final rune = runes[i];
      i++;
      if (rune == 0x1b) {
        if (i < runes.length && (runes[i] == 0x5b || runes[i] == 0x4f)) {
          i++;
          while (i < runes.length && !(runes[i] >= 0x40 && runes[i] <= 0x7e)) {
            i++;
          }
          i++;
        } else {
          i++;
        }
        continue;
      }
      if (rune == 0x0d || rune == 0x0a) {
        if (rune == 0x0d && i < runes.length && runes[i] == 0x0a) i++;
        final line = _typed.toString();
        _typed.clear();
        if (line.trim().isNotEmpty || _expectSecret) input(line, actor: actor);
      } else if (rune == 0x7f || rune == 0x08) {
        final text = _typed.toString();
        if (text.isNotEmpty) {
          final chars = text.runes.toList()..removeLast();
          _typed
            ..clear()
            ..write(String.fromCharCodes(chars));
        }
      } else if (rune == 0x03) {
        _typed.clear();
        event('cmd', '^C', actor: actor);
      } else if (rune >= 0x20) {
        _typed.writeCharCode(rune);
      }
    }
  }

  /// Output as the terminal received it (with control sequences).
  void output(String raw) {
    _out.write(raw);
    if (_out.length >= 4000) {
      flushOutput();
    } else {
      _timer ??= Timer(flushDelay, flushOutput);
    }
  }

  void flushOutput() {
    _timer?.cancel();
    _timer = null;
    if (_out.isEmpty) return;
    final raw = _out.toString();
    _out.clear();
    final text = stripAnsi(raw);
    final tail = text.length > 160 ? text.substring(text.length - 160) : text;
    if (_secretPrompt.hasMatch(tail)) _expectSecret = true;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final lines = trimmed.split('\n');
    final headline = lines.first.length > 100
        ? '${lines.first.substring(0, 100)}…'
        : lines.first;
    _emit(
      LogRecord.now(
        k: 'out',
        s: lines.length > 1 ? '$headline  (+${lines.length - 1} lines)' : headline,
        sid: sessionId,
        i: 1,
        d: trimmed,
      ),
    );
  }

  void dispose() {
    flushOutput();
  }
}
