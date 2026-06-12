import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String settingsPageSource() => [
      'lib/pages/settings_page.dart',
      'lib/pages/settings_actions.dart',
      'lib/pages/settings_sections.dart',
      'lib/pages/settings_widgets.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');

void main() {
  test('settings page exposes grouped sections without duplicate runtime card',
      () {
    final source = settingsPageSource();

    expect(source, contains('Widget _buildAppearanceSection('));
    expect(source, contains('Widget _buildRuntimeSection('));
    expect(source, contains('Widget _buildNetworkDebugSection('));
    expect(source, contains('Widget _buildDiagnosticsSection('));
    expect(source, contains('Widget _buildAboutSection('));
    expect(source, contains('_buildAppearanceSection(),'));
    expect(source, contains('_buildRuntimeSection(),'));
    expect(source, contains('_buildNetworkDebugSection(),'));
    expect(source, contains('_buildDiagnosticsSection(),'));
    expect(source, contains('_buildAboutSection(),'));
    expect(source, isNot(contains('_buildRuntimeStatusCard(),')));
    expect(source, isNot(contains('Widget _buildRuntimeStatusCard(')));
    expect(source, isNot(contains('if (false)')));
    expect(source, isNot(contains('ignore: dead_code')));
    expect(source, isNot(contains('=> const SizedBox.shrink()')));
  });
}
