import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:python_runner/services/network_debug_config.dart';

void main() {
  final config = NetworkDebugConfig.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await config.setDebugMode(false);
    await config.setProxy('', 0);
  });

  tearDown(() async {
    await config.setDebugMode(false);
    await config.setProxy('', 0);
  });

  group('NetworkDebugConfig proxy validation', () {
    test('accepts hostname, IPv4 and IPv6 literals', () async {
      await config.setProxy('localhost', 8080);
      expect(config.proxyHost, 'localhost');
      expect(config.proxyPort, 8080);

      await config.setProxy('Proxy.Example.COM', 3128);
      expect(config.proxyHost, 'proxy.example.com');

      await config.setProxy('127.0.0.1', 9000);
      expect(config.proxyAddress, '127.0.0.1:9000');

      await config.setProxy('[::1]', 8081);
      expect(config.proxyHost, '::1');
      expect(config.proxyAddress, '[::1]:8081');
    });

    test('clears proxy only with empty host and zero port', () async {
      await config.setProxy('localhost', 8080);
      await config.setProxy('', 0);

      expect(config.proxyHost, isEmpty);
      expect(config.proxyPort, 0);
    });

    test('rejects invalid host and port combinations without persisting them',
        () async {
      await config.setProxy('localhost', 8080);
      for (final (host, port) in <(String, int)>[
        ('http://proxy.example', 8080),
        ('proxy.example:8080', 8080),
        ('proxy/path', 8080),
        (' localhost', 8080),
        ('', 8080),
        ('localhost', 0),
        ('localhost', 65536),
      ]) {
        await expectLater(
          config.setProxy(host, port),
          throwsA(isA<FormatException>()),
        );
      }
      expect(config.proxyHost, 'localhost');
      expect(config.proxyPort, 8080);
    });

    test('disables invalid saved proxy configuration on load', () async {
      SharedPreferences.setMockInitialValues({
        'net_debug_mode': true,
        'net_proxy_host': 'https://proxy.example',
        'net_proxy_port': 99999,
      });

      await config.load();

      expect(config.proxyHost, isEmpty);
      expect(config.proxyPort, 0);
      expect(config.hasProxy, isFalse);
    });
  });
}
