import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('large Flutter pages are split into focused part files', () {
    final expectedLineCaps = {
      'lib/pages/network_inspector_page.dart': 500,
      'lib/pages/script_list_page.dart': 500,
      'lib/pages/settings_page.dart': 500,
    };

    for (final entry in expectedLineCaps.entries) {
      final lineCount = File(entry.key).readAsLinesSync().length;
      expect(lineCount, lessThanOrEqualTo(entry.value), reason: entry.key);
    }

    expect(
        File('lib/pages/network_inspector_detail.dart').existsSync(), isTrue);
    expect(
        File('lib/pages/network_inspector_widgets.dart').existsSync(), isTrue);
    expect(File('lib/pages/script_list_actions.dart').existsSync(), isTrue);
    expect(File('lib/pages/script_list_content.dart').existsSync(), isTrue);
    expect(File('lib/pages/script_list_widgets.dart').existsSync(), isTrue);
    expect(File('lib/pages/settings_actions.dart').existsSync(), isTrue);
    expect(File('lib/pages/settings_sections.dart').existsSync(), isTrue);
    expect(File('lib/pages/settings_widgets.dart').existsSync(), isTrue);
  });

  test('MainActivity delegates native bridge policy and script files', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt',
    ).readAsStringSync();
    final scriptStore = File(
      'android/app/src/main/kotlin/com/daozhang/py/ScriptFileStore.kt',
    ).readAsStringSync();

    expect(mainActivity, contains('NativeBridgeContract.validate'));
    expect(mainActivity, contains('ScriptFileStore(filesDir)'));
    expect(mainActivity, contains('scriptFileStore.createScript'));
    expect(mainActivity, contains('scriptFileStore.listScripts'));

    expect(scriptStore, contains('class ScriptFileStore'));
    expect(scriptStore, contains('fun safeScriptFile'));
    expect(scriptStore, contains('fun listScripts'));
  });
}
