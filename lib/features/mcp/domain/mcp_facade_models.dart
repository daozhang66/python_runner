import 'dart:convert';

/// 分页游标（计划 §9.3）：服务端生成的不透明值。
///
/// 编码为 base64url(JSON)，客户端不可构造；解码失败按非法参数处理。
class McpCursor {
  const McpCursor._();

  static const int maxDecodeLength = 256;

  static String encode(int offset) =>
      base64Url.encode(utf8.encode('{"o":$offset}'));

  /// 返回 null 表示 cursor 非法；返回 0 等价于第一页。
  static int? decode(String? cursor) {
    if (cursor == null || cursor.isEmpty) return 0;
    if (cursor.length > maxDecodeLength) return null;
    try {
      final json = utf8.decode(base64Url.decode(cursor));
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) return null;
      final offset = decoded['o'];
      if (offset is! int || offset < 0) return null;
      return offset;
    } catch (_) {
      return null;
    }
  }
}

/// 通用分页结果：`items` 为已序列化好的条目 Map，`nextCursor` 为空表示没有更多。
class McpPage {
  const McpPage({required this.items, this.nextCursor});

  final List<Map<String, dynamic>> items;
  final String? nextCursor;

  Map<String, dynamic> toMap() => {
        'items': items,
        if (nextCursor != null) 'next_cursor': nextCursor,
      };
}

class McpScriptSummary {
  const McpScriptSummary({
    required this.name,
    required this.modifiedAt,
    required this.createdAt,
    required this.groupId,
    required this.runCount,
    required this.isPinned,
  });

  final String name;
  final DateTime modifiedAt;
  final DateTime createdAt;
  final int? groupId;
  final int runCount;
  final bool isPinned;

  Map<String, dynamic> toMap() => {
        'name': name,
        'created_at': createdAt.millisecondsSinceEpoch,
        'modified_at': modifiedAt.millisecondsSinceEpoch,
        if (groupId != null) 'group_id': groupId,
        'run_count': runCount,
        'is_pinned': isPinned,
      };
}

class McpGroupSummary {
  const McpGroupSummary({
    required this.id,
    required this.name,
    required this.isProject,
    required this.modifiedAt,
    this.projectKey,
    this.mainFilePath,
  });

  final int id;
  final String name;
  final bool isProject;
  final String? projectKey;
  final String? mainFilePath;
  final DateTime modifiedAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'is_project': isProject,
        if (projectKey != null) 'project_key': projectKey,
        if (mainFilePath != null) 'main_file_path': mainFilePath,
        'modified_at': modifiedAt.millisecondsSinceEpoch,
      };
}

class McpProjectFileSummary {
  const McpProjectFileSummary({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.size,
    required this.modifiedAt,
  });

  final String path;
  final String name;
  final bool isDirectory;
  final int size;
  final DateTime modifiedAt;

  Map<String, dynamic> toMap() => {
        'path': path,
        'name': name,
        'is_directory': isDirectory,
        'size': size,
        'modified_at': modifiedAt.millisecondsSinceEpoch,
      };
}

class McpTextFileContent {
  const McpTextFileContent({
    required this.content,
    required this.size,
    required this.modifiedAt,
    this.truncated = false,
  });

  final String content;
  final int size;
  final DateTime modifiedAt;
  final bool truncated;

  Map<String, dynamic> toMap() => {
        'content': content,
        'size': size,
        'modified_at': modifiedAt.millisecondsSinceEpoch,
        'truncated': truncated,
      };
}

class McpNetworkQuery {
  const McpNetworkQuery({
    this.domain,
    this.method,
    this.statusClass,
    this.since,
    this.until,
    this.includeBody = false,
  });

  final String? domain;
  final String? method;
  final String? statusClass;
  final DateTime? since;
  final DateTime? until;
  final bool includeBody;

  static const statusClasses = {'1xx', '2xx', '3xx', '4xx', '5xx', 'error'};
}

class McpNetworkRecord {
  const McpNetworkRecord({
    required this.id,
    required this.timestamp,
    required this.method,
    required this.url,
    required this.domain,
    required this.statusCode,
    required this.durationMs,
    required this.library,
    required this.requestSize,
    required this.responseSize,
    required this.isError,
    required this.redacted,
    required this.truncated,
    this.requestHeaders,
    this.responseHeaders,
    this.requestBody,
    this.responseBody,
    this.errorType,
    this.errorMessage,
  });

  final String id;
  final DateTime timestamp;
  final String method;
  final String url;
  final String domain;
  final int? statusCode;
  final int? durationMs;
  final String library;
  final int requestSize;
  final int? responseSize;
  final bool isError;
  final bool redacted;
  final bool truncated;
  final Map<String, String>? requestHeaders;
  final Map<String, String>? responseHeaders;
  final String? requestBody;
  final String? responseBody;
  final String? errorType;
  final String? errorMessage;

