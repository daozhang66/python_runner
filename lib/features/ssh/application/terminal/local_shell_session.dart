import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../local_line_discipline.dart';
import '../local_shell_prefs.dart';
import '../python_launch.dart';
import 'terminal_session.dart';

/// A shell on this phone: Android's own `/system/bin/sh`, no Linux package
/// needed. It runs over plain pipes (no PTY), so [LineDiscipline] provides
/// echo and line editing; full-screen programs such as vim or top do not work.
///
/// There is no `python` executable on Android (Python is embedded in the
/// app), so `python`, `python3`, `py` and `run` are built-in commands that run
/// in the embedded interpreter and open a run console.
class LocalShellSession extends TerminalSession {
  LocalShellSession({required super.id, required super.title})
      : super(kind: 'local') {
    _line = LineDiscipline(
      echo: echo,
      sendLine: _onLine,
      onInterrupt: _sigint,
      onEof: _eof,
    );
    terminal.onOutput = (data) => _typed(filter.apply(data), 'human');
  }

  late final LineDiscipline _line;
  Process? _process;
  StreamSubscription<String>? _outSub;
  StreamSubscription<String>? _errSub;
  int _generation = 0;
  bool _running = false;
  String _startDir = '';
  String _actor = 'human';

  void _typed(String data, String actor) {
    _actor = actor;
    _line.feed(data);
    _actor = 'human';
  }

  @override
  void sendText(String text, {String actor = 'human'}) => _typed(text, actor);

  @override
  void interrupt() => _typed('\x03', _actor);

  void _onLine(String line) {
    logger.input(line, actor: _actor);
    unawaited(_handleLine(line));
  }

  void _sigint() {
    _process?.kill(ProcessSignal.sigint);
  }

  void _eof() {
    final process = _process;
    if (process == null || !_running) return;
    unawaited(process.stdin.close());
  }

  Future<void> _stopProcess() async {
    final out = _outSub;
    final err = _errSub;
    final process = _process;
    _outSub = null;
    _errSub = null;
    _process = null;
    _running = false;
    await out?.cancel();
    await err?.cancel();
    process?.kill(ProcessSignal.sigkill);
  }

  @override
  Future<void> start() async {
    final generation = ++_generation;
    setStatus(TerminalSessionStatus.connecting);
    await _stopProcess();

    final String support;
    try {
      support = (await getApplicationSupportDirectory()).path;
    } catch (e) {
      error('Cannot get a working directory: $e');
      setStatus(TerminalSessionStatus.failed, '$e');
      return;
    }
    final custom = await LocalShellPrefs.loadStartDir();
    if (generation != _generation) return;
    var dir = support;
    if (custom != null) {
      if (Directory(custom).existsSync()) {
        dir = custom;
      } else {
        error('Start directory does not exist: $custom, using the default');
      }
    }
    _startDir = dir;

    final shell = File('/system/bin/sh').existsSync() ? '/system/bin/sh' : 'sh';
    info(
      'Local shell ($shell). No PTY (pseudo terminal): full-screen programs '
      'such as vim or top do not work. Type pyhelp for the built-in '
      'python / run commands.',
    );
    info('Start directory: $dir');

    try {
      final process = await Process.start(
        shell,
        ['-i'],
        workingDirectory: dir,
        environment: {
          'HOME': dir,
          'TERM': 'xterm',
          'ENV': '',
          'PS1': r'$PWD $ ',
        },
      );
      if (generation != _generation) {
        process.kill(ProcessSignal.sigkill);
        return;
      }
      _process = process;
      _running = true;
      unawaited(process.stdin.done.catchError((Object _) => null));
      _outSub = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(_onShellOutput);
      _errSub = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(_onShellOutput);
      unawaited(
        process.exitCode.then((code) {
          if (generation != _generation) return;
          _running = false;
          info('[shell exited with code $code]');
          logger.event('session', 'shell exited with code $code');
          setStatus(TerminalSessionStatus.closed, 'exit $code');
        }),
      );
      logger.event('session', 'opened local shell', detail: 'dir: $dir');
      setStatus(TerminalSessionStatus.running);
    } catch (e) {
      error('Could not start the shell: $e');
      logger.event('session', 'failed to start: $e');
      setStatus(TerminalSessionStatus.failed, '$e');
    }
  }

