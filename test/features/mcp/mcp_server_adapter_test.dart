import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/mcp/application/mcp_confirmation_service.dart';
import 'package:python_runner/features/mcp/application/mcp_policy_service.dart';
import 'package:python_runner/features/mcp/domain/mcp_error_codes.dart';
import 'package:python_runner/features/mcp/domain/mcp_permission.dart';
import 'package:python_runner/features/mcp/infrastructure/mcp_audit_log.dart';
import 'package:python_runner/features/mcp/infrastructure/mcp_json_rpc.dart';
import 'package:python_runner/features/mcp/infrastructure/mcp_server_adapter.dart';
import 'package:python_runner/features/mcp/infrastructure/mcp_session_store.dart';
import 'package:python_runner/features/mcp/infrastructure/mcp_tool_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/mcp_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeMcpApplicationFacade facade;
  late McpSessionStore sessions;
  late McpPolicyService policy;
  late McpConfirmationService confirmations;
  late McpAuditLog audit;
  late McpServerAdapter adapter;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    facade = FakeMcpApplicationFacade();
    sessions = McpSessionStore();
    policy =
        McpPolicyService(preferences: await SharedPreferences.getInstance());
    confirmations = McpConfirmationService();
    audit = McpAuditLog();
    adapter = McpServerAdapter(
      tools: McpToolRegistry(facade),
      sessions: sessions,
      policy: policy,
      confirmations: confirmations,
      audit: audit,
      serverVersion: '1.0.0-test',
    );
  });

  Map<String, dynamic> message(String method,
      {Object? id, Map<String, dynamic>? params}) {
    return {
      'jsonrpc': '2.0',
      if (id != null) 'id': id,
      'method': method,
      if (params != null) 'params': params,
    };
  }

  Future<String> initialize() async {
    final outcome =
        await adapter.handleMessage(message('initialize', id: 1, params: {
      'protocolVersion': '2025-06-18',
      'clientInfo': {'name': 'Inspector', 'version': '0.14.0'},
      'capabilities': {},
    }));
    expect(outcome.httpStatus, 200);
    expect(outcome.newSessionId, isNotNull);
    return outcome.newSessionId!;
  }

  group('initialize', () {
    test('创建会话并返回协商的协议版本与 serverInfo', () async {
      final outcome =
          await adapter.handleMessage(message('initialize', id: 7, params: {
        'protocolVersion': '2025-06-18',
        'clientInfo': {'name': 'Cursor', 'version': '0.50'},
      }));
      expect(outcome.httpStatus, 200);
      expect(outcome.protocolVersion, '2025-06-18');
      final result = outcome.body!['result'] as Map<String, dynamic>;
      expect(result['protocolVersion'], '2025-06-18');
      expect((result['capabilities'] as Map)['tools'], isNotNull);
      expect((result['serverInfo'] as Map)['name'], 'python-runner');
      expect(sessions.activeCount, 1);
      expect(sessions.sessions.first.clientLabel, 'Cursor 0.50');
    });

    test('不支持的协议版本回落到 2025-06-18', () async {
      final outcome =
          await adapter.handleMessage(message('initialize', id: 1, params: {
        'protocolVersion': '1999-01-01',
        'clientInfo': {'name': 'x', 'version': '1'},
      }));
      expect((outcome.body!['result'] as Map)['protocolVersion'],
          McpServerAdapter.fallbackProtocolVersion);
    });

    test('2025-11-25 在支持列表内直接回显', () async {
      final outcome =
          await adapter.handleMessage(message('initialize', id: 1, params: {
        'protocolVersion': '2025-11-25',
        'clientInfo': {'name': 'x', 'version': '1'},
      }));
      expect((outcome.body!['result'] as Map)['protocolVersion'], '2025-11-25');
    });
  });

  group('会话校验', () {
    test('未携带会话的请求返回 400 + -32001', () async {
      final outcome = await adapter.handleMessage(message('tools/list', id: 2));
      expect(outcome.httpStatus, 400);
      final error = outcome.body!['error'] as Map;
      expect(error['code'], McpJsonRpc.sessionNotFound);
    });

    test('未知会话同样被拒绝', () async {
      final outcome = await adapter.handleMessage(
        message('tools/list', id: 2),
        sessionIdHeader: 'deadbeef',
      );
      expect(outcome.httpStatus, 400);
    });
  });

  group('tools/list', () {
    test('advertises tool metadata in English for external clients', () async {
      final sessionId = await initialize();
      final outcome = await adapter.handleMessage(
        message('tools/list', id: 2),
        sessionIdHeader: sessionId,
      );
      final tools = (outcome.body!['result'] as Map)['tools'] as List<dynamic>;
      final han = RegExp(r'[\u4E00-\u9FFF]');
      for (final tool in tools.cast<Map<dynamic, dynamic>>()) {
        expect(han.hasMatch(jsonEncode(tool)), isFalse,
            reason: 'Tool metadata contains Chinese: ${tool['name']}');
      }
    });

    test('返回全部工具且带 JSON Schema', () async {
      final sessionId = await initialize();
      final outcome = await adapter.handleMessage(
        message('tools/list', id: 2),
        sessionIdHeader: sessionId,
      );
      final tools = (outcome.body!['result'] as Map)['tools'] as List<dynamic>;
      expect(tools, isNotEmpty);
      expect(
          tools.map((t) => (t as Map)['name']).every((name) =>
              RegExp(r'^pyrunner_[a-zA-Z0-9_]+$').hasMatch(name as String)),
          isTrue);
      for (final tool in tools.cast<Map<dynamic, dynamic>>()) {
        final schema = tool['inputSchema'] as Map;
        expect(schema['type'], 'object');
        expect(tool['description'], isNotEmpty);
      }
    });
  });

  group('tools/call', () {
    test('授权写权限后直接执行，不等待确认', () async {
      await policy.setPermissionEnabled(McpPermission.writeScripts, true);
      final sessionId = await initialize();
      final outcome = await adapter.handleMessage(
          message('tools/call', id: 3, params: {
            'name': 'pyrunner_script_create',
            'arguments': {'name': 'yes.py'}
          }),
          sessionIdHeader: sessionId);
      expect((outcome.body!['result'] as Map)['isError'], isFalse);
      expect(confirmations.pending, isEmpty);
      expect(facade.createScriptCalls, 1);
    });
    test('只读工具直接执行并返回 JSON 内容', () async {
      final sessionId = await initialize();
      final outcome = await adapter.handleMessage(
        message('tools/call', id: 3, params: {
          'name': 'pyrunner_script_list',
          'arguments': {},
        }),
        sessionIdHeader: sessionId,
      );
      final result = outcome.body!['result'] as Map<String, dynamic>;
      expect(result['isError'], isFalse);
      final content = (result['content'] as List).first as Map;
      expect(content['type'], 'text');
      final payload = jsonDecode(content['text'] as String);
      expect(payload, isA<Map<String, dynamic>>());
      expect(facade.listScriptsCalls, 1);
    });

    test('未知工具返回 JSON-RPC -32602', () async {
      final sessionId = await initialize();
      final outcome = await adapter.handleMessage(
        message('tools/call',
            id: 3, params: {'name': 'no.such_tool', 'arguments': {}}),
        sessionIdHeader: sessionId,
      );
      final error = outcome.body!['error'] as Map;
      expect(error['code'], McpJsonRpc.invalidParams);
    });

    test('参数类型错误转换为 INVALID_ARGUMENT 工具错误', () async {
      final sessionId = await initialize();
      final outcome = await adapter.handleMessage(
        message('tools/call', id: 3, params: {
          'name': 'pyrunner_script_read',
          'arguments': {'name': 42},
        }),
        sessionIdHeader: sessionId,
      );
      final result = outcome.body!['result'] as Map<String, dynamic>;
      expect(result['isError'], isTrue);
      final payload =
          jsonDecode((result['content'] as List).first['text'] as String);
      expect(payload['code'], McpErrorCodes.invalidArgument);
    });

    test('权限未开启时返回 MCP_FORBIDDEN 工具错误（非 JSON-RPC 错误）', () async {
      final sessionId = await initialize();
      final outcome = await adapter.handleMessage(
        message('tools/call', id: 4, params: {
          'name': 'pyrunner_script_create',
          'arguments': {'name': 'a.py'},
        }),
        sessionIdHeader: sessionId,
      );
      final result = outcome.body!['result'] as Map<String, dynamic>;
      expect(result['isError'], isTrue);
      final payload =
          jsonDecode((result['content'] as List).first['text'] as String);
      expect(payload['code'], McpErrorCodes.mcpForbidden);
      expect(facade.createScriptCalls, 0, reason: '未授权时不能触碰 Facade');
    });
  });

  group('协议消息', () {
    test('ping 返回空结果', () async {
      final sessionId = await initialize();
      final outcome = await adapter.handleMessage(
        message('ping', id: 9),
        sessionIdHeader: sessionId,
      );
      expect((outcome.body!['result'] as Map), isEmpty);
    });

    test('notifications/initialized 返回 202 无响应体', () async {
      final sessionId = await initialize();
      final outcome = await adapter.handleMessage(
        message('notifications/initialized'),
        sessionIdHeader: sessionId,
      );
      expect(outcome.httpStatus, 202);
      expect(outcome.body, isNull);
    });

    test('未知方法返回 -32601', () async {
      final sessionId = await initialize();
      final outcome = await adapter.handleMessage(
        message('resources/list', id: 10),
        sessionIdHeader: sessionId,
      );
      expect(
          (outcome.body!['error'] as Map)['code'], McpJsonRpc.methodNotFound);
    });

    test('非法 jsonrpc 版本返回 -32600', () async {
      final outcome = await adapter
          .handleMessage({'jsonrpc': '1.0', 'id': 1, 'method': 'ping'});
      expect(
          (outcome.body!['error'] as Map)['code'], McpJsonRpc.invalidRequest);
    });

    test('acceptingRequests=false 时拒绝请求（服务关闭）', () async {
      adapter.acceptingRequests = false;
      final outcome =
          await adapter.handleMessage(message('initialize', id: 1, params: {
        'protocolVersion': '2025-06-18',
        'clientInfo': {'name': 'x', 'version': '1'},
      }));
      expect((outcome.body!['error'] as Map)['code'], McpJsonRpc.internalError);
      expect(sessions.activeCount, 0, reason: '关闭后不得创建会话');
    });
  });

  group('审计', () {
    test('工具调用写入审计：包含工具名、客户端与结果状态', () async {
      final sessionId = await initialize();
      await adapter.handleMessage(
        message('tools/call',
            id: 3, params: {'name': 'pyrunner_script_list', 'arguments': {}}),
        sessionIdHeader: sessionId,
      );
      final toolCalls =
          audit.entries.where((e) => e.kind == McpAuditKind.toolCall).toList();
      expect(toolCalls, hasLength(1));
      expect(toolCalls.first.tool, 'pyrunner_script_list');
      expect(toolCalls.first.status, 'ok');
      expect(toolCalls.first.clientLabel, 'Inspector 0.14.0');
    });

    test('审计不记录令牌明文', () async {
      final sessionId = await initialize();
      await adapter.handleMessage(
        message('tools/call',
            id: 3, params: {'name': 'pyrunner_script_list', 'arguments': {}}),
        sessionIdHeader: sessionId,
      );
      final serialized = audit.entries.map((e) => e.toMap().toString()).join();
      expect(serialized.contains('Bearer'), isFalse);
    });
  });
}
