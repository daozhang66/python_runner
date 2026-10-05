import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/scripts/presentation/pages/script_list_page.dart';
import 'package:python_runner/models/script_file.dart';
import 'package:python_runner/ui/app_popup_menu.dart';
import 'package:python_runner/ui/app_theme.dart';
import 'package:python_runner/ui/app_visual_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/script_workspace_harness.dart';

void main() {
  for (final locale in ['zh', 'en']) {
    for (final width in [320.0, 390.0]) {
      for (final textScale in [1.0, 1.5]) {
        testWidgets(
            'script glass menu matches original width: $locale $width $textScale',
            (tester) async {
          SharedPreferences.setMockInitialValues({});
          final harness = ScriptWorkspaceHarness(
            preferences: await SharedPreferences.getInstance(),
            bridge: FakeScriptNativeBridge(scriptNames: ['demo.py']),
            database: InMemoryScriptDatabase(scripts: [
              ScriptFile(
                  name: 'demo.py',
                  path: 'demo.py',
                  createdAt: DateTime(2026),
                  modifiedAt: DateTime(2026))
            ]),
          );
          addTearDown(harness.dispose);
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 844);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final visualStyle = ValueNotifier(AppVisualStyle.classic);
          addTearDown(visualStyle.dispose);
          await tester.pumpWidget(harness.buildPage(
            ValueListenableBuilder<AppVisualStyle>(
                valueListenable: visualStyle,
                builder: (_, style, child) => Theme(
                      data: AppTheme.build(
                          ColorScheme.fromSeed(seedColor: Colors.blue),
                          visualStyle: style),
                      child: child!,
                    ),
                child: const ScriptListPage()),
            locale: Locale(locale),
            textScaleFactor: textScale,
          ));
          double? originalWidth;
          for (final style in AppVisualStyle.values) {
            visualStyle.value = style;
            await tester.pumpAndSettle();
            await tester.tap(find.byType(AppPopupMenuButton<String>));
            await tester.pumpAndSettle();
            final item = find
                .byWidgetPredicate((widget) => widget is PopupMenuItem<String>)
                .first;
            final rect = tester.getRect(item);
            if (style == AppVisualStyle.classic) {
              originalWidth = rect.width;
            } else {
              expect(rect.width, closeTo(originalWidth!, 0.01));
            }
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(width));
            expect(tester.takeException(), isNull);
            await tester.tapAt(const Offset(2, 800));
            await tester.pumpAndSettle();
          }
        });
      }
    }
  }
}
