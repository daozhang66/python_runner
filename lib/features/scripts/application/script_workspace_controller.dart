import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/script_file.dart';
import '../../../models/script_group.dart';
import '../../../services/app_logger.dart';
import '../../../services/project_path_validator.dart';
import '../../../services/script_name_validator.dart';
import 'script_repository.dart';
import 'script_workspace_state.dart';

/// 脚本工作台业务 Controller（单一状态所有者，Level 2）。
///
/// 行为与迁移前的 legacy ChangeNotifier **1:1 对齐**：排序、置顶、拖拽、分组、
/// 项目元数据与错误吞咽语义全部逐行保留。内部仍用可变工作列表（`_scripts` /
/// `_groups`）承载算法对原可变字段的依赖，每次状态变更发布不可变快照。
///
/// 查询方法（[ungroupedScripts]、[scriptsInGroup]、[scriptCountInGroup]）为读时
/// 计算，与 legacy 一致；页面通过 `ref.watch(...select(...))` 监听 scripts/
/// groups/loading，命令方法返回值与 legacy 一致（成功/失败 bool 或 void）。
final scriptWorkspaceControllerProvider =
    NotifierProvider<ScriptWorkspaceController, ScriptWorkspaceState>(
  ScriptWorkspaceController.new,
);

class ScriptWorkspaceController extends Notifier<ScriptWorkspaceState> {
  ScriptWorkspaceController();

  late final ScriptRepository _repository;
  final AppLogger _logger = AppLogger.instance;

  // 可变工作列表：承载 legacy 算法对可变字段的依赖（原地排序、indexWhere 改写）。
  // 每次 [_commit] 发布不可变快照到 state。
  final List<ScriptFile> _scripts = [];
  final List<ScriptGroup> _groups = [];
  Future<void> _operationTail = Future<void>.value();
  int _generation = 0;
  int _layoutRevision = 0;

  @override
  ScriptWorkspaceState build() {
    _repository = ref.watch(scriptRepositoryProvider);
    return ScriptWorkspaceState();
  }

  // --- 查询 API（读时计算，与 legacy 1:1） ---

  List<ScriptFile> get scripts => state.scripts;
  List<ScriptGroup> get groups => state.groups;
  bool get loading => state.isLoading;

  List<ScriptFile> get ungroupedScripts =>
      scriptsInGroup(null).where((script) => script.groupId == null).toList();

  List<ScriptFile> scriptsInGroup(int? groupId) {
    final result =
        _scripts.where((script) => script.groupId == groupId).toList();
    _sortScriptList(result);
    return result;
  }

  int scriptCountInGroup(int groupId) =>
      _scripts.where((script) => script.groupId == groupId).length;

