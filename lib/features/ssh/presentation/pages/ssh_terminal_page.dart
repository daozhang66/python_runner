import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart' show SSHSession;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm2/xterm.dart'
    show Terminal, TerminalController, TerminalKey, TerminalStyle, TerminalView;

import '../../application/ssh_command_builder.dart';
import '../../application/ssh_connection.dart';
import '../../application/ssh_profile_store.dart';
import '../../domain/ssh_profile.dart';
import '../ssh_error_text.dart';
import '../ssh_text.dart';

/// A script that is uploaded and run instead of opening a login shell.
class SshRemoteTask {
  const SshRemoteTask({required this.fileName, required this.content});

  final String fileName;
  final String content;
}

class SshTerminalPage extends StatefulWidget {
  const SshTerminalPage({super.key, required this.profile, this.task});

  final SshProfile profile;
  final SshRemoteTask? task;

  @override
  State<SshTerminalPage> createState() => _SshTerminalPageState();
}

class _KeyAction {
  _KeyAction(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;
}

class _SshTerminalPageState extends State<SshTerminalPage> {
  final Terminal _terminal = Terminal(maxLines: 10000);
  final TerminalController _terminalController = TerminalController();

  SshConnection? _connection;
  SSHSession? _session;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  int _generation = 0;
  bool _busy = false;
  bool _connected = false;
  double _fontSize = 14;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_start());
    });
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_teardown());
    _terminalController.dispose();
    super.dispose();
  }

  void _info(String text) {
    _terminal.write('\x1b[90m$text\x1b[0m\r\n');
  }

  void _error(String text) {
    _terminal.write('\x1b[31m$text\x1b[0m\r\n');
  }

  Future<void> _teardown() async {
    _terminal.onOutput = null;
    _terminal.onResize = null;
    final out = _stdoutSub;
    final err = _stderrSub;
    _stdoutSub = null;
    _stderrSub = null;
    await out?.cancel();
    await err?.cancel();
    _session?.close();
    _session = null;
    _connection?.close();
    _connection = null;
  }

  Future<void> _start() async {
    final generation = ++_generation;
    await _teardown();
    if (!mounted || generation != _generation) return;

    final t = SshText.of(context);
    final profile = widget.profile;
    setState(() {
      _busy = true;
      _connected = false;
    });
    _info(t('正在连接 ${profile.endpoint} …', 'Connecting to ${profile.endpoint} …'));

    final connection = SshConnection(profile);
    try {
      final secrets = await SshProfileStore.instance.loadSecrets(profile.id);
      _connection = connection;
      await connection.connect(
        secrets: secrets,
        askPassword: () => _askSecret(t('输入密码', 'Password')),
        askPassphrase: () => _askSecret(t('输入私钥口令', 'Key passphrase')),
        confirmHostKey: _confirmHostKey,
      );
      if (!mounted || generation != _generation) {
        connection.close();
        return;
      }

      final cols = _terminal.viewWidth;
      final rows = _terminal.viewHeight;
      final task = widget.task;
      final SSHSession session;
      if (task == null) {
        session = await connection.openShell(cols, rows);
      } else {
        final fileName = safeRemoteFileName(task.fileName);
        _info(t('正在上传 $fileName …', 'Uploading $fileName …'));
        await connection.uploadText(
          buildUploadCommand(
            remoteDir: profile.remoteDir,
            fileName: fileName,
          ),
          task.content,
        );
        if (!mounted || generation != _generation) {
          connection.close();
          return;
        }
        session = await connection.execPty(
          buildRunCommand(
            remoteDir: profile.remoteDir,
            fileName: fileName,
            pythonCommand: profile.pythonCommand,
          ),
          cols,
          rows,
        );
      }
      if (!mounted || generation != _generation) {
        session.close();
        connection.close();
        return;
      }
      unawaited(SshProfileStore.instance.setLastProfileId(profile.id));
      _attach(session, generation);
    } on SshCancelled {
      connection.close();
      if (mounted && generation == _generation) {
        _info(t('已取消', 'Cancelled'));
        setState(() => _busy = false);
      }
    } catch (error) {
      connection.close();
      if (mounted && generation == _generation) {
        _error(describeSshError(error, t));
        setState(() => _busy = false);
      }
    }
  }

  void _attach(SSHSession session, int generation) {
    _session = session;
    _stdoutSub = session.stdout
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(_terminal.write);
    _stderrSub = session.stderr
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(_terminal.write);
    _terminal.onOutput = (data) {
      session.write(Uint8List.fromList(utf8.encode(data)));
    };
    _terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      session.resizeTerminal(width, height, pixelWidth, pixelHeight);
    };
    setState(() {
      _busy = false;
      _connected = true;
    });
    unawaited(_watchSession(session, generation));
  }

  Future<void> _watchSession(SSHSession session, int generation) async {
    try {
      await session.done;
    } catch (_) {
      // The connection dropped; handled below like a normal exit.
    }
    if (!mounted || generation != _generation) return;
    final t = SshText.of(context);
    _info(
      t(
        '[会话已结束，点右上角刷新按钮可重新连接/运行]',
        '[Session ended — tap refresh to reconnect / run again]',
      ),
    );
    setState(() => _connected = false);
  }

  Future<String?> _askSecret(String title) async {
    if (!mounted) return null;
    final t = SshText.of(context);
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          enableSuggestions: false,
          autocorrect: false,
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(t('连接', 'Connect')),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmHostKey(HostKeyPrompt prompt) async {
    if (!mounted) return false;
    final t = SshText.of(context);
    final previous = prompt.previousFingerprint;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(
          previous == null
              ? t('信任此主机？', 'Trust this host?')
              : t('主机密钥已变化！', 'Host key changed!'),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${prompt.host}:${prompt.port}  (${prompt.keyType})'),
              const SizedBox(height: 8),
              SelectableText(
                prompt.fingerprint,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              if (previous != null) ...[
                const SizedBox(height: 12),
                Text(t('之前信任的指纹：', 'Previously trusted:')),
                SelectableText(
                  previous,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                const SizedBox(height: 8),
                Text(
                  t(
                    '可能是服务器重装了系统，也可能有人在中途拦截连接。确认无误再继续。',
                    'The server may have been reinstalled, or someone may be intercepting the connection. Continue only if you are sure.',
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('拒绝', 'Reject')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('信任并继续', 'Trust & continue')),
          ),
        ],
      ),
    );
    return accepted ?? false;
  }

  Future<void> _copySelection() async {
    final selection = _terminalController.selection;
    final t = SshText.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (selection == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(t('先在终端里长按选择文字', 'Long-press the terminal to select text first')),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    final text = _terminal.buffer.getText(selection);
    await Clipboard.setData(ClipboardData(text: text));
    _terminalController.clearSelection();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) _terminal.paste(text);
  }

  void _changeFont(double delta) {
    setState(() => _fontSize = (_fontSize + delta).clamp(8, 28).toDouble());
  }

  Widget _buildKeyBar(SshText t) {
    final actions = <_KeyAction>[
      _KeyAction('Esc', () => _terminal.keyInput(TerminalKey.escape)),
      _KeyAction('Tab', () => _terminal.keyInput(TerminalKey.tab)),
      _KeyAction('↑', () => _terminal.keyInput(TerminalKey.arrowUp)),
      _KeyAction('↓', () => _terminal.keyInput(TerminalKey.arrowDown)),
      _KeyAction('←', () => _terminal.keyInput(TerminalKey.arrowLeft)),
      _KeyAction('→', () => _terminal.keyInput(TerminalKey.arrowRight)),
      _KeyAction('Home', () => _terminal.keyInput(TerminalKey.home)),
      _KeyAction('End', () => _terminal.keyInput(TerminalKey.end)),
      _KeyAction('PgUp', () => _terminal.keyInput(TerminalKey.pageUp)),
      _KeyAction('PgDn', () => _terminal.keyInput(TerminalKey.pageDown)),
      _KeyAction('^C', () => _terminal.keyInput(TerminalKey.keyC, ctrl: true)),
      _KeyAction('^D', () => _terminal.keyInput(TerminalKey.keyD, ctrl: true)),
      _KeyAction('^Z', () => _terminal.keyInput(TerminalKey.keyZ, ctrl: true)),
      _KeyAction('^L', () => _terminal.keyInput(TerminalKey.keyL, ctrl: true)),
      _KeyAction('/', () => _terminal.textInput('/')),
      _KeyAction('-', () => _terminal.textInput('-')),
      _KeyAction('|', () => _terminal.textInput('|')),
      _KeyAction('~', () => _terminal.textInput('~')),
      _KeyAction(t('粘贴', 'Paste'), _paste),
      _KeyAction(t('复制', 'Copy'), _copySelection),
    ];
    return Material(
      color: const Color(0xFF16181C),
      child: SizedBox(
        height: 42,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: actions.length,
          itemBuilder: (context, index) {
            final action = actions[index];
            return InkWell(
              canRequestFocus: false,
              onTap: action.onTap,
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  action.label,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = SshText.of(context);
    final profile = widget.profile;
    final isTask = widget.task != null;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isTask ? '${profile.name} · ${widget.task!.fileName}' : profile.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16),
            ),
            Text(
              profile.endpoint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: isTask
                ? t('重新上传并运行', 'Upload & run again')
                : t('重新连接', 'Reconnect'),
            onPressed: _busy ? null : () => unawaited(_start()),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'copy':
                  unawaited(_copySelection());
                case 'paste':
                  unawaited(_paste());
                case 'interrupt':
                  _terminal.keyInput(TerminalKey.keyC, ctrl: true);
                case 'bigger':
                  _changeFont(1);
                case 'smaller':
                  _changeFont(-1);
                case 'disconnect':
                  unawaited(_teardown().then((_) {
                    if (mounted) setState(() => _connected = false);
                  }));
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'copy', child: Text(t('复制选中文字', 'Copy selection'))),
              PopupMenuItem(value: 'paste', child: Text(t('粘贴', 'Paste'))),
              PopupMenuItem(value: 'interrupt', child: Text(t('中断 (Ctrl+C)', 'Interrupt (Ctrl+C)'))),
              PopupMenuItem(value: 'bigger', child: Text(t('字体放大', 'Larger font'))),
              PopupMenuItem(value: 'smaller', child: Text(t('字体缩小', 'Smaller font'))),
              if (_connected)
                PopupMenuItem(value: 'disconnect', child: Text(t('断开连接', 'Disconnect'))),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: TerminalView(
                _terminal,
                controller: _terminalController,
                autofocus: true,
                deleteDetection: true,
                textStyle: TerminalStyle(fontSize: _fontSize),
                padding: const EdgeInsets.all(6),
              ),
            ),
            _buildKeyBar(t),
          ],
        ),
      ),
    );
  }
}
