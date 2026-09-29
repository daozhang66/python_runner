import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/mcp/application/mcp_confirmation_service.dart';
import 'package:python_runner/features/mcp/domain/mcp_error_codes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('McpConfirmationService', () {
    test('resolve(allow) 完成等待中的请求', () async {
      final service = McpConfirmationService();
      final future = service.request(
        toolName: 'script.create',
        summary: '创建脚本 a.py（10 字符）',
        clientLabel: 'Inspector 1.0',
      );
      expect(service.pending, hasLength(1));
      expect(service.pending.first.toolName, 'script.create');

      service.resolve(service.pending.first.id, McpConfirmationDecision.allow);
      expect(await future, McpConfirmationDecision.allow);
      expect(service.pending, isEmpty);
    });

    test('超过超时时间自动拒绝（USER_CONFIRMATION_TIMEOUT）', () async {
      final service =
          McpConfirmationService(timeout: const Duration(milliseconds: 30));
      final future = service.request(
        toolName: 'package.install',
        summary: '安装 Python 包 requests',
        clientLabel: 'Inspector 1.0',
      );

      final decision = await future;
      expect(decision, McpConfirmationDecision.timeout);
      expect(service.pending, isEmpty);
      final exception = McpConfirmationService.toException(decision)!;
      expect(exception.code, McpErrorCodes.userConfirmationTimeout);
      expect(exception.retryable, isTrue);
    });

    test('allow/allowSession 决策不产生异常，deny 产生 MCP_FORBIDDEN', () {
      expect(McpConfirmationService.toException(McpConfirmationDecision.allow),
          isNull);
      expect(
          McpConfirmationService.toException(
              McpConfirmationDecision.allowSession),
          isNull);
      final denied =
          McpConfirmationService.toException(McpConfirmationDecision.deny)!;
      expect(denied.code, McpErrorCodes.mcpForbidden);
    });

    test('denyAll 把所有未决请求按拒绝结束（服务停止场景）', () async {
      final service = McpConfirmationService();
      final first =
          service.request(toolName: 'a', summary: 's', clientLabel: 'c');
      final second =
          service.request(toolName: 'b', summary: 's', clientLabel: 'c');

      service.denyAll();

      expect(await first, McpConfirmationDecision.deny);
      expect(await second, McpConfirmationDecision.deny);
      expect(service.pending, isEmpty);
    });

    test('重复 resolve 无效（幂等）', () async {
      final service = McpConfirmationService();
      final future =
          service.request(toolName: 'a', summary: 's', clientLabel: 'c');
      final item = service.pending.first;

      expect(service.resolve(item.id, McpConfirmationDecision.allow), isTrue);
      expect(service.resolve(item.id, McpConfirmationDecision.deny), isFalse);
      expect(await future, McpConfirmationDecision.allow);
    });
  });
}
