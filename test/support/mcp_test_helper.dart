import 'package:flutter/foundation.dart';
import 'package:python_runner/features/mcp/application/mcp_application_facade.dart';
import 'package:python_runner/features/mcp/domain/mcp_error_codes.dart';
import 'package:python_runner/features/mcp/domain/mcp_facade_models.dart';
import 'package:python_runner/features/network/application/network_inspector_repository.dart';
import 'package:python_runner/services/http_inspector_store.dart'
    show HttpRecord;

/// 测试用 [McpApplicationFacade]：内存实现，可注入脚本/分组/包数据与
/// 可观测调用计数，供适配器与传输层测试使用。
class FakeMcpApplicationFacade implements McpApplicationFacade {
  final fileMutations = <String>[];
  @override
  Future<void> createDirectory(String path, String name) async {
    fileMutations.add('mkdir:$path/$name');
  }

  @override
  Future<void> renameFileEntry(String path, String newName) async {
    fileMutations.add('rename:$path:$newName');
  }

  @override
  Future<void> deleteFileEntry(String path) async {
    fileMutations.add('delete:$path');
  }

  @override
  Future<void> writeTextFile(String path, String content) async {
    fileMutations.add('write:$path:$content');
  }

  FakeMcpApplicationFacade({
    List<McpScriptSummary> scripts = const [],
    List<McpGroupSummary> groups = const [],
    List<McpPackageSummary> packages = const [],
    List<HttpRecord> networkRecords = const [],
    this.appStatus,
  })  : _scripts = List.of(scripts),
        _groups = List.of(groups),
        _packages = List.of(packages),
        _networkRecords = List.of(networkRecords);

  final List<McpScriptSummary> _scripts;
  final List<McpGroupSummary> _groups;
  final List<McpPackageSummary> _packages;
  final List<HttpRecord> _networkRecords;
  McpAppStatus? appStatus;

  int listScriptsCalls = 0;
  int createScriptCalls = 0;
  int installPackageCalls = 0;
  String? lastInstallPackageName;

  @override
  Future<McpAppStatus> getAppStatus() async {
    return appStatus ??
        const McpAppStatus(
          appVersion: '1.0.0-test',
          runtimeBackend: 'chaquopy',
          linuxLikeAvailable: true,
          linuxLikeInstalled: false,
          mcpRunning: true,
          mcpPort: 37891,
        );
  }

  @override
  Future<McpPage> listScripts({
    String? query,
    int? groupId,
    int limit = 100,
    String? cursor,
  }) async {
    listScriptsCalls++;
    final offset = McpCursor.decode(cursor) ?? 0;
    var filtered = _scripts;
    if (query != null) {
      filtered = filtered
          .where((s) => s.name.toLowerCase().contains(query.toLowerCase()))
          .toList();
    }
    if (groupId != null) {
      filtered = filtered.where((s) => s.groupId == groupId).toList();
    }
    final end = (offset + limit).clamp(0, filtered.length);
    final items =
        filtered.skip(offset).take(limit).map((s) => s.toMap()).toList();
    return McpPage(
      items: items,
      nextCursor: end < filtered.length ? McpCursor.encode(end) : null,
    );
  }

  @override
  Future<McpScriptSummary> createScript({
    required String name,
    String content = '',
    int? groupId,
  }) async {
    createScriptCalls++;
    if (_scripts.any((s) => s.name == name)) {
      throw McpToolException(McpErrorCodes.scriptAlreadyExists, '脚本已存在');
    }
    final now = DateTime.now();
    final script = McpScriptSummary(
      name: name,
      modifiedAt: now,
      createdAt: now,
      groupId: groupId,
      runCount: 0,
      isPinned: false,
    );
    _scripts.add(script);
    return script;
  }

  @override
  Future<McpTextFileContent> readScript(String name,
      {int maxChars = 200000}) async {
    final script = _scripts.where((s) => s.name == name).firstOrNull;
    if (script == null) {
      throw McpToolException(McpErrorCodes.scriptNotFound, '脚本不存在');
    }
    return McpTextFileContent(
      content: '# $name',
      size: 10,
      modifiedAt: script.modifiedAt,
    );
  }

  @override
  Future<McpScriptSummary> saveScript({
    required String name,
    required String content,
    int? expectedModifiedAt,
  }) async {
    final script = _scripts.where((s) => s.name == name).firstOrNull;
    if (script == null) {
      throw McpToolException(McpErrorCodes.scriptNotFound, '脚本不存在');
    }
    if (expectedModifiedAt != null &&
        expectedModifiedAt != script.modifiedAt.millisecondsSinceEpoch) {
      throw McpToolException(McpErrorCodes.writeConflict, '冲突');
    }
    final updated = McpScriptSummary(
      name: script.name,
      modifiedAt: DateTime.now(),
      createdAt: script.createdAt,
      groupId: script.groupId,
      runCount: script.runCount,
      isPinned: script.isPinned,
    );
    final index = _scripts.indexWhere((s) => s.name == name);
    _scripts[index] = updated;
    return updated;
  }

  @override
  Future<List<McpGroupSummary>> listGroups() async => List.of(_groups);

  @override
  Future<McpGroupSummary> createGroup(String name) async {
    final group = McpGroupSummary(
      id: _groups.length + 1,
      name: name,
      isProject: false,
      modifiedAt: DateTime.now(),
    );
    _groups.add(group);
    return group;
  }

  @override
  Future<McpGroupSummary> createProjectGroup({
    required String name,
    String? projectKey,
    String? mainFilePath,
    String? mainFileContent,
  }) async {
    final group = McpGroupSummary(
      id: _groups.length + 1,
      name: name,
      isProject: true,
      projectKey: projectKey ?? 'project_generated',
      mainFilePath: mainFilePath ?? 'main.py',
      modifiedAt: DateTime.now(),
    );
    _groups.add(group);
    return group;
  }

