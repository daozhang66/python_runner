import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../services/app_logger.dart';
import 'mcp_audit_log.dart';
import 'mcp_json_rpc.dart';
import 'mcp_server_adapter.dart';
import 'mcp_session_store.dart';
import 'mcp_token_store.dart';

/// MCP Streamable HTTP 传输层（计划 §3.1 / §3.3）。
///
/// - 监听所有 IPv4 网卡，端点固定 `/mcp`；
/// - 可选 Bearer 配对令牌；认证开关由服务控制器传入；
/// - 校验 Origin 防止 DNS rebinding（只允许本机或私有局域网来源）；
/// - POST：JSON-RPC 请求/通知；GET：405（不提供 SSE 服务端推送）；
///   DELETE：终止会话。
class McpHttpTransport {
  McpHttpTransport({
    required McpServerAdapter adapter,
    required McpTokenStore tokens,
    required McpSessionStore sessions,
    required McpAuditLog audit,
    this.requireToken = true,
    void Function(String sessionId)? onSessionTerminated,
    AppLogger? logger,
  })  : _adapter = adapter,
        _tokens = tokens,
        _sessions = sessions,
        _audit = audit,
        _onSessionTerminated = onSessionTerminated,
        _logger = logger ?? AppLogger.instance;

  static const String endpoint = '/mcp';
  static const int defaultPort = 37891;
  static const int maxBodyBytes = 1024 * 1024;

  final McpServerAdapter _adapter;
  final McpTokenStore _tokens;
  final McpSessionStore _sessions;
  final McpAuditLog _audit;
  final void Function(String sessionId)? _onSessionTerminated;
  final AppLogger _logger;
  final bool requireToken;

  HttpServer? _server;
  int _boundPort = 0;

  bool get isRunning => _server != null;
  int get boundPort => _boundPort;

