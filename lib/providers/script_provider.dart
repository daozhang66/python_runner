import 'package:flutter/foundation.dart';
import '../models/script_file.dart';
import '../models/script_group.dart';
import '../services/native_bridge.dart';
import '../services/database_service.dart';
import '../services/project_path_validator.dart';
import '../services/script_name_validator.dart';

class ScriptProvider extends ChangeNotifier {
  final NativeBridge _bridge;
  final DatabaseService _db;

  List<ScriptFile> _scripts = [];
  List<ScriptGroup> _groups = [];
  bool _loading = false;

  List<ScriptFile> get scripts => _scripts;
  List<ScriptGroup> get groups => _groups;
  List<ScriptFile> get ungroupedScripts =>
      scriptsInGroup(null).where((script) => script.groupId == null).toList();
  bool get loading => _loading;

  ScriptProvider(this._bridge, this._db);

  void _sortScripts() {
    _sortScriptList(_scripts);
  }

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

  List<ScriptFile> scriptsInGroup(int? groupId) {
    final result =
        _scripts.where((script) => script.groupId == groupId).toList();
    _sortScriptList(result);
    return result;
  }

  int scriptCountInGroup(int groupId) =>
      _scripts.where((script) => script.groupId == groupId).length;

  int _maxSortOrderForGroup(int? groupId) {
    return _scripts.where((script) => script.groupId == groupId).fold<int>(
        0, (max, script) => script.sortOrder > max ? script.sortOrder : max);
  }

  Future<void> loadScripts() async {
    _loading = true;
    notifyListeners();
    try {
      _groups = await _db.getAllGroups();
      _sortGroups();
      final names = await _bridge.listScripts();
      final dbScripts = await _db.getAllScripts();
      final dbMap = {for (var s in dbScripts) s.name: s};

      final now = DateTime.now();
      _scripts = [];
      int maxOrder = dbScripts.fold<int>(
          0, (max, s) => s.sortOrder > max ? s.sortOrder : max);
      for (final name in names) {
        if (dbMap.containsKey(name)) {
          _scripts.add(dbMap[name]!);
        } else {
          maxOrder++;
          final script = ScriptFile(
            name: name,
            path: name,
            createdAt: now,
            modifiedAt: now,
            sortOrder: maxOrder,
          );
          await _db.upsertScript(script);
          _scripts.add(script);
        }
      }
      _sortScripts();
    } catch (e) {
      debugPrint('loadScripts error: $e');
    }
    _loading = false;
    notifyListeners();
  }

  Future<bool> createScript(String name,
      {String content = '', int? groupId}) async {
    try {
      final safeName = ScriptNameValidator.normalize(name);
      final path = await _bridge.createScript(safeName, content: content);
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
      await _db.upsertScript(script);
      _scripts.add(script);
      _sortScripts();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('createScript error: $e');
      return false;
    }
  }

  Future<bool> deleteScript(String name) async {
    try {
      final safeName = ScriptNameValidator.normalize(name);
      await _bridge.deleteScript(safeName);
      await _db.deleteScript(safeName);
      _scripts.removeWhere((s) => s.name == safeName);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('deleteScript error: $e');
      return false;
    }
  }

  Future<bool> renameScript(String oldName, String newName) async {
    try {
      final safeOldName = ScriptNameValidator.normalize(oldName);
      final safeNewName = ScriptNameValidator.normalize(newName);
      await _bridge.renameScript(safeOldName, safeNewName);
      await _db.renameScript(safeOldName, safeNewName, safeNewName);
      final idx = _scripts.indexWhere((s) => s.name == safeOldName);
      if (idx >= 0) {
        _scripts[idx] = _scripts[idx].copyWith(
            name: safeNewName, path: safeNewName, modifiedAt: DateTime.now());
        _sortScripts();
      }
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('renameScript error: $e');
      return false;
    }
  }

  Future<String> readScript(String name) async {
    try {
      final safeName = ScriptNameValidator.normalize(name);
      return await _bridge.readScript(safeName);
    } catch (e) {
      debugPrint('readScript error: $e');
      return '';
    }
  }

  Future<bool> saveScript(String name, String content) async {
    try {
      final safeName = ScriptNameValidator.normalize(name);
      await _bridge.saveScript(safeName, content);
      final now = DateTime.now();
      final idx = _scripts.indexWhere((s) => s.name == safeName);
      if (idx >= 0) {
        final updated = _scripts[idx].copyWith(modifiedAt: now);
        await _db.upsertScript(updated);
        _scripts[idx] = updated;
        _sortScripts();
        notifyListeners();
      } else {
        final existing = await _db.getScript(safeName);
        if (existing != null) {
          await _db.upsertScript(existing.copyWith(modifiedAt: now));
        }
      }
      return true;
    } catch (e) {
      debugPrint('saveScript error: $e');
      return false;
    }
  }

