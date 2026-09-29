import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/mcp/infrastructure/mcp_token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('McpTokenStore', () {
    test('生成的令牌为 64 位十六进制（256 bit）且可校验', () async {
      final store =
          McpTokenStore(preferences: await SharedPreferences.getInstance());
      final token = await store.regenerate();

      expect(token, hasLength(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(token), isTrue);
      expect(store.hasToken, isTrue);
      expect(store.verify(token), isTrue);
      expect(store.verify('wrong-token'), isFalse);
      expect(store.verify(null), isFalse);
      expect(store.verify(''), isFalse);
    });

    test('令牌前后空白不影响校验（Bearer 拼接容差）', () async {
      final store =
          McpTokenStore(preferences: await SharedPreferences.getInstance());
      final token = await store.regenerate();
      expect(store.verify('  $token '), isTrue);
    });

    test('重新生成后旧令牌立即失效', () async {
      final store =
          McpTokenStore(preferences: await SharedPreferences.getInstance());
      final oldToken = await store.regenerate();
      expect(store.verify(oldToken), isTrue);

      final newToken = await store.regenerate();
      expect(store.verify(oldToken), isFalse, reason: '旧令牌必须立即失效');
      expect(store.verify(newToken), isTrue);
      expect(oldToken, isNot(newToken));
    });

    test('提示片段与审计指纹不暴露完整令牌', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = McpTokenStore(preferences: prefs);
      final token = await store.regenerate();

      final hint = store.tokenHint!;
      expect(hint.startsWith(token.substring(0, 4)), isTrue);
      expect(hint.endsWith(token.substring(60)), isTrue);
      expect(hint.contains(token.substring(10, 50)), isFalse);

      expect(store.auditFingerprint, hasLength(8));
      expect(token.contains(store.auditFingerprint), isFalse,
          reason: '审计指纹是摘要前缀，不能出现在明文令牌中');
    });

    test('令牌摘要持久化：新实例可校验旧令牌', () async {
      final prefs = await SharedPreferences.getInstance();
      final token = await McpTokenStore(preferences: prefs).regenerate();

      final restored =
          McpTokenStore(preferences: await SharedPreferences.getInstance());
      expect(restored.verify(token), isTrue);
    });
  });
}
