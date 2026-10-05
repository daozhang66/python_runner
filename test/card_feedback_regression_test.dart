import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g1455/g1455.dart' as glass;
import 'package:python_runner/ui/app_glass_press.dart';
import 'package:python_runner/ui/app_liquid_host.dart';
import 'package:python_runner/ui/app_surfaces.dart';
import 'package:python_runner/ui/app_theme.dart';
import 'package:python_runner/ui/app_visual_style.dart';

void main() {
  testWidgets(
    'card has a visible edge and updates after light-dark round trip',
    (tester) async {
      final brightness = ValueNotifier(Brightness.dark);
      addTearDown(brightness.dispose);
      final shot = GlobalKey();
      await tester.pumpWidget(
        ValueListenableBuilder(
          valueListenable: brightness,
          builder: (_, value, _) => MaterialApp(
            theme: AppTheme.build(
              ColorScheme.fromSeed(seedColor: Colors.blue, brightness: value),
              visualStyle: AppVisualStyle.liquid,
            ),
            builder: (_, child) => AppLiquidHost(child: child!),
            home: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: shot,
                  child: SizedBox(
                    width: 280,
                    height: 100,
                    child: AppSurface(
                      margin: EdgeInsets.zero,
                      onTap: () {},
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final original = await _pixels(tester, shot);
      final state = tester.state(find.byType(AppGlassPress).first);
      for (final mode in [
        Brightness.light,
        Brightness.dark,
        Brightness.light,
        Brightness.dark,
      ]) {
        brightness.value = mode;
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(AppGlassPress).first), same(state));
        final frame = await _pixels(tester, shot);
        if (mode == Brightness.dark) {
          expect(
            List.generate(
              frame.length,
              (i) => frame[i] == original[i] ? 0 : 1,
            ).fold<int>(0, (a, b) => a + b),
            0,
            reason: 'Returned theme must render identically without remounting',
          );
        }
        // A stable theme-derived stroke must remain visible over pale pages,
        // independent of the shader's additive white rim.
        final decorations = tester.widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(AppSurface),
            matching: find.byType(DecoratedBox),
          ),
        );
        expect(
          decorations.any(
            (box) =>
                box.decoration is BoxDecoration &&
                (box.decoration as BoxDecoration).border != null,
          ),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  for (final reduced in [false, true]) {
    testWidgets(
      'visible touch wave survives the native host and cancels for scrolling: reduced=$reduced',
      (tester) async {
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(
              ColorScheme.fromSeed(seedColor: Colors.blue),
              visualStyle: AppVisualStyle.liquid,
            ),
            builder: (_, child) => AppLiquidHost(child: child!),
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Scaffold(
                body: ListView(
                  children: [
                    AppSurface(
                      onTap: () => taps++,
                      child: const SizedBox(height: 140),
                    ),
                    const SizedBox(height: 1600),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final native = tester.renderObject<glass.RenderGlassSurface>(
          find.byType(glass.GlassSurface).first,
        );
        final touch = await tester.startGesture(
          tester.getCenter(find.byType(AppSurface)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final paint = find.byKey(const ValueKey('glass-press-feedback'));
        expect(
          tester
              .widgetList<CustomPaint>(paint)
              .any((p) => p.foregroundPainter != null),
          !reduced,
        );
        if (!reduced) expect(native.rippleDraws, greaterThan(0));
        await touch.moveBy(const Offset(0, -80));
        await tester.pump(const Duration(milliseconds: 100));
        await touch.moveBy(const Offset(0, -60));
        await tester.pump(const Duration(milliseconds: 100));
        await touch.up();
        await tester.pumpAndSettle();
        expect(taps, 0);
        expect(
          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .pixels,
          greaterThan(0),
        );
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
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
