import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_dialogs.dart';
import '../application/backup_controller.dart';
import '../application/backup_providers.dart';
import '../domain/backup_manifest.dart';
import '../domain/backup_selection.dart';
import '../domain/restore_plan.dart';
import 'backup_selection_page.dart';
import 'backup_widgets.dart';

class BackupPreviewPage extends ConsumerStatefulWidget {
  const BackupPreviewPage({super.key});
  @override
  ConsumerState<BackupPreviewPage> createState() => _BackupPreviewPageState();
}

class _BackupPreviewPageState extends ConsumerState<BackupPreviewPage> {
  late final TextEditingController _name;
  Future<void> _nameUpdate = Future.value();
  bool _updating = false;
  bool _leaving = false;
  final _scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    final preview = ref.read(backupControllerProvider).state.preview;
    _name = TextEditingController(
      text: preview?.legacy == true ? preview!.manifest.groups.single.name : '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _scroll.dispose();
    super.dispose();
  }

  BackupController get controller => ref.read(backupControllerProvider);
  bool get _validName =>
      _name.text.trim().isNotEmpty &&
      _name.text.length <= 255 &&
      !RegExp(r'[\x00-\x1f\x7f]').hasMatch(_name.text);
  Future<void> _update(Future<void> Function() command) async {
    if (_updating || controller.state.busy) return;
    setState(() => _updating = true);
    await command();
    if (mounted) setState(() => _updating = false);
  }

  Future<void> _leave() async {
    if (_leaving || controller.state.operation?.cancellable == false) return;
    _leaving = true;
    if (controller.state.busy) {
      await controller.cancel();
      _leaving = false;
      return;
    }
    if (!mounted) return;
    await controller.discardPreview();
    if (!mounted) return;
    if (controller.state.preview != null) {
      _leaving = false;
      return;
    }
    await _pop();
  }

  Future<void> _pop([String? summary]) async {
    if (mounted) Navigator.pop(context, summary);
  }

  Future<void> _choose() async {
    final p = controller.state.preview!;
    final selected = await Navigator.push<BackupSelection>(
      context,
      MaterialPageRoute(
        builder: (_) => BackupSelectionPage(
          library: BackupLibrarySnapshot(
            scripts: p.manifest.scripts,
            groups: p.manifest.groups,
          ),
          selection: p.selection,
        ),
      ),
    );
    if (mounted && selected != null) {
      await _update(() => controller.updateRestoreSelection(selected));
    }
  }

