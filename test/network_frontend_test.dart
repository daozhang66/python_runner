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
}
