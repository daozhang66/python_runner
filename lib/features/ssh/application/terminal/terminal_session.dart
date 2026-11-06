import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:xterm2/xterm.dart' show Terminal;

import '../../presentation/widgets/terminal_pane.dart' show TerminalInputFilter;
import '../log/ansi.dart';
import '../log/session_logger.dart';
import '../log/terminal_logs.dart';
import '../python_launch.dart';
import '../ssh_connection.dart' show HostKeyPrompt;

/// What a session needs from the screen it is shown on: dialogs, and the
/// run console for the built-in `python` command. A session started while no
/// terminal page is open has no host and degrades gracefully.
abstract interface class TerminalHost {
  Future<void> launchPython(PythonLaunch launch);

  List<String> scriptNames();

  Future<String> readScript(String name);

  Future<String?> askSecret(String title);

  Future<bool> confirmHostKey(HostKeyPrompt prompt);
}

enum TerminalSessionStatus { idle, connecting, running, closed, failed }

class OutputSlice {
  const OutputSlice({
    required this.text,
    required this.next,
    required this.dropped,
  });

  final String text;

  /// Cursor to pass to the next read.
  final int next;

  /// True when output before the requested cursor was already discarded.
  final bool dropped;
}

/// The most recent plain-text output of a session, addressed by a cursor that
/// only grows. Lets an AI read "what is new since last time".
class OutputRing {
  OutputRing({this.capacity = 200000});

  final int capacity;
  String _buffer = '';
  int _start = 0;

  /// Cursor just after the newest character.
  int get end => _start + _buffer.length;

  void append(String text) {
    if (text.isEmpty) return;
    _buffer += text;
    if (_buffer.length > capacity) {
      final cut = _buffer.length - capacity;
      _buffer = _buffer.substring(cut);
      _start += cut;
    }
  }

  OutputSlice read(int from, {int maxChars = 20000}) {
    var offset = from;
    var dropped = false;
    if (offset < _start) {
      offset = _start;
      dropped = true;
    }
    if (offset > end) offset = end;
    final begin = offset - _start;
    final stop =
        begin + maxChars < _buffer.length ? begin + maxChars : _buffer.length;
    return OutputSlice(
      text: _buffer.substring(begin, stop),
      next: _start + stop,
      dropped: dropped,
    );
  }
}

/// One terminal: its screen, its output history, its log, and a way to type
/// into it. The same object is used by the person (keyboard) and the AI
/// (`sendText`), so both see the same terminal.
abstract class TerminalSession extends ChangeNotifier {
  TerminalSession({
    required this.id,
    required this.kind,
    required String title,
    TerminalLogs? logs,
  }) : _title = title {
    logger = SessionLogger(
      sessionId: id,
      sink: (channel, record) => (logs ?? TerminalLogs.instance).add(
        channel,
        record,
      ),
    );
  }

  final String id;

  /// `local` or `ssh`.
  final String kind;

  String _title;
  String get title => _title;
  set title(String value) {
    _title = value;
    notifyListeners();
  }

  final Terminal terminal = Terminal(maxLines: 10000);
  final TerminalInputFilter filter = TerminalInputFilter();
  final OutputRing ring = OutputRing();
  late final SessionLogger logger;

  TerminalHost? host;

  TerminalSessionStatus _status = TerminalSessionStatus.idle;
  String? statusDetail;

  TerminalSessionStatus get status => _status;

  bool get isAlive =>
      _status == TerminalSessionStatus.connecting ||
      _status == TerminalSessionStatus.running;

  @protected
  void setStatus(TerminalSessionStatus value, [String? detail]) {
    _status = value;
    statusDetail = detail;
    notifyListeners();
  }

  /// Shows [raw] on the screen, keeps it for readers and records it.
  @protected
  void emit(String raw) {
    terminal.write(raw);
    ring.append(stripAnsi(raw));
    logger.output(raw);
  }

  /// Local echo of typed characters: shown and readable, but not logged as
  /// output (the command itself is logged as a command).
  @protected
  void echo(String text) {
    terminal.write(text);
    ring.append(stripAnsi(text));
  }

  void info(String text) => emit('\x1b[90m$text\x1b[0m\r\n');

  void error(String text) => emit('\x1b[31m$text\x1b[0m\r\n');

  Future<void> start();

  Future<void> close();

  Future<void> restart() async {
    await close();
    await start();
  }

  /// Types [text] as if it came from the keyboard. [actor] is `human` or `ai`
  /// and decides how the command is attributed in the logs.
  void sendText(String text, {String actor = 'human'});

  /// Ctrl+C.
  void interrupt();

  Map<String, Object?> describe() => <String, Object?>{
        'id': id,
        'kind': kind,
        'title': title,
        'status': status.name,
        if (statusDetail != null) 'detail': statusDetail,
        'output_cursor': ring.end,
      };

  @override
  void dispose() {
    logger.dispose();
    super.dispose();
  }
}
