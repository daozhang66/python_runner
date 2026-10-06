import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/backup/domain/backup_manifest.dart';
import 'package:python_runner/features/backup/domain/backup_selection.dart';
import 'package:python_runner/features/backup/domain/restore_plan.dart';
import 'package:python_runner/features/backup/domain/restore_planner.dart';
import 'package:python_runner/models/script_file.dart';
import 'package:python_runner/models/script_group.dart';

import 'backup_manifest_test.dart' show manifestFixture, fileJson;

ScriptFile localScript(
  String name, {
  int? groupId,
  int sort = 30,
  int? home = 8,
  bool pinned = false,
}) => ScriptFile(
  name: name,
  path: '/local/$name',
  createdAt: DateTime.utc(2020),
  modifiedAt: DateTime.utc(2025),
  sortOrder: sort,
  groupId: groupId,
  homeSortOrder: home,
  isPinned: pinned,
);
ScriptGroup localGroup(
  int id,
  String name, {
  bool project = false,
  String? key,
  int sort = 20,
  int? home = 7,
}) => ScriptGroup(
  id: id,
  name: name,
  sortOrder: sort,
  createdAt: DateTime.utc(2020),
  modifiedAt: DateTime.utc(2025),
  isProject: project,
  projectKey: key,
  mainFilePath: project ? 'old.py' : null,
  homeSortOrder: home,
);

