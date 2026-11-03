import 'package:flutter/material.dart';

import '../application/ssh_profile_store.dart';
import '../domain/ssh_profile.dart';
import 'pages/ssh_profiles_page.dart';
import 'pages/ssh_terminal_page.dart';
import 'ssh_text.dart';

/// Picks an SSH host and runs a script on it.
class SshRunLauncher {
  const SshRunLauncher._();

  static Future<void> runScript(
    BuildContext context, {
    required String fileName,
    required String content,
  }) async {
    final t = SshText.of(context);
    final store = SshProfileStore.instance;
    final profiles = await store.loadProfiles();
    if (!context.mounted) return;

    if (profiles.isEmpty) {
      final goAdd = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('还没有 SSH 主机', 'No SSH host yet')),
          content: Text(
            t(
              '先添加一个主机，才能把脚本放到远程运行。',
              'Add a host first to run scripts remotely.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('添加主机', 'Add host')),
            ),
          ],
        ),
      );
      if (goAdd == true && context.mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const SshProfilesPage()),
        );
      }
      return;
    }

    SshProfile? target = profiles.length == 1 ? profiles.first : null;
    if (target == null) {
      final lastId = await store.lastProfileId();
      if (!context.mounted) return;
      target = await showModalBottomSheet<SshProfile>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final profile in profiles)
                ListTile(
                  leading: Icon(
                    profile.id == lastId
                        ? Icons.history
                        : Icons.dns_outlined,
                  ),
                  title: Text(profile.name),
                  subtitle: Text(profile.endpoint),
                  onTap: () => Navigator.pop(ctx, profile),
                ),
            ],
          ),
        ),
      );
    }
    final chosen = target;
    if (chosen == null || !context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SshTerminalPage(
          profile: chosen,
          task: SshRemoteTask(fileName: fileName, content: content),
        ),
      ),
    );
  }
}
