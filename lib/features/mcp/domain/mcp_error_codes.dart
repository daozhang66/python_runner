/// MCP 工具稳定错误码（计划 §9.2）。
///
/// 输入格式合法但业务失败时，工具结果使用 `isError: true` 并携带这里的
/// 稳定错误码；JSON-RPC 协议错误只用于请求格式、未知方法和严重协议问题，
/// 不把普通业务失败包装成 `-32603`。
class McpErrorCodes {
  const McpErrorCodes._();

  /// MCP 服务未开启。
  static const String mcpDisabled = 'MCP_DISABLED';

  /// 令牌缺失或无效。
  static const String mcpUnauthorized = 'MCP_UNAUTHORIZED';

  /// 令牌有效但权限不足（含用户在确认框拒绝）。
  static const String mcpForbidden = 'MCP_FORBIDDEN';

  /// 需要用户确认但当前无法弹出确认（如服务正在关闭）。
  static const String userConfirmationRequired = 'USER_CONFIRMATION_REQUIRED';

  /// 用户确认超时（默认 60 秒）自动拒绝。
  static const String userConfirmationTimeout = 'USER_CONFIRMATION_TIMEOUT';

  /// 参数格式非法（超长、类型错误、路径不合法等）。
  static const String invalidArgument = 'INVALID_ARGUMENT';

  static const String scriptNotFound = 'SCRIPT_NOT_FOUND';
  static const String scriptAlreadyExists = 'SCRIPT_ALREADY_EXISTS';
  static const String groupAlreadyExists = 'GROUP_ALREADY_EXISTS';

  static const String projectNotFound = 'PROJECT_NOT_FOUND';
  static const String projectPathInvalid = 'PROJECT_PATH_INVALID';
  static const String writeConflict = 'WRITE_CONFLICT';

  static const String directoryNotAccessible = 'DIRECTORY_NOT_ACCESSIBLE';
  static const String fileNotFound = 'FILE_NOT_FOUND';
  static const String fileTooLarge = 'FILE_TOO_LARGE';
  static const String binaryFileUnsupported = 'BINARY_FILE_UNSUPPORTED';

  static const String packageBackendUnavailable = 'PACKAGE_BACKEND_UNAVAILABLE';
  static const String packageInstallBusy = 'PACKAGE_INSTALL_BUSY';
  static const String packageInstallFailed = 'PACKAGE_INSTALL_FAILED';

  static const String networkRecordNotFound = 'NETWORK_RECORD_NOT_FOUND';
  static const String rateLimited = 'RATE_LIMITED';
  static const String internalError = 'INTERNAL_ERROR';

  /// 全部稳定错误码，供测试与文档对齐。
  static const Set<String> all = {
    mcpDisabled,
    mcpUnauthorized,
    mcpForbidden,
    userConfirmationRequired,
    userConfirmationTimeout,
    invalidArgument,
    scriptNotFound,
    scriptAlreadyExists,
    groupAlreadyExists,
    projectNotFound,
    projectPathInvalid,
    writeConflict,
    directoryNotAccessible,
    fileNotFound,
    fileTooLarge,
    binaryFileUnsupported,
    packageBackendUnavailable,
    packageInstallBusy,
    packageInstallFailed,
    networkRecordNotFound,
    rateLimited,
    internalError,
  };
}

/// 工具执行业务异常。
///
/// 由 Facade / 工具处理器抛出，MCP 适配层捕获后转换为
/// `isError: true` 的工具结果（计划 §9.2），不升级为 JSON-RPC 协议错误。
class McpToolException implements Exception {
  McpToolException(
    this.code, [
    this.message = '',
    this.retryable = false,
    this.details = const <String, dynamic>{},
  ]);

  final String code;
  final String message;
  final bool retryable;
  final Map<String, dynamic> details;

  /// 是否包含敏感信息，禁止写入审计日志明细。
  bool get safeToAudit => code != McpErrorCodes.mcpUnauthorized;

  Map<String, dynamic> toToolErrorPayload() {
    return {
      'code': code,
      'message': message,
      'retryable': retryable,
      if (details.isNotEmpty) 'details': details,
    };
  }

  @override
  String toString() => 'McpToolException($code): $message';
}