  /// 绑定本机回环地址并开始接收请求。
  Future<int> start({int port = defaultPort}) async {
    if (_server != null) {
      throw StateError('MCP transport is already running');
    }
    final server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      port,
      shared: false,
    );
    _server = server;
    _boundPort = server.port;
    _audit.recordServer('started', detail: '0.0.0.0:$_boundPort$endpoint');
    server.listen(
      (request) {
        _handle(request).catchError((Object error, StackTrace stackTrace) {
          _logger.error(
            'MCP request handling failed: $error',
            source: 'McpTransport',
            detail: stackTrace.toString(),
          );
          _respond(request, 500,
              body: McpJsonRpc.error(
                  null, McpJsonRpc.internalError, 'Internal server error'));
        });
      },
      onError: (Object error) {
        _logger.error('MCP HTTP service error: $error', source: 'McpTransport');
      },
    );
    return _boundPort;
  }

  /// 停止服务：拒绝新请求并断开现有连接（计划 §2.2）。
  Future<void> stop() async {
    final server = _server;
    _server = null;
    _adapter.acceptingRequests = false;
    if (server != null) {
      await server.close(force: true);
    }
    _audit.recordServer('stopped');
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (path != endpoint) {
        _respond(request, 404);
        return;
      }

      switch (request.method) {
        case 'OPTIONS':
          _respond(request, 204);
          return;
        case 'POST':
          await _handlePost(request);
          return;
        case 'GET':
          // 本服务不提供服务端 SSE 推送（MCP 规范允许返回 405）。
          request.response.headers.set('Allow', 'POST, DELETE, OPTIONS');
          _respond(request, 405);
          return;
        case 'DELETE':
          _handleDelete(request);
          return;
        default:
          request.response.headers.set('Allow', 'POST, GET, DELETE, OPTIONS');
          _respond(request, 405);
      }
    } finally {
      await request.response.close();
    }
  }

  Future<void> _handlePost(HttpRequest request) async {
    if (!_isOriginAllowed(request.headers.value('origin'))) {
      _respond(request, 403);
      return;
    }

    final contentType = request.headers.contentType?.mimeType ?? '';
    if (contentType.isNotEmpty &&
        contentType != 'application/json' &&
        !contentType.endsWith('+json')) {
      _respond(request, 415);
      return;
    }

    if (requireToken && !_tokens.verify(_bearerToken(request))) {
      _respondUnauthorized(request);
      return;
    }

    final bodyBytes = await _readBody(request);
    if (bodyBytes == null) {
      _respond(request, 413,
          body: McpJsonRpc.error(
            null,
            McpJsonRpc.internalError,
            'Request body exceeds the ${maxBodyBytes ~/ 1024} KiB limit',
          ));
      return;
    }
    if (bodyBytes.isEmpty) {
      _respond(request, 400,
          body: McpJsonRpc.error(
            null,
            McpJsonRpc.parseError,
            'Request body is empty',
          ));
      return;
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(bodyBytes));
    } catch (_) {
      _respond(request, 400,
          body: McpJsonRpc.error(
              null, McpJsonRpc.parseError, 'Request body is not valid JSON'));
      return;
    }
    if (decoded is List) {
      // JSON-RPC 批量请求已在 MCP 2025-06-18 移除。
      _respond(request, 400,
          body: McpJsonRpc.error(
            null,
            McpJsonRpc.invalidRequest,
            'JSON-RPC batch requests are unsupported',
          ));
      return;
    }
    if (decoded is! Map) {
      _respond(request, 400,
          body: McpJsonRpc.error(null, McpJsonRpc.invalidRequest,
              'Request body must be a JSON object'));
      return;
    }

    final sessionId = request.headers.value('Mcp-Session-Id');
    final outcome =
        await _adapter.handleMessage(decoded, sessionIdHeader: sessionId);
    if (outcome.newSessionId != null) {
      request.response.headers.set('Mcp-Session-Id', outcome.newSessionId!);
    }
    if (outcome.protocolVersion != null) {
      request.response.headers.set(
        'Mcp-Protocol-Version',
        outcome.protocolVersion!,
      );
    }
    _respond(request, outcome.httpStatus, body: outcome.body);
  }

  void _handleDelete(HttpRequest request) {
    // 与 POST 共用认证与 Origin 策略（P2 评审修正）。
    if (!_isOriginAllowed(request.headers.value('origin'))) {
      _respond(request, 403);
      return;
    }
    if (requireToken && !_tokens.verify(_bearerToken(request))) {
      _respondUnauthorized(request);
      return;
    }
    final sessionId = request.headers.value('Mcp-Session-Id');
    final session = sessionId == null ? null : _sessions.find(sessionId);
    if (session == null) {
      _respond(request, 404);
      return;
    }
    _sessions.terminate(session.id);
    _onSessionTerminated?.call(session.id);
    _audit.recordDisconnect(
      sessionId: session.id,
      clientLabel: session.clientLabel,
      reason: 'client-delete',
    );
    _respond(request, 204);
  }

  void _respondUnauthorized(HttpRequest request) {
    _audit.recordServer('unauthorized',
        detail: '${request.method} ${request.uri.path}');
    request.response.headers.set(
      'WWW-Authenticate',
      'Bearer realm="python-runner-mcp"',
    );
    _respond(request, 401,
        body: McpJsonRpc.error(
          null,
          McpJsonRpc.internalError,
          'Missing or invalid pairing token (Authorization: Bearer <token>)',
        ));
  }

  String? _bearerToken(HttpRequest request) {
    final authorization =
        request.headers.value(HttpHeaders.authorizationHeader);
    if (authorization == null) return null;
    const prefix = 'bearer ';
    if (authorization.length < prefix.length) return null;
    if (authorization.substring(0, prefix.length).toLowerCase() != prefix) {
      return null;
    }
    return authorization.substring(prefix.length).trim();
  }

  bool _isOriginAllowed(String? origin) {
    if (origin == null || origin.isEmpty) return true;
    final uri = Uri.tryParse(origin);
    if (uri == null) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    final address = InternetAddress.tryParse(uri.host);
    if (uri.host == 'localhost' || address?.isLoopback == true) return true;
    if (address == null) return false;
    if (address.type == InternetAddressType.IPv4) {
      final octets = address.rawAddress;
      final first = octets[0];
      final second = octets[1];
      return first == 10 ||
          (first == 172 && second >= 16 && second <= 31) ||
          (first == 192 && second == 168) ||
          (first == 169 && second == 254);
    }
    final bytes = address.rawAddress;
    return (bytes[0] & 0xfe) == 0xfc ||
        (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80);
  }

  Future<List<int>?> _readBody(HttpRequest request) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
      if (builder.length > maxBodyBytes) return null;
    }
    return builder.takeBytes();
  }

  void _respond(HttpRequest request, int status, {Map<String, dynamic>? body}) {
    final response = request.response;
    response.statusCode = status;
    _applyCorsHeaders(request, response);
    if (body != null) {
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode(body));
    }
  }

  void _applyCorsHeaders(HttpRequest request, HttpResponse response) {
    // LAN clients may use browser-based MCP clients; echo the validated HTTP origin.
    final origin = request.headers.value('origin');
    response.headers.set(
      'Access-Control-Allow-Origin',
      _isOriginAllowed(origin) && origin != null && origin.isNotEmpty
          ? origin
          : '*',
    );
    response.headers.set(
      'Access-Control-Allow-Methods',
      'POST, GET, DELETE, OPTIONS',
    );
    response.headers.set(
      'Access-Control-Allow-Headers',
      'Authorization, Content-Type, Mcp-Session-Id, Mcp-Protocol-Version',
    );
    response.headers.set(
      'Access-Control-Expose-Headers',
      'Mcp-Session-Id, Mcp-Protocol-Version',
    );
  }
}
