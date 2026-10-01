import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:python_runner/features/mcp/infrastructure/mcp_token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../support/mcp_token_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('McpTokenStore', () {
    test('custom keys persist, stay visible, and notify on every replacement',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = MemoryTokenStorage();
      final store = McpTokenStore(preferences: prefs, storage: storage);
      addTearDown(store.dispose);
      var changes = 0;
      store.addListener(() => changes++);
      await store.initialize();
      const first = 'custom-key-for-tests-1234';
      const second = 'custom-key-for-tests-5678';
      await store.setCustomToken(first);
      expect(store.token, first);
      expect(store.verify(first), isTrue);
      final initialChanges = changes;
      await store.setCustomToken('  $second  ');
      expect(changes, greaterThan(initialChanges));
      expect(store.token, second);
      expect(store.verify(first), isFalse);
      expect(store.verify(second), isTrue);
      expect(prefs.getKeys(), isNot(contains(McpTokenStore.tokenKey)));
      expect(prefs.getKeys(), isNot(contains(McpTokenStore.hashKey)));
      final restored = McpTokenStore(preferences: prefs, storage: storage);
      addTearDown(restored.dispose);
      await restored.initialize();
      expect(restored.token, second);
      expect(restored.verify(second), isTrue);
    });

    test('invalid keys and failed writes keep the previous credential',
        () async {
      final storage = MemoryTokenStorage(value: 'existing-key-for-testing');
      final store = McpTokenStore(
          preferences: await SharedPreferences.getInstance(), storage: storage);
      addTearDown(store.dispose);
      await store.initialize();
      for (final value in [
        '',
        'short',
        'has spaces inside key',
        'bad\r\nheader-12345678',
        'non-ascii-密钥-12345678',
        'a' * 257
      ]) {
        expect(() => store.setCustomToken(value), throwsArgumentError);
      }
      storage.failWrites = true;
      await expectLater(store.regenerate(), throwsStateError);
      expect(store.token, 'existing-key-for-testing');
      expect(store.verify(store.token), isTrue);
      expect(storage.value, store.token);
      storage.failWrites = false;
      await store.regenerate();
      expect(store.token, isNot('existing-key-for-testing'));
    });

    test('legacy digests stay valid and can regain a visible original key',
        () async {
      const original = 'known-legacy-token-123456';
      SharedPreferences.setMockInitialValues({
        McpTokenStore.hashKey: sha256.convert(utf8.encode(original)).toString(),
        McpTokenStore.hintKey: 'know…3456',
      });
      final prefs = await SharedPreferences.getInstance();
      final store =
          McpTokenStore(preferences: prefs, storage: MemoryTokenStorage());
      addTearDown(store.dispose);
      await store.initialize();
      expect(store.isLegacyToken, isTrue);
      expect(store.token, isNull);
      expect(store.verify(original), isTrue);
      await store.setCustomToken(original);
      expect(store.isLegacyToken, isFalse);
      expect(store.token, original);
      expect(store.verify(original), isTrue);
    });

    test('initialization retries and concurrent updates remain ordered',
        () async {
      final storage = MemoryTokenStorage()..failReads = true;
      final store = McpTokenStore(
          preferences: await SharedPreferences.getInstance(), storage: storage);
      await expectLater(store.initialize(), throwsStateError);
      expect(store.loadFailed, isTrue);
      storage.failReads = false;
      await store.initialize();
      expect(store.loadFailed, isFalse);
      storage.writeGate = Completer<void>();
      final generated = store.regenerate();
      final custom = store.setCustomToken('last-custom-key-123456');
      await Future<void>.delayed(Duration.zero);
      expect(storage.writes, 1);
      storage.writeGate!.complete();
      await generated;
      await custom;
      expect(store.token, 'last-custom-key-123456');
      expect(storage.value, store.token);
      store.dispose();
    });

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
      await restored.initialize();
      expect(restored.verify(token), isTrue);
      expect(restored.token, token);
    });
  });
}