  void _onShellOutput(String text) {
    emit(text.replaceAll(RegExp(r'\r?\n'), '\r\n'));
  }

  void _toShell(String line) {
    final process = _process;
    if (process == null || !_running) return;
    process.stdin.add(utf8.encode('$line\n'));
  }

  @override
  Future<void> close() async {
    final wasAlive = isAlive;
    _generation++;
    await _stopProcess();
    if (wasAlive) logger.event('session', 'closed');
    setStatus(TerminalSessionStatus.closed);
  }

  /// The shell's current directory (read from /proc), or the start directory.
  Future<String> _currentDir() async {
    final process = _process;
    if (process != null) {
      try {
        return await Link('/proc/${process.pid}/cwd').target();
      } catch (_) {
        // /proc may be hidden; fall back to the start directory.
      }
    }
    return _startDir;
  }

  Future<void> _handleLine(String raw) async {
    final line = raw.trim();
    if (line.isEmpty) {
      _toShell(raw);
      return;
    }
    try {
      if (await _runBuiltin(line)) {
        // Ask the shell for a fresh prompt: it never saw this line.
        _toShell('');
        return;
      }
    } on PythonCommandException catch (e) {
      error(e.message);
      _toShell('');
      return;
    }
    _toShell(raw);
  }

  /// Runs `python`, `run`, `scripts` and `pyhelp`. Returns false when [line]
  /// is an ordinary shell command.
  Future<bool> _runBuiltin(String line) async {
    final space = line.indexOf(RegExp(r'\s'));
    final first = space < 0 ? line : line.substring(0, space);
    final builtin = first == 'pyhelp' ||
        first == 'scripts' ||
        first == 'run' ||
        isPythonCommandName(first);
    if (!builtin) return false;
    if (first == 'pyhelp') {
      _printHelp();
      return true;
    }
    final host = this.host;
    if (host == null) {
      error(
        'Built-in commands need the terminal page to be open (they show '
        'their output in a run console).',
      );
      return true;
    }
    if (first == 'scripts') {
      final names = host.scriptNames();
      if (names.isEmpty) {
        info('(no scripts)');
      } else {
        for (final name in names) {
          emit('$name\r\n');
        }
      }
      return true;
    }
    if (first == 'run') {
      await _runWorkspaceScript(host, line);
      return true;
    }

    final cwd = await _currentDir();
    var launch = parsePythonCommand(line, cwd: cwd, home: _startDir);
    if (launch == null) return false;
    if (launch.mode == PythonLaunchMode.file) {
      final path = launch.filePath ?? '';
      final file = File(path);
      if (!file.existsSync()) {
        error(
          "python: can't open file '$path': [Errno 2] No such file or directory",
        );
        return true;
      }
      launch = launch.withSource(
        utf8.decode(await file.readAsBytes(), allowMalformed: true),
      );
    }
    await host.launchPython(launch);
    return true;
  }

  Future<void> _runWorkspaceScript(TerminalHost host, String line) async {
    final tokens = shellSplit(line);
    if (tokens.length < 2) {
      error('usage: run <script> [args...]');
      return;
    }
    var name = tokens[1];
    if (!name.endsWith('.py')) name = '$name.py';
    if (!host.scriptNames().contains(name)) {
      error('run: no script named $name (type scripts to list them)');
      return;
    }
    final source = await host.readScript(name);
    await host.launchPython(
      PythonLaunch(
        mode: PythonLaunchMode.file,
        displayName: name,
        source: source,
        args: tokens.sublist(2),
      ),
    );
  }

  void _printHelp() {
    const text = 'Built-in commands:\n'
        '  python | python3 | py [-c code | -m module | file] [args...]\n'
        '      run in the embedded Python; output opens in a new page (input() works)\n'
        '  run <script> [args...]   run a script from the script list\n'
        '  scripts                  list the scripts in the script list\n'
        '  pyhelp                   show this text\n'
        'Built-ins do not support pipes, redirects, && or ;. '
        'Everything else goes to the system sh.';
    emit('${text.replaceAll('\n', '\r\n')}\r\n');
  }
}
