import 'dart:convert';
import 'dart:math';

import '../../../models/script_file.dart';
import '../../../models/script_group.dart';
import '../../../services/project_path_validator.dart';
import '../../scripts/application/script_home_item.dart';
import 'backup_manifest.dart';
import 'backup_selection.dart';
import 'restore_plan.dart';

/// Pure planning with no filesystem/DB access. Supply a key factory to make new
/// project identities deterministic in tests; production uses random local keys.
class RestorePlanner {
  final String Function() projectKeyFactory;
  final String Function(ScriptGroup source)? projectKeyForGroup;
  RestorePlanner({String Function()? projectKeyFactory, this.projectKeyForGroup})
    : projectKeyFactory = projectKeyFactory ?? _randomProjectKey;

  RestorePlan plan({
    required BackupManifest manifest,
    required BackupSelection selection,
    required Iterable<ScriptFile> existingScripts,
    required Iterable<ScriptGroup> existingGroups,
    RestoreConflictPolicy policy = RestoreConflictPolicy.keepBoth,
  }) {
    final source = selection.select(manifest);
    final sourceGroupsById = {
      for (final group in source.groups) group.id: group,
    };
    final localScripts = existingScripts.toList();
    final localGroups = existingGroups.toList();
    final empty = localScripts.isEmpty && localGroups.isEmpty;
    final scriptsByName = {
      for (final script in localScripts) script.name: script,
    };
    final groupsByName = {for (final group in localGroups) group.name: group};
    final projectsByKey = {
      for (final group in localGroups.where((g) => g.isProject))
        group.projectKey: group,
    };
    final sourceProjectKeys = source.groups
        .where((g) => g.isProject)
        .map((g) => g.projectKey)
        .toSet();
    final reservedScriptNames = {
      ...scriptsByName.keys,
      ...source.scripts.map((s) => s.name),
    };
    final reservedGroupNames = {
      ...groupsByName.keys,
      ...source.groups.map((g) => g.name),
    };
    final reservedKeys = {
      ...projectsByKey.keys.nonNulls,
      ...manifest.groups.map((g) => g.projectKey).nonNulls,
    };
    final groups = <PlannedRestoreGroup>[];
    final scripts = <PlannedRestoreScript>[];
    final moves = <RestoreFileMove>[];
    final skippedScripts = <String>[];
    final skippedGroups = <int>[];
    final movedToRoot = <String>{};
    final preserveScriptPlacement = <String>{};
    var groupOrder =
        localGroups.fold(-1, (int value, g) => max(value, g.sortOrder)) + 1;
    var scriptOrder =
        localScripts.fold(-1, (int value, s) => max(value, s.sortOrder)) + 1;
    final groupRanks = <int, int>{};
    final scriptRanks = <String, int>{};
    for (final group
        in source.groups.toList()..sort((a, b) {
          final order = a.sortOrder.compareTo(b.sortOrder);
          return order != 0 ? order : a.id!.compareTo(b.id!);
        })) {
      groupRanks[group.id!] = groupOrder++;
    }
    for (final script
        in source.scripts.toList()..sort((a, b) {
          final order = a.sortOrder.compareTo(b.sortOrder);
          return order != 0 ? order : a.name.compareTo(b.name);
        })) {
      scriptRanks[script.name] = scriptOrder++;
    }
    for (final group in source.groups) {
      final named = groupsByName[group.name];
      // A stable-key match owns its destination even if a different source
      // project's display name also matches it earlier in manifest order.
      final availableNamedProject =
          named?.isProject == true &&
              (policy != RestoreConflictPolicy.overwrite ||
                  !sourceProjectKeys.contains(named!.projectKey) ||
                  named.projectKey == group.projectKey)
          ? named
          : null;
      final target = group.isProject
          ? (projectsByKey[group.projectKey] ?? availableNamedProject)
          : (named?.isProject == false ? named : null);
      if (group.isProject &&
          target != null &&
          policy == RestoreConflictPolicy.skip) {
        skippedGroups.add(group.id!);
        continue;
      }
      if (!group.isProject && target != null) {
        groups.add(
          PlannedRestoreGroup(
            sourceId: group.id!,
            group: target,
            action: RestoreAction.reuse,
          ),
        );
        continue;
      }
      final overwrite =
          group.isProject &&
          target != null &&
          policy == RestoreConflictPolicy.overwrite;
      final collision = named != null || target != null;
      final name = overwrite
          ? target.name
          : (collision
                ? _uniqueName(group.name, reservedGroupNames, script: false)
                : group.name);
      final key = group.isProject
          ? (overwrite ? target.projectKey : _newProjectKey(reservedKeys, group))
          : null;
      final destination = ScriptGroup(
        id: overwrite ? target.id : null,
        name: name,
        sortOrder: overwrite
            ? target.sortOrder
            : (empty ? group.sortOrder : groupRanks[group.id]!),
        createdAt: group.createdAt,
        modifiedAt: group.modifiedAt,
        projectKey: key,
        mainFilePath: group.mainFilePath,
        isProject: group.isProject,
        homeSortOrder: overwrite ? target.homeSortOrder : group.homeSortOrder,
      );
      groups.add(
        PlannedRestoreGroup(
          sourceId: group.id!,
          group: destination,
          action: overwrite ? RestoreAction.overwrite : RestoreAction.create,
        ),
      );
    }
    final destinationGroups = {
      for (final group in groups) group.sourceId: group.group,
    };
    for (final script in source.scripts) {
      final target = scriptsByName[script.name];
      if (target != null && policy == RestoreConflictPolicy.skip) {
        skippedScripts.add(script.name);
        continue;
      }
      final overwrite =
          target != null && policy == RestoreConflictPolicy.overwrite;
      final name = target != null && !overwrite
          ? _uniqueName(script.name, reservedScriptNames, script: true)
          : script.name;
      final destinationGroup = script.groupId == null
          ? null
          : destinationGroups[script.groupId]!;
      final samePlacement =
          overwrite &&
          (script.groupId == null
              ? target.groupId == null
              : destinationGroup!.id != null &&
                    destinationGroup.id == target.groupId);
      if (samePlacement) preserveScriptPlacement.add(script.name);
      if (overwrite && !samePlacement && script.groupId == null) {
        movedToRoot.add(script.name);
      }
      final destination = ScriptFile(
        name: name,
        path: '',
        createdAt: script.createdAt,
        modifiedAt: script.modifiedAt,
        runCount: script.runCount,
        isPinned: script.isPinned,
        sortOrder: samePlacement
            ? target.sortOrder
            : (empty ? script.sortOrder : scriptRanks[script.name]!),
        groupId: destinationGroup?.id,
        homeSortOrder: samePlacement
            ? target.homeSortOrder
            : script.homeSortOrder,
      );
      scripts.add(
        PlannedRestoreScript(
          sourceName: script.name,
          script: destination,
          sourceGroupId: script.groupId,
          action: overwrite ? RestoreAction.overwrite : RestoreAction.create,
        ),
      );
      moves.add(
        RestoreFileMove(
          sourceRoot: 'scripts/${script.name}',
          targetRoot: 'scripts/$name',
          overwrite: overwrite,
        ),
      );
    }
    for (final group in groups.where((g) => g.group.isProject)) {
      final sourceGroup = sourceGroupsById[group.sourceId]!;
      moves.add(
        RestoreFileMove(
          sourceRoot: 'projects/${sourceGroup.projectKey}',
          targetRoot: 'projects/${group.group.projectKey}',
          overwrite: group.action == RestoreAction.overwrite,
        ),
      );
    }

    final newRootKeys = {
      ...groups
          .where((g) => g.action == RestoreAction.create)
          .map((g) => 'group:${g.sourceId}'),
      ...scripts
          .where(
            (s) =>
                (s.action == RestoreAction.create ||
                    movedToRoot.contains(s.sourceName)) &&
                s.sourceGroupId == null &&
                !s.script.isPinned,
          )
          .map((s) => s.sourceName),
    };
    final homePlacements = <RestoreHomePlacement>[];
    final newHomes = <String, int>{};
    final existingHomes = <String, int>{};
    // Restored timestamps can reorder roots with null ranks even when every
    // selected item overwrites an existing item and nothing is appended.
    final overwritesRootMetadata =
        groups.any((g) => g.action == RestoreAction.overwrite) ||
        scripts.any(
          (s) => s.action == RestoreAction.overwrite && s.sourceGroupId == null,
        );
    if (!empty && (newRootKeys.isNotEmpty || overwritesRootMetadata)) {
      for (final item in ScriptHomeItem.ordered(
        localScripts,
        localGroups,
      ).where((i) => !i.isPinned)) {
        final rank = homePlacements.length;
        existingHomes[item.key] = rank;
        homePlacements.add(
          item.script != null
              ? RestoreHomePlacement.script(item.script!.name, rank)
              : RestoreHomePlacement.group(item.group!.id!, rank),
        );
      }
      var rank = homePlacements.length;
      for (final item in ScriptHomeItem.ordered(
        source.scripts,
        source.groups,
      )) {
        if (newRootKeys.contains(item.key)) newHomes[item.key] = rank++;
      }
    }
    return RestorePlan(
      groups: groups.map((planned) {
        final key = planned.action == RestoreAction.create
            ? 'group:${planned.sourceId}'
            : 'group:${planned.group.id}';
        final home = planned.action == RestoreAction.create
            ? newHomes[key]
            : existingHomes[key];
        return PlannedRestoreGroup(
          sourceId: planned.sourceId,
          group: home == null
              ? planned.group
              : planned.group.copyWith(homeSortOrder: home),
          action: planned.action,
        );
      }),
      scripts: scripts.map((planned) {
        final home = preserveScriptPlacement.contains(planned.sourceName)
            ? existingHomes[planned.script.name]
            : newHomes[planned.sourceName];
        return PlannedRestoreScript(
          sourceName: planned.sourceName,
          script: home == null
              ? planned.script
              : planned.script.copyWith(homeSortOrder: home),
          sourceGroupId: planned.sourceGroupId,
          action: planned.action,
        );
      }),
      fileMoves: moves,
      homePlacements: homePlacements,
      skippedScriptNames: skippedScripts,
      skippedGroupIds: skippedGroups,
    );
  }

