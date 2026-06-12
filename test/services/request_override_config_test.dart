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
  });
}
