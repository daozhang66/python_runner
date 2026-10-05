import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:python_runner/features/backup/domain/backup_manifest.dart';
import 'package:python_runner/features/backup/domain/backup_selection.dart';
import 'package:python_runner/features/backup/domain/restore_plan.dart';
import 'package:python_runner/features/backup/domain/restore_planner.dart';
import 'package:python_runner/features/scripts/application/script_home_item.dart';
import 'package:python_runner/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'backup_manifest_test.dart' show manifestFixture;
import 'restore_planner_test.dart' show localGroup, localScript;

void main() {
  late Directory dir;
  late DatabaseService service;
  late String scriptsRoot;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('backup_restore_db_');
    service = DatabaseService.test(databasePath: p.join(dir.path, 'test.db'));
    scriptsRoot = p.join(dir.path, 'scripts');
  });
  tearDown(() async {
    await service.closeForTest();
    await dir.delete(recursive: true);
  });

  Future<RestorePlan> makePlan({
    RestoreConflictPolicy policy = RestoreConflictPolicy.keepBoth,
  }) async {
    final snapshot = await service.readBackupSnapshot();
    final manifest = BackupManifest.fromJson(manifestFixture());
    return RestorePlanner(projectKeyFactory: () => 'new_local_key').plan(
      manifest: manifest,
      selection: BackupSelection.all(manifest),
      existingScripts: snapshot.scripts,
      existingGroups: snapshot.groups,
      policy: policy,
    );
  }

  test(
    'v6 migration preserves full metadata and adds an empty recovery ledger',
    () async {
      final seed = await openDatabase(
        p.join(dir.path, 'test.db'),
        singleInstance: false,
      );
      await DatabaseService.createSchemaForTest(seed, 6);
      final group = localGroup(81, 'Existing');
      final script = localScript('old.py', groupId: 81, pinned: true);
      await seed.insert('script_groups', group.toMap());
      await seed.insert('scripts', script.toMap());
      await seed.close();
      final snapshot = await service.readBackupSnapshot();
      expect(snapshot.groups.single.toMap(), group.toMap());
      expect(snapshot.scripts.single.toMap(), script.toMap());
      expect(await service.committedRestoreIds(), isEmpty);
      expect(await (await service.database).getVersion(), 7);
      final metadata = snapshot.toMetadataJson(
        createdAt: DateTime.fromMillisecondsSinceEpoch(42, isUtc: true),
      );
      expect(metadata['createdAt'], 42);
      expect(metadata['scripts'][0].containsKey('path'), isFalse);
      expect(metadata.containsKey('files'), isFalse);
    },
  );

  test('restore remaps source IDs, builds local paths, preserves unrelated records and commits once', () async {
    await service.createGroup(localGroup(81, 'Local group'));
    await service.createGroup(localGroup(7, '工具'));
    final untouched = localScript('untouched.py', groupId: 7);
    await service.upsertScript(untouched);
    final result = await makePlan();
    await service.applyRestorePlan(result, 'operation_1', scriptsRoot);
    final groups = await service.getAllGroups();
    expect(groups, hasLength(4));
    expect(groups.singleWhere((g) => g.name == '工具').id, 7);
    expect(groups.singleWhere((g) => g.name == 'Local group').id, 81);
    expect(groups.singleWhere((g) => g.name == 'Empty').id, 82);
    final restored = (await service.getScript('你好.py'))!;
    expect(restored.groupId, 7);
    expect(restored.path, p.join(scriptsRoot, '你好.py'));
    expect(restored.runCount, 12);
    expect(restored.isPinned, isTrue);
    expect(
      (await service.getScript('untouched.py'))!.toMap(),
      untouched.toMap(),
    );
    expect(await service.committedRestoreIds(), {'operation_1'});
    await service.applyRestorePlan(result, 'operation_1', scriptsRoot);
    expect(await service.getAllGroups(), hasLength(4));
    expect(await service.getAllScripts(), hasLength(3));
    await service.closeForTest();
    expect(await service.committedRestoreIds(), {'operation_1'});
    await service.forgetRestoreCommit('operation_1');
    await service.forgetRestoreCommit('operation_1');
    expect(await service.committedRestoreIds(), isEmpty);
  });

  test(
    'new ordinary group receives generated local ID, never donor ID',
    () async {
      final result = await makePlan();
      await service.applyRestorePlan(result, 'new_groups', scriptsRoot);
      final snapshot = await service.readBackupSnapshot();
      expect(snapshot.groups.map((g) => g.id), [1, 2, 3]);
      expect(snapshot.scripts.singleWhere((s) => s.name == '你好.py').groupId, 1);
      expect(snapshot.groups.last.projectKey, 'new_local_key');
    },
  );

  test('overwrite updates existing project in place without deleting other groups or members', () async {
    await service.createGroup(
      localGroup(7, 'Project', project: true, key: 'local_key'),
    );
    await service.createGroup(localGroup(8, '工具'));
    final untouched = localScript('unrelated.py', groupId: 8);
    final target = localScript('你好.py', groupId: 8, sort: 99);
    await service.upsertScript(untouched);
    await service.upsertScript(target);
    final result = await makePlan(policy: RestoreConflictPolicy.overwrite);
    await service.applyRestorePlan(result, 'overwrite', scriptsRoot);
    final project = (await service.getAllGroups()).singleWhere(
      (g) => g.isProject,
    );
    expect(project.id, 7);
    expect(project.projectKey, 'local_key');
    expect(project.mainFilePath, 'src/main.py');
    expect(
      (await service.getScript('unrelated.py'))!.toMap(),
      untouched.toMap(),
    );
    expect((await service.getScript('你好.py'))!.sortOrder, 99);
    expect((await service.getScript('你好.py'))!.groupId, 8);
  });

  test('overwrite remaps a different source group and restores the source pin flag', () async {
    await service.createGroup(localGroup(7, 'Elsewhere'));
    await service.upsertScript(localScript('你好.py', groupId: 7, pinned: false));
    final untouched = localScript('unrelated.py', groupId: 7);
    await service.upsertScript(untouched);
    await service.applyRestorePlan(
      await makePlan(policy: RestoreConflictPolicy.overwrite),
      'regroup',
      scriptsRoot,
    );
    final destination = (await service.getAllGroups()).singleWhere(
      (g) => g.name == '工具',
    );
    final restored = (await service.getScript('你好.py'))!;
    expect(destination.id, isNot(81));
    expect(restored.groupId, destination.id);
    expect(restored.groupId, isNot(7));
    expect(restored.isPinned, isTrue);
    expect(restored.sortOrder, greaterThan(untouched.sortOrder));
    expect(
      (await service.getScript('unrelated.py'))!.toMap(),
      untouched.toMap(),
    );
  });

  for (final overwriteProject in [true, false]) {
    test(
      'overwrite-only preserves null-rank home order: project=$overwriteProject',
      () async {
        final project = localGroup(
          7,
          'Project',
          project: true,
          key: 'donor_project',
          home: null,
        ).copyWith(modifiedAt: DateTime.utc(overwriteProject ? 2025 : 2024));
        final script = localScript(
          'alone.py',
          home: null,
        ).copyWith(modifiedAt: DateTime.utc(overwriteProject ? 2024 : 2025));
        await service.createGroup(project);
        await service.upsertScript(script);
        final expectedOrder = overwriteProject
            ? ['group:7', 'alone.py']
            : ['alone.py', 'group:7'];
        expect(
          ScriptHomeItem.ordered([script], [project]).map((item) => item.key),
          expectedOrder,
        );
        final json = manifestFixture();
        json[overwriteProject ? 'groups' : 'scripts'][overwriteProject
            ? 2
            : 1]['modifiedAt'] = DateTime.utc(2020)
            .millisecondsSinceEpoch;
        final manifest = BackupManifest.fromJson(json);
        final plan = RestorePlanner().plan(
          manifest: manifest,
          selection: overwriteProject
              ? BackupSelection(groupIds: {83})
              : BackupSelection(scriptNames: {'alone.py'}),
          existingScripts: [script],
          existingGroups: [project],
          policy: RestoreConflictPolicy.overwrite,
        );
        await service.applyRestorePlan(plan, 'overwrite_only', scriptsRoot);
        final after = await service.readBackupSnapshot();
        expect(
          ScriptHomeItem.ordered(
            after.scripts,
            after.groups,
          ).map((item) => item.key),
          expectedOrder,
        );
        expect(
          (overwriteProject
                  ? after.groups.single.modifiedAt
                  : after.scripts.single.modifiedAt)
              .toUtc(),
          DateTime.utc(2020),
        );
      },
    );
  }

  for (final failureTable in ['scripts', 'backup_restore_commits']) {
    test(
      'failure in $failureTable rolls back metadata, ordering and marker',
      () async {
        final group = localGroup(7, 'Local', home: null);
        final script = localScript('old.py', home: null);
        await service.createGroup(group);
        await service.upsertScript(script);
        final result = await makePlan();
        final db = await service.database;
        await db.execute(
          '''CREATE TRIGGER fail_restore BEFORE INSERT ON $failureTable
        BEGIN SELECT RAISE(ABORT, 'injected restore failure'); END''',
        );
        await expectLater(
          service.applyRestorePlan(result, 'must_rollback', scriptsRoot),
          throwsA(isA<DatabaseException>()),
        );
        final snapshot = await service.readBackupSnapshot();
        expect(snapshot.groups.single.toMap(), group.toMap());
        expect(snapshot.scripts.single.toMap(), script.toMap());
        expect(await service.committedRestoreIds(), isEmpty);
        await db.execute('DROP TRIGGER fail_restore');
        await service.applyRestorePlan(result, 'must_rollback', scriptsRoot);
        expect(await service.committedRestoreIds(), {'must_rollback'});
      },
    );
  }

  test('missing overwrite target aborts the transaction and does not mark committed', () async {
    await service.upsertScript(localScript('你好.py'));
    final result = await makePlan(policy: RestoreConflictPolicy.overwrite);
    await (await service.database).delete(
      'scripts',
      where: 'name = ?',
      whereArgs: ['你好.py'],
    );
    await expectLater(
      service.applyRestorePlan(result, 'stale', scriptsRoot),
      throwsStateError,
    );
    expect(await service.getAllGroups(), isEmpty);
    expect(await service.committedRestoreIds(), isEmpty);
  });
}
