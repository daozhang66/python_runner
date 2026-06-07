import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('script editor has command bar and status bar', () {
    final source = File('lib/pages/script_editor_page.dart').readAsStringSync();

    expect(source, contains('Widget _buildCommandBar('));
    expect(source, contains('Widget _buildEditorStatusBar('));
    expect(source, contains('AppToolbarButton('));
    expect(source, contains('已修改'));
  });
}
