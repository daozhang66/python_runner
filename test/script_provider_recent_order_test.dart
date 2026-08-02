import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/scripts/application/script_workspace_controller.dart';
import 'package:python_runner/models/script_file.dart';
import 'package:python_runner/models/script_group.dart';

import 'support/script_test_helper.dart';

/// 脚本工作台 Controller 的排序/置顶/项目行为回归测试（原 ScriptProvider 用例）。
///
/// 三个用例与迁移前 legacy ChangeNotifier 完全一致，用于验证 Riverpod 化后
/// 排序算法、置顶提升规则与项目最近使用刷新 1:1 保留。
void main() {
  ScriptFile script(
    String name,
    DateTime time, {
    required int sortOrder,
    int? groupId,
    bool isPinned = false,
  }) =>
      ScriptFile(
        name: name,
        path: name,
        createdAt: time,
        modifiedAt: time,
        sortOrder: sortOrder,
        groupId: groupId,
        isPinned: isPinned,
      );

  test('running a script promotes it to the front of its current group',
      () async {
    final now = DateTime.fromMillisecondsSinceEpoch(1000);
    final group = ScriptGroup(
      id: 1,
      name: 'Work',
      sortOrder: 0,
      createdAt: now,
      modifiedAt: now,
    );
    final scripts = [
      script('a.py', now, sortOrder: 0, groupId: group.id),
      script('b.py', now, sortOrder: 1, groupId: group.id),
      script('c.py', now, sortOrder: 2, groupId: group.id),
      script('home.py', now, sortOrder: 0),
    ];
    final repo = FakeScriptRepository(groups: [group], scripts: scripts);
    final container = buildScriptContainer(repository: repo);
    addTearDown(container.dispose);
    final notifier = container.read(scriptWorkspaceControllerProvider.notifier);

    await notifier.load();
    expect(
      notifier.scriptsInGroup(group.id).map((s) => s.name),
      ['a.py', 'b.py', 'c.py'],
    );

    await notifier.incrementRunCount('c.py');

    expect(
      notifier.scriptsInGroup(group.id).map((s) => s.name),
      ['c.py', 'a.py', 'b.py'],
    );
    expect(notifier.scriptsInGroup(group.id).first.runCount, 1);
    expect(notifier.ungroupedScripts.map((s) => s.name), ['home.py']);
    expect(
      repo.lastBatchSortOrders?.map((s) => s.name),
      ['c.py', 'a.py', 'b.py'],
    );
  });

  test('running a pinned script keeps pinned order fixed', () async {
    final now = DateTime.fromMillisecondsSinceEpoch(1000);
    final scripts = [
      script('pinned-a.py', now, sortOrder: 0, isPinned: true),
      script('pinned-b.py', now, sortOrder: 1, isPinned: true),
      script('regular.py', now, sortOrder: 2),
    ];
    final repo = FakeScriptRepository(scripts: scripts);
    final container = buildScriptContainer(repository: repo);
    addTearDown(container.dispose);
    final notifier = container.read(scriptWorkspaceControllerProvider.notifier);

    await notifier.load();
    await notifier.incrementRunCount('pinned-b.py');

    expect(
      notifier.ungroupedScripts.map((s) => s.name),
      ['pinned-a.py', 'pinned-b.py', 'regular.py'],
    );
    expect(notifier.ungroupedScripts[1].runCount, 1);
    expect(repo.batchUpdateSortOrdersCount, 0);
  });

  test('using a project refreshes its recent time without moving folders',
      () async {
    final oldTime = DateTime.fromMillisecondsSinceEpoch(1000);
    final regularGroup = ScriptGroup(
      id: 1,
      name: 'Folder',
      sortOrder: 0,
      createdAt: oldTime,
      modifiedAt: oldTime,
    );
    final project = ScriptGroup(
      id: 2,
      name: 'Project',
      sortOrder: 1,
      createdAt: oldTime,
      modifiedAt: oldTime,
      isProject: true,
      projectKey: 'project_1',
      mainFilePath: 'main.py',
    );
    final repo =
        FakeScriptRepository(groups: [regularGroup, project], scripts: const []);
    final container = buildScriptContainer(repository: repo);
    addTearDown(container.dispose);
    final notifier = container.read(scriptWorkspaceControllerProvider.notifier);

    await notifier.load();
    await notifier.markProjectGroupUsed(project);

    // touchGroup 应被调用一次（项目分组）。
    expect(repo.touchGroupCount, 1);
    expect(repo.lastTouchedGroupId, project.id);
    expect(
      notifier.groups.firstWhere((g) => g.id == project.id).modifiedAt,
      isNot(oldTime),
    );
    expect(
      notifier.groups.firstWhere((g) => g.id == regularGroup.id),
      regularGroup,
    );
  });
}
