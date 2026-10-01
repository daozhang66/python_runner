import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:python_runner/features/mcp/application/mcp_confirmation_service.dart';
import 'package:python_runner/features/mcp/application/mcp_policy_service.dart';
import 'package:python_runner/features/mcp/infrastructure/mcp_audit_log.dart';
import 'package:python_runner/features/mcp/infrastructure/mcp_http_transport.dart';
import 'package:python_runner/features/mcp/infrastructure/mcp_server_adapter.dart';
import 'package:python_runner/features/mcp/infrastructure/mcp_session_store.dart';
import 'package:python_runner/features/mcp/infrastructure/mcp_tool_registry.dart';
import 'package:python_runner/features/mcp/infrastructure/mcp_token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/mcp_test_helper.dart';

/// 简单 HTTP 响应记录。
class TestHttpResponse {
  TestHttpResponse(this.statusCode, this.body, this.headers);

  final int statusCode;
  final String body;
  final Map<String, String> headers;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 本文件验证真实 loopback HTTP 服务：解除 flutter_test 的 mock HttpClient，
  // 恢复真实网络客户端（只访问 127.0.0.1）。
  HttpOverrides.global = null;

  // HttpClient 必须在测试 zone 内创建（flutter_test 的 HttpOverrides 要求）。
  late HttpClient httpClient;

  setUp(() {
    httpClient = HttpClient();
  });

