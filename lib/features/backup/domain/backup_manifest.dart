import '../../../models/script_file.dart';
import '../../../models/script_group.dart';
import '../../../services/project_path_validator.dart';
import '../../../services/script_name_validator.dart';

/// A recognized backup format whose integral version this app cannot read.
/// Retains FormatException compatibility for callers that reject all bad input.
class UnsupportedBackupVersion extends FormatException {
  const UnsupportedBackupVersion(this.version)
    : super('Unsupported backup version');
  final int version;
}

/// Portable metadata. Source IDs link records only; script paths are discarded.
class BackupManifest {
  static const markerFileName = '.python_runner_backup.json';
  static const format = 'python_runner_backup';
  static const version = 1;
  static const maxMetadataRecords = 10000;
  static const maxFileRecords = 100000;

  final DateTime createdAt;
  final List<ScriptFile> scripts;
  final List<ScriptGroup> groups;
  final List<BackupFileEntry> files;

  BackupManifest({
    required this.createdAt,
    required Iterable<ScriptFile> scripts,
    required Iterable<ScriptGroup> groups,
    required Iterable<BackupFileEntry> files,
  }) : scripts = List.unmodifiable(scripts.map((s) => s.copyWith(path: ''))),
       groups = List.unmodifiable(groups),
       files = List.unmodifiable(files) {
    _validate();
  }

  factory BackupManifest.fromJson(Map<String, dynamic> json) {
    final archiveVersion = json['version'];
    if (json['format'] != format ||
        archiveVersion is! int ||
        archiveVersion < 0 ||
        archiveVersion > 9007199254740991) {
      throw const FormatException('Invalid backup format or version');
    }
    if (archiveVersion != version) {
      throw UnsupportedBackupVersion(archiveVersion);
    }
    return BackupManifest(
      createdAt: _date(json, 'createdAt'),
      scripts: _records(
        json,
        'scripts',
        maxMetadataRecords,
      ).map(_scriptFromJson),
      groups: _records(json, 'groups', maxMetadataRecords).map(_groupFromJson),
      files: _records(
        json,
        'files',
        maxFileRecords,
      ).map(BackupFileEntry.fromJson),
    );
  }

  Map<String, dynamic> toJson() => {
    ...BackupLibrarySnapshot(
      scripts: scripts,
      groups: groups,
    ).toMetadataJson(createdAt: createdAt),
    'files': files.map((f) => f.toJson()).toList(),
  };

