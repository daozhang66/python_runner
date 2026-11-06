import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:python_runner/features/scripts/application/script_workspace_controller.dart';

import '../../application/python_launch.dart';
import '../../application/ssh_keys.dart';
import '../../application/ssh_profile_store.dart';
import '../../application/terminal/session_manager.dart';
import '../../application/terminal/ssh_session.dart';
import '../../domain/ssh_profile.dart';
import '../python_launcher.dart';
import '../python_run_dialogs.dart';
import '../ssh_dialogs.dart';
import '../ssh_text.dart';
import 'ssh_profile_edit_page.dart';
import 'terminal_hub_page.dart';
import 'terminal_logs_page.dart';

/// Terminals on this phone (local shell, Python console) and saved SSH hosts.
/// Tap a host to open a terminal on it.
class SshProfilesPage extends ConsumerStatefulWidget {
  const SshProfilesPage({super.key});

  @override
  ConsumerState<SshProfilesPage> createState() => _SshProfilesPageState();
}

class _SshProfilesPageState extends ConsumerState<SshProfilesPage> {
  final TerminalSessionManager _manager = TerminalSessionManager.instance;
  List<SshProfile> _profiles = <SshProfile>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _manager.addListener(_onSessionsChanged);
    _load();
  }

  @override
  void dispose() {
    _manager.removeListener(_onSessionsChanged);
    super.dispose();
  }

  void _onSessionsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final profiles = await SshProfileStore.instance.loadProfiles();
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _loading = false;
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openLocal() async {
    try {
      final session = _manager.createLocal();
      await openTerminalHub(context, sessionId: session.id);
    } on StateError catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _openTerminal(SshProfile profile, {SshRemoteTask? task}) async {
    try {
      final session = _manager.createSsh(profile, task: task);
      await openTerminalHub(context, sessionId: session.id);
    } on StateError catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _edit([SshProfile? profile]) async {
    await Navigator.push<SshProfile>(
      context,
      MaterialPageRoute<SshProfile>(
        builder: (_) => SshProfileEditPage(profile: profile),
      ),
    );
    await _load();
  }

  Future<void> _delete(SshProfile profile) async {
    final t = SshText.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('删除主机', 'Delete host')),
        content: Text(
          t(
            '删除“${profile.name}”及其保存的凭据？',
            'Delete "${profile.name}" and its saved credentials?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('删除', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await SshProfileStore.instance.deleteProfile(profile.id);
    await _load();
  }

  Future<void> _showPublicKey(SshProfile profile) async {
    final t = SshText.of(context);
    final secrets = await SshProfileStore.instance.loadSecrets(profile.id);
    final pem = secrets.privateKey ?? '';
    final line = pem.isEmpty
        ? null
        : publicKeyLineFromPem(pem, passphrase: secrets.passphrase);
    if (!mounted) return;
    if (line == null) {
      _toast(
        t(
          '这个主机没有可读取的私钥，请编辑后粘贴或生成',
          'This host has no readable private key. Edit it to paste or generate one.',
        ),
      );
      return;
    }
    await showSshPublicKeyDialog(context, line);
  }

  Future<void> _runScript(SshProfile profile) async {
    final t = SshText.of(context);
    final scripts = ref.read(scriptWorkspaceControllerProvider).scripts;
    if (scripts.isEmpty) {
      _toast(t('还没有脚本', 'There are no scripts yet'));
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.6,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final script in scripts)
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(script.name),
                  onTap: () => Navigator.pop(ctx, script.name),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final content = await ref
        .read(scriptWorkspaceControllerProvider.notifier)
        .readScript(picked);
    if (!mounted) return;
    await _openTerminal(
      profile,
      task: SshRemoteTask(fileName: picked, content: content),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = SshText.of(context);
    final open = _manager.sessions.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('终端与 SSH', 'Terminal & SSH')),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: t('日志', 'Logs'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const TerminalLogsPage()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _edit,
        icon: const Icon(Icons.add),
        label: Text(t('添加主机', 'Add host')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                if (open > 0)
                  ListTile(
                    leading: const Icon(Icons.tab),
                    title: Text(t('已打开的终端（$open）', 'Open terminals ($open)')),
                    subtitle: Text(
                      t(
                        '终端会在后台继续运行，可以随时切回来',
                        'Terminals keep running in the background; come back any time',
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                    onTap: () => openTerminalHub(context),
                  ),
                _sectionTitle(context, t('本机', 'This phone')),
                ListTile(
                  leading: const Icon(Icons.terminal),
                  title: Text(t('本机 Shell', 'Local shell')),
                  subtitle: Text(
                    t(
                      '系统自带的 sh，不需要 Linux 包。没有 PTY（伪终端），不支持 vim 等全屏程序。python / python3 / run 是内置命令，用内置 Python 运行',
                      'The built-in sh, no Linux package needed. No PTY (pseudo terminal), so no vim and other full-screen programs. python / python3 / run are built-in commands that use the embedded Python',
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.folder_open_outlined),
                    tooltip: t('启动目录', 'Start directory'),
                    onPressed: () => showLocalShellSettingsDialog(context),
                  ),
                  onTap: _openLocal,
                ),
                ListTile(
                  leading: const Icon(Icons.data_object),
                  title: Text(t('Python 交互环境', 'Python console')),
                  subtitle: Text(
                    t(
                      '在内置 Python 里逐行输入代码，可以用已安装的 pip 包',
                      'Type code line by line in the built-in Python, with your installed pip packages',
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () => launchPython(
                    context,
                    ref,
                    const PythonLaunch(mode: PythonLaunchMode.interactive),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.play_circle_outline),
                  title: Text(t('运行 Python 文件…', 'Run a Python file…')),
                  subtitle: Text(
                    t(
                      '选择一个 .py 文件并填写参数，在新页面运行（同一时间只能运行一个 Python 脚本）',
                      'Pick a .py file and its arguments; it runs in a new page (only one Python script can run at a time)',
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                  isThreeLine: true,
                  onTap: () => showRunPythonFileDialog(context, ref),
                ),
                _sectionTitle(context, t('SSH 主机', 'SSH hosts')),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    t(
                      '连接任意 SSH 服务器，在远程终端里工作，或把脚本放到远程运行。每次打开都是一个独立的终端标签，可以同时有多个。也可以连接手机上 Stryker 等虚拟机里的 Debian：主机填 127.0.0.1 和它的 SSH 端口，用“生成密钥”后把公钥加入虚拟机的 authorized_keys。',
                      'Connect to any SSH server, work in a remote terminal, or run scripts remotely. Every open is its own terminal tab, and you can have several. You can also reach a Debian VM on this phone (for example Stryker): use 127.0.0.1 and its SSH port, generate a key here and add the public key to the VM\'s authorized_keys.',
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (_profiles.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text(t('还没有主机', 'No hosts yet'))),
                  ),
                for (final profile in _profiles)
                  ListTile(
                    leading: const Icon(Icons.dns_outlined),
                    title: Text(profile.name),
                    subtitle: Text('${profile.endpoint}\n${profile.remoteDir}'),
                    isThreeLine: true,
                    onTap: () => _openTerminal(profile),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        switch (value) {
                          case 'terminal':
                            _openTerminal(profile);
                          case 'run':
                            _runScript(profile);
                          case 'edit':
                            _edit(profile);
                          case 'key':
                            _showPublicKey(profile);
                          case 'delete':
                            _delete(profile);
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(value: 'terminal', child: Text(t('打开终端', 'Open terminal'))),
                        PopupMenuItem(value: 'run', child: Text(t('运行脚本…', 'Run a script…'))),
                        PopupMenuItem(value: 'edit', child: Text(t('编辑', 'Edit'))),
                        PopupMenuItem(value: 'key', child: Text(t('查看公钥', 'Show public key'))),
                        PopupMenuItem(value: 'delete', child: Text(t('删除', 'Delete'))),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
