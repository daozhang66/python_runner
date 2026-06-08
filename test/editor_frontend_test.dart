import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('script editor has command bar and status bar', () {
    final source = File('lib/pages/script_editor_page.dart').readAsStringSync();

    expect(source, contains('Widget _buildCommandBar('));
    expect(source, contains('Widget _buildEditorStatusBar('));
    expect(source, contains('PopupMenuButton<String>'));
    expect(source, contains("tooltip: '更多'"));
    expect(source, contains("tooltip: '编辑操作'"));
    expect(source, contains('Text(\'编辑操作\')'));
    expect(source, isNot(contains('void _showFontSizeSlider()')));
    expect(source, isNot(contains('Icons.format_size')));
    expect(source, isNot(contains("tooltip: '字体大小'")));
    expect(source, contains('已修改'));
  });

  test('project file editor consolidates actions and hides font button', () {
    final source =
        File('lib/pages/project_file_editor_page.dart').readAsStringSync();

    expect(source, contains('PopupMenuButton<String>'));
    expect(source, contains("tooltip: '更多'"));
    expect(source, contains("tooltip: '编辑操作'"));
    expect(source, contains('project_editor_font_size'));
    expect(source, isNot(contains('void _showFontSizeSlider()')));
    expect(source, isNot(contains('Icons.format_size')));
    expect(source, isNot(contains("tooltip: '字体大小'")));
  });
}