  late SharedPreferences prefs;
  late McpTokenStore tokens;
  late McpHttpTransport transport;
  late McpSessionStore sessions;
  late FakeMcpApplicationFacade facade;
  String token = '';
  int port = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    tokens = McpTokenStore(preferences: prefs);
    token = await tokens.regenerate();
    facade = FakeMcpApplicationFacade();
    sessions = McpSessionStore();
    final adapter = McpServerAdapter(
      tools: McpToolRegistry(facade),
      sessions: sessions,
      policy: McpPolicyService(preferences: prefs),
      confirmations: McpConfirmationService(),
      audit: McpAuditLog(),
      serverVersion: 'test',
    );
    transport = McpHttpTransport(
      adapter: adapter,
      tokens: tokens,
      sessions: sessions,
      audit: McpAuditLog(),
    );
    port = await transport.start(port: 0);
  });

  tearDown(() async {
    await transport.stop();
  });

  Future<TestHttpResponse> request(
    String method,
    Map<String, dynamic>? jsonBody, {
    String? token,
    String? sessionId,
  }) async {
    final uri = Uri.parse('http://127.0.0.1:$port/mcp');
    final request = await httpClient.openUrl(method, uri).timeout(
          const Duration(seconds: 10),
        );
    if (token != null) {
      request.headers.set('Authorization', 'Bearer $token');
    }
    if (sessionId != null) {
      request.headers.set('Mcp-Session-Id', sessionId);
    }
    if (jsonBody != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(jsonBody));
    }
    final response = await request.close().timeout(const Duration(seconds: 10));
    final body = await response.transform(utf8.decoder).join();
    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      headers[name] = values.join(',');
    });
    return TestHttpResponse(response.statusCode, body, headers);
  }

  test('未携带令牌的请求被拒绝（401）', () async {
    final response =
        await request('POST', {'jsonrpc': '2.0', 'id': 1, 'method': 'ping'});
    expect(response.statusCode, 401);
    expect(headersContain(response, 'www-authenticate'), isTrue);
  });

  test('错误令牌被拒绝', () async {
    final response = await request(
      'POST',
      {'jsonrpc': '2.0', 'id': 1, 'method': 'ping'},
      token: 'not-the-token',
    );
    expect(response.statusCode, 401);
  });

  test('完整 MCP 流程：initialize → tools/list → tools/call', () async {
    final init = await request(
      'POST',
      {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {
          'protocolVersion': '2025-06-18',
          'clientInfo': {'name': 'E2E-Client', 'version': '1.0'},
          'capabilities': {},
        },
      },
      token: token,
    );
    expect(init.statusCode, 200);
    final sessionId = headerValue(init, 'mcp-session-id');
    expect(sessionId, isNotNull);
    expect(
      (jsonDecode(init.body)['result'] as Map)['serverInfo'],
      isA<Map>(),
    );

    final list = await request(
      'POST',
      {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'},
      token: token,
      sessionId: sessionId,
    );
    expect(list.statusCode, 200);
    expect(
      ((jsonDecode(list.body)['result'] as Map)['tools'] as List).length,
      26,
    );

    final call = await request(
      'POST',
      {
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/call',
        'params': {'name': 'pyrunner_script_list', 'arguments': {}},
      },
      token: token,
      sessionId: sessionId,
    );
    expect(call.statusCode, 200);
    final result = jsonDecode(call.body)['result'] as Map;
    expect(result['isError'], isFalse);
    expect(facade.listScriptsCalls, 1);
  });

  test('令牌轮换后旧令牌立即失效', () async {
    final newToken = await tokens.regenerate();
    final old = await request(
      'POST',
      {'jsonrpc': '2.0', 'id': 1, 'method': 'ping'},
      token: token,
    );
    expect(old.statusCode, 401);

    final fresh = await request(
      'POST',
      {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {
          'protocolVersion': '2025-06-18',
          'clientInfo': {'name': 'x', 'version': '1'},
        },
      },
      token: newToken,
    );
    expect(fresh.statusCode, 200);
  });

  test(
      'custom credentials authenticate immediately without restarting transport',
      () async {
    const custom = 'custom-transport-token-123456';
    await tokens.setCustomToken(custom);
    final old = await request(
        'POST', {'jsonrpc': '2.0', 'id': 1, 'method': 'ping'},
        token: token);
    expect(old.statusCode, 401);
    final fresh = await request(
        'POST',
        {
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'initialize',
          'params': {
            'protocolVersion': '2025-06-18',
            'clientInfo': {'name': 'custom-key-client', 'version': '1'},
          },
        },
        token: custom);
    expect(fresh.statusCode, 200);
    expect(tokens.token, custom);
  });

  test('GET /mcp 返回 405（无 SSE 推送）', () async {
    final response = await request('GET', null, token: token);
    expect(response.statusCode, 405);
  });

  test('DELETE 未携带令牌同样被拒绝（401，与 POST 认证策略一致）', () async {
    final response =
        await request('DELETE', null, sessionId: 'whatever-session');
    expect(response.statusCode, 401);
    expect(headersContain(response, 'www-authenticate'), isTrue);
  });

  test('DELETE 终止会话，重复 DELETE 返回 404', () async {
    final init = await request(
      'POST',
      {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {
          'protocolVersion': '2025-06-18',
          'clientInfo': {'name': 'x', 'version': '1'},
        },
      },
      token: token,
    );
    final sessionId = headerValue(init, 'mcp-session-id')!;

    final deleted =
        await request('DELETE', null, token: token, sessionId: sessionId);
    expect(deleted.statusCode, 204);
    expect(sessions.find(sessionId), isNull);

    final again =
        await request('DELETE', null, token: token, sessionId: sessionId);
    expect(again.statusCode, 404);
  });

  test('stop 后端口不再接受连接（计划 §2.2）', () async {
    await transport.stop();
    expect(transport.isRunning, isFalse);
    expect(
      () => request('POST', {'jsonrpc': '2.0', 'id': 1, 'method': 'ping'},
          token: token),
      throwsA(anything),
    );
  });
}

bool headersContain(TestHttpResponse response, String name) {
  return response.headers.keys
      .any((key) => key.toLowerCase() == name.toLowerCase());
}

String? headerValue(TestHttpResponse response, String name) {
  for (final entry in response.headers.entries) {
    if (entry.key.toLowerCase() == name.toLowerCase()) return entry.value;
  }
  return null;
}
