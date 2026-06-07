import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/models/script_file.dart';
import 'package:python_runner/models/script_group.dart';
import 'package:python_runner/providers/script_provider.dart';
import 'package:python_runner/services/database_service.dart';
import 'package:python_runner/services/native_bridge.dart';

void main() {
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
      _script('a.py', now, sortOrder: 0, groupId: group.id),
      _script('b.py', now, sortOrder: 1, groupId: group.id),
      _script('c.py', now, sortOrder: 2, groupId: group.id),
      _script('home.py', now, sortOrder: 0),
    ];
    final db = _MemoryDatabaseService(groups: [group], scripts: scripts);
    final provider = ScriptProvider(
      _MemoryNativeBridge(scripts.map((script) => script.name).toList()),
      db,
    );

    await provider.loadScripts();
    expect(
      provider.scriptsInGroup(group.id).map((script) => script.name),
      ['a.py', 'b.py', 'c.py'],
    );

    await provider.incrementRunCount('c.py');

    expect(
      provider.scriptsInGroup(group.id).map((script) => script.name),
      ['c.py', 'a.py', 'b.py'],
    );
    expect(provider.scriptsInGroup(group.id).first.runCount, 1);
    expect(provider.ungroupedScripts.map((script) => script.name), ['home.py']);
    expect(
      db.sortOrderUpdates.last.map((script) => script.name),
      ['c.py', 'a.py', 'b.py'],
    );
  });

  test('running a pinned script keeps pinned order fixed', () async {
    final now = DateTime.fromMillisecondsSinceEpoch(1000);
    final scripts = [
      _script('pinned-a.py', now, sortOrder: 0, isPinned: true),
      _script('pinned-b.py', now, sortOrder: 1, isPinned: true),
      _script('regular.py', now, sortOrder: 2),
    ];
    final db = _MemoryDatabaseService(groups: const [], scripts: scripts);
    final provider = ScriptProvider(
      _MemoryNativeBridge(scripts.map((script) => script.name).toList()),
      db,
    );

    await provider.loadScripts();
    await provider.incrementRunCount('pinned-b.py');

    expect(
      provider.ungroupedScripts.map((script) => script.name),
      ['pinned-a.py', 'pinned-b.py', 'regular.py'],
    );
    expect(provider.ungroupedScripts[1].runCount, 1);
    expect(db.sortOrderUpdates, isEmpty);
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
    final db = _MemoryDatabaseService(
      groups: [regularGroup, project],
      scripts: const [],
    );
    final provider = ScriptProvider(_MemoryNativeBridge(const []), db);

    await provider.loadScripts();
    await provider.markProjectGroupUsed(project);

    expect(db.touchedGroupIds, [project.id]);
    expect(
        provider.groups
            .firstWhere((group) => group.id == project.id)
            .modifiedAt,
        isNot(oldTime));
    expect(provider.groups.firstWhere((group) => group.id == regularGroup.id),
        regularGroup);
  });
}

ScriptFile _script(
  String name,
  DateTime time, {
  required int sortOrder,
  int? groupId,
  bool isPinned = false,
}) {
  return ScriptFile(
    name: name,
    path: name,
    createdAt: time,
    modifiedAt: time,
    sortOrder: sortOrder,
    groupId: groupId,
    isPinned: isPinned,
  );
}

class _MemoryNativeBridge extends NativeBridge {
  final List<String> names;

  _MemoryNativeBridge(this.names);

  @override
  Future<List<String>> listScripts() async => names;
}

class _MemoryDatabaseService extends DatabaseService {
  final List<ScriptGroup> groups;
  final List<ScriptFile> scripts;
  final List<List<ScriptFile>> sortOrderUpdates = [];
  final List<int> touchedGroupIds = [];

  _MemoryDatabaseService({
    required this.groups,
    required this.scripts,
  });

  @override
  Future<List<ScriptGroup>> getAllGroups() async => List.of(groups);

  @override
  Future<List<ScriptFile>> getAllScripts() async => List.of(scripts);

  @override
  Future<void> incrementRunCount(String name) async {
    final index = scripts.indexWhere((script) => script.name == name);
    if (index < 0) return;
    scripts[index] = scripts[index].copyWith(
      runCount: scripts[index].runCount + 1,
      modifiedAt: DateTime.now(),
    );
  }

  @override
  Future<void> batchUpdateSortOrders(List<ScriptFile> updates) async {
    sortOrderUpdates.add(List.of(updates));
    for (final update in updates) {
      final index = scripts.indexWhere((script) => script.name == update.name);
      if (index >= 0) {
        scripts[index] = scripts[index].copyWith(sortOrder: update.sortOrder);
      }
    }
  }

  @override
  Future<void> touchGroup(int groupId) async {
    touchedGroupIds.add(groupId);
    final index = groups.indexWhere((group) => group.id == groupId);
    if (index >= 0) {
      groups[index] = groups[index].copyWith(modifiedAt: DateTime.now());
    }
  }
}
