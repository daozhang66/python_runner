import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:python_runner/features/scripts/application/script_repository.dart';
import 'package:python_runner/models/script_file.dart';
import 'package:python_runner/models/script_group.dart';

/// 构建一个绑定到 [FakeScriptRepository] 的 [ProviderContainer]，供 Level 2
/// 脚本工作台 Controller 单测使用。调用方负责 `container.dispose()`。
ProviderContainer buildScriptContainer({
  FakeScriptRepository? repository,
  List<Override> overrides = const [],
}) {
  final repo = repository ?? FakeScriptRepository();
  return ProviderContainer(
    overrides: [
      ...overrides,
      scriptRepositoryProvider.overrideWithValue(repo),
    ],
  );
}

/// 测试用 [ScriptRepository]。
///
/// 用内存列表模拟脚本/分组存储；每个命令方法暴露计数器和最近请求，便于 Level 2
/// Controller 断言调用参数与持久化顺序。文件类操作（listScriptFiles 等）用
/// 独立的内存集合，与数据库模拟分开，贴合真实 NativeBridge/DatabaseService 分工。
class FakeScriptRepository implements ScriptRepository {
  FakeScriptRepository({
    List<ScriptFile>? scripts,
    List<ScriptGroup>? groups,
    this.nextGroupId = 1,
  })  : _scripts = List<ScriptFile>.from(scripts ?? const []),
        _groups = List<ScriptGroup>.from(groups ?? const []) {
    // 与迁移前测试惯例一致：文件系统侧默认反映 DB 脚本名（bridge.listScripts
    // 返回同名集合）。Controller.load 据此与 DB 对账。
    for (final s in _scripts) {
      _files[s.name] = '';
      _scriptPaths[s.name] = s.path;
    }
  }

  final List<ScriptFile> _scripts;
  final List<ScriptGroup> _groups;
  int nextGroupId;

  // NativeBridge 侧的"文件系统"：脚本名 -> 文件内容。
  final Map<String, String> _files = {};
  final Map<String, String> _scriptPaths = {};

  // 可观测计数器与最近请求。
  int getAllScriptsCount = 0;
  int upsertScriptCount = 0;
  int deleteScriptDbCount = 0;
  int incrementRunCountCount = 0;
  int batchUpdateSortOrdersCount = 0;
  int createGroupCount = 0;
  int renameGroupCount = 0;
  int deleteGroupCount = 0;
  int moveScriptsToGroupCount = 0;
  int listScriptFilesCount = 0;
  int createScriptFileCount = 0;
  int deleteScriptFileCount = 0;
  int renameScriptFileCount = 0;
  int readScriptFileCount = 0;
  int saveScriptFileCount = 0;
  int importScriptFromUriCount = 0;
  int deleteScriptProjectCount = 0;
  int touchGroupCount = 0;

  ScriptFile? lastUpsertedScript;
  List<ScriptFile>? lastBatchSortOrders;
  ScriptGroup? lastCreatedGroup;
  int? lastTouchedGroupId;
  int? lastRenamedGroupId;
  List<ScriptFile>? lastMovedScripts;
  String? lastReadScriptName;
  String? lastSavedScriptName;
  String? lastSavedContent;
  String? lastImportUri;

  // --- DatabaseService：脚本元数据 ---

  @override
  Future<List<ScriptFile>> getAllScripts() async {
    getAllScriptsCount++;
    return List<ScriptFile>.from(_scripts);
  }

  @override
  Future<ScriptFile?> getScript(String name) async {
    return _scripts.where((s) => s.name == name).firstOrNull;
  }

  @override
  Future<void> upsertScript(ScriptFile script) async {
    upsertScriptCount++;
    lastUpsertedScript = script;
    _scripts.removeWhere((s) => s.name == script.name);
    _scripts.add(script);
  }

  @override
  Future<void> deleteScript(String name) async {
    deleteScriptDbCount++;
    _scripts.removeWhere((s) => s.name == name);
  }

  @override
  Future<void> renameScript(String oldName, String newName, String newPath) async {
    final index = _scripts.indexWhere((s) => s.name == oldName);
    if (index >= 0) {
      _scripts[index] = _scripts[index].copyWith(name: newName, path: newPath);
    }
  }

  @override
  Future<void> incrementRunCount(String name) async {
    incrementRunCountCount++;
    final index = _scripts.indexWhere((s) => s.name == name);
    if (index >= 0) {
      _scripts[index] =
          _scripts[index].copyWith(runCount: _scripts[index].runCount + 1);
    }
  }

