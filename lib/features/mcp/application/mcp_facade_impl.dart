import 'dart:async';
import 'dart:convert';

import '../../../models/script_group.dart';
import '../../../models/script_project_file.dart';
import '../../../runtime/runtime_manager.dart';
import '../../../runtime/runtime_package.dart' as runtime;
import '../../../services/app_logger.dart';
import '../../../services/http_inspector_store.dart' show HttpRecord;
import '../../../services/native_bridge.dart';
import '../../../services/project_path_validator.dart';
import '../../../services/script_name_validator.dart';
import '../../../services/script_project_service.dart';
import '../../network/application/network_inspector_repository.dart';
import '../../packages/application/package_repository.dart';
import '../../scripts/application/script_repository.dart';
import '../../scripts/application/script_workspace_controller.dart';
import '../domain/mcp_error_codes.dart';
import '../domain/mcp_facade_models.dart';
import '../domain/mcp_redaction.dart';
import '../domain/mcp_operation.dart';
import 'mcp_application_facade.dart';
import 'mcp_operation_registry.dart';

/// MCP 服务运行状态探针：由服务控制器注入，Facade 不感知传输层细节。
typedef McpServerStatusProbe = McpAppStatus Function(
  String appVersion,
  String runtimeBackend,
  bool linuxLikeAvailable,
  bool linuxLikeInstalled,
);

/// 生产 Facade：把 MCP 工具操作转发到现有应用服务层（计划 §5.2）。
///
/// - 脚本/分组写操作走 [ScriptWorkspaceController]，保证首页列表与 SQLite 同步；
/// - 项目文件复用 [ScriptProjectService] / [NativeBridge] 的路径校验；
/// - 网络记录复用 [NetworkInspectorRepository]（不直接读 JSONL）；
/// - 包安装复用 [PackageRepository]，并在本层做全局互斥；
/// - 文件系统复用文件选择器桥（只读，绝对路径，拒绝 content://）。
class AppMcpApplicationFacade implements McpApplicationFacade {
  AppMcpApplicationFacade({
    required ScriptRepository scriptRepository,
    required ScriptWorkspaceController workspaceController,
    required NativeBridge bridge,
    required NetworkInspectorRepository networkRepository,
    required PackageRepository packageRepository,
    required RuntimeManager runtimeManager,
    McpServerStatusProbe? statusProbe,
    McpOperationRegistry? operationRegistry,
    AppLogger? logger,
  })  : _scripts = scriptRepository,
        _workspace = workspaceController,
        _bridge = bridge,
        _network = networkRepository,
        _packages = packageRepository,
        _runtime = runtimeManager,
        _statusProbe = statusProbe,
        _operations = operationRegistry ?? McpOperationRegistry(),
        _logger = logger ?? AppLogger.instance;

  final ScriptRepository _scripts;
  final ScriptWorkspaceController _workspace;
  final NativeBridge _bridge;
  final NetworkInspectorRepository _network;
  final PackageRepository _packages;
  final RuntimeManager _runtime;
  final McpServerStatusProbe? _statusProbe;
  final McpOperationRegistry _operations;
  final AppLogger _logger;

  /// 输入与输出限制（计划 §9.1 / §9.3）。
  static const int maxLimit = 500;
  static const int maxNameLength = 100;
  static const int maxQueryLength = 200;
  static const int maxPathLength = 1024;
  static const int maxWriteContentBytes = 2 * 1024 * 1024;
  static const int maxReadChars = 200000;
  static const int maxFileBytes = 256 * 1024;

  /// 文件读取硬上限：先探测文件大小，超过此值直接拒绝，避免把整个
  /// 大文件读入内存后才截断（返回内容仍受 [maxFileBytes] 限制）。
  static const int maxReadableFileBytes = 4 * 1024 * 1024;
  static const int networkBodyBudgetChars = 16 * 1024;

  /// package.install 长任务的最大执行时间（与工具超时一致）。
  static const Duration installMaxDuration = Duration(minutes: 15);

  /// 包安装全局互斥（计划 §10.1：同一运行时同时只允许一个安装任务）。
  bool _installActive = false;

  ScriptProjectService get _projectService => ScriptProjectService(_bridge);

  // ── 基础 ──

  @override
  Future<McpAppStatus> getAppStatus() async {
    String appVersion = '';
    try {
      final info = await _bridge.getAppInfo();
      appVersion = info['version'] ?? '';
    } catch (e) {
      _logger.warn('MCP getAppStatus 读取应用信息失败: $e', source: 'McpFacade');
    }
    final backend = _runtime.activeBackendId;
    bool linuxLikeAvailable = false;
    bool linuxLikeInstalled = false;
    try {
      final info = await _bridge.getLinuxLikeRuntimeInfo();
      linuxLikeAvailable = info['available'] == 'true';
      linuxLikeInstalled = info['installed'] == 'true';
    } catch (e) {
      _logger.warn('MCP getAppStatus 读取运行时信息失败: $e', source: 'McpFacade');
    }
    if (_statusProbe != null) {
      return _statusProbe(
        appVersion,
        backend,
        linuxLikeAvailable,
        linuxLikeInstalled,
      );
    }
    return McpAppStatus(
      appVersion: appVersion,
      runtimeBackend: backend,
      linuxLikeAvailable: linuxLikeAvailable,
      linuxLikeInstalled: linuxLikeInstalled,
      mcpRunning: false,
      mcpPort: 0,
    );
  }

