import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:python_runner/features/scripts/application/script_workspace_controller.dart';
import 'package:xterm2/xterm.dart' show Terminal;

import '../../application/local_line_discipline.dart';
import '../../application/local_shell_prefs.dart';
import '../../application/python_launch.dart';
import '../python_launcher.dart';
import '../python_run_dialogs.dart';
import '../ssh_text.dart';
import '../widgets/terminal_pane.dart';

/// A shell on this phone: Android's own `/system/bin/sh`, no Linux package
/// needed. It runs over plain pipes (no PTY), so [LineDiscipline] provides
/// echo and line editing; full-screen programs such as vim or top do not work.
///
/// There is no `python` executable on Android (Python is embedded in the
/// app), so `python`, `python3`, `py` and `run` are built-in commands that run
/// in the embedded interpreter and open a run console.
class LocalTerminalPage extends ConsumerStatefulWidget {
  const LocalTerminalPage({super.key});

  @override
  ConsumerState<LocalTerminalPage> createState() => _LocalTerminalPageState();
}

class _LocalTerminalPageState extends ConsumerState<LocalTerminalPage> {
  final Terminal _terminal = Terminal(maxLines: 10000);
  final TerminalInputFilter _filter = TerminalInputFilter();
  late final LineDiscipline _line;

  Process? _process;
  StreamSubscription<String>? _outSub;
  StreamSubscription<String>? _errSub;
  int _generation = 0;
  bool _running = false;
  String _startDir = '';