  Future<void> _restore() async {
    // Guard callbacks immediately; the disabled button may not have rebuilt
    // yet when two accessibility/keyboard actions arrive in the same frame.
    if (_updating || controller.state.busy) return;
    Future<void> appliedName;
    do {
      appliedName = _nameUpdate;
      await appliedName;
    } while (!identical(appliedName, _nameUpdate));
    if (!mounted || _updating || controller.state.busy) {
      return;
    }
    final p = controller.state.preview;
    if (p == null || !p.hasChanges || (p.legacy && !_validName)) return;
    final l = AppLocalizations.of(context)!;
    final replaces = p.plan.fileMoves.any((m) => m.overwrite);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AppAlertDialog(
        title: Text(l.backupConfirmTitle),
        scrollable: true,
        content: Text(replaces ? l.backupReplaceConfirm : l.backupConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          TextButton(
            key: const ValueKey('restore-confirm-dialog'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.backupRestoreNow),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true) return;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await controller.confirmRestore(confirmed: true);
    if (!mounted) return;
    final s = controller.state;
    // A refreshed preview needs another deliberate confirmation; errors,
    // including cleanup errors, stay visible with their recovery action.
    if (s.error == null && s.lastResult?.kind == BackupResultKind.restored) {
      await _pop(
        l.backupRestored(
          p.plan.scripts.length,
          p.plan.groups.where((g) => g.group.isProject).length,
          p.plan.groups.where((g) => !g.group.isProject).length,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(backupControllerProvider).state;
    final p = s.preview;
    final l = AppLocalizations.of(context)!;
    final enabled = !s.busy && !_updating;
    return BackupPageFrame(
      title: p?.legacy == true ? l.backupLegacyTitle : l.backupPreviewTitle,
      scrollController: _scroll,
      canPop: false,
      onBack: _leave,
      children: [
        BackupStatusPanel(onRetry: p == null ? null : _restore),
        if (p != null) ...[
          if (!p.legacy)
            BackupNote(
              l.backupCreated(backupDate(context, p.manifest.createdAt)),
            ),
          BackupSection(
            title: l.backupContents,
            icon: Icons.inventory_2_outlined,
            children: [
              BackupNote(
                backupScope(
                  l,
                  p.selection.selectSnapshot(
                    BackupLibrarySnapshot(
                      scripts: p.manifest.scripts,
                      groups: p.manifest.groups,
                    ),
                  ),
                ),
              ),
              ListTile(
                key: const ValueKey('restore-choose-contents'),
                title: Text(l.backupChooseContents),
                trailing: const Icon(Icons.chevron_right),
                onTap: enabled ? _choose : null,
              ),
            ],
          ),
          if (p.legacy)
            BackupSection(
              title: l.backupLegacyTitle,
              icon: Icons.folder_zip_outlined,
              children: [
                BackupNote(l.backupLegacyHint),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    key: const ValueKey('legacy-project-name'),
                    controller: _name,
                    enabled: !s.busy,
                    decoration: InputDecoration(
                      labelText: l.backupProjectName,
                      errorText: !_validName
                          ? l.backupInvalidProjectName
                          : null,
                      errorMaxLines: 4,
                    ),
                    onChanged: (name) {
                      setState(() {});
                      _nameUpdate = controller.updateLegacyProjectName(name);
                    },
                  ),
                ),
                if (p.legacyEntryPoints.isEmpty)
                  BackupNote(l.backupNoPythonFiles),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('legacy-entry-${p.legacyEntryPoint}'),
                    isExpanded: true,
                    initialValue: p.legacyEntryPoint ?? '',
                    decoration: InputDecoration(labelText: l.backupEntryPoint),
                    items: [
                      DropdownMenuItem(
                        value: '',
                        child: Text(l.backupNoEntryPoint, maxLines: 2),
                      ),
                      for (final path in p.legacyEntryPoints)
                        DropdownMenuItem(
                          value: path,
                          child: Text(
                            path,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: enabled
                        ? (value) => _update(
                            () => controller.updateLegacyEntryPoint(
                              value == '' ? null : value,
                            ),
                          )
                        : null,
                  ),
                ),
              ],
            )
          else
            BackupSection(
              title: l.backupPolicyTitle,
              icon: Icons.compare_arrows,
              children: [
                RadioGroup<RestoreConflictPolicy>(
                  groupValue: p.policy,
                  onChanged: (value) {
                    if (enabled && value != null) {
                      _update(() => controller.updateRestorePolicy(value));
                    }
                  },
                  child: Column(
                    children: [
                      RadioListTile(
                        value: RestoreConflictPolicy.keepBoth,
                        key: const ValueKey('policy-keepBoth'),
                        enabled: enabled,
                        title: Text(l.backupKeepBoth),
                        subtitle: Text(l.backupKeepBothHint),
                      ),
                      RadioListTile(
                        value: RestoreConflictPolicy.overwrite,
                        key: const ValueKey('policy-overwrite'),
                        enabled: enabled,
                        title: Text(l.backupOverwrite),
                        subtitle: Text(l.backupOverwriteHint),
                      ),
                      RadioListTile(
                        value: RestoreConflictPolicy.skip,
                        key: const ValueKey('policy-skip'),
                        enabled: enabled,
                        title: Text(l.backupSkip),
                        subtitle: Text(l.backupSkipHint),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          BackupSection(
            title: l.backupPlanTitle,
            icon: Icons.fact_check_outlined,
            children: [
              BackupNote(
                l.backupPlanCounts(
                  p.plan.scripts.length,
                  p.plan.groups.where((g) => g.group.isProject).length,
                  p.plan.groups
                      .where(
                        (g) =>
                            g.group.isProject &&
                            g.action == RestoreAction.overwrite,
                      )
                      .length,
                  p.plan.skippedScriptNames.length +
                      p.plan.skippedGroupIds.length,
                ),
              ),
              for (final script in p.plan.scripts)
                if (script.sourceName != script.script.name)
                  BackupNote(
                    l.backupRename(script.sourceName, script.script.name),
                  )
                else if (script.action == RestoreAction.overwrite)
                  BackupNote(l.backupReplaceItem(script.script.name)),
              for (final group in p.plan.groups) ...[
                if (group.group.name !=
                    p.manifest.groups
                        .firstWhere((g) => g.id == group.sourceId)
                        .name)
                  BackupNote(
                    l.backupRename(
                      p.manifest.groups
                          .firstWhere((g) => g.id == group.sourceId)
                          .name,
                      group.group.name,
                    ),
                  )
                else if (group.action == RestoreAction.overwrite)
                  BackupNote(l.backupReplaceItem(group.group.name)),
              ],
              for (final name in p.plan.skippedScriptNames)
                BackupNote(l.backupSkipItem(name)),
              for (final id in p.plan.skippedGroupIds)
                BackupNote(
                  l.backupSkipItem(
                    p.manifest.groups.firstWhere((g) => g.id == id).name,
                  ),
                ),
              if (!p.hasChanges) BackupNote(l.backupNoChanges),
            ],
          ),
        ],
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                key: const ValueKey('restore-discard'),
                onPressed: enabled ? _leave : null,
                child: Text(p == null ? l.close : l.backupDiscardPreview),
              ),
              if (p != null)
                OutlinedButton(
                  key: const ValueKey('restore-confirm'),
                  onPressed:
                      enabled && p.hasChanges && (!p.legacy || _validName)
                      ? _restore
                      : null,
                  child: Text(l.backupRestoreNow),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
