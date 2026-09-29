import 'mcp_error_codes.dart';

/// MCP 工具执行结果。
///
/// 业务失败通过 [McpToolResult.error]（isError: true + 稳定错误码）表达；
/// 协议层错误（JSON-RPC）只用于请求格式和严重协议问题（计划 §9.2）。
class McpToolResult {
  const McpToolResult.success([this.data = const <String, dynamic>{}])
      : isError = false,
        error = null;

  const McpToolResult.error(McpToolException exception)
      : isError = true,
        error = exception,
        data = const <String, dynamic>{};

  final bool isError;
  final Map<String, dynamic> data;
  final McpToolException? error;

  factory McpToolResult.fromException(Object exception) {
    if (exception is McpToolException) {
      return McpToolResult.error(exception);
    }
    return McpToolResult.error(
      McpToolException(
          McpErrorCodes.internalError, 'Internal error: $exception'),
    );
  }

  Map<String, dynamic> toContentPayload() {
    if (isError) {
      return error!.toToolErrorPayload();
    }
    return data;
  }
}