void main() {
  late BackupManifest manifest;
  late RestorePlanner planner;
  setUp(() {
    manifest = BackupManifest.fromJson(manifestFixture());
    var next = 0;
    planner = RestorePlanner(projectKeyFactory: () => 'local_${++next}');
  });

  RestorePlan plan({
    List<ScriptFile> scripts = const [],
    List<ScriptGroup> groups = const [],
    RestoreConflictPolicy policy = RestoreConflictPolicy.keepBoth,
    BackupSelection? selection,
  }) => planner.plan(
    manifest: manifest,
    selection: selection ?? BackupSelection.all(manifest),
    existingScripts: scripts,
    existingGroups: groups,
    policy: policy,
  );

  test('empty restore preserves source order, pinning and project metadata while removing IDs', () {
    final result = plan();
    expect(result.groups.map((g) => g.sourceId), [81, 82, 83]);
    expect(result.groups.map((g) => g.group.id), everyElement(isNull));
    expect(result.groups.map((g) => g.group.sortOrder), [0, 1, 2]);
    expect(result.groups.map((g) => g.group.homeSortOrder), [0, 1, 3]);
    expect(result.groups.last.group.projectKey, 'local_1');
    expect(result.groups.last.group.mainFilePath, 'src/main.py');
    expect(result.scripts.first.sourceGroupId, 81);
    expect(result.scripts.first.script.groupId, isNull);
    expect(result.scripts.first.script.isPinned, isTrue);
    expect(result.scripts.first.script.sortOrder, 4);
    expect(result.fileMoves.map((m) => m.toJson()), [
      {
        'sourceRoot': 'scripts/你好.py',
        'targetRoot': 'scripts/你好.py',
        'overwrite': false,
      },
      {
        'sourceRoot': 'scripts/alone.py',
        'targetRoot': 'scripts/alone.py',
        'overwrite': false,
      },
      {
        'sourceRoot': 'projects/donor_project',
        'targetRoot': 'projects/local_1',
        'overwrite': false,
      },
    ]);
  });

  test('keepBoth allocates globally unique script names and reuses ordinary groups', () {
    final result = plan(
      scripts: [
        localScript('你好.py'),
        localScript('你好 (restored 1).py'),
        localScript('unrelated.py', groupId: 7),
      ],
      groups: [localGroup(7, '工具')],
    );
    expect(result.scripts.first.script.name, '你好 (restored 2).py');
    expect(result.scripts.first.script.sortOrder, greaterThan(30));
    expect(result.scripts.first.script.isPinned, isTrue);
    expect(result.groups.first.group.id, 7);
    expect(result.groups.first.action, RestoreAction.reuse);
    expect(result.groups.first.group.createdAt, DateTime.utc(2020));
    expect(result.fileMoves.first.targetRoot, 'scripts/你好 (restored 2).py');
  });

  for (final example in [
    (character: '汉', count: 80, kept: 79),
    (character: '😀', count: 60, kept: 59),
  ]) {
    test(
      'keepBoth fits ${example.character} names within UTF-8 filename limits',
      () {
        final name = '${example.character * example.count}.py';
        final json = manifestFixture();
        json['scripts'][1]['name'] = name;
        json['files'][1]['path'] = 'scripts/$name';
        manifest = BackupManifest.fromJson(json);
        expect(utf8.encode(name).length, 243);
        final firstCandidate =
            '${example.character * example.kept} (restored 1).py';
        final result = plan(
          scripts: [localScript(name), localScript(firstCandidate)],
          selection: BackupSelection(scriptNames: {name}),
        );
        final restoredName = result.scripts.single.script.name;
        expect(utf8.encode(restoredName).length, lessThanOrEqualTo(255));
        expect(
          restoredName,
          '${example.character * example.kept} (restored 2).py',
        );
        expect(utf8.decode(utf8.encode(restoredName)), restoredName);
        expect(result.fileMoves.single.targetRoot, 'scripts/$restoredName');
      },
    );
  }

  test('overwrite restores source membership and pinning and appends in the destination group', () {
    final existing = localScript('你好.py', groupId: 6, pinned: false);
    final result = plan(
      scripts: [existing],
      groups: [localGroup(6, 'Elsewhere')],
      policy: RestoreConflictPolicy.overwrite,
    );
    final restored = result.scripts.first;
    expect(restored.action, RestoreAction.overwrite);
    expect(restored.script.name, '你好.py');
    expect(restored.script.groupId, isNull);
    expect(restored.sourceGroupId, 81);
    expect(restored.script.sortOrder, greaterThan(30));
    expect(restored.script.isPinned, isTrue);
    expect(restored.script.runCount, 12);
    expect(restored.script.createdAt.millisecondsSinceEpoch, 1700000000000);
    expect(result.fileMoves.first.overwrite, isTrue);
  });

  test('overwrite in the same resolved group keeps local order while restoring pinning', () {
    final result = plan(
      scripts: [localScript('你好.py', groupId: 7, sort: 42)],
      groups: [localGroup(7, '工具')],
      policy: RestoreConflictPolicy.overwrite,
    );
    expect(result.scripts.first.sourceGroupId, 81);
    expect(result.scripts.first.script.sortOrder, 42);
    expect(result.scripts.first.script.isPinned, isTrue);
  });

  test('skip excludes conflicting scripts and projects from changes and file moves', () {
    final result = plan(
      scripts: [localScript('你好.py')],
      groups: [localGroup(7, 'Project', project: true, key: 'other_key')],
      policy: RestoreConflictPolicy.skip,
    );
    expect(result.scripts.map((s) => s.script.name), ['alone.py']);
    expect(result.groups.map((g) => g.sourceId), [81, 82]);
    expect(result.skippedScriptNames, ['你好.py']);
    expect(result.skippedGroupIds, [83]);
    expect(result.fileMoves.map((m) => m.sourceRoot), ['scripts/alone.py']);
  });

  test('same-name project overwrite reuses local project key and ID', () {
    final result = plan(
      groups: [localGroup(7, 'Project', project: true, key: 'existing_key')],
      policy: RestoreConflictPolicy.overwrite,
    );
    final project = result.groups.last;
    expect(project.group.id, 7);
    expect(project.group.projectKey, 'existing_key');
    expect(project.group.mainFilePath, 'src/main.py');
    expect(project.group.sortOrder, 20);
    expect(result.fileMoves.last.toJson(), {
      'sourceRoot': 'projects/donor_project',
      'targetRoot': 'projects/existing_key',
      'overwrite': true,
    });
  });

  test('project identity match wins over another project with the source display name', () {
    final result = plan(
      groups: [
        localGroup(7, 'Renamed', project: true, key: 'donor_project'),
        localGroup(8, 'Project', project: true, key: 'other'),
      ],
      policy: RestoreConflictPolicy.overwrite,
    );
    expect(result.groups.last.group.id, 7);
    expect(result.groups.last.group.name, 'Renamed');
    expect(result.groups.last.group.projectKey, 'donor_project');
  });

  test(
    'stable-key matches reserve targets before conflicting name matches',
    () {
      final json = manifestFixture();
      json['groups'][2]['name'] = 'Renamed';
      json['groups'].insert(0, {
        ...json['groups'][2] as Map<String, dynamic>,
        'id': 84,
        'name': 'Project',
        'projectKey': 'second_project',
        'mainFilePath': null,
      });
      json['files'].add(fileJson('projects/second_project', directory: true));
      manifest = BackupManifest.fromJson(json);
      final result = plan(
        groups: [localGroup(7, 'Project', project: true, key: 'donor_project')],
        policy: RestoreConflictPolicy.overwrite,
      );
      final projects = result.groups.where((g) => g.group.isProject).toList();
      expect(projects.first.group.id, isNull);
      expect(projects.first.group.name, 'Project (restored 1)');
      expect(projects.last.group.id, 7);
      expect(
        result.fileMoves.map((m) => m.targetRoot).toSet().length,
        result.fileMoves.length,
      );
    },
  );

  test(
    'native destinations accept only validated standalone and project roots',
    () {
      for (final root in [
        '/scripts/a.py',
        'scripts/../a.py',
        'scripts/a/b.py',
        r'scripts/a\b.py',
        'projects/../escape',
        'settings/config',
      ]) {
        expect(
          () => RestoreFileMove(
            sourceRoot: 'scripts/a.py',
            targetRoot: root,
            overwrite: false,
          ),
          throwsFormatException,
        );
      }
      expect(
        () => RestoreFileMove(
          sourceRoot: 'scripts/a.py',
          targetRoot: 'projects/valid',
          overwrite: false,
        ),
        throwsFormatException,
      );
    },
  );

  test('keepBoth creates a fresh project key and unique display name', () {
    final result = plan(
      groups: [
        localGroup(7, 'Project', project: true, key: 'donor_project'),
        localGroup(8, 'Project (restored 1)'),
      ],
    );
    expect(result.groups.last.group.name, 'Project (restored 2)');
    expect(result.groups.last.group.projectKey, 'local_1');
    expect(result.groups.last.group.id, isNull);
    expect(result.fileMoves.last.overwrite, isFalse);
  });

  for (final policy in RestoreConflictPolicy.values) {
    test('type collisions always rename under ${policy.name}', () {
      final result = plan(
        groups: [
          localGroup(7, 'Project'),
          localGroup(8, '工具', project: true, key: 'other'),
        ],
        policy: policy,
      );
      expect(result.groups.first.group.name, '工具 (restored 1)');
      expect(result.groups.last.group.name, 'Project (restored 1)');
      expect(
        result.groups.map((g) => g.action),
        everyElement(RestoreAction.create),
      );
    });
  }

  test(
    'partial selection retains selected empty group and omits project moves',
    () {
      final result = plan(
        selection: BackupSelection(scriptNames: {'alone.py'}, groupIds: {82}),
      );
      expect(result.groups.single.sourceId, 82);
      expect(result.scripts.single.script.name, 'alone.py');
      expect(result.fileMoves.single.sourceRoot, 'scripts/alone.py');
    },
  );

  test('new roots follow existing roots with legacy null home ranks', () {
    final result = plan(
      scripts: [localScript('old.py', home: null)],
      groups: [localGroup(7, 'Old', home: null)],
    );
    expect(result.homePlacements.map((p) => p.homeSortOrder), [0, 1]);
    final newRanks = [
      ...result.groups.map((g) => g.group.homeSortOrder!),
      result.scripts.last.script.homeSortOrder!,
    ];
    expect(newRanks, everyElement(greaterThan(1)));
    expect(
      result.groups[0].group.homeSortOrder,
      lessThan(result.groups[1].group.homeSortOrder!),
    );
    expect(
      result.groups[1].group.homeSortOrder,
      lessThan(result.scripts.last.script.homeSortOrder!),
    );
    expect(
      result.scripts.last.script.homeSortOrder,
      lessThan(result.groups[2].group.homeSortOrder!),
    );
  });

  test(
    'rejects unsafe generated project keys and cannot reuse an occupied key',
    () {
      final bad = RestorePlanner(projectKeyFactory: () => '../escape');
      expect(
        () => bad.plan(
          manifest: manifest,
          selection: BackupSelection.all(manifest),
          existingScripts: [],
          existingGroups: [],
        ),
        throwsFormatException,
      );
      final occupied = RestorePlanner(projectKeyFactory: () => 'taken');
      expect(
        () => occupied.plan(
          manifest: manifest,
          selection: BackupSelection.all(manifest),
          existingScripts: [],
          existingGroups: [localGroup(7, 'Local', project: true, key: 'taken')],
        ),
        throwsStateError,
      );
    },
  );
}
