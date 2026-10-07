import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g1455/glass_diagnostics.dart' as diagnostics;
import 'package:python_runner/ui/app_card.dart';
import 'package:python_runner/ui/app_liquid_host.dart';
import 'package:python_runner/ui/app_theme.dart';
import 'package:python_runner/ui/app_visual_style.dart';
import 'package:python_runner/utils/app_page_transitions.dart';

Future<Uint8List> pixels(
  WidgetTester tester,
  GlobalKey shot,
  String name,
) async {
  return (await tester.runAsync(() async {
    final image =
        await (shot.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 1);
    try {
      final dir = Directory('build/glass-route-first-frame');
      await dir.create(recursive: true);
      await File('${dir.path}/$name.png').writeAsBytes(
        (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
            .asUint8List(),
      );
      return Uint8List.fromList(
        (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer
            .asUint8List(),
      );
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  for (final brightness in Brightness.values) {
    for (final material in [false, true]) {
      for (final plainDestination in [false, true]) {
        testWidgets(
          'glass route does not flash on push or pop: $brightness material=$material plain=$plainDestination',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = const Size(390, 700);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(tester.view.resetPhysicalSize);
            final navigator = GlobalKey<NavigatorState>();
            final shot = GlobalKey();
            Widget page(String label, {bool plain = false}) => Scaffold(
              appBar: AppBar(title: Text(label)),
              body: plain
                  ? const Center(child: Text('Plain details'))
                  : Center(
                      child: SizedBox(
                        width: 320,
                        height: 200,
                        child: AppCard(
                          child: Center(
                            child: FilledButton(
                              onPressed: () {},
                              child: const Text('Action'),
                            ),
                          ),
                        ),
                      ),
                    ),
            );
            await tester.pumpWidget(
              MaterialApp(
                navigatorKey: navigator,
                theme: AppTheme.build(
                  ColorScheme.fromSeed(
                    seedColor: Colors.blue,
                    brightness: brightness,
                  ),
                  visualStyle: AppVisualStyle.liquid,
                ),
                builder: (_, child) => RepaintBoundary(
                  key: shot,
                  child: AppLiquidHost(child: child!),
                ),
                home: page('Home'),
              ),
            );
            await tester.pumpAndSettle();
            final home = await pixels(
              tester,
              shot,
              'home-${brightness.name}-$material',
            );
            navigator.currentState!.push(
              material
                  ? MaterialPageRoute<void>(
                      builder: (_) => page('Details', plain: plainDestination),
                    )
                  : AppPageTransitions.sharedAxisLeftRight(
                      page('Details', plain: plainDestination),
                    ),
            );
            await tester.pump();
            final first = await pixels(
              tester,
              shot,
              'first-${brightness.name}-$material',
            );
            await tester.pump();
            final second = await pixels(
              tester,
              shot,
              'second-${brightness.name}-$material',
            );
            await tester.pumpAndSettle();
            final settled = await pixels(
              tester,
              shot,
              'settled-${brightness.name}-$material',
            );
            navigator.currentState!.pop();
            await tester.pump();
            final back = await pixels(
              tester,
              shot,
              'back-${brightness.name}-$material',
            );
            await tester.pump();
            final backSecond = await pixels(
              tester,
              shot,
              'back-second-${brightness.name}-$material',
            );
            // Sample the panel/button interiors away from labels. Allow under
            // two 8-bit levels for blur/shadow rounding; the missing finish
            // produced mean differences of 8.5 (light) and 16.9 (dark).
            double meanDifference(
              Uint8List a,
              Uint8List b, {
              bool button = false,
            }) {
              var total = 0, count = 0;
              for (var y = button ? 361 : 310; y < (button ? 367 : 340); y++) {
                for (var x = button ? 155 : 70; x < (button ? 235 : 320); x++) {
                  for (var c = 0; c < 3; c++) {
                    total +=
                        (a[(y * 390 + x) * 4 + c] - b[(y * 390 + x) * 4 + c])
                            .abs();
                    count++;
                  }
                }
              }
              return total / count;
            }

            final pushDelta = meanDifference(first, settled);
            final popDelta = meanDifference(back, home);
            tester.printToConsole(
              'push mean RGB delta=$pushDelta, pop=$popDelta',
            );
            expect(
              pushDelta,
              lessThan(2),
              reason: 'The first visible panel must already have its material',
            );
            expect(meanDifference(second, settled), lessThan(2));
            expect(
              popDelta,
              lessThan(2),
              reason: 'Returning must not expose an unpainted glass panel',
            );
            expect(meanDifference(backSecond, home), lessThan(2));
            expect(
              meanDifference(first, settled, button: true),
              lessThan(2),
              reason: 'Buttons also need their fill on the first frame',
            );
            expect(meanDifference(back, home, button: true), lessThan(2));
            expect(meanDifference(backSecond, home, button: true), lessThan(2));
            await tester.pumpAndSettle();
            if (!plainDestination && !material) {
              final handle = diagnostics.GlassProxyScope.maybeOf(
                tester.element(find.byType(AppCard)),
              )!;
              final program = handle.program;
              expect(program, isNotNull);
              // Model a cold/delayed shader after an atlas is already available.
              // Warm navigation alone would miss this second readiness boundary.
              handle.program = null;
              await tester.pump();
              final waiting = await pixels(
                tester,
                shot,
                'waiting-shader-${brightness.name}',
              );
              expect(
                meanDifference(waiting, home),
                lessThan(2),
                reason: 'Waiting for a shader must not remove the card tint',
              );
              expect(meanDifference(waiting, home, button: true), lessThan(2));
              handle.program = program;
              await tester.pumpAndSettle();
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