  @override
  Future<void> batchUpdateSortOrders(List<ScriptFile> scripts) async {
    batchUpdateSortOrdersCount++;
    lastBatchSortOrders = List<ScriptFile>.from(scripts);
    for (var i = 0; i < scripts.length; i++) {
      final index = _scripts.indexWhere((s) => s.name == scripts[i].name);
      if (index >= 0) {
        _scripts[index] = _scripts[index].copyWith(sortOrder: i);
      }
    }
  }

  // --- DatabaseService：分组 ---

  @override
  Future<List<ScriptGroup>> getAllGroups() async {
    return List<ScriptGroup>.from(_groups);
  }

  @override
  Future<int> createGroup(ScriptGroup group) async {
    createGroupCount++;
    final id = group.id ?? nextGroupId++;
    final created = group.copyWith(id: id);
    lastCreatedGroup = created;
    _groups.add(created);
    return id;
  }

  @override
  Future<void> renameGroup(int groupId, String name) async {
    renameGroupCount++;
    lastRenamedGroupId = groupId;
    final index = _groups.indexWhere((g) => g.id == groupId);
    if (index >= 0) {
      _groups[index] = _groups[index].copyWith(name: name);
    }
  }

  @override
  Future<void> updateProjectMainFile(int groupId, String? mainFilePath) async {
    final index = _groups.indexWhere((g) => g.id == groupId);
    if (index >= 0) {
      _groups[index] = _groups[index].copyWith(
        mainFilePath: mainFilePath,
        clearMainFilePath: mainFilePath == null,
        modifiedAt: DateTime.now(),
      );
    }
  }

  @override
  Future<void> touchGroup(int groupId) async {
    touchGroupCount++;
    lastTouchedGroupId = groupId;
    final index = _groups.indexWhere((g) => g.id == groupId);
    if (index >= 0) {
      _groups[index] =
          _groups[index].copyWith(modifiedAt: DateTime.timestamp());
    }
  }

  @override
  Future<void> deleteGroup(int groupId) async {
    deleteGroupCount++;
    _groups.removeWhere((g) => g.id == groupId);
    for (var i = 0; i < _scripts.length; i++) {
      if (_scripts[i].groupId == groupId) {
        _scripts[i] = _scripts[i].copyWith(clearGroup: true);
      }
    }
  }

  @override
  Future<void> moveScriptsToGroup(List<ScriptFile> scripts) async {
    moveScriptsToGroupCount++;
    lastMovedScripts = List<ScriptFile>.from(scripts);
    for (final script in scripts) {
      final index = _scripts.indexWhere((s) => s.name == script.name);
      if (index >= 0) {
        _scripts[index] = _scripts[index].copyWith(
          groupId: script.groupId,
          sortOrder: script.sortOrder,
          clearGroup: script.groupId == null,
        );
      }
    }
  }

  // --- NativeBridge：脚本文件 ---

  @override
  Future<List<String>> listScriptFiles() async {
    listScriptFilesCount++;
    return _files.keys.toList();
  }

  @override
  Future<String> createScriptFile(String name, {String content = ''}) async {
    createScriptFileCount++;
    final path = '/scripts/$name.py';
    _scriptPaths[name] = path;
    _files[name] = content;
    return path;
  }

  @override
  Future<bool> deleteScriptFile(String name) async {
    deleteScriptFileCount++;
    _files.remove(name);
    _scriptPaths.remove(name);
    return true;
  }

  @override
  Future<bool> renameScriptFile(String oldName, String newName) async {
    renameScriptFileCount++;
    final content = _files.remove(oldName);
    if (content != null) _files[newName] = content;
    final path = _scriptPaths.remove(oldName);
    if (path != null) _scriptPaths[newName] = path.replaceAll(oldName, newName);
    return true;
  }

  @override
  Future<String> readScriptFile(String name) async {
    readScriptFileCount++;
    lastReadScriptName = name;
    return _files[name] ?? '';
  }

  @override
  Future<bool> saveScriptFile(String name, String content) async {
    saveScriptFileCount++;
    lastSavedScriptName = name;
    lastSavedContent = content;
    _files[name] = content;
    return true;
  }

  @override
  Future<String> importScriptFromUri(String uri, String name) async {
    importScriptFromUriCount++;
    lastImportUri = uri;
    final path = '/scripts/$name.py';
    _scriptPaths[name] = path;
    _files[name] = '';
    return path;
  }

  @override
  Future<bool> deleteScriptProject(String projectKey) async {
    deleteScriptProjectCount++;
    return true;
  }

  // --- 测试观测辅助 ---

  List<ScriptFile> get scripts => List.unmodifiable(_scripts);
  List<ScriptGroup> get groups => List.unmodifiable(_groups);
}
