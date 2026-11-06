import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:python_runner/features/scripts/application/script_workspace_controller.dart';

import '../../application/python_launch.dart';
import '../../application/ssh_connection.dart' show HostKeyPrompt;
import '../../application/ssh_profile_store.dart';
import '../../application/terminal/session_manager.dart';
import '../../application/terminal/terminal_session.dart';
import '../../domain/ssh_profile.dart';
import '../python_launcher.dart' as launcher;
import '../ssh_text.dart';
import '../widgets/terminal_pane.dart';
import 'ssh_profiles_page.dart';
import 'terminal_logs_page.dart';

/// Opens the terminal page, optionally on a given session.
Future<void> openTerminalHub(BuildContext context, {String? sessionId}) {
  return Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => TerminalHubPage(initialSessionId: sessionId),
    ),
  );
}

/// Terminal sessions as tabs. Sessions keep running when this page is left.
class TerminalHubPage extends ConsumerStatefulWidget {
  const TerminalHubPage({super.key, this.initialSessionId});

  final String? initialSessionId;

  @override
  ConsumerState<TerminalHubPage> createState() => _TerminalHubPageState();
}

class _TerminalHubPageState extends ConsumerState<TerminalHubPage>
    implements TerminalHost {
  final TerminalSessionManager _manager = TerminalSessionManager.instance;
  String? _activeId;

  @override
  void initState() {
    super.initState();
    _activeId = widget.initialSessionId;
    _manager.addListener(_onSessionsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _attachHost();
    });
  }

  @override
  void dispose() {
    _manager.removeListener(_onSessionsChanged);
    for (final session in _manager.sessions) {
      if (identical(session.host, this)) session.host = null;
    }
    super.dispose();
  }

  void _onSessionsChanged() {
    if (!mounted) return;
    _attachHost();
    setState(() {});
  }

  /// Gives every session a screen to ask questions on, and starts the ones
  /// that were created but never started.
  void _attachHost() {
    for (final session in _manager.sessions) {
      session.host ??= this;
      if (session.status == TerminalSessionStatus.idle) {
        unawaited(session.start());
      }
    }
  }

  TerminalSession? _active(List<TerminalSession> sessions) {
    if (sessions.isEmpty) return null;
    for (final session in sessions) {
      if (session.id == _activeId) return session;
    }
    return sessions.last;
  }

  // ── TerminalHost ──

  @override
  Future<void> launchPython(PythonLaunch launch) async {
    if (!mounted) return;
    await launcher.launchPython(context, ref, launch);
  }

  @override
  List<String> scriptNames() => ref
      .read(scriptWorkspaceControllerProvider)
      .scripts
      .map((script) => script.name)
      .toList();

  @override
  Future<String> readScript(String name) => ref
      .read(scriptWorkspaceControllerProvider.notifier)
      .readScript(name);

  @override
  Future<String?> askSecret(String title) async {
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

  @override
  Future<bool> confirmHostKey(HostKeyPrompt prompt) async {
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

  // ── actions ──

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _newLocal() {
    try {
      final session = _manager.createLocal();
      setState(() => _activeId = session.id);
    } on StateError catch (e) {
      _toast(e.message);
    }
  }

  void _newSsh(SshProfile profile) {
    try {
      final session = _manager.createSsh(profile);
      setState(() => _activeId = session.id);
    } on StateError catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _showNewSessionSheet() async {
    final t = SshText.of(context);
    final profiles = await SshProfileStore.instance.loadProfiles();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.terminal),
              title: Text(t('本机 Shell', 'Local shell')),
              onTap: () {
                Navigator.pop(ctx);
                _newLocal();
              },
            ),
            for (final profile in profiles)
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: Text(profile.name),
                subtitle: Text(profile.endpoint),
                onTap: () {
                  Navigator.pop(ctx);
                  _newSsh(profile);
                },
              ),
            ListTile(
              leading: const Icon(Icons.settings_ethernet),
              title: Text(t('管理 SSH 主机…', 'Manage SSH hosts…')),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const SshProfilesPage(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _closeSession(TerminalSession session) async {
    await _manager.remove(session.id);
    if (mounted && _activeId == session.id) {
      setState(() => _activeId = null);
    }
  }

  Color _statusColor(TerminalSessionStatus status) => switch (status) {
        TerminalSessionStatus.running => Colors.greenAccent,
        TerminalSessionStatus.connecting => Colors.amber,
        TerminalSessionStatus.failed => Colors.redAccent,
        _ => Colors.grey,
      };

  PreferredSizeWidget _buildTabs(
    List<TerminalSession> sessions,
    TerminalSession? active,
  ) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(40),
      child: SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final session in sessions)
              InkWell(
                onTap: () => setState(() => _activeId = session.id),
                child: Container(
                  padding: const EdgeInsets.only(left: 12, right: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        width: 2,
                        color: identical(session, active)
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 9,
                        color: _statusColor(session.status),
                      ),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 140),
                        child: Text(
                          session.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        icon: const Icon(Icons.close),
                        onPressed: () => _closeSession(session),
                      ),
                    ],
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _showNewSessionSheet,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = SshText.of(context);
    final sessions = _manager.sessions;
    final active = _active(sessions);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(t('终端', 'Terminal')),
        bottom: _buildTabs(sessions, active),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: t('日志', 'Logs'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const TerminalLogsPage(),
              ),
            ),
          ),
          if (active != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: t('重新连接 / 重启', 'Reconnect / restart'),
              onPressed: () => unawaited(active.restart()),
            ),
        ],
      ),
      body: active == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.terminal, size: 48, color: Colors.white38),
                  const SizedBox(height: 12),
                  Text(
                    t('没有打开的终端', 'No terminal is open'),
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _showNewSessionSheet,
                    icon: const Icon(Icons.add),
                    label: Text(t('新建终端', 'New terminal')),
                  ),
                ],
              ),
            )
          : SafeArea(
              child: TerminalPane(
                key: ValueKey(active.id),
                terminal: active.terminal,
                filter: active.filter,
              ),
            ),
    );
  }
}