  void _validate() {
    if (scripts.length > maxMetadataRecords ||
        groups.length > maxMetadataRecords ||
        files.length > maxFileRecords) {
      throw const FormatException('Backup record limit exceeded');
    }
    _validEpoch(createdAt.millisecondsSinceEpoch, 'createdAt');
    final groupById = <int, ScriptGroup>{};
    final groupNames = <String>{};
    final projectKeys = <String>{};
    for (final group in groups) {
      _groupFromJson(_groupJson(group));
      if (groupById.containsKey(group.id) || !groupNames.add(group.name)) {
        throw const FormatException('Duplicate group ID or name');
      }
      groupById[group.id!] = group;
      if (group.isProject && !projectKeys.add(group.projectKey!)) {
        throw const FormatException('Duplicate project key');
      }
    }
    final scriptNames = <String>{};
    for (final script in scripts) {
      _scriptFromJson(_scriptJson(script));
      if (!scriptNames.add(script.name)) {
        throw const FormatException('Duplicate script name');
      }
      if (script.groupId != null) {
        final group = groupById[script.groupId];
        if (group == null || group.isProject) {
          throw const FormatException(
            'Invalid standalone script group reference',
          );
        }
      }
    }
    final fileByPath = <String, BackupFileEntry>{};
    final populatedProjects = <String>{};
    for (final file in files) {
      file.validate();
      if (fileByPath.containsKey(file.path)) {
        throw const FormatException('Duplicate payload path');
      }
      fileByPath[file.path] = file;
      final parts = file.path.split('/');
      if ((file.path == 'scripts' || file.path == 'projects') &&
          file.isDirectory) {
        continue;
      }
      if (parts.first == 'scripts') {
        if (parts.length != 2 ||
            file.isDirectory ||
            !scriptNames.contains(parts[1])) {
          throw const FormatException('Unknown standalone script payload');
        }
      } else if (parts.first == 'projects') {
        if (parts.length < 2 ||
            !projectKeys.contains(parts[1]) ||
            (parts.length == 2 && !file.isDirectory)) {
          throw const FormatException('Unknown project payload');
        }
        populatedProjects.add(parts[1]);
      } else {
        throw const FormatException('Payload outside scripts/projects');
      }
    }
    for (final file in files) {
      final parts = file.path.split('/');
      for (var i = 1; i < parts.length; i++) {
        final ancestor = fileByPath[parts.take(i).join('/')];
        if (ancestor != null && !ancestor.isDirectory) {
          throw const FormatException('Payload has a file as an ancestor');
        }
      }
    }
    for (final script in scripts) {
      if (fileByPath['scripts/${script.name}']?.isDirectory != false) {
        throw const FormatException('Missing script payload');
      }
    }
    for (final group in groups.where((g) => g.isProject)) {
      final root = 'projects/${group.projectKey}';
      if (!populatedProjects.contains(group.projectKey)) {
        throw const FormatException('Missing project payload');
      }
      if (group.mainFilePath != null &&
          fileByPath['$root/${group.mainFilePath}']?.isDirectory != false) {
        throw const FormatException('Missing project entrypoint');
      }
    }
  }
}

/// A transactionally read library snapshot, before native payload enumeration.
class BackupLibrarySnapshot {
  final List<ScriptFile> scripts;
  final List<ScriptGroup> groups;

  BackupLibrarySnapshot({
    required Iterable<ScriptFile> scripts,
    required Iterable<ScriptGroup> groups,
  }) : scripts = List.unmodifiable(scripts),
       groups = List.unmodifiable(groups);

  Map<String, dynamic> toMetadataJson({required DateTime createdAt}) => {
    'format': BackupManifest.format,
    'version': BackupManifest.version,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'scripts': scripts.map(_scriptJson).toList(),
    'groups': groups.map(_groupJson).toList(),
  };
}

class BackupFileEntry {
  final String path;
  final bool isDirectory;
  final int size;
  final String? sha256;
  final DateTime modifiedAt;

  const BackupFileEntry({
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.sha256,
    required this.modifiedAt,
  });

  factory BackupFileEntry.fromJson(Map<String, dynamic> json) {
    final entry = BackupFileEntry(
      path: _string(json, 'path'),
      isDirectory: _boolean(json, 'isDirectory'),
      size: _integer(json, 'size'),
      sha256: _nullableString(json, 'sha256'),
      modifiedAt: _date(json, 'modifiedAt'),
    );
    entry.validate();
    return entry;
  }

  void validate() {
    validateBackupRelativePath(path);
    _validEpoch(modifiedAt.millisecondsSinceEpoch, 'modifiedAt');
    if (size < 0 || size > 9007199254740991) {
      throw const FormatException('Invalid file size');
    }
    if (isDirectory
        ? (size != 0 || sha256 != null)
        : (sha256 == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256!))) {
      throw const FormatException('Invalid payload size or SHA-256');
    }
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'isDirectory': isDirectory,
    'size': size,
    'sha256': sha256,
    'modifiedAt': modifiedAt.millisecondsSinceEpoch,
  };
}

String validateBackupRelativePath(String path) {
  ProjectPathValidator.normalizeRelativePath(path);
  if (path.length > 4096 || path.contains(':')) {
    throw const FormatException('Invalid backup relative path');
  }
  return path;
}