  // --- 排序/提升算法（逐行复制自 legacy，勿改） ---

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _operationTail.then<T>(
      (_) => operation(),
      onError: (_) => operation(),
    );
    _operationTail = result.then<void>(
      (_) {},
      onError: (_, __) {},
    );
    return result;
  }

  void _sortScripts() => _sortScriptList(_scripts);

  void _sortScriptList(List<ScriptFile> scripts) {
    scripts.sort((a, b) {
      final pinCompare = (b.isPinned ? 1 : 0).compareTo(a.isPinned ? 1 : 0);
      if (pinCompare != 0) return pinCompare;
      return a.sortOrder.compareTo(b.sortOrder);
    });
  }

  void _sortGroups() {
    _groups.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  int _maxSortOrderForGroup(int? groupId, [List<ScriptFile>? scripts]) {
    return (scripts ?? _scripts)
        .where((script) => script.groupId == groupId)
        .fold<int>(0,
            (max, script) => script.sortOrder > max ? script.sortOrder : max);
  }

  List<ScriptFile> _applyGroupSortOrders(
    List<ScriptFile> candidateScripts,
    List<ScriptFile> groupScripts,
  ) {
    final updates = <ScriptFile>[];
    for (int i = 0; i < groupScripts.length; i++) {
      final updated = groupScripts[i].copyWith(sortOrder: i);
      groupScripts[i] = updated;
      final sourceIndex =
          candidateScripts.indexWhere((s) => s.name == updated.name);
      if (sourceIndex >= 0) {
        candidateScripts[sourceIndex] = updated;
        updates.add(updated);
      }
    }
    return updates;
  }

  List<ScriptFile> _promoteScriptToFrontInGroup(
    List<ScriptFile> candidateScripts,
    ScriptFile script,
  ) {
    if (script.isPinned) return const [];

    final groupScripts = candidateScripts
        .where((item) => item.groupId == script.groupId)
        .toList();
    _sortScriptList(groupScripts);
    if (!groupScripts.any((item) => item.name == script.name)) {
      return const [];
    }

    final pinnedScripts = groupScripts.where((item) => item.isPinned).toList();
    final regularScripts =
        groupScripts.where((item) => !item.isPinned).toList();
    regularScripts.removeWhere((item) => item.name == script.name);
    regularScripts.insert(0, script);
    return _applyGroupSortOrders(
      candidateScripts,
      [...pinnedScripts, ...regularScripts],
    );
  }

  void _commit({
    bool scriptsChanged = true,
    bool groupsChanged = true,
    bool layoutChanged = true,
  }) {
    state = state.copyWith(
      scripts:
          scriptsChanged ? List.unmodifiable(List.of(_scripts)) : state.scripts,
      groups:
          groupsChanged ? List.unmodifiable(List.of(_groups)) : state.groups,
      generation: ++_generation,
      layoutRevision: layoutChanged ? ++_layoutRevision : state.layoutRevision,
    );
  }

  // --- 命令：加载 ---

  Future<void> load() {
    state = state.copyWith(isLoading: true);
    return _enqueue(() async {
      try {
        final candidateGroups = await _repository.getAllGroups();
        candidateGroups.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        final names = await _repository.listScriptFiles();
        final dbScripts = await _repository.getAllScripts();
        final dbMap = {for (var s in dbScripts) s.name: s};

        final candidateScripts = <ScriptFile>[];
        final now = DateTime.now();
        int maxOrder = dbScripts.fold<int>(
            0, (max, s) => s.sortOrder > max ? s.sortOrder : max);
        for (final name in names) {
          if (dbMap.containsKey(name)) {
            candidateScripts.add(dbMap[name]!);
          } else {
            maxOrder++;
            final script = ScriptFile(
              name: name,
              path: name,
              createdAt: now,
              modifiedAt: now,
              sortOrder: maxOrder,
            );
            await _repository.upsertScript(script);
            candidateScripts.add(script);
          }
        }
        _sortScriptList(candidateScripts);
        _groups
          ..clear()
          ..addAll(candidateGroups);
        _scripts
          ..clear()
          ..addAll(candidateScripts);
        state = state.copyWith(isLoading: false, clearLoadError: true);
        _commit();
      } catch (e, stackTrace) {
        _logger.error(
          '加载脚本列表失败: $e',
          source: 'ScriptWorkspace',
          detail: stackTrace.toString(),
        );
        state = state.copyWith(
          isLoading: false,
          loadError: e.toString(),
        );
      }
    });
  }

  // --- 命令：脚本 CRUD ---

  Future<bool> createScript(String name, {String content = '', int? groupId}) {
    return _enqueue(() async {
      try {
        final safeName = ScriptNameValidator.normalize(name);
        final path =
            await _repository.createScriptFile(safeName, content: content);
        final now = DateTime.now();
        final maxOrder = _maxSortOrderForGroup(groupId);
        final script = ScriptFile(
          name: safeName,
          path: path,
          createdAt: now,
          modifiedAt: now,
          sortOrder: maxOrder + 1,
          groupId: groupId,
        );
        await _repository.upsertScript(script);
        _scripts.add(script);
        _sortScripts();
        _commit();
        return true;
      } catch (e, stackTrace) {
        _logger.error(
          '创建脚本失败: $e',
          source: 'ScriptWorkspace',
          detail: stackTrace.toString(),
        );
        return false;
      }
    });
  }

  Future<bool> deleteScript(String name) {
    return _enqueue(() async {
      try {
        final safeName = ScriptNameValidator.normalize(name);
        await _repository.deleteScriptFile(safeName);
        await _repository.deleteScript(safeName);
        _scripts.removeWhere((s) => s.name == safeName);
        _commit();
        return true;
      } catch (e, stackTrace) {
        _logger.error(
          '删除脚本失败: $e',
          source: 'ScriptWorkspace',
          detail: stackTrace.toString(),
        );
        return false;
      }
    });
  }

  Future<bool> renameScript(String oldName, String newName) {
    return _enqueue(() async {
      try {
        final safeOldName = ScriptNameValidator.normalize(oldName);
        final safeNewName = ScriptNameValidator.normalize(newName);
        await _repository.renameScriptFile(safeOldName, safeNewName);
        await _repository.renameScript(safeOldName, safeNewName, safeNewName);
        final idx = _scripts.indexWhere((s) => s.name == safeOldName);
        if (idx >= 0) {
          _scripts[idx] = _scripts[idx].copyWith(
              name: safeNewName, path: safeNewName, modifiedAt: DateTime.now());
          _sortScripts();
        }
        _commit();
        return true;
      } catch (e, stackTrace) {
        _logger.error(
          '重命名脚本失败: $e',
          source: 'ScriptWorkspace',
          detail: stackTrace.toString(),
        );
        return false;
      }
    });
  }

  Future<String> readScript(String name) async {
    try {
      final safeName = ScriptNameValidator.normalize(name);
      return await _repository.readScriptFile(safeName);
    } catch (e, stackTrace) {
      _logger.error(
        '读取脚本失败: $e',
        source: 'ScriptWorkspace',
        detail: stackTrace.toString(),
      );
      return '';
    }
  }

  Future<bool> saveScript(String name, String content) {
    return _enqueue(() async {
      try {
        final safeName = ScriptNameValidator.normalize(name);
        await _repository.saveScriptFile(safeName, content);
        final now = DateTime.now();
        final idx = _scripts.indexWhere((s) => s.name == safeName);
        if (idx >= 0) {
          final updated = _scripts[idx].copyWith(modifiedAt: now);
          await _repository.upsertScript(updated);
          _scripts[idx] = updated;
          _sortScripts();
          _commit(groupsChanged: false, layoutChanged: false);
        } else {
          final existing = await _repository.getScript(safeName);
          if (existing != null) {
            await _repository.upsertScript(existing.copyWith(modifiedAt: now));
          }
        }
        return true;
      } catch (e, stackTrace) {
        _logger.error(
          '保存脚本失败: $e',
          source: 'ScriptWorkspace',
          detail: stackTrace.toString(),
        );
        return false;
      }
    });
  }

  Future<String?> importScript(String uri, String name, {int? groupId}) {
    return _enqueue(() async {
      try {
        final safeName = ScriptNameValidator.normalize(name);
        final path = await _repository.importScriptFromUri(uri, safeName);
        final now = DateTime.now();
        final maxOrder = _maxSortOrderForGroup(groupId);
        final script = ScriptFile(
          name: safeName,
          path: path,
          createdAt: now,
          modifiedAt: now,
          sortOrder: maxOrder + 1,
          groupId: groupId,
        );
        await _repository.upsertScript(script);
        _scripts.add(script);
        _sortScripts();
        _commit();
        return path;
      } catch (e, stackTrace) {
        _logger.error(
          '导入脚本失败: $e',
          source: 'ScriptWorkspace',
          detail: stackTrace.toString(),
        );
        return null;
      }
    });
  }

  Future<void> incrementRunCount(String name) {
    return _enqueue(() async {
      try {
        await _repository.incrementRunCount(name);
        final idx = _scripts.indexWhere((s) => s.name == name);
        if (idx < 0) return;

        final candidateScripts = List<ScriptFile>.of(_scripts);
        final updated = candidateScripts[idx].copyWith(
          runCount: candidateScripts[idx].runCount + 1,
          modifiedAt: DateTime.now(),
        );
        candidateScripts[idx] = updated;
        final updates = _promoteScriptToFrontInGroup(candidateScripts, updated);
        if (updates.isNotEmpty) {
          try {
            await _repository.batchUpdateSortOrders(updates);
          } catch (e, stackTrace) {
            // 运行次数已单独持久化成功；只放弃本次置顶排序，避免内存
            // 仍显示旧次数而与数据库不一致。
            _scripts[idx] = updated;
            _commit(groupsChanged: false, layoutChanged: false);
            _logger.error(
              '按运行次数调整脚本排序失败: $e',
              source: 'ScriptWorkspace',
              detail: stackTrace.toString(),
            );
            return;
          }
        }
        _sortScriptList(candidateScripts);
        _scripts
          ..clear()
          ..addAll(candidateScripts);
        _commit(groupsChanged: false, layoutChanged: updates.isNotEmpty);
      } catch (e, stackTrace) {
        _logger.error(
          '增加脚本运行次数失败: $e',
          source: 'ScriptWorkspace',
          detail: stackTrace.toString(),
        );
      }
    });
  }

  Future<void> togglePinned(String name) {
    return _enqueue(() async {
      final idx = _scripts.indexWhere((s) => s.name == name);
      if (idx < 0) return;

      final candidateScripts = List<ScriptFile>.of(_scripts);
      final current = candidateScripts[idx];
      final updated = current.copyWith(isPinned: !current.isPinned);
      await _repository.upsertScript(updated);
      candidateScripts[idx] = updated;
      _sortScriptList(candidateScripts);
      _scripts
        ..clear()
        ..addAll(candidateScripts);
      _commit(groupsChanged: false);
    });
  }

  // --- 命令：分组 ---

  Future<void> loadGroups() {
    return _enqueue(() async {
      final candidateGroups = await _repository.getAllGroups();
      candidateGroups.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      _groups
        ..clear()
        ..addAll(candidateGroups);
      _commit(scriptsChanged: false);
    });
  }

  Future<bool> createGroup(String name) {
    return _enqueue(() async {
      final trimmedName = name.trim();
      if (trimmedName.isEmpty) return false;
      if (_groups.any((group) => group.name == trimmedName)) return false;

      try {
        final now = DateTime.now();
        final maxOrder = _groups.fold<int>(
            0, (max, group) => group.sortOrder > max ? group.sortOrder : max);
        final draft = ScriptGroup(
          name: trimmedName,
          sortOrder: maxOrder + 1,
          createdAt: now,
          modifiedAt: now,
        );
        final id = await _repository.createGroup(draft);
        _groups.add(draft.copyWith(id: id));
        _sortGroups();
        _commit(scriptsChanged: false);
        return true;
      } catch (e, stackTrace) {
        _logger.error(
          '创建分组失败: $e',
          source: 'ScriptWorkspace',
          detail: stackTrace.toString(),
        );
        return false;
      }
    });
  }

  String _generateProjectKey() =>
      'project_${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';

  Future<ScriptGroup?> createProjectGroup(
    String name, {
    String? mainFilePath,
    String? projectKey,
  }) {
    return _enqueue(() async {
      final trimmedName = name.trim();
      if (trimmedName.isEmpty) return null;
      if (_groups.any((group) => group.name == trimmedName)) return null;

      try {
        final safeProjectKey = ProjectPathValidator.normalizeProjectKey(
            projectKey ?? _generateProjectKey());
        final safeMainFilePath = mainFilePath == null
            ? null
            : ProjectPathValidator.validateMainFilePath(mainFilePath);
        final now = DateTime.now();
        final maxOrder = _groups.fold<int>(
            0, (max, group) => group.sortOrder > max ? group.sortOrder : max);
        final draft = ScriptGroup(
          name: trimmedName,
          sortOrder: maxOrder + 1,
          createdAt: now,
          modifiedAt: now,
          projectKey: safeProjectKey,
          mainFilePath: safeMainFilePath,
          isProject: true,
        );
        final id = await _repository.createGroup(draft);
        final group = draft.copyWith(id: id);
        _groups.add(group);
        _sortGroups();
        _commit(scriptsChanged: false);
        return group;
      } catch (e, stackTrace) {
        _logger.error(
          '创建项目分组失败: $e',
          source: 'ScriptWorkspace',
          detail: stackTrace.toString(),
        );
        return null;
      }
    });
  }

  Future<bool> updateProjectMainFile(ScriptGroup group, String? mainFilePath) {
    return _enqueue(() async {
      final groupId = group.id;
      if (groupId == null || !group.isProject) return false;

      try {
        final safeMainFilePath = mainFilePath == null
            ? null
            : ProjectPathValidator.validateMainFilePath(mainFilePath);
        await _repository.updateProjectMainFile(groupId, safeMainFilePath);
        final idx = _groups.indexWhere((item) => item.id == groupId);
        if (idx >= 0) {
          _groups[idx] = _groups[idx].copyWith(
            mainFilePath: safeMainFilePath,
            clearMainFilePath: safeMainFilePath == null,
            modifiedAt: DateTime.now(),
          );
        }
        _commit(scriptsChanged: false);
        return true;
      } catch (e, stackTrace) {
        _logger.error(
          '更新项目主程序失败: $e',
          source: 'ScriptWorkspace',
          detail: stackTrace.toString(),
        );
        return false;
      }
    });
  }

  Future<void> markProjectGroupUsed(ScriptGroup group) {
    return _enqueue(() async {
      final groupId = group.id;
      if (groupId == null || !group.isProject) return;

      final now = DateTime.now();
      await _repository.touchGroup(groupId);
      final idx = _groups.indexWhere((item) => item.id == groupId);
      if (idx >= 0) {
        _groups[idx] = _groups[idx].copyWith(modifiedAt: now);
        _commit(scriptsChanged: false, layoutChanged: false);
      }
    });
  }

  Future<bool> renameGroup(int groupId, String name) {
    return _enqueue(() async {
      final trimmedName = name.trim();
      if (trimmedName.isEmpty) return false;
      if (_groups
          .any((group) => group.id != groupId && group.name == trimmedName)) {
        return false;
      }

      try {
        await _repository.renameGroup(groupId, trimmedName);
        final idx = _groups.indexWhere((group) => group.id == groupId);
        if (idx >= 0) {
          _groups[idx] = _groups[idx]
              .copyWith(name: trimmedName, modifiedAt: DateTime.now());
        }
        _sortGroups();
        _commit(scriptsChanged: false);
        return true;
      } catch (e, stackTrace) {
        _logger.error(
          '重命名分组失败: $e',
          source: 'ScriptWorkspace',
          detail: stackTrace.toString(),
        );
        return false;
      }
    });
  }

  Future<bool> deleteGroup(int groupId) {
    return _enqueue(() async {
      try {
        final matches = _groups.where((item) => item.id == groupId);
        final group = matches.isEmpty ? null : matches.first;
        final projectKey = group?.isProject == true ? group?.projectKey : null;
        if (projectKey != null) {
          await _repository.deleteScriptProject(projectKey);
        }
        await _repository.deleteGroup(groupId);
        _groups.removeWhere((group) => group.id == groupId);
        for (int i = 0; i < _scripts.length; i++) {
          if (_scripts[i].groupId == groupId) {
            _scripts[i] = _scripts[i].copyWith(clearGroup: true);
          }
        }
        _sortScripts();
        _commit();
        return true;
      } catch (e, stackTrace) {
        _logger.error(
          '删除分组失败: $e',
          source: 'ScriptWorkspace',
          detail: stackTrace.toString(),
        );
        return false;
      }
    });
  }

  Future<void> moveScriptsToGroup(Iterable<String> scriptNames, int? groupId) {
    final names = scriptNames.toSet();
    if (names.isEmpty) return Future<void>.value();
    return _enqueue(() async {
      try {
        final candidateScripts = List<ScriptFile>.of(_scripts);
        final now = DateTime.now();
        var maxOrder = _maxSortOrderForGroup(groupId, candidateScripts);
        final updates = <ScriptFile>[];
        for (int i = 0; i < candidateScripts.length; i++) {
          final script = candidateScripts[i];
          if (!names.contains(script.name)) continue;
          maxOrder++;
          final updated = script.copyWith(
            groupId: groupId,
            clearGroup: groupId == null,
            sortOrder: maxOrder,
            modifiedAt: now,
          );
          candidateScripts[i] = updated;
          updates.add(updated);
        }
        if (updates.isEmpty) return;

        await _repository.moveScriptsToGroup(updates);
        _sortScriptList(candidateScripts);
        _scripts
          ..clear()
          ..addAll(candidateScripts);
        _commit();
      } catch (e, stackTrace) {
        _logger.error(
          '移动脚本分组失败: $e',
          source: 'ScriptWorkspace',
          detail: stackTrace.toString(),
        );
      }
    });
  }

  // --- 命令：拖拽排序 ---

  Future<void> reorderScript(int oldIndex, int newIndex) {
    return _enqueue(() async {
      try {
        if (oldIndex == newIndex) return;
        if (oldIndex < 0 || oldIndex >= _scripts.length) return;
        if (newIndex < 0 || newIndex >= _scripts.length) return;

        final candidateScripts = List<ScriptFile>.of(_scripts);
        if (candidateScripts[oldIndex].isPinned) return;
        final pinnedCount = candidateScripts.where((s) => s.isPinned).length;
        if (newIndex < pinnedCount) return;

        final script = candidateScripts.removeAt(oldIndex);
        candidateScripts.insert(newIndex, script);
        for (int i = 0; i < candidateScripts.length; i++) {
          candidateScripts[i] = candidateScripts[i].copyWith(sortOrder: i);
        }

        await _repository.batchUpdateSortOrders(candidateScripts);
        _scripts
          ..clear()
          ..addAll(candidateScripts);
        _commit();
      } catch (e, stackTrace) {
        _logger.error(
          '调整脚本排序失败: $e',
          source: 'ScriptWorkspace',
          detail: stackTrace.toString(),
        );
      }
    });
  }

  Future<void> reorderScriptInGroup(int? groupId, int oldIndex, int newIndex) {
    return _enqueue(() => _reorderScriptInGroup(groupId, oldIndex, newIndex));
  }

  Future<void> _reorderScriptInGroup(
      int? groupId, int oldIndex, int newIndex) async {
    try {
      final candidateScripts = List<ScriptFile>.of(_scripts);
      final groupScripts = candidateScripts
          .where((script) => script.groupId == groupId)
          .toList();
      _sortScriptList(groupScripts);
      if (oldIndex == newIndex) return;
      if (oldIndex < 0 || oldIndex >= groupScripts.length) return;
      if (newIndex < 0 || newIndex >= groupScripts.length) return;
      if (groupScripts[oldIndex].isPinned) return;
      final pinnedCount = groupScripts.where((s) => s.isPinned).length;
      if (newIndex < pinnedCount) return;

      final script = groupScripts.removeAt(oldIndex);
      groupScripts.insert(newIndex, script);
      final updates = _applyGroupSortOrders(candidateScripts, groupScripts);
      await _repository.batchUpdateSortOrders(updates);
      _sortScriptList(candidateScripts);
      _scripts
        ..clear()
        ..addAll(candidateScripts);
      _commit();
    } catch (e, stackTrace) {
      _logger.error(
        '调整分组内脚本排序失败: $e',
        source: 'ScriptWorkspace',
        detail: stackTrace.toString(),
      );
    }
  }

  Future<void> swapScriptPositionsInGroup(
      int? groupId, int oldIndex, int newIndex) {
    return _enqueue(
        () => _swapScriptPositionsInGroup(groupId, oldIndex, newIndex));
  }

  Future<void> _swapScriptPositionsInGroup(
      int? groupId, int oldIndex, int newIndex) async {
    try {
      final candidateScripts = List<ScriptFile>.of(_scripts);
      final groupScripts = candidateScripts
          .where((script) => script.groupId == groupId)
          .toList();
      _sortScriptList(groupScripts);
      if (oldIndex == newIndex) return;
      if (oldIndex < 0 || oldIndex >= groupScripts.length) return;
      if (newIndex < 0 || newIndex >= groupScripts.length) return;
      if (groupScripts[oldIndex].isPinned || groupScripts[newIndex].isPinned) {
        return;
      }

      final oldScript = groupScripts[oldIndex];
      groupScripts[oldIndex] = groupScripts[newIndex];
      groupScripts[newIndex] = oldScript;
      final updates = _applyGroupSortOrders(candidateScripts, groupScripts);
      await _repository.batchUpdateSortOrders(updates);
      _sortScriptList(candidateScripts);
      _scripts
        ..clear()
        ..addAll(candidateScripts);
      _commit();
    } catch (e, stackTrace) {
      _logger.error(
        '交换分组内脚本位置失败: $e',
        source: 'ScriptWorkspace',
        detail: stackTrace.toString(),
      );
    }
  }

  Future<void> swapScriptPositions(int oldIndex, int newIndex) {
    return _enqueue(() => _swapScriptPositions(oldIndex, newIndex));
  }

  Future<void> _swapScriptPositions(int oldIndex, int newIndex) async {
    try {
      if (oldIndex == newIndex) return;
      if (oldIndex < 0 || oldIndex >= _scripts.length) return;
      if (newIndex < 0 || newIndex >= _scripts.length) return;

      final candidateScripts = List<ScriptFile>.of(_scripts);
      if (candidateScripts[oldIndex].isPinned ||
          candidateScripts[newIndex].isPinned) {
        return;
      }

      final oldScript = candidateScripts[oldIndex];
      candidateScripts[oldIndex] = candidateScripts[newIndex];
      candidateScripts[newIndex] = oldScript;
      for (int i = 0; i < candidateScripts.length; i++) {
        candidateScripts[i] = candidateScripts[i].copyWith(sortOrder: i);
      }

      await _repository.batchUpdateSortOrders(candidateScripts);
      _scripts
        ..clear()
        ..addAll(candidateScripts);
      _commit();
    } catch (e, stackTrace) {
      _logger.error(
        '交换脚本位置失败: $e',
        source: 'ScriptWorkspace',
        detail: stackTrace.toString(),
      );
    }
  }

  Future<void> swapScriptPositionsByName(
    String draggedName,
    String targetName, {
    int? groupId,
  }) {
    return _enqueue(() async {
      final groupScripts = scriptsInGroup(groupId);
      final oldIndex = groupScripts.indexWhere((s) => s.name == draggedName);
      final newIndex = groupScripts.indexWhere((s) => s.name == targetName);
      await _swapScriptPositionsInGroup(groupId, oldIndex, newIndex);
    });
  }
}
