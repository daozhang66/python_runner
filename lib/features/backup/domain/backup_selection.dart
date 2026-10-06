import 'backup_manifest.dart';

/// Group selection includes its scripts; selecting a script includes its group
/// metadata without implicitly selecting siblings. Projects are always whole.
class BackupSelection {
  final Set<String> scriptNames;
  final Set<int> groupIds;

  BackupSelection({
    Iterable<String> scriptNames = const [],
    Iterable<int> groupIds = const [],
  }) : scriptNames = Set.unmodifiable(scriptNames),
       groupIds = Set.unmodifiable(groupIds);

  factory BackupSelection.all(BackupManifest manifest) => BackupSelection(
    scriptNames: manifest.scripts.map((s) => s.name),
    groupIds: manifest.groups.map((g) => g.id!),
  );

  BackupLibrarySnapshot selectSnapshot(BackupLibrarySnapshot snapshot) {
    if (!snapshot.scripts.map((s) => s.name).toSet().containsAll(scriptNames) ||
        !snapshot.groups.map((g) => g.id).toSet().containsAll(groupIds)) {
      throw const FormatException('Selection references missing metadata');
    }
    final scripts = snapshot.scripts
        .where(
          (s) => scriptNames.contains(s.name) || groupIds.contains(s.groupId),
        )
        .toList();
    final selectedGroups = {
      ...groupIds,
      ...scripts.map((s) => s.groupId).nonNulls,
    };
    return BackupLibrarySnapshot(
      scripts: scripts,
      groups: snapshot.groups.where((g) => selectedGroups.contains(g.id)),
    );
  }

  BackupManifest select(BackupManifest manifest) {
    final snapshot = selectSnapshot(
      BackupLibrarySnapshot(scripts: manifest.scripts, groups: manifest.groups),
    );
    final names = snapshot.scripts.map((s) => s.name).toSet();
    final keys = snapshot.groups
        .where((g) => g.isProject)
        .map((g) => g.projectKey)
        .toSet();
    return BackupManifest(
      createdAt: manifest.createdAt,
      scripts: snapshot.scripts,
      groups: snapshot.groups,
      files: manifest.files.where((f) {
        final parts = f.path.split('/');
        if (parts.length == 1) {
          return parts.first == 'scripts' ? names.isNotEmpty : keys.isNotEmpty;
        }
        return parts.first == 'scripts'
            ? names.contains(parts[1])
            : keys.contains(parts[1]);
      }),
    );
  }
}
