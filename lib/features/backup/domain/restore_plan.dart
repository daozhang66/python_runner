import '../../../models/script_file.dart';
import '../../../models/script_group.dart';
import '../../../services/project_path_validator.dart';
import '../../../services/script_name_validator.dart';

enum RestoreConflictPolicy { keepBoth, overwrite, skip }

enum RestoreAction { create, reuse, overwrite }

class PlannedRestoreGroup {
  final int sourceId;

  /// ID is null for creates and the local ID for reuse/overwrite.
  final ScriptGroup group;
  final RestoreAction action;
  const PlannedRestoreGroup({
    required this.sourceId,
    required this.group,
    required this.action,
  });
}

class PlannedRestoreScript {
  final String sourceName;

  /// The final local name and metadata. Never contains a donor absolute path.
  final ScriptFile script;

  /// Source linkage to resolve after group insertion; null for root scripts.
  final int? sourceGroupId;
  final RestoreAction action;
  const PlannedRestoreScript({
    required this.sourceName,
    required this.script,
    required this.sourceGroupId,
    required this.action,
  });
}

class RestoreFileMove {
  final String sourceRoot;
  final String targetRoot;
  final bool overwrite;
  RestoreFileMove({
    required this.sourceRoot,
    required this.targetRoot,
    required this.overwrite,
  }) {
    _validateRoot(sourceRoot);
    _validateRoot(targetRoot);
    if (sourceRoot.split('/').first != targetRoot.split('/').first) {
      throw const FormatException('Restore roots must have the same kind');
    }
  }
  Map<String, dynamic> toJson() => {
    'sourceRoot': sourceRoot,
    'targetRoot': targetRoot,
    'overwrite': overwrite,
  };

  static void _validateRoot(String root) {
    final parts = root.split('/');
    if (parts.length != 2) throw const FormatException('Invalid restore root');
    if (parts[0] == 'scripts') {
      if (ScriptNameValidator.normalize(parts[1]) != parts[1]) {
        throw const FormatException('Invalid script root');
      }
    } else if (parts[0] == 'projects') {
      ProjectPathValidator.normalizeProjectKey(parts[1]);
    } else {
      throw const FormatException('Invalid restore root kind');
    }
  }
}

/// Backfills legacy root ranks so appended restored items cannot precede roots
/// that previously had null homeSortOrder. Relative existing order is unchanged.
class RestoreHomePlacement {
  final String? scriptName;
  final int? groupId;
  final int homeSortOrder;
  const RestoreHomePlacement.script(String name, this.homeSortOrder)
    : scriptName = name,
      groupId = null;
  const RestoreHomePlacement.group(int id, this.homeSortOrder)
    : scriptName = null,
      groupId = id;
}

class RestorePlan {
  final List<PlannedRestoreGroup> groups;
  final List<PlannedRestoreScript> scripts;
  final List<RestoreFileMove> fileMoves;
  final List<RestoreHomePlacement> homePlacements;
  final List<String> skippedScriptNames;
  final List<int> skippedGroupIds;
  RestorePlan({
    required Iterable<PlannedRestoreGroup> groups,
    required Iterable<PlannedRestoreScript> scripts,
    required Iterable<RestoreFileMove> fileMoves,
    Iterable<RestoreHomePlacement> homePlacements = const [],
    Iterable<String> skippedScriptNames = const [],
    Iterable<int> skippedGroupIds = const [],
  }) : groups = List.unmodifiable(groups),
       scripts = List.unmodifiable(scripts),
       fileMoves = List.unmodifiable(fileMoves),
       homePlacements = List.unmodifiable(homePlacements),
       skippedScriptNames = List.unmodifiable(skippedScriptNames),
       skippedGroupIds = List.unmodifiable(skippedGroupIds);
}
