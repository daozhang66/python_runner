import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/ui/app_liquid_host.dart';
import 'package:python_runner/ui/app_settings_section.dart';
import 'package:python_runner/ui/app_theme.dart';
import 'package:python_runner/ui/app_visual_style.dart';
import 'package:python_runner/utils/app_page_transitions.dart';

Future<Uint8List> _pixels(WidgetTester tester, GlobalKey key) async =>
    (await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1);
      try {
        return Uint8List.fromList(
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer
              .asUint8List(),
        );
      } finally {
        image.dispose();
      }
    }))!;

void main() {
  for (final style in AppVisualStyle.values) {
    for (final customRoute in [false, true]) {
      for (final brightness in Brightness.values) {
        testWidgets(
          'settings row clears pressed ink after return: $style custom=$customRoute $brightness',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = const Size(390, 700);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(tester.view.resetPhysicalSize);
            final shot = GlobalKey();
            final navigator = GlobalKey<NavigatorState>();
            await tester.pumpWidget(
              MaterialApp(
                navigatorKey: navigator,
                theme: AppTheme.build(
                  ColorScheme.fromSeed(
                    seedColor: Colors.blue,
                    brightness: brightness,
                  ),
                  visualStyle: style,
                ),
                builder: (_, child) => AppLiquidHost(child: child!),
                home: Scaffold(
                  body: RepaintBoundary(
                    key: shot,
                    child: ListView(
                      children: [
                        for (var i = 0; i < 3; i++)
                          AppSettingsSection(
                            framed: true,
                            icon: Icons.settings,
                            title: 'Section $i',
                            children: [
                              ListTile(
                                title: Text('Open $i'),
                                subtitle: const Text('Description'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  const next = Scaffold(
                                    body: Center(child: Text('Detail')),
                                  );
                                  navigator.currentState!.push(
                                    customRoute
                                        ? AppPageTransitions.sharedAxisLeftRight(
                                            next,
                                          )
                                        : MaterialPageRoute<void>(
                                            builder: (_) => next,
                                          ),
                                  );
                                },
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final before = await _pixels(tester, shot);
            for (var i = 0; i < 3; i++) {
              final target = find.text('Open $i');
              final press = await tester.startGesture(tester.getCenter(target));
              await tester.pump(const Duration(milliseconds: 120));
              await tester.pump(const Duration(milliseconds: 80));
              if (i == 0 && style == AppVisualStyle.classic) {
                expect(
                  await _pixels(tester, shot),
                  isNot(orderedEquals(before)),
                  reason: 'Keep normal pressed feedback; only stale ink must be removed',
                );
              }
              await press.up();
              await tester.pumpAndSettle();
              await tester.pump(const Duration(seconds: 1));
              navigator.currentState!.pop();
              await tester.pumpAndSettle();
              await tester.pump(const Duration(seconds: 2));
            }
            final after = await _pixels(tester, shot);
            var changed = 0;
            for (var i = 0; i < before.length; i += 4) {
              if ((before[i] - after[i]).abs() > 2 ||
                  (before[i + 1] - after[i + 1]).abs() > 2 ||
                  (before[i + 2] - after[i + 2]).abs() > 2) {
                changed++;
              }
            }
            tester.printToConsole('persistently changed pixels=$changed');
            expect(
              changed,
              lessThan(20),
              reason: 'Released navigation ink must not remain on visited settings rows',
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
