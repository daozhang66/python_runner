import 'dart:async';
import 'dart:convert';

import '../application/mcp_policy_service.dart';
import '../domain/mcp_error_codes.dart';
import '../domain/mcp_tool_definition.dart';
import '../domain/mcp_tool_result.dart';
import 'mcp_audit_log.dart';
import '../application/mcp_confirmation_service.dart';
import 'mcp_json_rpc.dart';
import 'mcp_session_store.dart';
import 'mcp_tool_registry.dart';

/// 适配器处理结果：HTTP 状态 + 可选 JSON-RPC 响应体 + 新建会话 id。
class McpAdapterOutcome {
  const McpAdapterOutcome({
    required this.httpStatus,
    this.body,
    this.newSessionId,
    this.protocolVersion,
  });

  final int httpStatus;
  final Map<String, dynamic>? body;
  final String? newSessionId;
  final String? protocolVersion;
}

/// MCP Server 适配器（计划 §4：tools/list、tools/call、协议错误、工具执行错误）。
///
/// 实现 Streamable HTTP 传输之上的 MCP 协议子集：
/// initialize / notifications/* / ping / tools/list / tools/call。
/// 每次工具调用经过：会话校验 → 限流 → 权限 → 带超时执行 → 审计。
class McpServerAdapter {
  McpServerAdapter({
    required McpToolRegistry tools,
    required McpSessionStore sessions,
    required McpPolicyService policy,
    required McpAuditLog audit,
    McpConfirmationService? confirmations,
    required String serverVersion,
  })  : _tools = tools,
        _sessions = sessions,
        _policy = policy,
        _audit = audit,
        _serverVersion = serverVersion;

  static const String serverName = 'python-runner';

  /// 本实现验证过的协议版本（计划 §3.1：未经验证不宣称更高版本）。
  static const Set<String> supportedProtocolVersions = {
    '2025-06-18',
    '2025-11-25',
  };
  static const String fallbackProtocolVersion = '2025-06-18';

  final McpToolRegistry _tools;
  final McpSessionStore _sessions;
  final McpPolicyService _policy;
  final McpAuditLog _audit;
  String _serverVersion;

  bool _acceptingRequests = true;

  /// 服务停止后拒绝新请求（计划 §2.2）。
  set acceptingRequests(bool value) => _acceptingRequests = value;

  /// serverInfo 报告的版本（控制器启动后从原生 App 信息回填）。
  set serverVersion(String value) {
    if (value.isNotEmpty) _serverVersion = value;
  }

  Future<McpAdapterOutcome> handleMessage(
    Map<dynamic, dynamic> message, {
    String? sessionIdHeader,
  }) async {
    final envelopeError = McpJsonRpc.validateEnvelope(message);
    if (envelopeError != null) {
      return _outbound(
        McpJsonRpc.error(
          message['id'],
          McpJsonRpc.invalidRequest,
          envelopeError,
        ),
      );
    }

    if (!_acceptingRequests) {
      if (McpJsonRpc.isNotification(message)) return const _NoContent();
      return _outbound(McpJsonRpc.error(
        message['id'],
        McpJsonRpc.internalError,
        'The MCP service is shutting down or is stopped',
      ));
    }

    final method = message['method'] as String;
    final id = message['id'];
    final params = _asMap(message['params']);
    final isNotification = McpJsonRpc.isNotification(message);

    if (method == 'initialize') {
      return _handleInitialize(id, params);
    }

    // initialize 之外的请求必须携带有效会话。
    final session = _sessions.find(sessionIdHeader);
    if (session == null) {
      if (isNotification) return const _NoContent();
      return McpAdapterOutcome(
        httpStatus: 400,
        body: McpJsonRpc.error(
          id,
          McpJsonRpc.sessionNotFound,
          'Session does not exist or has expired; initialize again',
        ),
      );
    }
    _sessions.touch(session.id);

    if (method.startsWith('notifications/')) {
      return const _NoContent();
    }

    return switch (method) {
      'ping' => _outbound(McpJsonRpc.result(id, const {})),
      'tools/list' => _outbound(McpJsonRpc.result(id, {
          'tools': _tools.definitions
              .map((definition) => definition.toProtocolMap())
              .toList(),
        })),
      'tools/call' => _handleToolCall(session, id, params),
      _ => isNotification
          ? const _NoContent()
          : _outbound(McpJsonRpc.error(
              id,
              McpJsonRpc.methodNotFound,
              'Unknown method: $method (this service provides tools only)',
            )),
    };
  }