  Future<String?> importScript(String uri, String name, {int? groupId}) async {
    try {
      final safeName = ScriptNameValidator.normalize(name);
      final path = await _bridge.importScriptFromUri(uri, safeName);
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
      await _db.upsertScript(script);
      _scripts.add(script);
      _sortScripts();
      notifyListeners();
      return path;
    } catch (e) {
      debugPrint('importScript error: $e');
      return null;
    }
  }

  List<ScriptFile> _applyGroupSortOrders(List<ScriptFile> groupScripts) {
    final updates = <ScriptFile>[];
    for (int i = 0; i < groupScripts.length; i++) {
      final updated = groupScripts[i].copyWith(sortOrder: i);
      groupScripts[i] = updated;
      final sourceIndex = _scripts.indexWhere((s) => s.name == updated.name);
      if (sourceIndex >= 0) {
        _scripts[sourceIndex] = updated;
        updates.add(updated);
      }
    }
    return updates;
  }

  List<ScriptFile> _promoteScriptToFrontInGroup(ScriptFile script) {
    if (script.isPinned) return const [];

    final groupScripts = scriptsInGroup(script.groupId);
    if (!groupScripts.any((item) => item.name == script.name)) {
      return const [];
    }

    final pinnedScripts = groupScripts.where((item) => item.isPinned).toList();
    final regularScripts =
        groupScripts.where((item) => !item.isPinned).toList();
    regularScripts.removeWhere((item) => item.name == script.name);
    regularScripts.insert(0, script);
    return _applyGroupSortOrders([...pinnedScripts, ...regularScripts]);
  }

  Future<void> incrementRunCount(String name) async {
    await _db.incrementRunCount(name);
    final idx = _scripts.indexWhere((s) => s.name == name);
    if (idx >= 0) {
      final updated = _scripts[idx].copyWith(
        runCount: _scripts[idx].runCount + 1,
        modifiedAt: DateTime.now(),
      );
      _scripts[idx] = updated;
      final updates = _promoteScriptToFrontInGroup(updated);
      if (updates.isNotEmpty) {
        await _db.batchUpdateSortOrders(updates);
      }
      _sortScripts();
      notifyListeners();
    }
  }

  Future<void> togglePinned(String name) async {
    final idx = _scripts.indexWhere((s) => s.name == name);
    if (idx < 0) return;

    final current = _scripts[idx];
    final updated = current.copyWith(isPinned: !current.isPinned);
    await _db.upsertScript(updated);
    _scripts[idx] = updated;
    _sortScripts();
    notifyListeners();
  }

  Future<void> loadGroups() async {
    _groups = await _db.getAllGroups();
    _sortGroups();
    notifyListeners();
  }