  // ── 脚本 ──

  @override
  Future<McpPage> listScripts({
    String? query,
    int? groupId,
    int limit = 100,
    String? cursor,
  }) async {
    final offset = _decodeCursor(cursor);
    final safeLimit = _normalizeLimit(limit);
    _validateQuery(query);
    if (groupId != null && groupId < 0) {
      throw _invalidArgument('group_id cannot be negative');
    }

    final all = await _scripts.getAllScripts();
    all.sort((a, b) {
      final pin = (b.isPinned ? 1 : 0).compareTo(a.isPinned ? 1 : 0);
      if (pin != 0) return pin;
      return a.sortOrder.compareTo(b.sortOrder);
    });
    final filtered = all.where((script) {
      if (groupId != null && script.groupId != groupId) return false;
      if (query != null &&
          !script.name.toLowerCase().contains(query.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();
    return _paginate(
      filtered
          .map((s) => McpScriptSummary(
                name: s.name,
                modifiedAt: s.modifiedAt,
                createdAt: s.createdAt,
                groupId: s.groupId,
                runCount: s.runCount,
                isPinned: s.isPinned,
              ).toMap())
          .toList(),
      offset,
      safeLimit,
    );
  }

  @override
  Future<McpScriptSummary> createScript({
    required String name,
    String content = '',
    int? groupId,
  }) async {
    final safeName = _validateScriptName(name);
    _validateContent(content);
    await _ensureWorkspaceLoaded();

    final existing = await _scripts.getScript(safeName);
    final fileNames = await _scripts.listScriptFiles();
    if (existing != null || fileNames.contains(safeName)) {
      throw McpToolException(
        McpErrorCodes.scriptAlreadyExists,
        'Script already exists: $safeName',
        false,
        {'name': safeName},
      );
    }
    if (groupId != null) {
      final groups = await _scripts.getAllGroups();
      if (!groups.any((group) => group.id == groupId)) {
        throw _invalidArgument('Group not found: $groupId');
      }
    }

    final created = await _workspace.createScript(
      safeName,
      content: content,
      groupId: groupId,
    );
    if (!created) {
      throw McpToolException(
        McpErrorCodes.internalError,
        'Failed to create script: $safeName',
      );
    }
    final script = await _scripts.getScript(safeName);
    if (script == null) {
      throw McpToolException(
        McpErrorCodes.internalError,
        'Script was created but metadata is missing: $safeName',
      );
    }
    return McpScriptSummary(
      name: script.name,
      modifiedAt: script.modifiedAt,
      createdAt: script.createdAt,
      groupId: script.groupId,
      runCount: script.runCount,
      isPinned: script.isPinned,
    );
  }

  @override
  Future<McpTextFileContent> readScript(String name,
      {int maxChars = maxReadChars}) async {
    final safeName = _validateScriptName(name);
    if (maxChars < 1 || maxChars > maxReadChars) {
      throw _invalidArgument('max_chars is out of range (1..$maxReadChars)');
    }
    final script = await _scripts.getScript(safeName);
    if (script == null) {
      final fileNames = await _scripts.listScriptFiles();
      if (!fileNames.contains(safeName)) {
        throw McpToolException(
          McpErrorCodes.scriptNotFound,
          'Script not found: $safeName',
          false,
          {'name': safeName},
        );
      }
    }
    final content = await _scripts.readScriptFile(safeName);
    if (content.length > maxChars) {
      throw McpToolException(
        McpErrorCodes.fileTooLarge,
        'Script content exceeds the limit (${content.length} characters > $maxChars)',
        false,
        {'size': content.length, 'max_chars': maxChars, 'name': safeName},
      );
    }
    return McpTextFileContent(
      content: content,
      size: content.length,
      modifiedAt: script?.modifiedAt ?? DateTime.now(),
    );
  }

  @override
  Future<McpScriptSummary> saveScript({
    required String name,
    required String content,
    int? expectedModifiedAt,
  }) async {
    final safeName = _validateScriptName(name);
    _validateContent(content);
    await _ensureWorkspaceLoaded();

    final script = await _scripts.getScript(safeName);
    if (script == null) {
      throw McpToolException(
        McpErrorCodes.scriptNotFound,
        'Script not found: $safeName',
        false,
        {'name': safeName},
      );
    }
    final saved =
        await _workspace.saveScript(safeName, content, beforeSave: () async {
      final current = await _scripts.getScript(safeName);
      if (current == null) {
        throw McpToolException(
            McpErrorCodes.scriptNotFound, 'Script not found: $safeName');
      }
      _checkConflict(expectedModifiedAt, current.modifiedAt,
          'Script changed after it was read: $safeName');
    });
    if (!saved) {
      throw McpToolException(
          McpErrorCodes.internalError, 'Failed to save script: $safeName');
    }
    final updated = await _scripts.getScript(safeName);
    return McpScriptSummary(
      name: safeName,
      modifiedAt: updated?.modifiedAt ?? DateTime.now(),
      createdAt: updated?.createdAt ?? script.createdAt,
      groupId: updated?.groupId ?? script.groupId,
      runCount: updated?.runCount ?? script.runCount,
      isPinned: updated?.isPinned ?? script.isPinned,
    );
  }

  // ── 分组与项目组 ──

  @override
  Future<List<McpGroupSummary>> listGroups() async {
    final groups = await _scripts.getAllGroups();
    groups.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return groups.map((group) => _groupSummary(group)).toList(growable: false);
  }

  @override
  Future<McpGroupSummary> createGroup(String name) async {
    final trimmed = _validateGroupName(name);
    await _ensureWorkspaceLoaded();
    final groups = await _scripts.getAllGroups();
    if (groups.any((group) => group.name == trimmed)) {
      throw McpToolException(
        McpErrorCodes.groupAlreadyExists,
        'Group already exists: $trimmed',
        false,
        {'name': trimmed},
      );
    }
    final created = await _workspace.createGroup(trimmed);
    if (!created) {
      throw McpToolException(
          McpErrorCodes.internalError, 'Failed to create group: $trimmed');
    }
    final group = _workspace.groups.firstWhere(
      (item) => item.name == trimmed,
      orElse: () => throw McpToolException(
        McpErrorCodes.internalError,
        'Failed to create group: $trimmed',
      ),
    );
    return _groupSummary(group);
  }

  @override
  Future<McpGroupSummary> createProjectGroup({
    required String name,
    String? projectKey,
    String? mainFilePath,
    String? mainFileContent,
  }) async {
    final trimmed = _validateGroupName(name);
    await _ensureWorkspaceLoaded();

    // 1. 校验 projectKey / mainFilePath。
    String safeKey;
    try {
      safeKey = projectKey == null || projectKey.trim().isEmpty
          ? _generateProjectKey()
          : ProjectPathValidator.normalizeProjectKey(projectKey);
    } on FormatException catch (e) {
      throw McpToolException(
        McpErrorCodes.projectPathInvalid,
        'Invalid project key: ${e.message}',
        false,
        {'project_key': projectKey ?? ''},
      );
    }
    final effectiveMainPath = mainFilePath?.trim().isEmpty == true
        ? 'main.py'
        : (mainFilePath ?? 'main.py');
    String safeMainPath;
    try {
      safeMainPath =
          ProjectPathValidator.validateMainFilePath(effectiveMainPath);
    } on FormatException catch (e) {
      throw McpToolException(
        McpErrorCodes.projectPathInvalid,
        'Invalid main file path: ${e.message}',
        false,
        {'main_file_path': effectiveMainPath},
      );
    }

    // 名称与 key 唯一性。
    final groups = await _scripts.getAllGroups();
    if (groups.any((group) => group.name == trimmed)) {
      throw McpToolException(
        McpErrorCodes.groupAlreadyExists,
        'Group already exists: $trimmed',
        false,
        {'name': trimmed},
      );
    }
    if (groups.any((group) => group.projectKey == safeKey)) {
      throw McpToolException(
        McpErrorCodes.groupAlreadyExists,
        'Project key is already in use: $safeKey',
        false,
        {'project_key': safeKey},
      );
    }

    // 2. 创建项目目录；数据库失败时回滚目录。
    try {
      await _projectService.createEmptyProject(safeKey);
    } catch (e) {
      _logger.error('MCP 创建项目目录失败: $e', source: 'McpFacade');
      throw McpToolException(
        McpErrorCodes.internalError,
        'Failed to create project directory: $safeKey',
      );
    }

    final group = await _workspace.createProjectGroup(
      trimmed,
      mainFilePath: safeMainPath,
      projectKey: safeKey,
    );
    if (group == null || group.id == null) {
      await _tryRollbackProject(safeKey);
      throw McpToolException(
        McpErrorCodes.internalError,
        'Failed to create project group; the project directory was rolled back: $trimmed',
      );
    }

    // 3. 写入主程序；失败时删除刚创建的分组（连带项目目录），不留半成品。
    final content = mainFileContent ?? 'print("Hello from $trimmed")\n';
    bool fileWritten = false;
    try {
      fileWritten =
          await _bridge.saveProjectFile(safeKey, safeMainPath, content);
    } catch (e) {
      _logger.error('MCP 写入项目主程序失败: $e', source: 'McpFacade');
    }
    if (!fileWritten) {
      await _workspace.deleteGroup(group.id!);
      throw McpToolException(
        McpErrorCodes.internalError,
        'Failed to write the project main program; the project group was rolled back: $safeMainPath',
      );
    }
    return _groupSummary(group);
  }

  // ── 项目文件 ──

  @override
  Future<McpPage> listProjectFiles(
    String projectKey, {
    int limit = 200,
    String? cursor,
  }) async {
    final group = await _requireProjectGroup(projectKey);
    final offset = _decodeCursor(cursor);
    final safeLimit = _normalizeLimit(limit);
    final files = await _projectService.loadProjectFiles(group);
    files.sort((a, b) {
      final dir = (b.isDirectory ? 1 : 0).compareTo(a.isDirectory ? 1 : 0);
      if (dir != 0) return dir;
      return a.path.toLowerCase().compareTo(b.path.toLowerCase());
    });
    return _paginate(
      files.map((file) => _projectFileSummary(file).toMap()).toList(),
      offset,
      safeLimit,
    );
  }

  @override
  Future<McpTextFileContent> readProjectFile(
    String projectKey,
    String path, {
    int maxChars = maxReadChars,
  }) async {
    final group = await _requireProjectGroup(projectKey);
    final safePath = _validateRelativePath(path);
    if (maxChars < 1 || maxChars > maxReadChars) {
      throw _invalidArgument('max_chars is out of range (1..$maxReadChars)');
    }
    final files = await _projectService.loadProjectFiles(group);
    final file = files.where((item) => item.path == safePath).firstOrNull;
    if (file == null || file.isDirectory) {
      throw McpToolException(
        McpErrorCodes.projectNotFound,
        'Project file not found: $safePath',
        false,
        {'project_key': group.projectKey, 'path': safePath},
      );
    }
    final content = await _projectService.readProjectFile(group, safePath);
    if (content.length > maxChars) {
      throw McpToolException(
        McpErrorCodes.fileTooLarge,
        'File content exceeds the limit (${content.length} characters > $maxChars)',
        false,
        {'size': content.length, 'max_chars': maxChars, 'path': safePath},
      );
    }
    return McpTextFileContent(
      content: content,
      size: content.length,
      modifiedAt: file.modifiedAt,
    );
  }

  @override
  Future<McpProjectFileSummary> saveProjectFile({
    required String projectKey,
    required String path,
    required String content,
    int? expectedModifiedAt,
  }) async {
    final group = await _requireProjectGroup(projectKey);
    final safePath = _validateRelativePath(path);
    _validateContent(content);

    final files = await _projectService.loadProjectFiles(group);
    final existing = files.where((item) => item.path == safePath).firstOrNull;
    if (existing != null && existing.isDirectory) {
      throw _invalidArgument(
          'Target is a directory and cannot be saved as a file: $safePath');
    }
    if (expectedModifiedAt != null) {
      if (existing == null) {
        throw McpToolException(
          McpErrorCodes.writeConflict,
          'File does not exist but expected_modified_at was supplied; create it first or omit conflict detection',
          false,
          {'path': safePath},
        );
      }
      _checkConflict(
        expectedModifiedAt,
        existing.modifiedAt,
        'File changed after it was read: $safePath',
      );
    }

    final bool saved;
    try {
      saved = await _bridge.saveProjectFile(
          group.projectKey!, safePath, content,
          expectedModifiedAt: expectedModifiedAt);
    } on NativeBridgeException catch (e) {
      if (e.rawCode == '1047') {
        throw McpToolException(McpErrorCodes.writeConflict,
            'Project file changed after it was read: $safePath');
      }
      rethrow;
    }
    if (!saved) {
      throw McpToolException(
        McpErrorCodes.internalError,
        'Failed to save project file: $safePath',
      );
    }
    final refreshed = await _projectService.loadProjectFiles(group);
    final savedEntry =
        refreshed.where((item) => item.path == safePath).firstOrNull;
    if (savedEntry == null) {
      // 目录可能是新建的但列表刷新失败；按保存成功处理并返回合成摘要。
      return McpProjectFileSummary(
        path: safePath,
        name: safePath.split('/').last,
        isDirectory: false,
        size: content.length,
        modifiedAt: DateTime.now(),
      );
    }
    return _projectFileSummary(savedEntry);
  }

  // ── 网络记录 ──

  @override
  Future<McpPage> listNetworkRecords(
    McpNetworkQuery query, {
    int limit = 50,
    String? cursor,
  }) async {
    final offset = _decodeCursor(cursor);
    final safeLimit = _normalizeLimit(limit);
    _validateNetworkQuery(query);

    await _network.ensureLoaded();
    final records = List.of(_network.records)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final filtered = records.where((record) {
      if (query.domain != null &&
          !_hostOf(record.url).contains(query.domain!.toLowerCase())) {
        return false;
      }
      if (query.method != null &&
          record.method.toUpperCase() != query.method!.toUpperCase()) {
        return false;
      }
      if (query.statusClass != null &&
          !_statusMatches(record, query.statusClass!)) {
        return false;
      }
      if (query.since != null && record.timestamp.isBefore(query.since!)) {
        return false;
      }
      if (query.until != null && record.timestamp.isAfter(query.until!)) {
        return false;
      }
      return true;
    }).toList();
    return _paginate(
      filtered.map(_networkSummary).toList(),
      offset,
      safeLimit,
    );
  }

  @override
  Future<McpNetworkRecord> getNetworkRecord(String id,
      {bool includeBody = false}) async {
    if (id.isEmpty || id.length > 128) {
      throw _invalidArgument('Record ID is invalid');
    }
    await _network.ensureLoaded();
    final record = _network.records.where((item) => item.id == id).firstOrNull;
    if (record == null) {
      throw McpToolException(
        McpErrorCodes.networkRecordNotFound,
        'Network record not found: $id',
        false,
        {'id': id},
      );
    }
    var truncated = record.responseBodyTruncated;
    String? requestBody;
    String? responseBody;
    if (includeBody) {
      final (reqBody, reqTruncated) = McpRedactor.truncateBody(
        record.requestBody,
        networkBodyBudgetChars,
      );
      final (respBody, respTruncated) = McpRedactor.truncateBody(
        record.responseBodyPreview,
        networkBodyBudgetChars,
      );
      requestBody = reqBody;
      responseBody = respBody;
      truncated = truncated || reqTruncated || respTruncated;
    }
    return McpNetworkRecord(
      id: record.id,
      timestamp: record.timestamp,
      method: record.method,
      url: McpRedactor.sanitizeUrl(record.url),
      domain: _hostOf(record.url),
      statusCode: record.statusCode,
      durationMs: record.durationMs,
      library: record.library,
      requestSize: record.requestBody?.length ?? 0,
      responseSize: record.responseBodyBytes,
      isError: record.isError,
      redacted: true,
      truncated: truncated,
      requestHeaders: McpRedactor.redactHeaders(record.requestHeaders),
      responseHeaders: record.responseHeaders == null
          ? null
          : McpRedactor.redactHeaders(record.responseHeaders!),
      requestBody: requestBody,
      responseBody: responseBody,
      errorType: record.errorType,
      errorMessage: record.errorMessage,
    );
  }

  // ── Python 库 ──

  @override
  Future<McpPage> listPackages({
    String? backend,
    String? query,
    int limit = 100,
    String? cursor,
  }) async {
    _validateBackendParam(backend);
    final offset = _decodeCursor(cursor);
    final safeLimit = _normalizeLimit(limit);
    _validateQuery(query);

    final packages = await _packages.listPackages();
    packages.sort((a, b) => a.name.compareTo(b.name));
    final filtered = packages.where((package) {
      if (query != null &&
          !package.name.toLowerCase().contains(query.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();
    return _paginate(
      filtered
          .map((package) => McpPackageSummary(
                name: package.name,
                version: package.version,
                isUserPackage: package.isUserPackage,
                integrityStatus: package.integrityStatus,
              ).toMap())
          .toList(),
      offset,
      safeLimit,
    );
  }

  @override
  Future<McpPackageInstallResult> installPackage({
    required String packageName,
    String? version,
    String? indexUrl,
    String? backend,
  }) async {
    _validateBackendParam(backend);
    _validatePackageName(packageName);
    if (version != null) _validateVersion(version);
    if (indexUrl != null) _validateIndexUrl(indexUrl);

    if (_installActive) {
      throw McpToolException(
        McpErrorCodes.packageInstallBusy,
        'An installation is already running; try again later',
        true,
      );
    }

    final activeBackend = _runtime.activeBackendId;
    // 长任务登记：operation.get_status 可查询进度与结果（计划 §10.2）。
    final operation = _operations.begin(
      kind: 'package.install',
      description: 'Install $packageName'
          '${version == null ? '' : '@$version'}'
          '${indexUrl == null ? '' : ' (index: ${Uri.tryParse(indexUrl)?.host ?? indexUrl})'}',
      maxDuration: installMaxDuration,
    );
    // Reserve before yielding so another call cannot start a second install.
    _installActive = true;
    unawaited(
        _runInstall(operation, packageName, version, indexUrl, activeBackend));
    return McpPackageInstallResult(
      success: false,
      accepted: true,
      message:
          'Installation submitted; query operation.get_status for the result',
      backend: activeBackend,
      operationId: operation.id,
    );
  }

  Future<void> _runInstall(McpOperation operation, String packageName,
      String? version, String? indexUrl, String activeBackend) async {
    StreamSubscription<runtime.PackageInstallProgress>? progressSubscription;
    final timer = Timer(installMaxDuration, () {
      _operations.finish(operation,
          failureReason:
              'Installation timed out; the underlying task may still be running and will not retry automatically');
    });
    try {
      progressSubscription = _packages.packageInstallProgressStream.listen(
        (progress) => _operations.reportProgress(
          operation,
          '${progress.status}: ${progress.message}',
        ),
        onError: (Object error) =>
            _operations.reportProgress(operation, 'Failed to read progress'),
      );
      final result = await _packages.installPackage(
        runtime.PackageInstallRequest(
          packageName: packageName,
          version: version,
          indexUrl: indexUrl,
        ),
      );
      _operations.finish(
        operation,
        failureReason:
            result.success ? null : 'Installation failed: $packageName',
        result: {
          'success': result.success,
          'backend': activeBackend,
          'package_name': packageName
        },
      );
    } catch (e) {
      _operations.finish(operation,
          failureReason: 'Installation failed: $packageName');
    } finally {
      timer.cancel();
      await progressSubscription?.cancel();
      _installActive = false;
    }
  }

  // ── 可访问文件系统（只读）──

  String _mutablePath(String path) {
    final safe = _validateAbsolutePath(path);
    if (safe == '/' ||
        ['/system', '/proc', '/sys', '/dev']
            .any((prefix) => safe == prefix || safe.startsWith('$prefix/'))) {
      throw McpToolException(
          McpErrorCodes.mcpForbidden, 'Modifying system paths is not allowed');
    }
    return safe;
  }

  String _entryName(String name) {
    if (name.trim().isEmpty ||
        name == '.' ||
        name == '..' ||
        name.length > 255 ||
        name.contains('/') ||
        name.contains('\\') ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(name)) {
      throw _invalidArgument('File or directory name is invalid');
    }
    return name;
  }

  @override
  Future<void> createDirectory(String path, String name) =>
      _bridge.createFileManagerDirectory(_mutablePath(path), _entryName(name));

  @override
  Future<void> renameFileEntry(String path, String newName) =>
      _bridge.renameFileManagerEntry(_mutablePath(path), _entryName(newName));

  @override
  Future<void> deleteFileEntry(String path) =>
      _bridge.deleteFileManagerEntry(_mutablePath(path));

  @override
  Future<void> writeTextFile(String path, String content) async {
    final safe = _mutablePath(path);
    _validateContent(content);
    await _bridge.writeFileManagerFile(safe, content);
  }

  @override
  Future<McpDirectoryListing> listAccessibleDirectory({
    required String path,
    int limit = 100,
    String? cursor,
    bool includeHidden = false,
  }) async {
    final safePath = _validateAbsolutePath(path);
    final offset = _decodeCursor(cursor);
    final safeLimit = _normalizeLimit(limit);

    final List<Map<String, dynamic>> entries;
    try {
      final raw = await _bridge.listFilePickerDirectory(safePath);
      final visible = includeHidden
          ? raw
          : raw.where((entry) => !entry.name.startsWith('.')).toList();
      visible.sort((a, b) {
        final dir = (b.isDirectory ? 1 : 0).compareTo(a.isDirectory ? 1 : 0);
        if (dir != 0) return dir;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      entries = visible
          .map((entry) => McpFileEntry(
                path: entry.path,
                name: entry.name,
                isDirectory: entry.isDirectory,
                size: entry.size,
                modifiedAt: entry.modifiedAt,
              ).toMap())
          .toList();
    } on NativeBridgeException catch (e) {
      throw McpToolException(
        McpErrorCodes.directoryNotAccessible,
        'Directory is inaccessible (app permission limited or path missing): $safePath',
        false,
        {'path': safePath, 'native_error': e.message},
      );
    } catch (e) {
      throw McpToolException(
        McpErrorCodes.directoryNotAccessible,
        'Directory is inaccessible: $safePath',
        false,
        {'path': safePath},
      );
    }
    // 列表调用成功即视为可访问；空列表不代表权限受限（P2 评审修正）。
    return McpDirectoryListing(
      page: _paginate(entries, offset, safeLimit),
      accessible: true,
    );
  }

  @override
  Future<McpFileContent> readAccessibleFile({
    required String path,
    int maxBytes = maxFileBytes,
  }) async {
    final safePath = _validateAbsolutePath(path);
    if (maxBytes < 1 || maxBytes > maxFileBytes) {
      throw _invalidArgument('max_bytes is out of range (1..$maxFileBytes)');
    }

    // 先探测文件大小：超过硬上限直接拒绝，不把大文件读入内存（P1 评审修正）。
    // Probe is only an optimization; the native reader enforces the limit.
    final probe = await _probeFileEntry(safePath);
    if (probe.isDirectory) {
      throw McpToolException(
        McpErrorCodes.fileNotFound,
        'Target is a directory and cannot be read as a file: $safePath',
        false,
        {'path': safePath},
      );
    }
    final probeSize = probe.size;
    if (probeSize != null && probeSize > maxReadableFileBytes) {
      throw McpToolException(
        McpErrorCodes.fileTooLarge,
        'File exceeds the read limit ($probeSize bytes > $maxReadableFileBytes); process it in chunks or use a script',
        false,
        {
          'path': safePath,
          'size': probeSize,
          'max_bytes': maxReadableFileBytes
        },
      );
    }

    final List<int> bytes;
    try {
      bytes = await _bridge.readFileBounded(safePath,
          maxBytes: maxReadableFileBytes);
    } on NativeBridgeException catch (e) {
      if (e.rawCode == '1046') {
        throw McpToolException(
            McpErrorCodes.fileTooLarge, 'File exceeds the read limit');
      }
      throw McpToolException(
          McpErrorCodes.fileNotFound, 'File cannot be read: $safePath');
    } catch (e) {
      throw McpToolException(
        McpErrorCodes.fileNotFound,
        'File cannot be read (missing or inaccessible): $safePath',
        false,
        {'path': safePath},
      );
    }
    if (bytes.length > maxReadableFileBytes) {
      throw McpToolException(
        McpErrorCodes.fileTooLarge,
        'File exceeds the read limit (${bytes.length} bytes > $maxReadableFileBytes)',
        false,
        {
          'path': safePath,
          'size': bytes.length,
          'max_bytes': maxReadableFileBytes
        },
      );
    }
    if (bytes.isEmpty) {
      return const McpFileContent(size: 0, content: '');
    }

    // 二进制判断：NUL 字节或 UTF-8 解码失败（计划 §6.5）。
    final truncated = bytes.length > maxBytes;
    final slice = truncated ? bytes.sublist(0, maxBytes) : bytes;
    if (slice.contains(0)) {
      return McpFileContent(size: bytes.length, isBinary: true);
    }
    try {
      final content = _decodeUtf8(slice);
      return McpFileContent(
        size: bytes.length,
        content: content,
        truncated: truncated,
      );
    } on FormatException {
      return McpFileContent(size: bytes.length, isBinary: true);
    }
  }

  /// 通过父目录列表探测目标文件的大小与类型。
  ///
  /// 返回 null size 表示未知（父目录列表失败或未命中）；命中目录条目时
  /// [isDirectory] 为 true。
  Future<({int? size, bool isDirectory})> _probeFileEntry(
    String safePath,
  ) async {
    final slash = safePath.lastIndexOf('/');
    final parent = slash <= 0 ? '/' : safePath.substring(0, slash);
    final name = safePath.substring(slash + 1);
    if (name.isEmpty) return (size: null, isDirectory: true);
    try {
      final entries = await _bridge.listFilePickerDirectory(parent);
      for (final entry in entries) {
        if (entry.path == safePath || entry.name == name) {
          return (size: entry.size, isDirectory: entry.isDirectory);
        }
      }
      return (size: null, isDirectory: false);
    } catch (_) {
      return (size: null, isDirectory: false);
    }
  }

  // ── 内部工具 ──

  Future<void> _ensureWorkspaceLoaded() async {
    if (_workspace.loading) {
      // 等待当前加载完成（粗粒度：加载队列很短）。
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return;
    }
    if (_workspace.scripts.isEmpty && _workspace.groups.isEmpty) {
      await _workspace.load();
    }
  }

  /// UTF-8 严格解码：失败抛 [FormatException]，调用方据此判定二进制。
  String _decodeUtf8(List<int> bytes) => utf8.decode(bytes);

  String _generateProjectKey() =>
      'project_${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';

  Future<void> _tryRollbackProject(String projectKey) async {
    try {
      await _bridge.deleteScriptProject(projectKey);
    } catch (e) {
      _logger.error(
        'MCP 回滚项目目录失败: $projectKey: $e',
        source: 'McpFacade',
      );
    }
  }

  Future<ScriptGroup> _requireProjectGroup(String projectKey) async {
    if (projectKey.isEmpty || projectKey.length > maxNameLength) {
      throw _invalidArgument('project_key is invalid');
    }
    final groups = await _scripts.getAllGroups();
    ScriptGroup? match;
    for (final group in groups) {
      if (group.isProject && group.projectKey == projectKey) {
        match = group;
        break;
      }
    }
    if (match == null) {
      throw McpToolException(
        McpErrorCodes.projectNotFound,
        'Project not found: $projectKey',
        false,
        {'project_key': projectKey},
      );
    }
    return match;
  }

  McpGroupSummary _groupSummary(ScriptGroup group) => McpGroupSummary(
        id: group.id ?? 0,
        name: group.name,
        isProject: group.isProject,
        projectKey: group.projectKey,
        mainFilePath: group.mainFilePath,
        modifiedAt: group.modifiedAt,
      );

  McpProjectFileSummary _projectFileSummary(ScriptProjectFile file) =>
      McpProjectFileSummary(
        path: file.path,
        name: file.name,
        isDirectory: file.isDirectory,
        size: file.size,
        modifiedAt: file.modifiedAt,
      );

  Map<String, dynamic> _networkSummary(HttpRecord record) => McpNetworkRecord(
        id: record.id,
        timestamp: record.timestamp,
        method: record.method,
        url: McpRedactor.sanitizeUrl(record.url),
        domain: _hostOf(record.url),
        statusCode: record.statusCode,
        durationMs: record.durationMs,
        library: record.library,
        requestSize: record.requestBody?.length ?? 0,
        responseSize: record.responseBodyBytes,
        isError: record.isError,
        redacted: true,
        truncated: record.responseBodyTruncated,
      ).toSummaryMap();

  McpPage _paginate(List<Map<String, dynamic>> all, int offset, int limit) {
    final start = offset >= all.length ? all.length : offset;
    final end = start + limit >= all.length ? all.length : start + limit;
    final items = all.sublist(start, end);
    return McpPage(
      items: items,
      nextCursor: end < all.length ? McpCursor.encode(end) : null,
    );
  }

  McpToolException _invalidArgument(String message) =>
      McpToolException(McpErrorCodes.invalidArgument, message);

  String _validateScriptName(String name) {
    if (name.length > maxNameLength + 16) {
      throw _invalidArgument('Script name is too long');
    }
    try {
      return ScriptNameValidator.normalize(name);
    } on FormatException catch (e) {
      throw _invalidArgument('Invalid script name: ${e.message}');
    }
  }

  String _validateGroupName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > maxNameLength) {
      throw _invalidArgument('Group name is empty or too long');
    }
    return trimmed;
  }

  String _validateRelativePath(String path) {
    if (path.length > maxPathLength) {
      throw _invalidArgument('Path is too long');
    }
    try {
      return ProjectPathValidator.normalizeRelativePath(path);
    } on FormatException catch (e) {
      throw McpToolException(
        McpErrorCodes.projectPathInvalid,
        'Invalid project-relative path: ${e.message}',
        false,
        {'path': path},
      );
    }
  }

  String _validateAbsolutePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty || trimmed.length > maxPathLength) {
      throw _invalidArgument('Path is empty or too long');
    }
    if (trimmed.startsWith('content://')) {
      throw _invalidArgument(
          'content:// URIs are unsupported; use an absolute path');
    }
    if (!trimmed.startsWith('/')) {
      throw _invalidArgument('Path must be absolute and start with /');
    }
    if (trimmed.contains(r'\') ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(trimmed)) {
      throw _invalidArgument('Path contains invalid characters');
    }
    final segments = trimmed.split('/').skip(1).toList();
    if (segments.any((segment) => segment == '.' || segment == '..')) {
      throw _invalidArgument('Path cannot contain . or .. segments');
    }
    return trimmed;
  }

  void _validateQuery(String? query) {
    if (query != null && query.length > maxQueryLength) {
      throw _invalidArgument('Search query is too long');
    }
  }

  /// 写入内容限制按 UTF-8 字节数计算（P2 评审修正）：
  /// UTF-16 长度是字节数下界，先用它做廉价预检，接近上限时再精确编码统计。
  void _validateContent(String content) {
    var sizeBytes = content.length;
    if (sizeBytes > maxWriteContentBytes ~/ 3 &&
        sizeBytes <= maxWriteContentBytes) {
      sizeBytes = utf8.encode(content).length;
    }
    if (sizeBytes > maxWriteContentBytes) {
      throw McpToolException(
        McpErrorCodes.fileTooLarge,
        'Content exceeds the write limit ($sizeBytes > $maxWriteContentBytes bytes)',
        false,
        {'size_bytes': sizeBytes, 'max_bytes': maxWriteContentBytes},
      );
    }
  }

  void _validateBackendParam(String? backend) {
    const allowed = {'active', 'chaquopy', 'linux_like'};
    if (backend != null && !allowed.contains(backend)) {
      throw _invalidArgument(
          'backend supports active / chaquopy / linux_like only');
    }
    if (backend != null &&
        backend != 'active' &&
        backend != _runtime.activeBackendId) {
      throw McpToolException(
        McpErrorCodes.packageBackendUnavailable,
        'Requested backend ($backend) is not the active runtime (${_runtime.activeBackendId}); switch runtimes in app settings first',
        false,
        {'requested': backend, 'active': _runtime.activeBackendId},
      );
    }
  }

  void _validatePackageName(String name) {
    final regex = RegExp(r'^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?$');
    if (name.isEmpty || name.length > maxNameLength || !regex.hasMatch(name)) {
      throw _invalidArgument('Package name is invalid: $name');
    }
  }

  void _validateVersion(String version) {
    // PEP 440 常用子集：1.0 / 2.32.3 / 3.11.0rc1 / 1.0.0.post1 / 1.0.dev2。
    final regex = RegExp(r'^\d+(\.\d+)*((a|b|rc|\.post|\.dev)\d*)*$');
    if (version.isEmpty || version.length > 64 || !regex.hasMatch(version)) {
      throw _invalidArgument('Version is invalid: $version');
    }
  }

  void _validateIndexUrl(String indexUrl) {
    if (indexUrl.length > 2048) {
      throw _invalidArgument('index_url is too long');
    }
    final uri = Uri.tryParse(indexUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw _invalidArgument('index_url must be an http(s) URL');
    }
    // 禁止 userinfo：凭据不应出现在 URL 中（P1 评审修正）。
    if (uri.userInfo.isNotEmpty) {
      throw _invalidArgument('index_url cannot contain username or password');
    }
  }

  void _validateNetworkQuery(McpNetworkQuery query) {
    _validateQuery(query.domain);
    if (query.method != null &&
        (query.method!.isEmpty || query.method!.length > 16)) {
      throw _invalidArgument('method is invalid');
    }
    if (query.statusClass != null &&
        !McpNetworkQuery.statusClasses.contains(query.statusClass)) {
      throw _invalidArgument(
          'status_class supports ${McpNetworkQuery.statusClasses.join(' / ')} only');
    }
    if (query.since != null &&
        query.until != null &&
        query.since!.isAfter(query.until!)) {
      throw _invalidArgument('since is later than until');
    }
  }

  int _normalizeLimit(int limit) {
    if (limit < 1 || limit > maxLimit) {
      throw _invalidArgument('limit is out of range (1..$maxLimit)');
    }
    return limit;
  }

  int _decodeCursor(String? cursor) {
    final offset = McpCursor.decode(cursor);
    if (offset == null) {
      throw _invalidArgument('Pagination cursor is invalid');
    }
    return offset;
  }

  /// 版本冲突检测：严格比较（P1 评审修正）。
  ///
  /// 比较对象是 SQLite 元数据的毫秒时间戳，精度足够，不做时间容差；
  /// 任何不一致都拒绝写入，避免覆盖用户刚保存的修改。
  void _checkConflict(int? expected, DateTime actual, String message) {
    if (expected == null) return;
    final actualMs = actual.millisecondsSinceEpoch;
    if (expected != actualMs) {
      throw McpToolException(
        McpErrorCodes.writeConflict,
        message,
        false,
        {'expected_modified_at': expected, 'actual_modified_at': actualMs},
      );
    }
  }

  bool _statusMatches(HttpRecord record, String statusClass) {
    if (statusClass == 'error') return record.isError;
    final statusCode = record.statusCode;
    if (statusCode == null) return false;
    return '${statusCode ~/ 100}xx' == statusClass;
  }

  String _hostOf(String url) {
    final uri = Uri.tryParse(url);
    return uri?.host.toLowerCase() ?? '';
  }
}