  McpAdapterOutcome _handleInitialize(Object? id, Map<String, dynamic> params) {
    final clientInfo = _asMap(params['clientInfo']);
    final clientName = clientInfo['name']?.toString() ?? '';
    final clientVersion = clientInfo['clientVersion']?.toString() ??
        clientInfo['version']?.toString() ??
        '';
    final requested =
        params['protocolVersion']?.toString() ?? fallbackProtocolVersion;
    final negotiated = supportedProtocolVersions.contains(requested)
        ? requested
        : fallbackProtocolVersion;

    final session = _sessions.create(
      clientName: clientName,
      clientVersion: clientVersion,
      protocolVersion: negotiated,
    );
    _audit.recordConnect(
      sessionId: session.id,
      clientLabel: session.clientLabel,
      tokenFingerprint: 'session',
    );

    return McpAdapterOutcome(
      httpStatus: 200,
      newSessionId: session.id,
      protocolVersion: negotiated,
      body: McpJsonRpc.result(id, {
        'protocolVersion': negotiated,
        'capabilities': {
          'tools': {'listChanged': false},
        },
        'serverInfo': {
          'name': serverName,
          'version': _serverVersion.isEmpty ? 'unknown' : _serverVersion,
        },
        'instructions':
            "This service exposes Python Runner scripts, projects, captured network records, Python packages, and file-management capabilities. Authorized tool permissions execute directly without per-call confirmation dialogs. Script and project runs return an execution_id; poll pyrunner_execution_output for results.",
      }),
    );
  }

  Future<McpAdapterOutcome> _handleToolCall(
    McpSession session,
    Object? id,
    Map<String, dynamic> params,
  ) async {
    final stopwatch = Stopwatch()..start();
    final name = params['name'];
    final arguments = _asMap(params['arguments']);

    if (name is! String || name.isEmpty) {
      return _outbound(McpJsonRpc.error(
        id,
        McpJsonRpc.invalidParams,
        'tools/call requires name and optional arguments',
      ));
    }
    final entry = _tools.find(name);
    if (entry == null) {
      return _outbound(McpJsonRpc.error(
        id,
        McpJsonRpc.invalidParams,
        'Unknown tool: $name',
      ));
    }

    final context = McpToolContext(
      sessionId: session.id,
      clientName: session.clientName,
      clientVersion: session.clientVersion,
    );
    var summary = entry.definition.name;

    McpToolResult result;
    var permissionDecision = 'allowed';
    try {
      _policy.checkRateLimit(session.id);
      _policy.checkToolPermission(entry.definition);
      summary = entry.summarize?.call(arguments) ?? summary;
      result = await _execute(entry, context, arguments);
    } on McpToolException catch (exception) {
      permissionDecision = exception.code == McpErrorCodes.rateLimited
          ? 'rate_limited'
          : permissionDecision == 'allowed'
              ? 'denied:${exception.code}'
              : permissionDecision;
      result = McpToolResult.error(exception);
    } catch (error) {
      result = McpToolResult.error(
        McpToolException(McpErrorCodes.internalError, 'Internal error: $error'),
      );
    }

    _audit.recordToolCall(
      sessionId: session.id,
      clientLabel: session.clientLabel,
      tool: name,
      argsSummary: summary,
      permissionDecision: permissionDecision,
      confirmationRequired: false,
      ok: !result.isError,
      errorCode: result.error?.code,
      durationMs: stopwatch.elapsedMilliseconds,
    );

    return _outbound(McpJsonRpc.result(id, {
      'content': [
        {
          'type': 'text',
          'text': jsonEncode(result.toContentPayload()),
        }
      ],
      'isError': result.isError,
    }));
  }

  Future<McpToolResult> _execute(
    McpToolEntry entry,
    McpToolContext context,
    Map<String, dynamic> arguments,
  ) {
    final session = _sessions.find(context.sessionId);
    if (session == null) {
      throw McpToolException(
          McpErrorCodes.mcpForbidden, 'Session is no longer valid');
    }
    _checkExecutionAllowed(session, entry);
    return entry.handler(context, arguments).timeout(entry.timeout,
        onTimeout: () {
      throw McpToolException(
        McpErrorCodes.internalError,
        'Tool execution timed out after ${entry.timeout.inSeconds} seconds; narrow the parameters and retry',
        true,
        {'tool': entry.definition.name},
      );
    });
  }

  void _checkExecutionAllowed(McpSession session, McpToolEntry entry) {
    if (!_acceptingRequests ||
        !identical(_sessions.find(session.id), session) ||
        session.isIdleBeyond(McpSessionStore.idleTimeout)) {
      throw McpToolException(
          McpErrorCodes.mcpForbidden, 'Service stopped or session expired');
    }
    _policy.checkToolPermission(entry.definition);
  }

  McpAdapterOutcome _outbound(Map<String, dynamic> body) =>
      McpAdapterOutcome(httpStatus: 200, body: body);

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v));
    return const {};
  }
}

class _NoContent implements McpAdapterOutcome {
  const _NoContent();

  @override
  int get httpStatus => 202;

  @override
  Map<String, dynamic>? get body => null;

  @override
  String? get newSessionId => null;

  @override
  String? get protocolVersion => null;
}
