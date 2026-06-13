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
    expect(terminal, contains('TerminalColorMode.dark'));
    expect(terminal, contains('_colorModePrefsKey'));
    expect(terminal, contains('prefs.setString(_colorModePrefsKey'));
    expect(terminal, contains('inputFillColor'));
    expect(terminal, contains('inputTextColor'));
    expect(terminal, contains('inputBorderColor'));
    expect(terminal, contains('toolbarText'));
    expect(terminal, contains('toolbarMuted'));
    expect(terminal, contains('toolbarActive'));
    expect(terminal, contains('toolbarHintColor'));
    expect(terminal, contains('foregroundColor: toolbarText'));
    expect(terminal, contains('iconColor: toolbarActive'));
    expect(terminal, contains('BoxConstraints(minHeight: 44)'));
    expect(terminal, contains('Border.all(color: inputBorderColor'));
    expect(terminal, contains('filled: false'));
    expect(terminal, contains('fillColor: Colors.transparent'));
    expect(terminal, contains('border: InputBorder.none'));
  });
}
