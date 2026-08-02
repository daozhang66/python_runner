import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/script_file.dart';
import '../../../models/script_group.dart';
import '../../../providers/infrastructure_providers.dart';
import '../../../services/database_service.dart';
import '../../../services/native_bridge.dart';

/// 脚本工作台数据访问接口（Level 0 交付物）。
///
/// 封装迁移前 legacy ChangeNotifier 内部调用的全部 `DatabaseService` 与
/// `NativeBridge` 脚本方法，作为 Level 2 [ScriptWorkspaceController] 的唯一
/// 依赖入口。Controller 通过此抽象读取与变更脚本/分组，测试经
/// `ProviderScope.overrides` 注入 [FakeScriptRepository]（在 test/support 中），
/// 避免依赖 SQLite 与原生桥接。
///
/// 直接转发现有 [ScriptFile] / [ScriptGroup] 模型，不复制；脚本展示偏好仍由
/// `scriptWorkspaceUiProvider` 管理，不并入本 Repository。
///
/// 注意：本接口仅提供"数据访问"语义；分组排序、置顶提升、拖拽规则等业务逻辑
/// 留待 Level 2 的 Controller 实现，Repository 不持有排序算法。
abstract class ScriptRepository {
  // --- DatabaseService：脚本元数据 ---

  Future<List<ScriptFile>> getAllScripts();

  Future<ScriptFile?> getScript(String name);

  Future<void> upsertScript(ScriptFile script);

  Future<void> deleteScript(String name);

  Future<void> renameScript(String oldName, String newName, String newPath);

  Future<void> incrementRunCount(String name);

  Future<void> batchUpdateSortOrders(List<ScriptFile> scripts);

  // --- DatabaseService：分组 ---

  Future<List<ScriptGroup>> getAllGroups();

  Future<int> createGroup(ScriptGroup group);

  Future<void> renameGroup(int groupId, String name);

  Future<void> updateProjectMainFile(int groupId, String? mainFilePath);

  Future<void> touchGroup(int groupId);

  Future<void> deleteGroup(int groupId);

  Future<void> moveScriptsToGroup(List<ScriptFile> scripts);

  // --- NativeBridge：脚本文件 ---

  Future<List<String>> listScriptFiles();

  Future<String> createScriptFile(String name, {String content = ''});

  Future<bool> deleteScriptFile(String name);

  Future<bool> renameScriptFile(String oldName, String newName);

  Future<String> readScriptFile(String name);

  Future<bool> saveScriptFile(String name, String content);

  Future<String> importScriptFromUri(String uri, String name);

  Future<bool> deleteScriptProject(String projectKey);
}

/// 生产实现：组合 [DatabaseService] 与 [NativeBridge]。
///
/// 仅做转发，不引入额外业务逻辑；保持与迁移前 legacy ChangeNotifier 调用顺序一致。
class DatabaseScriptRepository implements ScriptRepository {
  DatabaseScriptRepository({
    required DatabaseService database,
    required NativeBridge bridge,
  })  : _database = database,
        _bridge = bridge;

  final DatabaseService _database;
  final NativeBridge _bridge;

  @override
  Future<List<ScriptFile>> getAllScripts() => _database.getAllScripts();

  @override
  Future<ScriptFile?> getScript(String name) => _database.getScript(name);

  @override
  Future<void> upsertScript(ScriptFile script) =>
      _database.upsertScript(script);

  @override
  Future<void> deleteScript(String name) => _database.deleteScript(name);

  @override
  Future<void> renameScript(
          String oldName, String newName, String newPath) =>
      _database.renameScript(oldName, newName, newPath);

  @override
  Future<void> incrementRunCount(String name) =>
      _database.incrementRunCount(name);

  @override
  Future<void> batchUpdateSortOrders(List<ScriptFile> scripts) =>
      _database.batchUpdateSortOrders(scripts);

  @override
  Future<List<ScriptGroup>> getAllGroups() => _database.getAllGroups();

  @override
  Future<int> createGroup(ScriptGroup group) => _database.createGroup(group);

  @override
  Future<void> renameGroup(int groupId, String name) =>
      _database.renameGroup(groupId, name);

  @override
  Future<void> updateProjectMainFile(int groupId, String? mainFilePath) =>
      _database.updateProjectMainFile(groupId, mainFilePath);

  @override
  Future<void> touchGroup(int groupId) => _database.touchGroup(groupId);

  @override
  Future<void> deleteGroup(int groupId) => _database.deleteGroup(groupId);

  @override
  Future<void> moveScriptsToGroup(List<ScriptFile> scripts) =>
      _database.moveScriptsToGroup(scripts);

  @override
  Future<List<String>> listScriptFiles() => _bridge.listScripts();

  @override
  Future<String> createScriptFile(String name, {String content = ''}) =>
      _bridge.createScript(name, content: content);

  @override
  Future<bool> deleteScriptFile(String name) => _bridge.deleteScript(name);

  @override
  Future<bool> renameScriptFile(String oldName, String newName) =>
      _bridge.renameScript(oldName, newName);

  @override
  Future<String> readScriptFile(String name) => _bridge.readScript(name);

  @override
  Future<bool> saveScriptFile(String name, String content) =>
      _bridge.saveScript(name, content);

  @override
  Future<String> importScriptFromUri(String uri, String name) =>
      _bridge.importScriptFromUri(uri, name);

  @override
  Future<bool> deleteScriptProject(String projectKey) =>
      _bridge.deleteScriptProject(projectKey);
}

/// 脚本 Repository Provider。测试通过 override 注入 fake。
final scriptRepositoryProvider = Provider<ScriptRepository>((ref) {
  return DatabaseScriptRepository(
    database: ref.watch(databaseServiceProvider),
    bridge: ref.watch(nativeBridgeProvider),
  );
});