  @override
  void initState() {
    super.initState();
    _line = LineDiscipline(
      echo: _terminal.write,
      sendLine: (line) => unawaited(_handleLine(line)),
      onInterrupt: _interrupt,
      onEof: _sendEof,
    );
    _terminal.onOutput = (data) => _line.feed(_filter.apply(data));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_start());
    });
  }

  @override
  void dispose() {
    _generation++;
    _terminal.onOutput = null;
    unawaited(_stop());
    _filter.dispose();
    super.dispose();
  }

  void _info(String text) {
    _terminal.write('\x1b[90m$text\x1b[0m\r\n');
  }

  void _error(String text) {
    _terminal.write('\x1b[31m$text\x1b[0m\r\n');
  }

  Future<void> _stop() async {
    final out = _outSub;
    final err = _errSub;
    final process = _process;
    _outSub = null;
    _errSub = null;
    _process = null;
    await out?.cancel();
    await err?.cancel();
    process?.kill(ProcessSignal.sigkill);
  }

  Future<void> _start() async {
    final generation = ++_generation;
    await _stop();
    if (!mounted || generation != _generation) return;
    final t = SshText.of(context);
    setState(() => _running = false);

    final String support;
    try {
      support = (await getApplicationSupportDirectory()).path;
    } catch (error) {
      _error(t('无法获取工作目录：$error', 'Cannot get a working directory: $error'));
      return;
    }
    final custom = await LocalShellPrefs.loadStartDir();
    if (!mounted || generation != _generation) return;
    var dir = support;
    if (custom != null) {
      if (Directory(custom).existsSync()) {
        dir = custom;
      } else {
        _error(
          t(
            '启动目录不存在：$custom，已改用默认目录',
            'Start directory does not exist: $custom, using the default',
          ),
        );
      }
    }
    _startDir = dir;

    final shell = File('/system/bin/sh').existsSync() ? '/system/bin/sh' : 'sh';
    _info(
      t(
        '本机 Shell（$shell）。没有 PTY（伪终端），vim、top 这类全屏程序不可用。输入 pyhelp 查看内置的 python / run 命令。',
        'Local shell ($shell). No PTY (pseudo terminal), so full-screen programs such as vim or top do not work. Type pyhelp for the built-in python / run commands.',
      ),
    );
    _info(t('启动目录：$dir', 'Start directory: $dir'));

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
      if (!mounted || generation != _generation) {
        process.kill(ProcessSignal.sigkill);
        return;
      }
      _process = process;
      unawaited(process.stdin.done.catchError((Object _) => null));
      _outSub = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(_onShellOutput);
      _errSub = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(_onShellOutput);
      unawaited(
        process.exitCode.then((code) {
          if (!mounted || generation != _generation) return;
          _info(
            t(
              '[shell 已退出，代码 $code — 点右上角刷新重新启动]',
              '[shell exited with code $code — tap refresh to restart]',
            ),
          );
          setState(() => _running = false);
        }),
      );
      setState(() => _running = true);
    } catch (error) {
      _error(t('启动 shell 失败：$error', 'Could not start the shell: $error'));
    }
  }

  void _onShellOutput(String text) {
    _terminal.write(text.replaceAll(RegExp(r'\r?\n'), '\r\n'));
  }

  void _toShell(String line) {
    final process = _process;
    if (process == null || !_running) return;
    process.stdin.add(utf8.encode('$line\n'));
  }

  void _interrupt() {
    _process?.kill(ProcessSignal.sigint);
  }

  void _sendEof() {
    final process = _process;
    if (process == null || !_running) return;
    unawaited(process.stdin.close());
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
    } on PythonCommandException catch (error) {
      _error(error.message);
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
    if (first == 'pyhelp') {
      _printHelp();
      return true;
    }
    if (first == 'scripts') {
      _listScripts();
      return true;
    }
    if (first == 'run') {
      await _runWorkspaceScript(line);
      return true;
    }
    if (!isPythonCommandName(first)) return false;

    final cwd = await _currentDir();
    var launch = parsePythonCommand(line, cwd: cwd, home: _startDir);
    if (launch == null) return false;
    if (launch.mode == PythonLaunchMode.file) {
      final path = launch.filePath ?? '';
      final file = File(path);
      if (!file.existsSync()) {
        _error(
          "python: can't open file '$path': [Errno 2] No such file or directory",
        );
        return true;
      }
      launch = launch.withSource(
        utf8.decode(await file.readAsBytes(), allowMalformed: true),
      );
    }
    if (!mounted) return true;
    await launchPython(context, ref, launch);
    return true;
  }

  Future<void> _runWorkspaceScript(String line) async {
    final tokens = shellSplit(line);
    if (tokens.length < 2) {
      _error('usage: run <script> [args...]');
      return;
    }
    var name = tokens[1];
    if (!name.endsWith('.py')) name = '$name.py';
    final scripts = ref.read(scriptWorkspaceControllerProvider).scripts;
    if (!scripts.any((script) => script.name == name)) {
      _error('run: no script named $name (type scripts to list them)');
      return;
    }
    final source =
        await ref.read(scriptWorkspaceControllerProvider.notifier).readScript(name);
    if (!mounted) return;
    await launchPython(
      context,
      ref,
      PythonLaunch(
        mode: PythonLaunchMode.file,
        displayName: name,
        source: source,
        args: tokens.sublist(2),
      ),
    );
  }

  void _listScripts() {
    final scripts = ref.read(scriptWorkspaceControllerProvider).scripts;
    if (scripts.isEmpty) {
      _info('(no scripts)');
      return;
    }
    for (final script in scripts) {
      _terminal.write('${script.name}\r\n');
    }
  }

  void _printHelp() {
    final t = SshText.of(context);
    final text = t(
      '内置命令：\n'
          '  python | python3 | py [-c 代码 | -m 模块 | 文件] [参数...]\n'
          '      在内置 Python 里运行，结果在新页面显示（支持 input()）\n'
          '  run <脚本名> [参数...]   运行脚本列表里的脚本\n'
          '  scripts                  列出脚本列表里的脚本\n'
          '  pyhelp                   显示这段说明\n'
          '内置命令不支持管道、重定向、&& 和 ;。其他命令交给系统 sh。',
      'Built-in commands:\n'
          '  python | python3 | py [-c code | -m module | file] [args...]\n'
          '      run in the embedded Python; output opens in a new page (input() works)\n'
          '  run <script> [args...]   run a script from the script list\n'
          '  scripts                  list the scripts in the script list\n'
          '  pyhelp                   show this text\n'
          'Built-ins do not support pipes, redirects, && or ;. Everything else goes to the system sh.',
    );
    _terminal.write('${text.replaceAll('\n', '\r\n')}\r\n');
  }

  Future<void> _changeStartDir() async {
    final changed = await showLocalShellSettingsDialog(context);
    if (changed && mounted) unawaited(_start());
  }

  @override
  Widget build(BuildContext context) {
    final t = SshText.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(t('本机 Shell', 'Local shell')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: t('重新启动', 'Restart'),
            onPressed: () => unawaited(_start()),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'dir':
                  unawaited(_changeStartDir());
                case 'help':
                  _printHelp();
                case 'interrupt':
                  _interrupt();
                case 'kill':
                  unawaited(_stop().then((_) {
                    if (mounted) setState(() => _running = false);
                  }));
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'dir',
                child: Text(t('启动目录…', 'Start directory…')),
              ),
              PopupMenuItem(
                value: 'help',
                child: Text(t('内置命令说明', 'Built-in commands')),
              ),
              PopupMenuItem(
                value: 'interrupt',
                child: Text(t('中断 (SIGINT)', 'Interrupt (SIGINT)')),
              ),
              PopupMenuItem(
                value: 'kill',
                child: Text(t('强制结束 shell', 'Kill the shell')),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: TerminalPane(terminal: _terminal, filter: _filter),
      ),
    );
  }
}
