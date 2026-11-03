import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:python_runner/features/scripts/application/script_workspace_controller.dart';

import '../../application/ssh_keys.dart';
import '../../application/ssh_profile_store.dart';
import '../../domain/ssh_profile.dart';
import '../ssh_dialogs.dart';
import '../ssh_text.dart';
import 'ssh_profile_edit_page.dart';
import 'ssh_terminal_page.dart';

/// Lists saved SSH hosts. Tap a host to open a terminal on it.
class SshProfilesPage extends ConsumerStatefulWidget {
  const SshProfilesPage({super.key});

  @override
  ConsumerState<SshProfilesPage> createState() => _SshProfilesPageState();
}

class _SshProfilesPageState extends ConsumerState<SshProfilesPage> {
  List<SshProfile> _profiles = <SshProfile>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profiles = await SshProfileStore.instance.loadProfiles();
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _loading = false;
    });
  }

  Future<void> _openTerminal(SshProfile profile) {
    return Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SshTerminalPage(profile: profile),
      ),
    );
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
    final messenger = ScaffoldMessenger.of(context);
    final secrets = await SshProfileStore.instance.loadSecrets(profile.id);
    final pem = secrets.privateKey ?? '';
    final line = pem.isEmpty
        ? null
        : publicKeyLineFromPem(pem, passphrase: secrets.passphrase);
    if (!mounted) return;
    if (line == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            t(
              '这个主机没有可读取的私钥，请编辑后粘贴或生成',
              'This host has no readable private key. Edit it to paste or generate one.',
            ),
          ),
        ),
      );
      return;
    }
    await showSshPublicKeyDialog(context, line);
  }

  Future<void> _runScript(SshProfile profile) async {
    final t = SshText.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final scripts = ref.read(scriptWorkspaceControllerProvider).scripts;
    if (scripts.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(t('还没有脚本', 'There are no scripts yet'))),
      );
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
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SshTerminalPage(
          profile: profile,
          task: SshRemoteTask(fileName: picked, content: content),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = SshText.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t('SSH 远程与终端', 'SSH & Terminal'))),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text(
                    t(
                      '连接任意 SSH 服务器，在远程终端里工作，或把脚本放到远程运行。也可以连接手机上 Stryker 等虚拟机里的 Debian：主机填 127.0.0.1 和它的 SSH 端口，用“生成密钥”后把公钥加入虚拟机的 authorized_keys。',
                      'Connect to any SSH server, work in a remote terminal, or run scripts remotely. You can also reach a Debian VM on this phone (for example Stryker): use 127.0.0.1 and its SSH port, generate a key here and add the public key to the VM\'s authorized_keys.',
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (_profiles.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
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