ScriptFile _scriptFromJson(Map<String, dynamic> json) {
  final name = _string(json, 'name');
  if (name.length > 255 || ScriptNameValidator.normalize(name) != name) {
    throw const FormatException('Invalid script name');
  }
  return ScriptFile(
    name: name,
    path: '',
    createdAt: _date(json, 'createdAt'),
    modifiedAt: _date(json, 'modifiedAt'),
    runCount: _integer(json, 'runCount'),
    isPinned: _boolean(json, 'isPinned'),
    sortOrder: _integer(json, 'sortOrder'),
    groupId: _nullableInteger(json, 'groupId', minimum: 1),
    homeSortOrder: _nullableInteger(json, 'homeSortOrder'),
  );
}

ScriptGroup _groupFromJson(Map<String, dynamic> json) {
  final name = _string(json, 'name');
  if (name.trim() != name ||
      name.isEmpty ||
      name.length > 255 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(name)) {
    throw const FormatException('Invalid group name');
  }
  final project = _boolean(json, 'isProject');
  final key = _nullableString(json, 'projectKey');
  final main = _nullableString(json, 'mainFilePath');
  if (project) {
    if (key == null || key.length > 255) {
      throw const FormatException('Missing or invalid project key');
    }
    ProjectPathValidator.normalizeProjectKey(key);
    if (main != null) {
      validateBackupRelativePath(main);
      ProjectPathValidator.validateMainFilePath(main);
    }
  } else if (key != null || main != null) {
    throw const FormatException('Ordinary group contains project metadata');
  }
  return ScriptGroup(
    id: _integer(json, 'id', minimum: 1),
    name: name,
    sortOrder: _integer(json, 'sortOrder'),
    createdAt: _date(json, 'createdAt'),
    modifiedAt: _date(json, 'modifiedAt'),
    projectKey: key,
    mainFilePath: main,
    isProject: project,
    homeSortOrder: _nullableInteger(json, 'homeSortOrder'),
  );
}

Map<String, dynamic> _scriptJson(ScriptFile s) => {
  'name': s.name,
  'createdAt': s.createdAt.millisecondsSinceEpoch,
  'modifiedAt': s.modifiedAt.millisecondsSinceEpoch,
  'runCount': s.runCount,
  'isPinned': s.isPinned,
  'sortOrder': s.sortOrder,
  'groupId': s.groupId,
  'homeSortOrder': s.homeSortOrder,
};
Map<String, dynamic> _groupJson(ScriptGroup g) => {
  'id': g.id,
  'name': g.name,
  'sortOrder': g.sortOrder,
  'createdAt': g.createdAt.millisecondsSinceEpoch,
  'modifiedAt': g.modifiedAt.millisecondsSinceEpoch,
  'isProject': g.isProject,
  'projectKey': g.projectKey,
  'mainFilePath': g.mainFilePath,
  'homeSortOrder': g.homeSortOrder,
};

List<Map<String, dynamic>> _records(
  Map<String, dynamic> json,
  String key,
  int limit,
) {
  final value = json[key];
  if (value is! List || value.length > limit) {
    throw FormatException('Invalid $key list');
  }
  return value.map((entry) {
    if (entry is! Map<String, dynamic>) {
      throw FormatException('Invalid $key record');
    }
    return entry;
  }).toList();
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('Invalid $key string');
  return value;
}

String? _nullableString(Map<String, dynamic> json, String key) =>
    json[key] == null ? null : _string(json, key);
bool _boolean(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('Invalid $key boolean');
  return value;
}

int _integer(Map<String, dynamic> json, String key, {int minimum = 0}) {
  final value = json[key];
  if (value is! int || value < minimum || value > 9007199254740991) {
    throw FormatException('Invalid $key integer');
  }
  return value;
}

int? _nullableInteger(
  Map<String, dynamic> json,
  String key, {
  int minimum = 0,
}) => json[key] == null ? null : _integer(json, key, minimum: minimum);
DateTime _date(Map<String, dynamic> json, String key) {
  final value = _integer(json, key);
  _validEpoch(value, key);
  return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
}

void _validEpoch(int value, String key) {
  if (value < 0 || value > 8640000000000000) {
    throw FormatException('Invalid $key timestamp');
  }
}
