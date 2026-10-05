import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/scripts/presentation/widgets/code_find_panel.dart';
import 'package:python_runner/l10n/app_localizations.dart';
import 'package:python_runner/ui/app_theme.dart';
import 'package:python_runner/ui/app_visual_style.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  setUpAll(() async {
    for (final font in {
      'MiSans': 'assets/fonts/MiSansVF.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  for (final visual in AppVisualStyle.values) {
    for (final brightness in Brightness.values) {
      for (final width in [280.0, 320.0, 390.0, 600.0]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets(
            'find panel fits $visual $brightness $width scale=$scale',
            (tester) async {
              tester.view.devicePixelRatio = 1;
              tester.view.physicalSize = Size(width, 500);
              addTearDown(tester.view.resetDevicePixelRatio);
              addTearDown(tester.view.resetPhysicalSize);
              final editing = CodeLineEditingController.fromText(
                'import os\nprint("hello")\nprint("world")',
              );
              final find = CodeFindController(editing);
              addTearDown(editing.dispose);
              addTearDown(find.dispose);
              await tester.pumpWidget(
                MaterialApp(
                  theme: AppTheme.build(
                    ColorScheme.fromSeed(
                      seedColor: Colors.indigo,
                      brightness: brightness,
                    ),
                    visualStyle: visual,
                    fontFamily: 'MiSans',
                  ),
                  locale: const Locale('zh'),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: MediaQuery(
                    data: MediaQueryData(
                      size: Size(width, 500),
                      textScaler: TextScaler.linear(scale),
                    ),
                    child: Scaffold(
                      body: CodeEditor(
                        controller: editing,
                        findController: find,
                        autofocus: false,
                        style: const CodeEditorStyle(fontFamily: 'MiSans'),
                        findBuilder: (context, controller, readOnly) =>
                            CodeFindPanelView(
                              controller: controller,
                              readOnly: readOnly,
                              textScaler: MediaQuery.textScalerOf(context),
                            ),
                      ),
                    ),
                  ),
                ),
              );
              find.findMode();
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              final panel = tester.getRect(findWidgetPanel);
              for (final icon in [
                Icons.arrow_upward,
                Icons.arrow_downward,
                Icons.close,
              ]) {
                final button = findIcon(icon);
                expect(panel.contains(tester.getRect(button).topLeft), isTrue);
                expect(
                  panel.contains(
                    tester.getRect(button).bottomRight - const Offset(0.1, 0.1),
                  ),
                  isTrue,
                );
                expect(
                  tester.getSize(button).shortestSide,
                  greaterThanOrEqualTo(48),
                );
              }
              expect(findText('No results'), findsNothing);
              expect(findText('无匹配结果'), findsOneWidget);
              await tester.tap(findIcon(Icons.close));
              await tester.pumpAndSettle();
              expect(find.value, isNull);
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox());
            },
          );
        }
      }
    }
  }
}

// These aliases avoid shadowing flutter_test's finder with the controller.
Finder get findWidgetPanel => find.byType(CodeFindPanelView);
Finder get findEditor => find.byType(CodeEditor);
Finder findIcon(IconData icon) => find.widgetWithIcon(IconButton, icon);
Finder findText(String value) => find.text(value);
