import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xterm2/xterm.dart' show Terminal;

import '../../application/local_line_discipline.dart';
import '../ssh_text.dart';
import '../widgets/terminal_pane.dart';

/// A shell on this phone: Android's own `/system/bin/sh`, no Linux package
/// needed. It runs over plain pipes (no PTY), so [LineDiscipline] provides
/// echo and line editing; full-screen programs such as vim or top do not work.
class LocalTerminalPage extends StatefulWidget {
  const LocalTerminalPage({super.key});

  @override
  State<LocalTerminalPage> createState() => _LocalTerminalPageState();
}

class _LocalTerminalPageState extends State<LocalTerminalPage> {
  final Terminal _terminal = Terminal(maxLines: 10000);
  final TerminalInputFilter _filter = TerminalInputFilter();
  late final LineDiscipline _line;

  Process? _process;
  StreamSubscription<String>? _outSub;
  StreamSubscription<String>? _errSub;
  int _generation = 0;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _line = LineDiscipline(
      echo: _terminal.write,
      sendLine: _sendLine,
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

    final Directory dir;
    try {
      dir = await getApplicationSupportDirectory();
    } catch (error) {
      _error(t('无法获取工作目录：$error', 'Cannot get a working directory: $error'));
      return;
    }
    if (!mounted || generation != _generation) return;

    final shell = File('/system/bin/sh').existsSync() ? '/system/bin/sh' : 'sh';
    _info(
      t(
        '本机 Shell（$shell）。没有 PTY，vim / top 这类全屏程序不可用；Python 请用“Python 交互环境”。',
        'Local shell ($shell). There is no PTY, so full-screen programs such as vim or top do not work; use "Python console" for Python.',
      ),
    );
    _info(t('工作目录：${dir.path}', 'Working directory: ${dir.path}'));

    try {
      final process = await Process.start(
        shell,
        ['-i'],
        workingDirectory: dir.path,
        environment: {'HOME': dir.path, 'TERM': 'xterm', 'PS1': r'$ '},
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

  void _sendLine(String line) {
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
              if (value == 'interrupt') {
                _interrupt();
              } else if (value == 'kill') {
                unawaited(_stop().then((_) {
                  if (mounted) setState(() => _running = false);
                }));
              }
            },
            itemBuilder: (context) => [
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
