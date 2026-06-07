import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('terminal frontend uses console chrome and status badges', () {
    final console = File('lib/pages/run_console_page.dart').readAsStringSync();
    final terminal = File('lib/widgets/terminal_view.dart').readAsStringSync();

    expect(console, contains('AppStatusBadge('));
    expect(console, contains('运行中'));
    expect(console, contains('等待输入'));
    expect(console, contains('Widget _buildRunStatusBadge('));
    expect(
      RegExp(r'AppStatusBadge\([\s\S]{0,900}AnimatedSwitcher')
          .hasMatch(console),
      isFalse,
    );
    expect(terminal, contains('_buildTerminalToolbar'));
    expect(terminal, contains('_buildStdinPrompt'));
    expect(terminal, contains('fontFamily:'));
  });
}