  Map<String, dynamic> toSummaryMap() => {
        'id': id,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'method': method,
        'url': url,
        'domain': domain,
        if (statusCode != null) 'status_code': statusCode,
        if (durationMs != null) 'duration_ms': durationMs,
        'library': library,
        'request_size': requestSize,
        if (responseSize != null) 'response_size': responseSize,
        'is_error': isError,
        'truncated': truncated,
        'redacted': redacted,
      };

  Map<String, dynamic> toDetailMap() => {
        ...toSummaryMap(),
        if (requestHeaders != null) 'request_headers': requestHeaders,
        if (responseHeaders != null) 'response_headers': responseHeaders,
        if (requestBody != null) 'request_body': requestBody,
        if (responseBody != null) 'response_body': responseBody,
        if (errorType != null) 'error_type': errorType,
        if (errorMessage != null) 'error_message': errorMessage,
      };
}

class McpPackageSummary {
  const McpPackageSummary({
    required this.name,
    required this.version,
    required this.isUserPackage,
    required this.integrityStatus,
  });

  final String name;
  final String version;
  final bool isUserPackage;
  final String integrityStatus;

  Map<String, dynamic> toMap() => {
        'name': name,
        'version': version,
        'is_user_package': isUserPackage,
        'integrity_status': integrityStatus,
      };
}

class McpPackageInstallResult {
  const McpPackageInstallResult({
    required this.success,
    required this.message,
    required this.backend,
    this.operationId,
    this.accepted = false,
  });

  final bool success;
  final String message;
  final String backend;

  /// 长任务登记 id，可用 `operation.get_status` 查询进度与状态。
  final String? operationId;
  final bool accepted;

  Map<String, dynamic> toMap() => {
        if (!accepted) 'success': success,
        if (accepted) 'accepted': true,
        if (accepted) 'status': 'running',
        'message': message,
        'backend': backend,
        if (operationId != null) 'operation_id': operationId,
      };
}

/// 目录列表结果：`accessible` 由 Facade 显式判定（列表调用成功），
/// 不以"结果为空"推断权限受限；权限不足时 Facade 抛
/// DIRECTORY_NOT_ACCESSIBLE 而不是返回空列表（计划 §5.2）。
class McpDirectoryListing {
  const McpDirectoryListing({required this.page, required this.accessible});

  final McpPage page;
  final bool accessible;
}

class McpFileEntry {
  const McpFileEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.size,
    required this.modifiedAt,
    this.permissionLimited = false,
  });

  final String path;
  final String name;
  final bool isDirectory;
  final int size;
  final DateTime modifiedAt;

  /// 结果受 Android 权限限制（例如返回空列表时避免被误认为目录为空）。
  final bool permissionLimited;

  Map<String, dynamic> toMap() => {
        'path': path,
        'name': name,
        'is_directory': isDirectory,
        'size': size,
        'modified_at': modifiedAt.millisecondsSinceEpoch,
        'permission_limited': permissionLimited,
      };
}

class McpAppStatus {
  const McpAppStatus({
    required this.appVersion,
    required this.runtimeBackend,
    required this.linuxLikeAvailable,
    required this.linuxLikeInstalled,
    required this.mcpRunning,
    required this.mcpPort,
    this.message,
  });

  final String appVersion;
  final String runtimeBackend;
  final bool linuxLikeAvailable;
  final bool linuxLikeInstalled;
  final bool mcpRunning;
  final int mcpPort;
  final String? message;

  Map<String, dynamic> toMap() => {
        'app_version': appVersion,
        'runtime_backend': runtimeBackend,
        'linux_like_available': linuxLikeAvailable,
        'linux_like_installed': linuxLikeInstalled,
        'mcp_running': mcpRunning,
        'mcp_port': mcpPort,
        if (message != null) 'message': message,
      };
}

/// 文件内容读取结果。
///
/// 文本文件返回 [content]；二进制文件置 [isBinary]，由工具层转换为
/// `BINARY_FILE_UNSUPPORTED` 错误并附元数据（计划 §6.5：不能无条件 Base64）。
class McpFileContent {
  const McpFileContent({
    required this.size,
    this.content,
    this.truncated = false,
    this.isBinary = false,
  });

  final String? content;
  final int size;
  final bool truncated;
  final bool isBinary;

  Map<String, dynamic> toMap() => {
        if (content != null) 'content': content,
        'size': size,
        'truncated': truncated,
        'is_binary': isBinary,
      };
}
