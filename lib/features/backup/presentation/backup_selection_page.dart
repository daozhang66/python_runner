import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/script_file.dart';
import '../domain/backup_manifest.dart';
import '../domain/backup_selection.dart';
import 'backup_widgets.dart';

class BackupSelectionPage extends StatefulWidget {
  const BackupSelectionPage({
    super.key,
    required this.library,
    required this.selection,
  });
  final BackupLibrarySnapshot library;
  final BackupSelection selection;
  @override
  State<BackupSelectionPage> createState() => _BackupSelectionPageState();
}

class _BackupSelectionPageState extends State<BackupSelectionPage> {
  late Set<String> scripts = {...widget.selection.scriptNames};
  late Set<int> groups = {...widget.selection.groupIds};
  BackupSelection get selection =>
      BackupSelection(scriptNames: scripts, groupIds: groups);
  bool selected(ScriptFile script) =>
      scripts.contains(script.name) || groups.contains(script.groupId);
  void toggleScript(ScriptFile script, bool value) => setState(() {
    // A selected group means ALL of its children. Expand it before removing
    // one child so that the remaining explicit siblings stay selected.
    if (groups.remove(script.groupId)) {
      scripts.addAll(
        widget.library.scripts
            .where((s) => s.groupId == script.groupId)
            .map((s) => s.name),
      );
    }
    value ? scripts.add(script.name) : scripts.remove(script.name);
  });
  Widget scriptTile(ScriptFile script) => CheckboxListTile(
    key: ValueKey('script-${script.name}'),
    controlAffinity: ListTileControlAffinity.leading,
    title: Text(script.name),
    value: selected(script),
    onChanged: (value) => toggleScript(script, value ?? false),
  );
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return BackupPageFrame(
      title: l.backupChooseContents,
      children: [
        BackupNote(backupScope(l, selection.selectSnapshot(widget.library))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => setState(() {
                  scripts = widget.library.scripts.map((s) => s.name).toSet();
                  groups = widget.library.groups.map((g) => g.id!).toSet();
                }),
                child: Text(l.backupSelectAll),
              ),
              TextButton(
                onPressed: () => setState(() {
                  scripts.clear();
                  groups.clear();
                }),
                child: Text(l.backupClearAll),
              ),
            ],
          ),
        ),
        if (widget.library.scripts.any((s) => s.groupId == null))
          BackupSection(
            title: l.backupRootScripts,
            icon: Icons.code,
            children: widget.library.scripts
                .where((s) => s.groupId == null)
                .map(scriptTile)
                .toList(),
          ),
        for (final group in widget.library.groups)
          if (group.isProject)
            CheckboxListTile(
              key: ValueKey('group-${group.id}'),
              controlAffinity: ListTileControlAffinity.leading,
              value: groups.contains(group.id),
              title: Text(group.name),
              subtitle: Text(l.backupWholeProject),
              onChanged: (v) => setState(() {
                v == true ? groups.add(group.id!) : groups.remove(group.id);
              }),
            )
          else
            Builder(
              builder: (context) {
                final children = widget.library.scripts
                    .where((s) => s.groupId == group.id)
                    .toList();
                final count = children.where(selected).length;
                final bool? value =
                    groups.contains(group.id) ||
                        (children.isNotEmpty && count == children.length)
                    ? true
                    : count == 0
                    ? false
                    : null;
                void toggle(bool? _) => setState(() {
                  final all = value == true;
                  if (all) {
                    groups.remove(group.id);
                    scripts.removeAll(children.map((s) => s.name));
                  } else {
                    groups.add(group.id!);
                  }
                });
                if (children.isEmpty) {
                  return CheckboxListTile(
                    key: ValueKey('group-${group.id}'),
                    controlAffinity: ListTileControlAffinity.leading,
                    value: value,
                    title: Text(group.name),
                    subtitle: Text(l.backupEmptyGroup),
                    onChanged: toggle,
                  );
                }
                return ExpansionTile(
                  key: ValueKey('expand-${group.id}'),
                  leading: Checkbox(
                    key: ValueKey('group-${group.id}'),
                    tristate: true,
                    value: value,
                    onChanged: toggle,
                  ),
                  title: Text(group.name),
                  children: children.map(scriptTile).toList(),
                );
              },
            ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey('selection-confirm'),
              onPressed: () => Navigator.pop(context, selection),
              child: Text(l.backupUseSelection),
            ),
          ),
        ),
      ],
    );
  }
}
