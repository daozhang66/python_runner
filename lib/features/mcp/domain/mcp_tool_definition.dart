import 'mcp_permission.dart';

/// MCP 工具调用上下文：处理器只依赖该对象，不接触 Widget / BuildContext /
/// MethodChannel / SQLite（计划 §5.1）。
class McpToolContext {
  const McpToolContext({
    required this.sessionId,
    required this.clientName,
    required this.clientVersion,
  });

  final String sessionId;

  /// 来自 MCP initialize 请求的客户端信息，用于审计与确认界面。
  final String clientName;
  final String clientVersion;
}

/// MCP tools use unique ASCII names with the pyrunner_ prefix.
class McpToolDefinition {
  const McpToolDefinition({
    required this.name,
    required this.description,
    required this.permission,
    required this.inputSchema,
    this.requiresConfirmation = false,
  });

  final String name;
  final String description;
  final McpPermission permission;

  /// JSON Schema（type=object）描述，序列化后直接进入 tools/list。
  final Map<String, dynamic> inputSchema;

  /// 写入类工具默认需要用户确认（权限开启后仍逐次确认）。
  final bool requiresConfirmation;

  Map<String, dynamic> toProtocolMap() => {
        'name': name,
        'description': description,
        'inputSchema': inputSchema,
      };
}