  @override
  Future<McpPage> listProjectFiles(String projectKey,
      {int limit = 200, String? cursor}) async {
    return const McpPage(items: []);
  }

  @override
  Future<McpTextFileContent> readProjectFile(String projectKey, String path,
      {int maxChars = 200000}) async {
    return McpTextFileContent(
      content: 'print("ok")',
      size: 12,
      modifiedAt: DateTime.now(),
    );
  }

  @override
  Future<McpProjectFileSummary> saveProjectFile({
    required String projectKey,
    required String path,
    required String content,
    int? expectedModifiedAt,
  }) async {
    return McpProjectFileSummary(
      path: path,
      name: path.split('/').last,
      isDirectory: false,
      size: content.length,
      modifiedAt: DateTime.now(),
    );
  }

  @override
  Future<McpPage> listNetworkRecords(McpNetworkQuery query,
      {int limit = 50, String? cursor}) async {
    final offset = McpCursor.decode(cursor) ?? 0;
    final items =
        _networkRecords.skip(offset).take(limit).map(_summarize).toList();
    return McpPage(items: items);
  }

  @override
  Future<McpNetworkRecord> getNetworkRecord(String id,
      {bool includeBody = false}) async {
    final record = _networkRecords.where((r) => r.id == id).firstOrNull;
    if (record == null) {
      throw McpToolException(McpErrorCodes.networkRecordNotFound, '记录不存在');
    }
    return _detail(record, includeBody: includeBody);
  }

  @override
  Future<McpPage> listPackages({
    String? backend,
    String? query,
    int limit = 100,
    String? cursor,
  }) async {
    final offset = McpCursor.decode(cursor) ?? 0;
    final end = (offset + limit).clamp(0, _packages.length);
    return McpPage(
      items: _packages.skip(offset).take(limit).map((p) => p.toMap()).toList(),
      nextCursor: end < _packages.length ? McpCursor.encode(end) : null,
    );
  }

  @override
  Future<McpPackageInstallResult> installPackage({
    required String packageName,
    String? version,
    String? indexUrl,
    String? backend,
  }) async {
    installPackageCalls++;
    lastInstallPackageName = packageName;
    return McpPackageInstallResult(
      success: true,
      message: 'installed',
      backend: 'chaquopy',
    );
  }

  @override
  Future<McpDirectoryListing> listAccessibleDirectory({
    required String path,
    int limit = 100,
    String? cursor,
    bool includeHidden = false,
  }) async {
    return const McpDirectoryListing(
      page: McpPage(items: []),
      accessible: true,
    );
  }

  @override
  Future<McpFileContent> readAccessibleFile({
    required String path,
    int maxBytes = 256 * 1024,
  }) async {
    return const McpFileContent(size: 4, content: 'data');
  }

  Map<String, dynamic> _summarize(HttpRecord record) => McpNetworkRecord(
        id: record.id,
        timestamp: record.timestamp,
        method: record.method,
        url: record.url,
        domain: '',
        statusCode: record.statusCode,
        durationMs: record.durationMs,
        library: record.library,
        requestSize: 0,
        responseSize: record.responseBodyBytes,
        isError: record.isError,
        redacted: true,
        truncated: record.responseBodyTruncated,
      ).toSummaryMap();

  McpNetworkRecord _detail(HttpRecord record, {required bool includeBody}) {
    return McpNetworkRecord(
      id: record.id,
      timestamp: record.timestamp,
      method: record.method,
      url: record.url,
      domain: '',
      statusCode: record.statusCode,
      durationMs: record.durationMs,
      library: record.library,
      requestSize: 0,
      responseSize: record.responseBodyBytes,
      isError: record.isError,
      redacted: true,
      truncated: record.responseBodyTruncated,
      requestHeaders: {
        'Authorization': '<redacted>',
        'Content-Type': 'application/json',
      },
      requestBody: includeBody ? 'request-body' : null,
    );
  }
}

/// 测试用 [NetworkInspectorRepository]：内存记录 + 空 Listenable。
class FakeNetworkInspectorRepository implements NetworkInspectorRepository {
  FakeNetworkInspectorRepository({List<HttpRecord> records = const []})
      : _records = List.of(records);

  final List<HttpRecord> _records;
  bool ensureLoadedCalled = false;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}

  @override
  List<HttpRecord> get records => List.unmodifiable(_records);

  @override
  int get count => _records.length;

  @override
  Map<String, dynamic> get stats => const {};

  @override
  Map<String, dynamic> get visibleStats => const {};

  @override
  List<MapEntry<String, int>> get domainStats => const [];

  @override
  int get hiddenNoiseCount => 0;

  @override
  bool get isLoaded => true;

  @override
  Object? get lastStorageError => null;

  @override
  List<HttpRecord> get filteredRecords => records;

  @override
  String get filterDomain => '';

  @override
  String get filterMethod => '';

  @override
  int? get filterStatus => null;

  @override
  bool get hideNoiseMethods => false;

  @override
  void setFilterDomain(String value) {}

  @override
  void setFilterMethod(String value) {}

  @override
  void setFilterStatus(int? value) {}

  @override
  void setHideNoiseMethods(bool value) {}

  @override
  void clearFilters() {}

  @override
  void addFromJson(Map<String, dynamic> json) {}

  @override
  void clear() => _records.clear();

  @override
  Future<void> ensureLoaded() async {
    ensureLoadedCalled = true;
  }

  @override
  Future<void> loadDisplayPreferences() async {}

  @override
  Future<void> flush() async {}

  @override
  String exportAll() => '';

  @override
  String exportFiltered() => '';

  @override
  String exportHar({bool filteredOnly = false}) => '';
}
