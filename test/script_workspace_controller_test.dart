import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/scripts/application/script_workspace_controller.dart';
import 'package:python_runner/models/script_file.dart';
import 'package:python_runner/models/script_group.dart';

import 'support/script_test_helper.dart';

/// 脚本工作台 Controller 单测：验证排序/置顶/拖拽/分组业务逻辑 1:1 保留。
/// 使用 [FakeScriptRepository] 经 `scriptRepositoryProvider` override 注入。
void main() {
  ProviderContainer makeContainer(FakeScriptRepository repository) {
    final container = buildScriptContainer(repository: repository);
    addTearDown(container.dispose);
    container.read(scriptWorkspaceControllerProvider);
    return container;
  }

  ScriptFile script(
    String name,
    DateTime time, {
    required int sortOrder,
    int? groupId,
    bool isPinned = false,
    int runCount = 0,
  }) =>
      ScriptFile(
        name: name,
        path: name,
        createdAt: time,
        modifiedAt: time,
        sortOrder: sortOrder,
        groupId: groupId,
        isPinned: isPinned,
        runCount: runCount,
      );

  ScriptGroup makeGroup(
    int id,
    String name,
    DateTime time, {
    bool isProject = false,
    String? projectKey,
    String? mainFilePath,
  }) =>
      ScriptGroup(
        id: id,
        name: name,
        sortOrder: id,
        createdAt: time,
        modifiedAt: time,
        isProject: isProject,
        projectKey: projectKey,
        mainFilePath: mainFilePath,
      );

  group('load', () {
    test('reconciles file system with DB, backfilling new scripts', () async {
      final now = DateTime(2026, 1, 1);
      final repo = FakeScriptRepository(
        scripts: [script('existing.py', now, sortOrder: 0)],
      );
      // 文件系统返回 existing.py + new.py；existing 在 DB，new 不在。
      // createScriptFile 把文件写入 _files，listScriptFiles 读 _files。
      await repo.createScriptFile('existing.py');
      await repo.createScriptFile('new.py', content: '');
      final container = makeContainer(repo);

      await container.read(scriptWorkspaceControllerProvider.notifier).load();

      final notifier =
          container.read(scriptWorkspaceControllerProvider.notifier);
      expect(notifier.scripts.map((s) => s.name),
          containsAll(['existing.py', 'new.py']));
      // 新脚本应被 upsert 到 DB。
      expect(repo.upsertScriptCount, greaterThanOrEqualTo(1));
      expect(repo.lastUpsertedScript?.name, 'new.py');
    });

    test('swallows load errors and exposes loadError', () async {
      final repo = _ThrowingListRepository();
      final container = makeContainer(repo);

      await container.read(scriptWorkspaceControllerProvider.notifier).load();

      final state = container.read(scriptWorkspaceControllerProvider);
      expect(state.isLoading, isFalse);
      expect(state.loadError, isNotNull);
      expect(state.scripts, isEmpty);
    });

    test('keeps the last committed snapshot when a refresh fails', () async {
      final now = DateTime(2026, 1, 1);
      final repo = _FailingLoadRepository(
        scripts: [script('stable.py', now, sortOrder: 0)],
      );
      final container = makeContainer(repo);
      final controller =
          container.read(scriptWorkspaceControllerProvider.notifier);
      await controller.load();
      final generation =
          container.read(scriptWorkspaceControllerProvider).generation;

      repo.failGetAllScripts = true;
      await controller.load();

      final state = container.read(scriptWorkspaceControllerProvider);
      expect(state.scripts.map((item) => item.name), ['stable.py']);
      expect(state.generation, generation);
      expect(state.isLoading, isFalse);
      expect(state.loadError, isNotNull);
    });

    test('serializes a delayed load before a following move command', () async {
      final now = DateTime(2026, 1, 1);
      final repo = _DelayedGroupsRepository(
        groups: [makeGroup(1, 'Work', now)],
        scripts: [script('a.py', now, sortOrder: 0)],
      );
      final container = makeContainer(repo);
      final controller =
          container.read(scriptWorkspaceControllerProvider.notifier);

      final load = controller.load();
      await repo.firstGroupsRequest;
      var moveCompleted = false;
      final move = controller.moveScriptsToGroup(['a.py'], 1).then((_) {
        moveCompleted = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(moveCompleted, isFalse);

      repo.releaseFirstGroupsRequest();
      await Future.wait([load, move]);

      final state = container.read(scriptWorkspaceControllerProvider);
      expect(state.scriptByName('a.py')!.groupId, 1);
      expect(state.generation, 2);
    });

    test('keeps the later refresh when two loads complete out of order',
        () async {
      final now = DateTime(2026, 1, 1);
      final repo = _SequencedGroupsRepository(
        firstGroups: [makeGroup(1, 'Older', now)],
        laterGroups: [makeGroup(1, 'Newer', now)],
        scripts: [script('a.py', now, sortOrder: 0)],
      );
      final container = makeContainer(repo);
      final controller =
          container.read(scriptWorkspaceControllerProvider.notifier);

      final first = controller.load();
      await repo.firstGroupsRequest;
      final second = controller.load();
      repo.releaseFirstGroupsRequest();
      await Future.wait([first, second]);

      final state = container.read(scriptWorkspaceControllerProvider);
      expect(state.groups.single.name, 'Newer');
      expect(state.generation, 2);
    });
  });

  group('incrementRunCount', () {
    test('promotes non-pinned script to front of its group', () async {
      final now = DateTime(2026, 1, 1);
      final g = makeGroup(1, 'Work', now);
      final repo = FakeScriptRepository(groups: [
        g
      ], scripts: [
        script('a.py', now, sortOrder: 0, groupId: 1),
        script('b.py', now, sortOrder: 1, groupId: 1),
        script('c.py', now, sortOrder: 2, groupId: 1),
        script('home.py', now, sortOrder: 0),
      ]);
      final container = makeContainer(repo);
      await container.read(scriptWorkspaceControllerProvider.notifier).load();

      await container
          .read(scriptWorkspaceControllerProvider.notifier)
          .incrementRunCount('c.py');

      final notifier =
          container.read(scriptWorkspaceControllerProvider.notifier);
      expect(
        notifier.scriptsInGroup(1).map((s) => s.name),
        ['c.py', 'a.py', 'b.py'],
      );
      expect(notifier.scriptsInGroup(1).first.runCount, 1);
      expect(notifier.ungroupedScripts.map((s) => s.name), ['home.py']);
      // 排序应持久化。
      expect(
        repo.lastBatchSortOrders?.map((s) => s.name),
        ['c.py', 'a.py', 'b.py'],
      );
    });

    test('keeps pinned scripts fixed when a pinned script runs', () async {
      final now = DateTime(2026, 1, 1);
      final repo = FakeScriptRepository(scripts: [
        script('pinned-a.py', now, sortOrder: 0, isPinned: true),
        script('pinned-b.py', now, sortOrder: 1, isPinned: true),
        script('regular.py', now, sortOrder: 2),
      ]);
      final container = makeContainer(repo);
      await container.read(scriptWorkspaceControllerProvider.notifier).load();

      await container
          .read(scriptWorkspaceControllerProvider.notifier)
          .incrementRunCount('pinned-b.py');

      final notifier =
          container.read(scriptWorkspaceControllerProvider.notifier);
      expect(
        notifier.ungroupedScripts.map((s) => s.name),
        ['pinned-a.py', 'pinned-b.py', 'regular.py'],
      );
      expect(notifier.ungroupedScripts[1].runCount, 1);
      // 置顶不变 → 不触发 batchUpdateSortOrders。
      expect(repo.batchUpdateSortOrdersCount, 0);
    });
  });

  group('togglePinned', () {
    test('moves script between pinned and regular regions', () async {
      final now = DateTime(2026, 1, 1);
      final repo = FakeScriptRepository(scripts: [
        script('a.py', now, sortOrder: 0),
        script('b.py', now, sortOrder: 1),
      ]);
      final container = makeContainer(repo);
      await container.read(scriptWorkspaceControllerProvider.notifier).load();

      await container
          .read(scriptWorkspaceControllerProvider.notifier)
          .togglePinned('b.py');

      final notifier =
          container.read(scriptWorkspaceControllerProvider.notifier);
      // 置顶后 b.py 在最前。
      expect(notifier.scripts.first.name, 'b.py');
      expect(notifier.scripts.first.isPinned, isTrue);
      expect(repo.upsertScriptCount, greaterThanOrEqualTo(1));
    });
  });

  group('createScript', () {
    test('appends new script at end of group sort order', () async {
      final now = DateTime(2026, 1, 1);
      final repo = FakeScriptRepository(scripts: [
        script('a.py', now, sortOrder: 0, groupId: 1),
        script('b.py', now, sortOrder: 1, groupId: 1),
      ]);
      final container = makeContainer(repo);
      await container.read(scriptWorkspaceControllerProvider.notifier).load();

      final ok = await container
          .read(scriptWorkspaceControllerProvider.notifier)
          .createScript('c.py', groupId: 1);

      expect(ok, isTrue);
      final notifier =
          container.read(scriptWorkspaceControllerProvider.notifier);
      // 新脚本 sortOrder 应是组内 maxOrder+1 = 2。
      final created = notifier.scripts.firstWhere((s) => s.name == 'c.py');
      expect(created.sortOrder, 2);
      expect(created.groupId, 1);
    });
  });

  group('deleteGroup', () {
    test('clears groupId on member scripts', () async {
      final now = DateTime(2026, 1, 1);
      final g = makeGroup(1, 'Work', now);
      final repo = FakeScriptRepository(groups: [
        g
      ], scripts: [
        script('a.py', now, sortOrder: 0, groupId: 1),
        script('b.py', now, sortOrder: 0),
      ]);
      final container = makeContainer(repo);
      await container.read(scriptWorkspaceControllerProvider.notifier).load();

      await container
          .read(scriptWorkspaceControllerProvider.notifier)
          .deleteGroup(1);

      final notifier =
          container.read(scriptWorkspaceControllerProvider.notifier);
      expect(notifier.groups, isEmpty);
      expect(
        notifier.scripts.firstWhere((s) => s.name == 'a.py').groupId,
        isNull,
      );
    });
  });

  group('createProjectGroup', () {
    test('rejects empty name and duplicate name', () async {
      final now = DateTime(2026, 1, 1);
      final repo = FakeScriptRepository(groups: [makeGroup(1, 'Exists', now)]);
      final container = makeContainer(repo);

      final notifier =
          container.read(scriptWorkspaceControllerProvider.notifier);
      // 先加载，让内存 _groups 含 'Exists'，才能命中重名校验。
      await notifier.load();
      expect(await notifier.createProjectGroup(''), isNull);
      expect(await notifier.createProjectGroup('Exists'), isNull);
    });

    test('creates project group with normalized projectKey', () async {
      final repo = FakeScriptRepository();
      final container = makeContainer(repo);

      final created = await container
          .read(scriptWorkspaceControllerProvider.notifier)
          .createProjectGroup('MyProj', mainFilePath: 'main.py');

      expect(created, isNotNull);
      expect(created!.isProject, isTrue);
      expect(created.name, 'MyProj');
      expect(created.mainFilePath, 'main.py');
      expect(created.projectKey, isNotNull);
      expect(repo.createGroupCount, 1);
    });
  });

  group('swapScriptPositionsByName (drag)', () {
    test('swaps two non-pinned scripts in a group and persists', () async {
      final now = DateTime(2026, 1, 1);
      final g = makeGroup(1, 'Work', now);
      final repo = FakeScriptRepository(groups: [
        g
      ], scripts: [
        script('a.py', now, sortOrder: 0, groupId: 1),
        script('b.py', now, sortOrder: 1, groupId: 1),
        script('c.py', now, sortOrder: 2, groupId: 1),
      ]);
      final container = makeContainer(repo);
      await container.read(scriptWorkspaceControllerProvider.notifier).load();

      await container
          .read(scriptWorkspaceControllerProvider.notifier)
          .swapScriptPositionsByName('a.py', 'c.py', groupId: 1);

      final notifier =
          container.read(scriptWorkspaceControllerProvider.notifier);
      // a 与 c 互换后顺序：c, b, a（重新分配 sortOrder）。
      expect(
        notifier.scriptsInGroup(1).map((s) => s.name),
        ['c.py', 'b.py', 'a.py'],
      );
      expect(repo.batchUpdateSortOrdersCount, greaterThanOrEqualTo(1));
    });

    test('does not swap when a pinned script is involved', () async {
      final now = DateTime(2026, 1, 1);
      final g = makeGroup(1, 'Work', now);
      final repo = FakeScriptRepository(groups: [
        g
      ], scripts: [
        script('pin.py', now, sortOrder: 0, groupId: 1, isPinned: true),
        script('reg.py', now, sortOrder: 1, groupId: 1),
      ]);
      final container = makeContainer(repo);
      await container.read(scriptWorkspaceControllerProvider.notifier).load();
      repo.batchUpdateSortOrdersCount = 0;

      await container
          .read(scriptWorkspaceControllerProvider.notifier)
          .swapScriptPositionsByName('pin.py', 'reg.py', groupId: 1);

      expect(repo.batchUpdateSortOrdersCount, 0, reason: '涉及置顶脚本的交换应被拒绝');
    });
  });

  group('sort persistence failures', () {
    test('does not publish a reorder candidate when batch persistence fails',
        () async {
      final now = DateTime(2026, 1, 1);
      final repo = _FailingSortRepository(scripts: [
        script('a.py', now, sortOrder: 0),
        script('b.py', now, sortOrder: 1),
      ]);
      final container = makeContainer(repo);
      final controller =
          container.read(scriptWorkspaceControllerProvider.notifier);
      await controller.load();
      final before = container.read(scriptWorkspaceControllerProvider);

      repo.failBatchUpdate = true;
      await controller.reorderScript(0, 1);

      final after = container.read(scriptWorkspaceControllerProvider);
      expect(after.scripts.map((item) => item.name), ['a.py', 'b.py']);
      expect(after.generation, before.generation);
    });

    test('does not publish a move candidate when persistence fails', () async {
      final now = DateTime(2026, 1, 1);
      final repo = _FailingMoveRepository(
        groups: [makeGroup(1, 'Work', now)],
        scripts: [script('a.py', now, sortOrder: 0)],
      );
      final container = makeContainer(repo);
      final controller =
          container.read(scriptWorkspaceControllerProvider.notifier);
      await controller.load();
      final before = container.read(scriptWorkspaceControllerProvider);

      await controller.moveScriptsToGroup(['a.py'], 1);

      final after = container.read(scriptWorkspaceControllerProvider);
      expect(after.scriptByName('a.py')!.groupId, isNull);
      expect(after.generation, before.generation);
    });

    test('increments generation only after a successful reorder', () async {
      final now = DateTime(2026, 1, 1);
      final repo = FakeScriptRepository(scripts: [
        script('a.py', now, sortOrder: 0),
        script('b.py', now, sortOrder: 1),
      ]);
      final container = makeContainer(repo);
      final controller =
          container.read(scriptWorkspaceControllerProvider.notifier);
      await controller.load();
      final generation =
          container.read(scriptWorkspaceControllerProvider).generation;

      await controller.reorderScript(0, 1);

      final state = container.read(scriptWorkspaceControllerProvider);
      expect(state.scripts.map((item) => item.name), ['b.py', 'a.py']);
      expect(state.generation, generation + 1);
    });

    test('keeps a persisted run count when its promotion sort fails', () async {
      final now = DateTime(2026, 1, 1);
      final repo = _FailingSortRepository(scripts: [
        script('a.py', now, sortOrder: 0),
        script('b.py', now, sortOrder: 1),
      ]);
      final container = makeContainer(repo);
      final controller =
          container.read(scriptWorkspaceControllerProvider.notifier);
      await controller.load();
      final generation =
          container.read(scriptWorkspaceControllerProvider).generation;

      repo.failBatchUpdate = true;
      await controller.incrementRunCount('b.py');

      final state = container.read(scriptWorkspaceControllerProvider);
      expect(controller.ungroupedScripts.map((item) => item.name),
          ['a.py', 'b.py']);
      expect(state.scriptByName('b.py')!.runCount, 1);
      expect(state.generation, generation + 1);
    });
  });

  group('error swallowing', () {
    test('createScript returns false on repository failure without throwing',
        () async {
      final repo = _ThrowingCreateRepository();
      final container = makeContainer(repo);

      final ok = await container
          .read(scriptWorkspaceControllerProvider.notifier)
          .createScript('boom.py');

      expect(ok, isFalse);
    });
  });

  group('presentation selectors', () {
    test('metadata update with 300 scripts notifies only the target card',
        () async {
      final now = DateTime(2026, 1, 1);
      final repository = FakeScriptRepository(
        scripts: List.generate(
          300,
          (index) => script(
            'script_$index.py',
            now,
            sortOrder: index,
          ),
        ),
      );
      final container = makeContainer(repository);
      final controller =
          container.read(scriptWorkspaceControllerProvider.notifier);
      await controller.load();

      var layoutNotifications = 0;
      var targetNotifications = 0;
      var untouchedNotifications = 0;
      final layoutSubscription = container.listen(
        scriptWorkspaceControllerProvider.select((state) => state.layout),
        (previousLayout, nextLayout) => layoutNotifications++,
        fireImmediately: true,
      );
      final targetSubscription = container.listen(
        scriptWorkspaceControllerProvider.select(
          (state) => state.scriptByName('script_150.py'),
        ),
        (previousScript, nextScript) => targetNotifications++,
        fireImmediately: true,
      );
      final untouchedSubscription = container.listen(
        scriptWorkspaceControllerProvider.select(
          (state) => state.scriptByName('script_151.py'),
        ),
        (previousScript, nextScript) => untouchedNotifications++,
        fireImmediately: true,
      );
      addTearDown(layoutSubscription.close);
      addTearDown(targetSubscription.close);
      addTearDown(untouchedSubscription.close);

      expect(
          await controller.saveScript('script_150.py', 'print(150)'), isTrue);

      expect(layoutNotifications, 1, reason: '修改时间不改变分组、置顶或排序，不应重建 Sliver 容器');
      expect(targetNotifications, 2, reason: '目标脚本卡片应收到自己的元数据更新');
      expect(untouchedNotifications, 1, reason: '未修改的脚本卡片不应收到其他脚本的更新');
    });
  });
}

class _ThrowingListRepository extends FakeScriptRepository {
  @override
  Future<List<ScriptFile>> getAllScripts() async =>
      throw StateError('db locked');
}

class _ThrowingCreateRepository extends FakeScriptRepository {
  @override
  Future<String> createScriptFile(String name, {String content = ''}) async {
    throw StateError('disk full');
  }
}

class _FailingLoadRepository extends FakeScriptRepository {
  _FailingLoadRepository({super.scripts});

  bool failGetAllScripts = false;

  @override
  Future<List<ScriptFile>> getAllScripts() async {
    if (failGetAllScripts) throw StateError('db locked during refresh');
    return super.getAllScripts();
  }
}

class _DelayedGroupsRepository extends FakeScriptRepository {
  _DelayedGroupsRepository({super.groups, super.scripts});

  final Completer<void> _firstGroupsRequest = Completer<void>();
  final Completer<void> _releaseFirstGroupsRequest = Completer<void>();
  bool _shouldDelay = true;

  Future<void> get firstGroupsRequest => _firstGroupsRequest.future;

  void releaseFirstGroupsRequest() => _releaseFirstGroupsRequest.complete();

  @override
  Future<List<ScriptGroup>> getAllGroups() async {
    if (_shouldDelay) {
      _shouldDelay = false;
      _firstGroupsRequest.complete();
      await _releaseFirstGroupsRequest.future;
    }
    return super.getAllGroups();
  }
}

class _SequencedGroupsRepository extends FakeScriptRepository {
  _SequencedGroupsRepository({
    required this.firstGroups,
    required this.laterGroups,
    super.scripts,
  });

  final List<ScriptGroup> firstGroups;
  final List<ScriptGroup> laterGroups;
  final Completer<void> _firstGroupsRequest = Completer<void>();
  final Completer<void> _releaseFirstGroupsRequest = Completer<void>();
  var _requestCount = 0;

  Future<void> get firstGroupsRequest => _firstGroupsRequest.future;

  void releaseFirstGroupsRequest() => _releaseFirstGroupsRequest.complete();

  @override
  Future<List<ScriptGroup>> getAllGroups() async {
    _requestCount++;
    if (_requestCount == 1) {
      _firstGroupsRequest.complete();
      await _releaseFirstGroupsRequest.future;
      return List<ScriptGroup>.from(firstGroups);
    }
    return List<ScriptGroup>.from(laterGroups);
  }
}

class _FailingSortRepository extends FakeScriptRepository {
  _FailingSortRepository({super.scripts});

  bool failBatchUpdate = false;

  @override
  Future<void> batchUpdateSortOrders(List<ScriptFile> scripts) async {
    if (failBatchUpdate) throw StateError('sort write failed');
    await super.batchUpdateSortOrders(scripts);
  }
}

class _FailingMoveRepository extends FakeScriptRepository {
  _FailingMoveRepository({super.groups, super.scripts});

  @override
  Future<void> moveScriptsToGroup(List<ScriptFile> scripts) async {
    throw StateError('move write failed');
  }
}
