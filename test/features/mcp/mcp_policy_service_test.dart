import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/mcp/application/mcp_policy_service.dart';
import 'package:python_runner/features/mcp/domain/mcp_error_codes.dart';
import 'package:python_runner/features/mcp/domain/mcp_permission.dart';
import 'package:python_runner/features/mcp/domain/mcp_tool_definition.dart';
import 'package:shared_preferences/shared_preferences.dart';

McpToolDefinition _tool(McpPermission permission,
        {bool confirmation = false}) =>
    McpToolDefinition(
      name: 'test.tool',
      description: 'test',
      permission: permission,
      inputSchema: const {},
      requiresConfirmation: confirmation,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('McpPolicyService 权限', () {
    test('explicit empty and unknown permissions fail closed after restart',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await McpPolicyService(preferences: prefs).updateEnabledPermissions({});
      expect(McpPolicyService(preferences: prefs).enabledPermissions, isEmpty);
      await prefs.setStringList(McpPolicyService.prefsKey, ['obsolete']);
      expect(McpPolicyService(preferences: prefs).enabledPermissions, isEmpty);
    });
    test('无持久化数据时加载首期默认权限', () async {
      final service =
          McpPolicyService(preferences: await SharedPreferences.getInstance());
      expect(service.enabledPermissions, McpPermission.defaults);
      expect(
          service.enabledPermissions.containsAll([
            McpPermission.readScripts,
            McpPermission.readProjects,
            McpPermission.readNetwork,
            McpPermission.readPackages,
            McpPermission.readFilesystem,
          ]),
          isTrue);
      expect(service.enabledPermissions.contains(McpPermission.writeScripts),
          isFalse);
      expect(service.enabledPermissions.contains(McpPermission.installPackages),
          isFalse);
    });

    test('未开启权限时 checkToolPermission 抛 MCP_FORBIDDEN', () async {
      final service =
          McpPolicyService(preferences: await SharedPreferences.getInstance());
      expect(
        () => service.checkToolPermission(_tool(McpPermission.writeScripts)),
        throwsA(isA<McpToolException>()
            .having((e) => e.code, 'code', McpErrorCodes.mcpForbidden)),
      );
    });

    test('开启权限后通过检查并持久化', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = McpPolicyService(preferences: prefs);
      await service.setPermissionEnabled(McpPermission.writeScripts, true);

      expect(
          () => service.checkToolPermission(_tool(McpPermission.writeScripts)),
          returnsNormally);

      final restored = McpPolicyService(preferences: prefs);
      expect(
          () => restored.checkToolPermission(_tool(McpPermission.writeScripts)),
          returnsNormally);
    });

    test('写权限子域标记正确', () {
      expect(McpPermission.writeScripts.isWriteScope, isTrue);
      expect(McpPermission.writeProjects.isWriteScope, isTrue);
      expect(McpPermission.installPackages.isWriteScope, isTrue);
      expect(McpPermission.readScripts.isWriteScope, isFalse);
    });
  });

  group('McpPolicyService 限流', () {
    test('窗口内超过配额抛 RATE_LIMITED', () async {
      final service =
          McpPolicyService(preferences: await SharedPreferences.getInstance());
      for (var i = 0; i < McpPolicyService.perSessionRateLimit; i++) {
        service.checkRateLimit('session-a');
      }
      expect(
        () => service.checkRateLimit('session-a'),
        throwsA(isA<McpToolException>()
            .having((e) => e.code, 'code', McpErrorCodes.rateLimited)),
      );
      // 其他会话不受影响。
      expect(() => service.checkRateLimit('session-b'), returnsNormally);
    });

    test('forgetSession 清理会话计数', () async {
      final service =
          McpPolicyService(preferences: await SharedPreferences.getInstance());
      for (var i = 0; i < McpPolicyService.perSessionRateLimit; i++) {
        service.checkRateLimit('session-a');
      }
      service.forgetSession('session-a');
      expect(() => service.checkRateLimit('session-a'), returnsNormally);
    });
  });
}
