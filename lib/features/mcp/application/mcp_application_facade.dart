import '../domain/mcp_facade_models.dart';

/// MCP 应用服务门面（计划 §5.1）。
///
/// MCP Tool 处理器只依赖该抽象接口，不接触 Flutter Widget、BuildContext、
/// SQLite 或 MethodChannel；所有实现必须复用现有业务规则，保证 AI 与 App
/// 界面行为一致（AI 创建的脚本必须出现在首页列表）。
///
/// 约定：
/// - 输入在 Facade 入口再次校验（不能只依赖 MCP JSON Schema）；
/// - 业务失败抛 [McpToolException]（见 mcp_error_codes.dart）；
/// - 每个变更方法返回结构化结果。
abstract interface class McpApplicationFacade {
  // --- 基础 ---

  Future<McpAppStatus> getAppStatus();

  // --- 脚本与分组 ---

  Future<McpPage> listScripts({
    String? query,
    int? groupId,
    int limit = 100,
    String? cursor,
  });

  Future<McpScriptSummary> createScript({
    required String name,
    String content = '',
    int? groupId,
  });

  Future<McpTextFileContent> readScript(String name, {int maxChars = 200000});

  Future<McpScriptSummary> saveScript({
    required String name,
    required String content,
    int? expectedModifiedAt,
  });

  Future<List<McpGroupSummary>> listGroups();

  Future<McpGroupSummary> createGroup(String name);

  Future<McpGroupSummary> createProjectGroup({
    required String name,
    String? projectKey,
    String? mainFilePath,
    String? mainFileContent,
  });

  // --- 项目文件 ---

  Future<McpPage> listProjectFiles(
    String projectKey, {
    int limit = 200,
    String? cursor,
  });

  Future<McpTextFileContent> readProjectFile(
    String projectKey,
    String path, {
    int maxChars = 200000,
  });

  Future<McpProjectFileSummary> saveProjectFile({
    required String projectKey,
    required String path,
    required String content,
    int? expectedModifiedAt,
  });

  // --- 网络调试数据 ---

  Future<McpPage> listNetworkRecords(
    McpNetworkQuery query, {
    int limit = 50,
    String? cursor,
  });

  Future<McpNetworkRecord> getNetworkRecord(String id,
      {bool includeBody = false});

  // --- Python 库 ---

  Future<McpPage> listPackages({
    String? backend,
    String? query,
    int limit = 100,
    String? cursor,
  });

  Future<McpPackageInstallResult> installPackage({
    required String packageName,
    String? version,
    String? indexUrl,
    String? backend,
  });

  // --- 可访问文件系统（只读）---

  /// 返回 [McpDirectoryListing.accessible] 显式标识目录是否可访问；
  /// 权限不足时抛 DIRECTORY_NOT_ACCESSIBLE，不以空列表表达受限。
  Future<McpDirectoryListing> listAccessibleDirectory({
    required String path,
    int limit = 100,
    String? cursor,
    bool includeHidden = false,
  });

  Future<McpFileContent> readAccessibleFile({
    required String path,
    int maxBytes = 256 * 1024,
  });

  Future<void> createDirectory(String path, String name);
  Future<void> renameFileEntry(String path, String newName);
  Future<void> deleteFileEntry(String path);
  Future<void> writeTextFile(String path, String content);
}
