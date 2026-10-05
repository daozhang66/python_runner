import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/scripts/presentation/pages/script_list_page.dart';
import 'package:python_runner/models/script_file.dart';
import 'package:python_runner/ui/app_theme.dart';
import 'package:python_runner/ui/app_visual_style.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/script_workspace_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in {
      'MiSans': 'assets/fonts/MiSansVF.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf'
    }.entries) {
      final loader = FontLoader(font.key)..addFont(rootBundle.load(font.value));
      await loader.load();
    }
  });
  for (final brightness in Brightness.values) {
    for (final grid in [false, true]) {
      testWidgets('liquid workspace $brightness grid=$grid', (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final harness = ScriptWorkspaceHarness(
            preferences: prefs,
            bridge:
                FakeScriptNativeBridge(scriptNames: ['daily.py', 'report.py']),
            database: InMemoryScriptDatabase(scripts: [
              for (final (index, name) in ['daily.py', 'report.py'].indexed)
                ScriptFile(
                    name: name,
                    path: name,
                    sortOrder: index,
                    createdAt: DateTime(2026, 1, 2),
                    modifiedAt: DateTime(2026, 1, 2, 3, 4),
                    runCount: 3),
            ]));
        addTearDown(harness.dispose);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(harness.buildPage(
            Theme(
                data: AppTheme.build(
                    ColorScheme.fromSeed(
                        seedColor: Colors.blue, brightness: brightness),
                    fontFamily: 'MiSans',
                    visualStyle: AppVisualStyle.liquid),
                child: const ScriptListPage()),
            brightness: brightness));
        await tester.pumpAndSettle();
        if (grid) {
          await tester.tap(find.byWidgetPredicate((widget) => widget is PopupMenuButton<String>));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(ListTile, '宫格视图'));
          await tester.pumpAndSettle();
        }
        await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
                'goldens/global_liquid_scripts_${brightness.name}_${grid ? "grid" : "list"}.png'));
      }, tags: const ['golden']);
    }
  }
}
