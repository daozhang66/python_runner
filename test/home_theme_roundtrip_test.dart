import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/scripts/presentation/pages/script_list_page.dart';
import 'package:python_runner/models/script_file.dart';
import 'package:python_runner/ui/app_navigation_pages.dart';
import 'package:python_runner/ui/app_theme.dart';
import 'package:python_runner/ui/app_visual_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/script_workspace_harness.dart';

void main() {
  for (final grid in [false, true]) {
    testWidgets('hidden home refreshes theme without reopening: grid=$grid', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'script_grid_view': grid});
      final prefs = await SharedPreferences.getInstance();
      final harness = ScriptWorkspaceHarness(
        preferences: prefs,
        bridge: FakeScriptNativeBridge(scriptNames: ['daily.py']),
        database: InMemoryScriptDatabase(
          scripts: [
            ScriptFile(
              name: 'daily.py',
              path: 'daily.py',
              sortOrder: 0,
              createdAt: DateTime(2026),
              modifiedAt: DateTime(2026),
              runCount: 3,
            ),
          ],
        ),
      );
      addTearDown(harness.dispose);
      final mode = ValueNotifier(Brightness.dark);
      final page = ValueNotifier(0);
      addTearDown(mode.dispose);
      addTearDown(page.dispose);
      final shot = GlobalKey();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        harness.buildPage(
          AnimatedBuilder(
            animation: Listenable.merge([mode, page]),
            builder: (_, _) => AnimatedTheme(
              data: AppTheme.build(
                ColorScheme.fromSeed(
                  seedColor: Colors.blue,
                  brightness: mode.value,
                ),
                visualStyle: AppVisualStyle.liquid,
              ),
              duration: const Duration(milliseconds: 200),
              child: AppNavigationPages(
                index: page.value,
                children: [
                  RepaintBoundary(key: shot, child: const ScriptListPage()),
                  const Scaffold(body: Text('Settings')),
                ],
              ),
            ),
          ),
          brightness: Brightness.dark,
        ),
      );
      await tester.pumpAndSettle();
      final homeState = tester.state(find.byType(ScriptListPage));
      final dark = await _pixels(tester, shot);
      Uint8List? light;
      for (final next in [
        Brightness.light,
        Brightness.dark,
        Brightness.light,
        Brightness.dark,
      ]) {
        page.value = 1;
        await tester.pumpAndSettle();
        mode.value = next;
        await tester.pumpAndSettle();
        page.value = 0;
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(ScriptListPage)), same(homeState));
        final pixels = await _pixels(tester, shot);
        if (next == Brightness.light) {
          expect(
            List.generate(
              pixels.length,
              (i) => pixels[i] == dark[i] ? 0 : 1,
            ).fold<int>(0, (a, b) => a + b),
            greaterThan(1000),
            reason: 'Changing brightness must actually change the visible home',
          );
        }
        light ??= pixels;
        final expected = next == Brightness.dark ? dark : light;
        final changed = List.generate(
          pixels.length,
          (i) => pixels[i] == expected[i] ? 0 : 1,
        ).fold<int>(0, (a, b) => a + b);
        expect(
          changed,
          0,
          reason: 'The same theme must draw the same home after returning from settings',
        );
        expect(tester.takeException(), isNull);
      }
    });
  }
}

Future<Uint8List> _pixels(
  WidgetTester tester,
  GlobalKey key,
) async => (await tester.runAsync(() async {
  final image =
      await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
          .toImage();
  try {
    return Uint8List.fromList((await image.toByteData())!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}))!;