  String _newProjectKey(Set<String> reserved, ScriptGroup source) {
    for (var attempt = 0; attempt < 100; attempt++) {
      final key = ProjectPathValidator.normalizeProjectKey(projectKeyForGroup?.call(source) ?? projectKeyFactory());
      if (key.length > 255) throw const FormatException('Project key too long');
      if (reserved.add(key)) return key;
    }
    throw StateError('Project key factory did not produce an unused key');
  }

  static String _uniqueName(
    String name,
    Set<String> reserved, {
    required bool script,
  }) {
    final dot = script ? name.lastIndexOf('.') : -1;
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final extension = dot > 0 ? name.substring(dot) : '';
    for (var i = 1; ; i++) {
      final suffix = ' (restored $i)$extension';
      final shortened = script
          ? _utf8Prefix(stem, 255 - utf8.encode(suffix).length)
          : (stem.length + suffix.length > 255
                ? stem.substring(0, 255 - suffix.length)
                : stem);
      final candidate = '$shortened$suffix';
      if (reserved.add(candidate)) return candidate;
    }
  }

  static String _utf8Prefix(String value, int maxBytes) {
    final prefix = StringBuffer();
    var usedBytes = 0;
    // Iterate scalars so truncation cannot split a UTF-16 surrogate pair.
    for (final rune in value.runes) {
      final character = String.fromCharCode(rune);
      final bytes = utf8.encode(character).length;
      if (usedBytes + bytes > maxBytes) break;
      prefix.write(character);
      usedBytes += bytes;
    }
    return prefix.toString();
  }

  static String _randomProjectKey() {
    final random = Random.secure();
    return 'restored_${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  }
}
