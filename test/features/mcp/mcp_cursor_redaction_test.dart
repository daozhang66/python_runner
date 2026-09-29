import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/mcp/domain/mcp_facade_models.dart';
import 'package:python_runner/features/mcp/domain/mcp_redaction.dart';

void main() {
  group('McpCursor', () {
    test('编码 / 解码往返', () {
      for (final offset in [0, 1, 99, 500, 999999]) {
        expect(McpCursor.decode(McpCursor.encode(offset)), offset);
      }
    });

    test('游标是不透明值：不是明文数字', () {
      final cursor = McpCursor.encode(100);
      expect(cursor.contains('100'), isFalse);
      expect(cursor.contains('offset'), isFalse);
    });

    test('空与 null 解码为第一页', () {
      expect(McpCursor.decode(null), 0);
      expect(McpCursor.decode(''), 0);
    });

    test('非法游标解码为 null（客户端不可构造）', () {
      expect(McpCursor.decode('garbage!!'), isNull);
      expect(McpCursor.decode('MTIz'), isNull, reason: '非本格式 base64');
      expect(McpCursor.decode('x' * 300), isNull, reason: '超长游标');
    });
  });

  group('McpRedactor', () {
    test('脱敏标准敏感头（大小写不敏感）', () {
      final headers = {
        'Authorization': 'Bearer secret-token',
        'authorization': 'Basic abc',
        'COOKIE': 'session=1',
        'Set-Cookie': 'a=b',
        'Proxy-Authorization': 'Basic x',
        'X-Api-Key': 'k1',
        'X-Auth-Token': 't1',
        'Content-Type': 'application/json',
        'Accept': '*/*',
      };
      final redacted = McpRedactor.redactHeaders(headers);
      expect(redacted['Authorization'], McpRedactor.redactedValue);
      expect(redacted['authorization'], McpRedactor.redactedValue);
      expect(redacted['COOKIE'], McpRedactor.redactedValue);
      expect(redacted['Set-Cookie'], McpRedactor.redactedValue);
      expect(redacted['Proxy-Authorization'], McpRedactor.redactedValue);
      expect(redacted['X-Api-Key'], McpRedactor.redactedValue);
      expect(redacted['X-Auth-Token'], McpRedactor.redactedValue);
      expect(redacted['Content-Type'], 'application/json');
      expect(redacted['Accept'], '*/*');
      // 原 Map 不被修改。
      expect(headers['Authorization'], 'Bearer secret-token');
    });

    test('名称包含 token/secret/password/credential 的头被脱敏', () {
      final headers = {
        'X-GitHub-Token': 'gh_x',
        'Client-Secret': 's',
        'User-Password': 'p',
        'X-Credential': 'c',
        'X-Token-Expiry': 'e',
      };
      final redacted = McpRedactor.redactHeaders(headers);
      for (final name in headers.keys) {
        expect(redacted[name], McpRedactor.redactedValue, reason: name);
      }
    });

    test('非敏感头名不会被误伤', () {
      expect(McpRedactor.isSensitiveHeader('Content-Type'), isFalse);
      expect(McpRedactor.isSensitiveHeader('User-Agent'), isFalse);
      expect(McpRedactor.isSensitiveHeader('Host'), isFalse);
    });

    test('truncateBody 在预算内原样返回，超预算截断并标记', () {
      expect(McpRedactor.truncateBody(null, 100), (null, false));
      expect(McpRedactor.truncateBody('short', 100), ('short', false));
      final (content, truncated) = McpRedactor.truncateBody('a' * 250, 100);
      expect(truncated, isTrue);
      expect(content, hasLength(100));
    });
  });
}
