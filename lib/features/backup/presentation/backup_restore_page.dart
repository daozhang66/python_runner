import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../application/backup_controller.dart';
import '../application/backup_providers.dart';
import '../domain/backup_selection.dart';
import 'backup_history_page.dart';
import 'backup_preview_page.dart';
import 'backup_selection_page.dart';
import 'backup_webdav_page.dart';
import 'backup_widgets.dart';

class BackupRestorePage extends ConsumerStatefulWidget {
  const BackupRestorePage({super.key});
  @override
  ConsumerState<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends ConsumerState<BackupRestorePage> {
  Future<void> Function()? _retry;
  String? _restoredSummary;
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(backupControllerProvider).loadLibrary();
    });
  }

  BackupController get controller => ref.read(backupControllerProvider);
  Future<void> _run(Future<void> Function() command) async {
    setState(() {
      _retry = command;
      _restoredSummary = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await command();
  }

  Future<bool> _configure() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const BackupWebDavPage()),
    );
    return mounted && saved == true;
  }

  Future<void> _export() async {
    if (controller.state.localDirectory == null ||
        controller.state.error?.code == 'PERMISSION_LOST') {
      await controller.chooseLocalDirectory();
      if (!mounted ||
          controller.state.error != null ||
          controller.state.lastResult?.kind == BackupResultKind.cancelled ||
          controller.state.localDirectory == null) {
        return;
      }
    }
    await controller.exportLocal();
  }

  Future<void> _upload() async {
    if (controller.state.profile == null && !await _configure()) return;
    if (mounted) await controller.backupWebDav();
  }

  Future<void> _preview() async {
    if (!mounted || controller.state.preview == null) return;
    final summary = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BackupPreviewPage()),
    );
    if (mounted && summary != null) setState(() => _restoredSummary = summary);
  }

  Future<void> _restoreLocal() async {
    await controller.pickAndStageLocal();
    if (mounted) await _preview();
  }

  Future<void> _restoreRemote() async {
    if (controller.state.profile == null && !await _configure()) return;
    if (!mounted) return;
    final summary = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BackupHistoryPage()),
    );
    if (mounted && summary != null) setState(() => _restoredSummary = summary);
  }

  Future<void> _chooseContents() async {
    final s = controller.state;
    if (s.library == null) return;
    final selected = await Navigator.push<BackupSelection>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            BackupSelectionPage(library: s.library!, selection: s.selection),
      ),
    );
    if (!mounted || selected == null) return;
    final full = selected.selectSnapshot(s.library!);
    if (full.scripts.length == s.library!.scripts.length &&
        full.groups.length == s.library!.groups.length) {
      controller.selectAllLibrary();
    } else {
      controller.selectLibrary(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(backupControllerProvider).state;
    final l = AppLocalizations.of(context)!;
    final selected = s.library == null
        ? null
        : s.selection.selectSnapshot(s.library!);
    final empty =
        s.library != null &&
        s.library!.scripts.isEmpty &&
        s.library!.groups.isEmpty;
    final noSelection =
        selected == null ||
        (selected.scripts.isEmpty && selected.groups.isEmpty);
    final available = !s.busy && s.preview == null;
    Widget destination(String title, String subtitle, Widget button) =>
        LayoutBuilder(
          builder: (context, constraints) {
            final inline =
                constraints.maxWidth >=
                MediaQuery.textScalerOf(context).scale(240);
            final tile = ListTile(
              title: Text(title),
              subtitle: Text(subtitle),
              trailing: inline ? button : null,
            );
            return inline
                ? tile
                : Column(
                    children: [
                      tile,
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: button,
                        ),
                      ),
                    ],
                  );
          },
        );
    Widget action(
      String key,
      IconData icon,
      String title,
      Future<void> Function() command, {
      bool enabled = true,
    }) => ListTile(
      key: ValueKey(key),
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      enabled: available && enabled,
      onTap: available && enabled ? () => _run(command) : null,
    );
    return BackupPageFrame(
      title: l.backupTitle,
      scrollController: _scroll,
      canPop: s.operation?.cancellable != false,
      children: [
        BackupStatusPanel(
          onRetry: s.error == null
              ? null
              : () => _run(_retry ?? controller.loadLibrary),
          restoredSummary: _restoredSummary,
        ),
        if (s.preview != null)
          ListTile(
            key: const ValueKey('backup-resume-preview'),
            leading: const Icon(Icons.preview_outlined),
            title: Text(l.backupPreviewTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: s.busy ? null : _preview,
          ),
        BackupSection(
          title: l.backupContents,
          icon: Icons.inventory_2_outlined,
          children: [
            if (selected != null) BackupNote(backupScope(l, selected)),
            BackupNote(empty ? l.backupEmptyLibrary : l.backupScopeHint),
            if (!empty)
              ListTile(
                key: const ValueKey('backup-choose-contents'),
                title: Text(l.backupChooseContents),
                trailing: const Icon(Icons.chevron_right),
                onTap: available && s.library != null ? _chooseContents : null,
              ),
          ],
        ),
        BackupSection(
          title: l.backupActions,
          icon: Icons.backup_outlined,
          children: [
            if (noSelection && !empty) BackupNote(l.backupNothingSelected),
            action(
              'backup-export-local',
              Icons.save_alt,
              l.backupExportLocal,
              _export,
              enabled: !noSelection,
            ),
            action(
              'backup-upload',
              Icons.cloud_upload_outlined,
              l.backupUpload,
              _upload,
              enabled: !noSelection,
            ),
          ],
        ),
        BackupSection(
          title: l.backupRestoreSection,
          icon: Icons.restore,
          children: [
            BackupNote(l.backupRestoreHint),
            action(
              'backup-restore-local',
              Icons.folder_open_outlined,
              l.backupRestoreLocal,
              _restoreLocal,
            ),
            action(
              'backup-restore-remote',
              Icons.cloud_download_outlined,
              l.backupRestoreRemote,
              _restoreRemote,
            ),
          ],
        ),
        BackupSection(
          title: l.backupDestinations,
          icon: Icons.folder_outlined,
          children: [
            destination(
              l.backupLocalFolder,
              s.localDirectory?.name ?? l.backupFolderUnset,
              TextButton(
                key: const ValueKey('backup-change-folder'),
                onPressed: s.busy
                    ? null
                    : () => _run(controller.chooseLocalDirectory),
                child: Text(l.backupChange),
              ),
            ),
            destination(
              'WebDAV',
              s.profile == null
                  ? l.backupCloudUnset
                  : '${s.profile!.baseUri.host}${s.profile!.folderUri.path}',
              TextButton(
                key: const ValueKey('backup-configure'),
                onPressed: s.busy ? null : _configure,
                child: Text(s.profile == null ? l.backupConfigure : l.edit),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
