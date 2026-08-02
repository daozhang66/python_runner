import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/models/script_file.dart';
import 'package:python_runner/models/script_group.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/script_test_helper.dart';

/// FakeScriptRepository 契约测试：验证内存实现符合 [ScriptRepository] 契约，
/// 保证 Level 2 脚本工作台 Controller 单测可信赖本 fake。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  ScriptFile script(String name, {int? groupId, bool pinned = false}) =>
      ScriptFile(
        name: name,
        path: '/scripts/$name.py',
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 1),
        sortOrder: 0,
        groupId: groupId,
        isPinned: pinned,
      );

  group('FakeScriptRepository scripts', () {
    test('getAllScripts returns persisted scripts', () async {
      final repo = FakeScriptRepository(scripts: [script('a'), script('b')]);
      final result = await repo.getAllScripts();
      expect(result.map((s) => s.name), ['a', 'b']);
      expect(repo.getAllScriptsCount, 1);
    });

    test('upsertScript replaces by name and tracks last upsert', () async {
      final repo = FakeScriptRepository(scripts: [script('a')]);
      await repo.upsertScript(script('a', pinned: true));
      expect(repo.upsertScriptCount, 1);
      expect(repo.lastUpsertedScript?.name, 'a');
      expect((await repo.getAllScripts()).single.isPinned, isTrue);
    });

    test('incrementRunCount bumps run count in memory', () async {
      final repo = FakeScriptRepository(scripts: [script('a')]);
      await repo.incrementRunCount('a');
      await repo.incrementRunCount('a');
      expect(repo.incrementRunCountCount, 2);
      expect((await repo.getScript('a'))?.runCount, 2);
    });

    test('batchUpdateSortOrders writes sortOrder and records request', () async {
      final repo = FakeScriptRepository(
        scripts: [script('a'), script('b'), script('c')],
      );
      await repo.batchUpdateSortOrders([
        script('c'),
        script('a'),
        script('b'),
      ]);
      expect(repo.batchUpdateSortOrdersCount, 1);
      expect(repo.lastBatchSortOrders?.map((s) => s.name), ['c', 'a', 'b']);
      final scripts = await repo.getAllScripts();
      expect(scripts.firstWhere((s) => s.name == 'c').sortOrder, 0);
      expect(scripts.firstWhere((s) => s.name == 'b').sortOrder, 2);
    });

    test('deleteScript removes from db side', () async {
      final repo = FakeScriptRepository(scripts: [script('a'), script('b')]);
      await repo.deleteScript('a');
      expect(repo.deleteScriptDbCount, 1);
      expect((await repo.getAllScripts()).map((s) => s.name), ['b']);
    });
  });

  group('FakeScriptRepository groups', () {
    test('createGroup assigns incremental id and records request', () async {
      final repo = FakeScriptRepository(nextGroupId: 5);
      final id = await repo.createGroup(
        ScriptGroup(
          name: 'g1',
          sortOrder: 0,
          createdAt: DateTime(2026, 1, 1),
          modifiedAt: DateTime(2026, 1, 1),
        ),
      );
      expect(id, 5);
      expect(repo.createGroupCount, 1);
      expect(repo.lastCreatedGroup?.id, 5);
      expect((await repo.getAllGroups()).single.name, 'g1');
    });

    test('deleteGroup clears groupId on member scripts', () async {
      final repo = FakeScriptRepository(
        scripts: [script('a', groupId: 1), script('b', groupId: 1)],
        groups: [
          ScriptGroup(
            id: 1,
            name: 'g1',
            sortOrder: 0,
            createdAt: DateTime(2026, 1, 1),
            modifiedAt: DateTime(2026, 1, 1),
          ),
        ],
      );
      await repo.deleteGroup(1);
      expect(repo.deleteGroupCount, 1);
      expect((await repo.getAllGroups()), isEmpty);
      expect((await repo.getScript('a'))?.groupId, isNull);
      expect((await repo.getScript('b'))?.groupId, isNull);
    });

    test('moveScriptsToGroup updates membership and records request', () async {
      final repo = FakeScriptRepository(scripts: [script('a'), script('b')]);
      await repo.moveScriptsToGroup([
        script('a', groupId: 2),
        script('b', groupId: 2),
      ]);
      expect(repo.moveScriptsToGroupCount, 1);
      expect(repo.lastMovedScripts?.length, 2);
      expect((await repo.getScript('a'))?.groupId, 2);
    });
  });

  group('FakeScriptRepository files (NativeBridge side)', () {
    test('createScriptFile then readScriptFile round-trips content', () async {
      final repo = FakeScriptRepository();
      await repo.createScriptFile('demo', content: 'print(1)');
      expect(repo.createScriptFileCount, 1);
      expect(await repo.readScriptFile('demo'), 'print(1)');
      expect(repo.lastReadScriptName, 'demo');
    });

    test('saveScriptFile overwrites content', () async {
      final repo = FakeScriptRepository();
      await repo.createScriptFile('demo', content: 'old');
      await repo.saveScriptFile('demo', 'new');
      expect(repo.saveScriptFileCount, 1);
      expect(repo.lastSavedContent, 'new');
      expect(await repo.readScriptFile('demo'), 'new');
    });

    test('listScriptFiles reflects creates and deletes', () async {
      final repo = FakeScriptRepository();
      await repo.createScriptFile('a');
      await repo.createScriptFile('b');
      expect(await repo.listScriptFiles(), containsAll(['a', 'b']));
      await repo.deleteScriptFile('a');
      expect(await repo.listScriptFiles(), ['b']);
      expect(repo.deleteScriptFileCount, 1);
    });

    test('deleteScriptProject records call', () async {
      final repo = FakeScriptRepository();
      expect(await repo.deleteScriptProject('proj'), isTrue);
      expect(repo.deleteScriptProjectCount, 1);
    });
  });
}
