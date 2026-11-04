import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart' show SSHSession;
import 'package:flutter/material.dart';
import 'package:xterm2/xterm.dart' show Terminal;

import '../../application/ssh_command_builder.dart';
import '../../application/ssh_connection.dart';
import '../../application/ssh_profile_store.dart';
import '../../domain/ssh_profile.dart';
import '../ssh_error_text.dart';
import '../ssh_text.dart';
import '../widgets/terminal_pane.dart';

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

class _SshTerminalPageState extends State<SshTerminalPage> {
  final Terminal _terminal = Terminal(maxLines: 10000);
  final TerminalInputFilter _filter = TerminalInputFilter();

  SshConnection? _connection;
  SSHSession? _session;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  int _generation = 0;
  bool _busy = false;
  bool _connected = false;

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
    _filter.dispose();
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
      session.write(Uint8List.fromList(utf8.encode(_filter.apply(data))));
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

  @override
  Widget build(BuildContext context) {
    final t = SshText.of(context);
    final profile = widget.profile;
    final task = widget.task;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              task == null ? profile.name : '${profile.name} · ${task.fileName}',
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
            tooltip: task != null
                ? t('重新上传并运行', 'Upload & run again')
                : t('重新连接', 'Reconnect'),
            onPressed: _busy ? null : () => unawaited(_start()),
          ),
          if (_connected)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'disconnect') {
                  unawaited(
                    _teardown().then((_) {
                      if (mounted) setState(() => _connected = false);
                    }),
                  );
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'disconnect',
                  child: Text(t('断开连接', 'Disconnect')),
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
