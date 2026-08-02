import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:python_runner/services/request_override_config.dart';

void main() {
  group('RequestOverrideConfig', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('setGlobalHeaders validates JSON object input', () async {
      final config = RequestOverrideConfig.instance;
      await config.load();

      expect(
        () => config.setGlobalHeaders('[["Accept", "application/json"]]'),
        throwsA(isA<FormatException>()),
      );

      await config.setGlobalHeaders('{"Accept":"application/json"}');

      expect(config.parsedHeaders, {'Accept': 'application/json'});
      expect(config.configError, isNull);
    });

    test('load preserves invalid saved strings and exposes configError',
        () async {
      SharedPreferences.setMockInitialValues({
        'req_global_headers': '{"Accept":',
        'req_domain_rules': '{"example.com": true}',
      });

      final config = RequestOverrideConfig.instance;
      await config.load();

      expect(config.globalHeaders, '{"Accept":');
      expect(config.domainRulesJson, '{"example.com": true}');
      expect(config.parsedHeaders, isEmpty);
      expect(config.domainRules, isEmpty);
      expect(config.configError, contains('全局请求头配置错误'));
      expect(config.configError, contains('域名规则配置错误'));
    });

    test('parsed headers use the validated cache and recover after correction',
        () async {
      SharedPreferences.setMockInitialValues({
        'req_global_headers': '{"Accept":',
      });
      final config = RequestOverrideConfig.instance;
      await config.load();

      expect(config.parsedHeaders, isEmpty);
      expect(config.configError, contains('全局请求头配置错误'));

      await config.setGlobalHeaders('{"Accept":"application/json"}');

      expect(config.parsedHeaders, {'Accept': 'application/json'});
      expect(config.configError, isNull);
    });

    test('setDomainRules saves valid JSON and clears domain rule error',
        () async {
      SharedPreferences.setMockInitialValues({
        'req_domain_rules': 'not json',
      });

      final config = RequestOverrideConfig.instance;
      await config.load();
      expect(config.configError, contains('域名规则配置错误'));

      await config.setDomainRules([
        {
          'domain': 'example.com',
          'headers': <String, String>{'X-Test': '1'}
        },
      ]);

      expect(config.domainRules, hasLength(1));
      expect(config.domainRulesJson, contains('example.com'));
      expect(config.configError, isNull);
    });

    test('applyOverrides validates before changing the active configuration',
        () async {
      final config = RequestOverrideConfig.instance;
      await config.load();
      await config.applyOverrides(
        userAgent: 'agent-a',
        headersJson: '{"X-Mode":"first"}',
        cookie: 'a=1',
        timeoutSeconds: 15,
        followRedirects: true,
        useDebugProxyWhenUnset: false,
        domainRules: const [],
      );

      await expectLater(
        config.applyOverrides(
          userAgent: 'agent-b',
          headersJson: '[]',
          cookie: '',
          timeoutSeconds: 0,
          followRedirects: false,
          useDebugProxyWhenUnset: false,
          domainRules: const [],
        ),
        throwsA(isA<FormatException>()),
      );

      expect(config.globalUserAgent, 'agent-a');
      expect(config.parsedHeaders, {'X-Mode': 'first'});
      expect(config.defaultTimeout, 15);
    });

    test('domain rules preview first wildcard match over global fields',
        () async {
      final config = RequestOverrideConfig.instance;
      await config.load();
      await config.applyOverrides(
        userAgent: 'global-agent',
        headersJson: '{"X-Global":"1"}',
        cookie: 'global=1',
        timeoutSeconds: 0,
        followRedirects: true,
        useDebugProxyWhenUnset: false,
        domainRules: [
          {
            'domain': '*.example.com',
            'user_agent': 'wildcard-agent',
            'headers': {'X-Rule': 'first'},
          },
          {
            'domain': 'api.example.com',
            'user_agent': 'later-agent',
          },
        ],
      );

      final preview = config.previewForHost('api.example.com');
      expect(preview.matchedRuleIndex, 0);
      expect(preview.userAgent, 'wildcard-agent');
      expect(preview.cookie, 'global=1');
      expect(preview.headers, {'X-Global': '1', 'X-Rule': 'first'});
      expect(
        RequestOverrideConfig.validateDomainPattern('https://example.com'),
        isNotNull,
      );
    });

    test('export and import preserve a complete override configuration',
        () async {
      final config = RequestOverrideConfig.instance;
      await config.load();
      await config.applyOverrides(
        userAgent: 'export-agent',
        headersJson: '{"X-Export":42}',
        cookie: 'token=abc',
        timeoutSeconds: 45,
        followRedirects: false,
        useDebugProxyWhenUnset: true,
        domainRules: [
          {
            'domain': 'example.com',
            'cookie': 'domain=1',
          },
        ],
      );
      final exported = config.exportOverrides();

      SharedPreferences.setMockInitialValues({});
      await config.load();
      await config.importOverrides(exported);

      expect(config.globalUserAgent, 'export-agent');
      expect(config.parsedHeaders, {'X-Export': '42'});
      expect(config.defaultTimeout, 45);
      expect(config.followRedirects, isFalse);
      expect(config.forceProxy, isTrue);
      expect(config.domainRules.single['domain'], 'example.com');
    });
  });
}
