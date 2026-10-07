import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/scripts/application/script_workspace_controller.dart';
import 'package:python_runner/models/script_file.dart';
import 'package:python_runner/models/script_group.dart';

import 'support/script_test_helper.dart';

void main() {
  test('mixed order persists without changing metadata or nested scripts',
      () async {
    final repo = _repository();
    final container = buildScriptContainer(repository: repo);
    addTearDown(container.dispose);
    final controller =
        container.read(scriptWorkspaceControllerProvider.notifier);
    await controller.load();
    final before = controller.scripts.map((s) => s.toMap()).toList();
    await controller.swapHomeItems('group:2', 'first.py');
    const expected = ['pin.py', 'group:1', 'group:2', 'first.py', 'second.py'];
    expect(controller.homeItems.map((item) => item.key), expected);
    for (final script in controller.scripts) {
      final original = before.singleWhere((s) => s['name'] == script.name);
      expect(script.modifiedAt.millisecondsSinceEpoch, original['modifiedAt']);
      expect(script.runCount, original['runCount']);
      if (script.isPinned || script.groupId != null) {
        expect(script.toMap(), original);
      }
    }
    final reopened = buildScriptContainer(repository: repo);
    addTearDown(reopened.dispose);
    final reloaded = reopened.read(scriptWorkspaceControllerProvider.notifier);
    await reloaded.load();
    expect(reloaded.homeItems.map((item) => item.key), expected);
  });

  test('invalid, pinned and nested entries never trigger a write', () async {
    final repo = _repository();
    final container = buildScriptContainer(repository: repo);
    addTearDown(container.dispose);
    final controller =
        container.read(scriptWorkspaceControllerProvider.notifier);
    await controller.load();
    final generation =
        container.read(scriptWorkspaceControllerProvider).generation;
    for (final key in [
      'pin.py',
      'nested.py',
      'missing.py',
      'group:99',
      'group:2'
    ]) {
      await controller.swapHomeItems('group:2', key);
    }
    expect(repo.homeWrites, 0);
    expect(container.read(scriptWorkspaceControllerProvider).generation,
        generation);
  });

  test('failed persistence retains the committed order and supports retry',
      () async {
    final repo = _repository()..failHomeWrite = true;
    final container = buildScriptContainer(repository: repo);
    addTearDown(container.dispose);
    final controller =
        container.read(scriptWorkspaceControllerProvider.notifier);
    await controller.load();
    final before = controller.homeItems.map((item) => item.key).toList();
    final generation =
        container.read(scriptWorkspaceControllerProvider).generation;
    await controller.swapHomeItems('group:1', 'second.py');
    expect(controller.homeItems.map((item) => item.key), before);
    expect(container.read(scriptWorkspaceControllerProvider).generation,
        generation);
    await controller.load();
    expect(controller.homeItems.map((item) => item.key), before);
    repo.failHomeWrite = false;
    await controller.swapHomeItems('group:1', 'second.py');
    expect(controller.homeItems.map((item) => item.key),
        ['pin.py', 'second.py', 'first.py', 'group:2', 'group:1']);
  });

  test('queued swaps read the most recently committed order', () async {
    final repo = _repository();
    final container = buildScriptContainer(repository: repo);
    addTearDown(container.dispose);
    final controller =
        container.read(scriptWorkspaceControllerProvider.notifier);
    await controller.load();
    final original = controller.homeItems.map((item) => item.key).toList();
    await Future.wait([
      controller.swapHomeItems('group:1', 'second.py'),
      controller.swapHomeItems('group:1', 'second.py'),
    ]);
    expect(controller.homeItems.map((item) => item.key), original);
    await controller.load();
    expect(controller.homeItems.map((item) => item.key), original);
  });

  test('rename, delete and create keep remaining mixed entries in order',
      () async {
    final repo = _repository();
    final container = buildScriptContainer(repository: repo);
    addTearDown(container.dispose);
    final controller =
        container.read(scriptWorkspaceControllerProvider.notifier);
    await controller.load();
    await controller.swapHomeItems('group:2', 'first.py');
    await controller.renameScript('first.py', 'renamed.py');
    await controller.renameGroup(2, 'Renamed project');
    expect(controller.homeItems.map((item) => item.key),
        ['pin.py', 'group:1', 'group:2', 'renamed.py', 'second.py']);
    await controller.deleteScript('renamed.py');
    await controller.createScript('new.py');
    await controller.load();
    expect(controller.homeItems.map((item) => item.key),
        ['pin.py', 'new.py', 'group:1', 'group:2', 'second.py']);
  });

  test('running scripts keeps manual group positions and promotes script slots',
      () async {
    final repo = _repository();
    final container = buildScriptContainer(repository: repo);
    addTearDown(container.dispose);
    final controller =
        container.read(scriptWorkspaceControllerProvider.notifier);
    await controller.load();
    await controller.swapHomeItems('group:1', 'second.py');
    await controller.incrementRunCount('first.py');
    expect(controller.homeItems.map((item) => item.key),
        ['pin.py', 'first.py', 'second.py', 'group:2', 'group:1']);
    await controller.load();
    expect(controller.homeItems.map((item) => item.key),
        ['pin.py', 'first.py', 'second.py', 'group:2', 'group:1']);
  });

  test('moving scripts into and out of folders clears their old home rank',
      () async {
    final repo = _repository();
    final container = buildScriptContainer(repository: repo);
    addTearDown(container.dispose);
    final controller =
        container.read(scriptWorkspaceControllerProvider.notifier);
    await controller.load();
    await controller.swapHomeItems('group:1', 'first.py');
    await controller.moveScriptsToGroup(['first.py'], 1);
    await controller.moveScriptsToGroup(['first.py'], null);
    await controller.load();
    expect(controller.homeItems.last.key, 'first.py');
    expect(
        controller.ungroupedScripts
            .singleWhere((s) => s.name == 'first.py')
            .homeSortOrder,
        isNull);
  });
}

_HomeRepository _repository() {
  final created = DateTime(2025, 1, 1);
  return _HomeRepository(
    scripts: [
      for (final (index, name)
          in ['pin.py', 'first.py', 'second.py', 'nested.py'].indexed)
        ScriptFile(
            name: name,
            path: name,
            createdAt: created,
            modifiedAt: DateTime(2025, 1, 4 - index),
            sortOrder: index,
            runCount: index,
            isPinned: index == 0,
            groupId: index == 3 ? 1 : null),
    ],
    groups: [
      ScriptGroup(
          id: 1,
          name: 'Folder',
          sortOrder: 0,
          createdAt: created,
          modifiedAt: created),
      ScriptGroup(
          id: 2,
          name: 'Project',
          sortOrder: 1,
          createdAt: created,
          modifiedAt: DateTime(2025, 1, 2, 12),
          isProject: true,
          projectKey: 'project_2'),
    ],
  );
}

class _HomeRepository extends FakeScriptRepository {
  _HomeRepository({super.scripts, super.groups}) : super(nextGroupId: 3);
  bool failHomeWrite = false;
  int homeWrites = 0;

  @override
  Future<void> batchUpdateHomeSortOrders(
      List<ScriptFile> scripts, List<ScriptGroup> groups) async {
    if (failHomeWrite) throw StateError('home sort write failed');
    homeWrites++;
    await super.batchUpdateHomeSortOrders(scripts, groups);
  }
}
