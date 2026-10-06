import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../application/backup_providers.dart';
import '../infrastructure/webdav_client.dart';
import 'backup_preview_page.dart';
import 'backup_widgets.dart';

class BackupHistoryPage extends ConsumerStatefulWidget {
  const BackupHistoryPage({super.key});
  @override
  ConsumerState<BackupHistoryPage> createState() => _BackupHistoryPageState();
}

class _BackupHistoryPageState extends ConsumerState<BackupHistoryPage> {
  final _scroll = ScrollController();
  RemoteBackup? _retryRemote;
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(backupControllerProvider).refreshRemoteBackups();
    });
  }

  Future<void> _open(RemoteBackup remote) async {
    final c = ref.read(backupControllerProvider);
    _retryRemote = remote;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await c.downloadAndStageRemote(remote);
    if (!mounted || c.state.preview == null) return;
    final summary = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BackupPreviewPage()),
    );
    if (mounted && summary != null) Navigator.pop(context, summary);
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(backupControllerProvider);
    final s = c.state;
    final l = AppLocalizations.of(context)!;
    return BackupPageFrame(
      title: l.backupHistoryTitle,
      scrollController: _scroll,
      canPop: s.operation?.cancellable != false,
      children: [
        BackupStatusPanel(
          onRetry: () => _retryRemote == null
              ? c.refreshRemoteBackups()
              : _open(_retryRemote!),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('backup-history-refresh'),
              onPressed: s.busy
                  ? null
                  : () {
                      _retryRemote = null;
                      c.refreshRemoteBackups();
                    },
              icon: const Icon(Icons.refresh),
              label: Text(l.backupRefresh),
            ),
          ),
        ),
        if (!s.busy && s.error == null && s.remoteBackups.isEmpty)
          BackupNote(l.backupHistoryEmpty),
        for (final remote in s.remoteBackups)
          ListTile(
            key: ValueKey('remote-${remote.name}'),
            leading: const Icon(Icons.folder_zip_outlined),
            title: Text(remote.name),
            subtitle: Text(
              '${backupDate(context, remote.modifiedAt)} · ${remote.size == null ? l.backupUnknownSize : _size(remote.size!)}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: s.busy || s.preview != null ? null : () => _open(remote),
          ),
      ],
    );
  }

  String _size(int bytes) => bytes < 1024
      ? '$bytes B'
      : bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
