/// JSON-RPC 2.0 消息构造与校验助手。
///
/// 协议错误只用于请求格式、未知方法和严重协议问题（计划 §9.2）；
/// 业务失败一律进入工具结果的 isError 通道。
class McpJsonRpc {
  const McpJsonRpc._();

  // JSON-RPC 标准错误码。
  static const int parseError = -32700;
  static const int invalidRequest = -32600;
  static const int methodNotFound = -32601;
  static const int invalidParams = -32602;
  static const int internalError = -32603;
  static const int sessionNotFound = -32001; // MCP Streamable HTTP 约定

  static Map<String, dynamic> result(Object? id, Map<String, dynamic> result) {
    return {
      'jsonrpc': '2.0',
      'id': id,
      'result': result,
    };
  }

  static Map<String, dynamic> error(
    Object? id,
    int code,
    String message, {
    Object? data,
  }) {
    return {
      'jsonrpc': '2.0',
      if (id != null) 'id': id,
      'error': {
        'code': code,
        'message': message,
        if (data != null) 'data': data,
      },
    };
  }

  static bool isNotification(Map<dynamic, dynamic> message) =>
      !message.containsKey('id');

  /// 基本合法性：jsonrpc 字段与方法名（无 id 的消息允许缺少 id）。
  static String? validateEnvelope(Map<dynamic, dynamic> message) {
    if (message['jsonrpc'] != '2.0') return 'jsonrpc must be "2.0"';
    final method = message['method'];
    if (method is! String || method.isEmpty) {
      return 'method must be a non-empty string';
    }
    final id = message['id'];
    if (message.containsKey('id') &&
        (id is! num && id is! String && id != null)) {
      return 'id must be a string, number, or null';
    }
    final params = message['params'];
    if (params != null && params is! Map && params is! List) {
      return 'params must be an object or array';
    }
    return null;
  }
}
