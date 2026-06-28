import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String networkInspectorSource() => [
      'lib/pages/network_inspector_page.dart',
      'lib/pages/network_inspector_widgets.dart',
      'lib/pages/network_inspector_detail.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');

void main() {
  test('network inspector uses dashboard and request badges', () {
    final source = networkInspectorSource();

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
    final source = networkInspectorSource();
    final storeSource =
        File('lib/services/http_inspector_store.dart').readAsStringSync();

    expect(source, contains("'DNS'"));
    expect(source, contains("'CONNECT'"));
    expect(source, contains("'PROCESS'"));
    expect(source, contains('Icons.visibility_off_outlined'));
    expect(source, contains('isSelected: _store.hideNoiseMethods'));
    expect(source, contains('显示 DNS/connect/进程记录'));
    expect(source, contains('隐藏 DNS/connect/进程记录'));
    expect(source, contains('_store.visibleStats'));
    expect(source, contains(r'显示 $visibleTotal / 全部'));
    expect(source, contains('运行包含网络请求的脚本后'));
    expect(storeSource, contains("static const Set<String> noiseMethods"));
    expect(storeSource, contains("'DNS', 'CONNECT', 'PROCESS'"));
    expect(
      storeSource,
      contains('if (_hideNoiseMethods && isNoiseMethod(_filterMethod))'),
    );
  });

  test('full body search uses read-only code editor find navigation', () {
    final source = networkInspectorSource();

    expect(source, contains('CodeLineEditingController'));
    expect(source, contains('CodeFindController'));
    expect(source, contains('CodeScrollController'));
    expect(source, contains('CodeEditor('));
    expect(source,
        contains("key: const ValueKey('network_full_body_code_editor')"));
    expect(source, contains('SelectionToolbarController'));
    expect(source, contains('_buildSelectionToolbarController'));
    expect(source, contains('toolbarController: _toolbarController'));
    expect(source, contains('ContextMenuButtonType.copy'));
    expect(source, contains('ContextMenuButtonType.selectAll'));
    expect(source, contains('void _copyFormattedBody()'));
    expect(source, contains('readOnly: true'));
    expect(source, contains('wordWrap: true'));
    expect(source, contains('chunkAnalyzer: const NonCodeChunkAnalyzer()'));
    expect(source, contains('_formatTextBody('));
    expect(source, contains('_looksLikeHtml('));
    expect(source, contains('_basicFormatHtml('));
    expect(source, contains('class _BodyCodeFindPanel'));
    expect(source, contains('controller.previousMatch'));
    expect(source, contains('controller.nextMatch'));
    expect(source, isNot(contains('SelectableText.rich(')));
    expect(source, isNot(contains('List<int> _searchMatches')));
    expect(source, isNot(contains('class _BodySearchMatch')));
    expect(source, isNot(contains('Approximate: each line is roughly')));
  });
}
