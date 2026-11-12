import 'dart:math' as math;

import '../../../../models/execution_state.dart';
import '../../../../models/log_entry.dart';
import '../../../../providers/execution_provider.dart';
import 'ansi.dart';
import 'log_record.dart';
import 'terminal_logs.dart';

/// A line that asks for a password: whatever is typed after it is not logged.
final RegExp _passwordAsk = RegExp(
  r'(pass(word|phrase|code)|口令|密码)[^\n]{0,40}[:：]\s*$',
  caseSensitive: false,
);

/// A prompt line with the answer already merged into it.
final RegExp _passwordAnswered = RegExp(
  r'^.*?(pass(word|phrase|code)|口令|密码)[^\n]{0,40}?[:：]\s*\S.*$',
  caseSensitive: false,
);

/// Records every script run — everything the run console shows, and every
/// answer typed to `input()` — and files it by who started it:
///
/// * started by a person (home screen, editor, terminal commands) → the
///   terminal log;
/// * started by an AI over MCP → the AI operations log, including the inputs
///   the AI sent, so nothing an AI did is hidden.
///
/// The one thing it leaves out is an answer to a password prompt (for example
/// from `getpass`); that is recorded as hidden.
///
/// It only observes the shared [ExecutionProvider]; it never changes a run.
class RunLogRecorder {
  RunLogRecorder._();

  static final RunLogRecorder instance = RunLogRecorder._();

  static const int _maxCharsPerRun = 2 * 1024 * 1024;
  static const int _recordChars = 24 * 1024;

  ExecutionProvider? _exec;
  bool _aiPending = false;
  String? _nextLabel;

  String? _runId;
  String _origin = 'human';
  String _sid = '';
  int _seenAbs = 0;
  String _lastContent = '';
  String _lastOutput = '';
  int _recorded = 0;
  bool _capNoted = false;
  bool _wasRunning = false;
  bool _promptShown = false;
  int _seq = 0;
  String _skipEcho = '';

  LogChannel get _channel =>
      _origin == 'ai' ? LogChannel.operations : LogChannel.terminal;

  /// Starts watching [exec]. Calling it again with the same provider is free.
  void attach(ExecutionProvider exec) {
    if (identical(_exec, exec)) return;
    _exec?.removeListener(_onChange);
    _exec = exec;
    exec.addListener(_onChange);
    _onChange();
  }

  /// Call right before an AI starts a run: the next run is the AI's.
  void expectAiRun() => _aiPending = true;

  /// The AI's run could not be started after all.
  void cancelExpectedAiRun() => _aiPending = false;

  /// A readable name for the next run (for example `python demo.py`).
  void setNextLabel(String label) => _nextLabel = label;

  /// What the run console shows last, which is the prompt an answer follows.
  String _lastShownLine() {
    final logs = _exec?.logs;
    return logs == null || logs.isEmpty ? '' : logs.last.content;
  }

  /// An answer an AI sent to the running script.
  void noteAiInput(String input) {
    final secret = _passwordAsk.hasMatch(_lastShownLine());
    _skipEcho = input;
    TerminalLogs.instance.add(
      LogChannel.operations,
      LogRecord.now(
        k: 'run_in',
        s: secret ? 'AI input: <hidden input>' : 'AI input: $input',
        sid: _sid.isEmpty ? 'run' : _sid,
        a: 'ai',
        i: 0,
        d: secret ? null : input,
      ),
    );
  }

  void noteAiStop() {
    TerminalLogs.instance.add(
      LogChannel.operations,
      LogRecord.now(
        k: 'run',
        s: 'AI asked to stop the run',
        sid: _sid.isEmpty ? 'run' : _sid,
        a: 'ai',
        i: 0,
      ),
    );
  }

  void _emit(LogRecord record) =>
      TerminalLogs.instance.add(_channel, record);

  ScriptLogRecord? _historyOf(ExecutionProvider exec, String id) {
    final history = exec.logHistory;
    for (var i = history.length - 1; i >= 0; i--) {
      if (history[i].executionId == id) return history[i];
    }
    return null;
  }

  void _onChange() {
    final exec = _exec;
    if (exec == null) return;
    final id = exec.state.executionId;
    if (id != null && id != _runId) {
      if (_runId != null) _finish(exec, superseded: true);
      _begin(exec, id);
    }
    if (_runId != null) _drain(exec);
    final running = exec.isRunning;
    if (_wasRunning && !running && _runId != null) _finish(exec);
    _wasRunning = running;
    _promptShown = exec.waitingForInput;
  }

  void _begin(ExecutionProvider exec, String id) {
    _runId = id;
    _origin = _aiPending ? 'ai' : 'human';
    _aiPending = false;
    _seq++;
    _sid = 'run-$_seq';
    _seenAbs = 0;
    _lastContent = '';
    _lastOutput = '';
    _recorded = 0;
    _capNoted = false;
    _skipEcho = '';
    final name = _nextLabel ?? exec.currentScriptName ?? '?';
    _nextLabel = null;
    _emit(
      LogRecord.now(
        k: 'run',
        s: 'run started: $name',
        sid: _sid,
        a: _origin,
        i: 0,
        d: 'script: ${exec.currentScriptName ?? '?'}\n'
            'command: $name\n'
            'execution: $id\n'
            'started by: $_origin',
      ),
    );
  }

