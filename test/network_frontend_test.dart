import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('network inspector uses dashboard and request badges', () {
    final source =
        File('lib/pages/network_inspector_page.dart').readAsStringSync();

    expect(source, contains('Widget _buildRequestDashboard('));
    expect(source, contains('Widget _buildMethodBadge('));
    expect(source, contains('Widget _buildStatusBadge('));
    expect(source, contains('AppSearchBar('));
    expect(source, contains('AppSectionCard('));
    expect(source, contains('LayoutBuilder('));
    expect(source, contains('useStackedLayout'));
    expect(source, contains('hasLongValue'));
    expect(source, contains('value.length > 24'));
    expect(source, contains('EdgeInsets.fromLTRB(16, 0, 16, 6)'));
    expect(source, isNot(contains('class _SectionCard')));
  });

  test('network hook captures dns socket and subprocess activity', () {
    final hookFiles = [
      'android/app/src/main/python/http_debug_hook.py',
      'android/app/src/main/assets/python_hooks/http_debug_hook.py',
      'assets/python_hooks/http_debug_hook.py',
    ];

    for (final path in hookFiles) {
      final source = File(path).readAsStringSync();
      expect(source, contains('def _hook_socket():'));
      expect(source, contains('socket.getaddrinfo = _patched_getaddrinfo'));
      expect(source, contains('socket.socket.connect = _patched_connect'));
      expect(source, contains('def _hook_subprocess():'));
      expect(source, contains('subprocess.run = _patched_run'));
      expect(source, contains("'method': 'DNS'"));
      expect(source, contains("'method': 'CONNECT'"));
      expect(source, contains("'method': 'PROCESS'"));
      expect(source, contains('_hook_socket()'));
      expect(source, contains('_hook_subprocess()'));
    }
  });

  test('network inspector exposes non-http network method filters', () {
    final source =
        File('lib/pages/network_inspector_page.dart').readAsStringSync();

    expect(source, contains("'DNS'"));
    expect(source, contains("'CONNECT'"));
    expect(source, contains("'PROCESS'"));
    expect(source, contains('运行包含网络请求的脚本后'));
  });
}