  Future<bool> createGroup(String name) async {
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
      final id = await _db.createGroup(draft);
      _groups.add(draft.copyWith(id: id));
      _sortGroups();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('createGroup error: $e');
      return false;
    }
  }

  String _generateProjectKey() =>
      'project_${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';

  Future<ScriptGroup?> createProjectGroup(
    String name, {
    String? mainFilePath,
    String? projectKey,
  }) async {
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
      final id = await _db.createGroup(draft);
      final group = draft.copyWith(id: id);
      _groups.add(group);
      _sortGroups();
      notifyListeners();
      return group;
    } catch (e) {
      debugPrint('createProjectGroup error: $e');
      return null;
    }
  }

  Future<bool> updateProjectMainFile(
      ScriptGroup group, String? mainFilePath) async {
    final groupId = group.id;
    if (groupId == null || !group.isProject) return false;

    try {
      final safeMainFilePath = mainFilePath == null
          ? null
          : ProjectPathValidator.validateMainFilePath(mainFilePath);
      await _db.updateProjectMainFile(groupId, safeMainFilePath);
      final idx = _groups.indexWhere((item) => item.id == groupId);
      if (idx >= 0) {
        _groups[idx] = _groups[idx].copyWith(
          mainFilePath: safeMainFilePath,
          clearMainFilePath: safeMainFilePath == null,
          modifiedAt: DateTime.now(),
        );
      }
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('updateProjectMainFile error: $e');
      return false;
    }
  }

  Future<void> markProjectGroupUsed(ScriptGroup group) async {
    final groupId = group.id;
    if (groupId == null || !group.isProject) return;

    final now = DateTime.now();
    await _db.touchGroup(groupId);
    final idx = _groups.indexWhere((item) => item.id == groupId);
    if (idx >= 0) {
      _groups[idx] = _groups[idx].copyWith(modifiedAt: now);
      notifyListeners();
    }
  }

  Future<bool> renameGroup(int groupId, String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return false;
    if (_groups
        .any((group) => group.id != groupId && group.name == trimmedName)) {
      return false;
    }

    try {
      await _db.renameGroup(groupId, trimmedName);
      final idx = _groups.indexWhere((group) => group.id == groupId);
      if (idx >= 0) {
        _groups[idx] = _groups[idx]
            .copyWith(name: trimmedName, modifiedAt: DateTime.now());
      }
      _sortGroups();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('renameGroup error: $e');
      return false;
    }
  }

  Future<bool> deleteGroup(int groupId) async {
    try {
      final matches = _groups.where((item) => item.id == groupId);
      final group = matches.isEmpty ? null : matches.first;
      final projectKey = group?.isProject == true ? group?.projectKey : null;
      if (projectKey != null) {
        await _bridge.deleteScriptProject(projectKey);
      }
      await _db.deleteGroup(groupId);
      _groups.removeWhere((group) => group.id == groupId);
      for (int i = 0; i < _scripts.length; i++) {
        if (_scripts[i].groupId == groupId) {
          _scripts[i] = _scripts[i].copyWith(clearGroup: true);
        }
      }
      _sortScripts();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('deleteGroup error: $e');
      return false;
    }
  }

  Future<void> moveScriptsToGroup(
      Iterable<String> scriptNames, int? groupId) async {
    final names = scriptNames.toSet();
    if (names.isEmpty) return;

    final now = DateTime.now();
    var maxOrder = _maxSortOrderForGroup(groupId);
    final updates = <ScriptFile>[];
    for (int i = 0; i < _scripts.length; i++) {
      final script = _scripts[i];
      if (!names.contains(script.name)) continue;
      maxOrder++;
      final updated = script.copyWith(
        groupId: groupId,
        clearGroup: groupId == null,
        sortOrder: maxOrder,
        modifiedAt: now,
      );
      _scripts[i] = updated;
      updates.add(updated);
    }

    if (updates.isEmpty) return;
    await _db.moveScriptsToGroup(updates);
    _sortScripts();
    notifyListeners();
  }

  Future<void> reorderScript(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= _scripts.length) return;
    if (newIndex < 0 || newIndex >= _scripts.length) return;

    // 置顶脚本固定在顶部，只允许非置顶脚本调整顺序。
    final isPinned = _scripts[oldIndex].isPinned;
    if (isPinned) return;

    // 置顶/非置顶不能跨区域移动
    final pinnedCount = _scripts.where((s) => s.isPinned).length;

    if (!isPinned && newIndex < pinnedCount) return;

    // 执行移动
    final script = _scripts.removeAt(oldIndex);
    _scripts.insert(newIndex, script);

    // 重新分配 sortOrder
    for (int i = 0; i < _scripts.length; i++) {
      _scripts[i] = _scripts[i].copyWith(sortOrder: i);
    }

    // 批量更新数据库
    await _db.batchUpdateSortOrders(_scripts);

    notifyListeners();
  }

  Future<void> reorderScriptInGroup(
      int? groupId, int oldIndex, int newIndex) async {
    final groupScripts = scriptsInGroup(groupId);
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= groupScripts.length) return;
    if (newIndex < 0 || newIndex >= groupScripts.length) return;

    final isPinned = groupScripts[oldIndex].isPinned;
    if (isPinned) return;

    final pinnedCount = groupScripts.where((s) => s.isPinned).length;
    if (!isPinned && newIndex < pinnedCount) return;

    final script = groupScripts.removeAt(oldIndex);
    groupScripts.insert(newIndex, script);

    final updates = _applyGroupSortOrders(groupScripts);

    await _db.batchUpdateSortOrders(updates);
    _sortScripts();
    notifyListeners();
  }

  Future<void> swapScriptPositionsInGroup(
      int? groupId, int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    final groupScripts = scriptsInGroup(groupId);
    if (oldIndex < 0 || oldIndex >= groupScripts.length) return;
    if (newIndex < 0 || newIndex >= groupScripts.length) return;

    if (groupScripts[oldIndex].isPinned || groupScripts[newIndex].isPinned) {
      return;
    }

    final oldScript = groupScripts[oldIndex];
    groupScripts[oldIndex] = groupScripts[newIndex];
    groupScripts[newIndex] = oldScript;

    final updates = _applyGroupSortOrders(groupScripts);
    await _db.batchUpdateSortOrders(updates);
    _sortScripts();
    notifyListeners();
  }

  Future<void> swapScriptPositions(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= _scripts.length) return;
    if (newIndex < 0 || newIndex >= _scripts.length) return;

    if (_scripts[oldIndex].isPinned || _scripts[newIndex].isPinned) return;

    final oldScript = _scripts[oldIndex];
    _scripts[oldIndex] = _scripts[newIndex];
    _scripts[newIndex] = oldScript;

    for (int i = 0; i < _scripts.length; i++) {
      _scripts[i] = _scripts[i].copyWith(sortOrder: i);
    }

    await _db.batchUpdateSortOrders(_scripts);

    notifyListeners();
  }

  Future<void> swapScriptPositionsByName(
    String draggedName,
    String targetName, {
    int? groupId,
  }) async {
    final groupScripts = scriptsInGroup(groupId);
    final oldIndex = groupScripts.indexWhere((s) => s.name == draggedName);
    final newIndex = groupScripts.indexWhere((s) => s.name == targetName);
    await swapScriptPositionsInGroup(groupId, oldIndex, newIndex);
  }
}