  void _drain(ExecutionProvider exec) {
    final id = _runId;
    if (id == null) return;
    final record = _historyOf(exec, id);
    if (record == null) return;
    final logs = record.logs;
    final total = record.droppedLogCount + logs.length;
    if (total < _seenAbs) {
      _seenAbs = total;
      return;
    }
    if (total == _seenAbs) {
      // Same length: the last line may have been rewritten, which is how an
      // answer typed to input() is merged into its prompt line.
      if (logs.isNotEmpty && logs.last.content != _lastContent) {
        _lastContent = logs.last.content;
        if (_promptShown) {
          _recordInput(
            logs.last.content,
            secret: _passwordAnswered.hasMatch(logs.last.content),
          );
        }
      }
      return;
    }
    var start = _seenAbs - record.droppedLogCount;
    if (start < 0) start = 0;
    final fresh = logs.sublist(start);
    _seenAbs = total;
    _lastContent = logs.last.content;
    _writeEntries(fresh);
  }

  void _writeEntries(List<LogEntry> entries) {
    LogType? groupType;
    final buffer = StringBuffer();
    void flush() {
      if (buffer.isEmpty) return;
      _writeOutput(groupType ?? LogType.stdout, buffer.toString());
      buffer.clear();
    }

    for (final entry in entries) {
      if (entry.type == LogType.info && entry.content.startsWith('> ')) {
        flush();
        groupType = null;
        _recordInput(
          entry.content.substring(2),
          secret: _passwordAsk.hasMatch(_lastOutput),
        );
        _lastOutput = '';
        continue;
      }
      _lastOutput = entry.content;
      final type = (entry.type == LogType.stderr || entry.type == LogType.error)
          ? LogType.stderr
          : entry.type;
      if (groupType != type) {
        flush();
        groupType = type;
      }
      buffer.write(entry.content);
      if (!entry.content.endsWith('\n')) buffer.write('\n');
    }
    flush();
  }

  void _writeOutput(LogType type, String text) {
    final plain = stripAnsi(text).trimRight();
    if (plain.isEmpty) return;
    if (_recorded >= _maxCharsPerRun) {
      if (!_capNoted) {
        _capNoted = true;
        _emit(
          LogRecord.now(
            k: 'run_out',
            s: 'output cut: the log keeps at most $_maxCharsPerRun characters per run',
            sid: _sid,
            i: 0,
          ),
        );
      }
      return;
    }
    _recorded += plain.length;
    final isError = type == LogType.stderr;
    for (var offset = 0; offset < plain.length; offset += _recordChars) {
      final piece =
          plain.substring(offset, math.min(plain.length, offset + _recordChars));
      final lines = piece.split('\n');
      final head = lines.first.length > 100
          ? '${lines.first.substring(0, 100)}…'
          : lines.first;
      _emit(
        LogRecord.now(
          k: isError ? 'run_err' : 'run_out',
          s: lines.length > 1 ? '$head  (+${lines.length - 1} lines)' : head,
          sid: _sid,
          i: isError ? 0 : 1,
          d: piece,
        ),
      );
    }
  }

  void _recordInput(String line, {bool secret = false}) {
    final skip = _skipEcho;
    if (skip.isNotEmpty && line.endsWith(skip)) {
      // Already recorded as the AI's input.
      _skipEcho = '';
      return;
    }
    _emit(
      LogRecord.now(
        k: 'run_in',
        s: secret ? 'input: <hidden input>' : 'input: $line',
        sid: _sid,
        a: 'human',
        i: 0,
        d: secret ? null : line,
      ),
    );
  }

  void _finish(ExecutionProvider exec, {bool superseded = false}) {
    final id = _runId;
    if (id == null) return;
    if (!superseded) _drain(exec);
    final record = _historyOf(exec, id);
    final code = record?.exitCode ?? exec.state.exitCode;
    final status = record?.status ?? exec.state.status;
    _emit(
      LogRecord.now(
        k: 'run',
        s: superseded
            ? 'run replaced by a new run'
            : 'run finished: ${status.name}${code == null ? '' : ' (exit $code)'}',
        sid: _sid,
        i: 0,
        d: 'status: ${status.name}\n'
            'exit code: ${code ?? '?'}\n'
            'recorded output characters: $_recorded',
      ),
    );
    _runId = null;
  }
}

/// Used by the status line of the run: avoids an unused-import warning when
/// [ExecutionStatus] is only needed for documentation.
bool isFinishedStatus(ExecutionStatus status) =>
    status != ExecutionStatus.stopping && status != ExecutionStatus.running;
