import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g1455/g1455.dart' as glass;
import 'package:python_runner/ui/app_liquid_host.dart';
import 'package:python_runner/ui/app_materials.dart';
import 'package:python_runner/ui/app_theme.dart';
import 'package:python_runner/ui/app_visual_style.dart';
import 'package:python_runner/widgets/app_dialogs.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'native button refracts, ripples and settles; reduced=$reduced',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 280);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final shot = GlobalKey();
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.build(
              ColorScheme.fromSeed(seedColor: Colors.indigo),
              visualStyle: AppVisualStyle.liquid,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: AppLiquidHost(child: child!),
            ),
            home: RepaintBoundary(
              key: shot,
              child: Scaffold(
                body: Stack(
                  children: [
                    const Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(painter: _Grid()),
                      ),
                    ),
                    Positioned(
                      left: 55,
                      top: 90,
                      width: 250,
                      height: 80,
                      child: OutlinedButton(
                        onPressed: () => taps++,
                        child: const Icon(Icons.play_arrow, size: 28),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (var i = 0; i < 6; i++) {
          await tester.pump();
        }
        final surface = tester.renderObject<glass.RenderGlassSurface>(
          find.byType(glass.GlassSurface),
        );
        final dynamic host = tester.state(find.byType(glass.GlassHost));
        expect(
          host.recorded as int,
          greaterThan(0),
          reason: 'Actual backdrop capture must be used',
        );
        final before = await _pixels(tester, shot);
        final gesture = await tester.startGesture(const Offset(120, 125));
        var changed = 0;
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          if (i == 9) {
            final current = await _pixels(tester, shot);
            changed = _different(before, current);
          }
          if (const bool.fromEnvironment('recordGlassDemo') && !reduced) {
            await _record(tester, shot, i);
          }
        }
        expect(changed, greaterThan(50));
        expect(surface.rippleDraws, reduced ? 0 : greaterThan(0));
        await gesture.up();
        for (var i = 20; i < 90; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          if (const bool.fromEnvironment('recordGlassDemo') && !reduced) {
            await _record(tester, shot, i);
          }
        }
        await tester.pumpAndSettle();
        expect(taps, 1);
        expect(tester.binding.hasScheduledFrame, isFalse);
        final recorded = host.recorded as int;
        await tester.pump(const Duration(seconds: 1));
        expect(
          host.recorded as int,
          recorded,
          reason: 'Idle glass must not keep capturing',
        );
        expect(_different(before, await _pixels(tester, shot)), lessThan(20));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('style switch preserves focused input inside native glass', (
    tester,
  ) async {
    final style = ValueNotifier(AppVisualStyle.classic);
    final input = TextEditingController(text: 'print');
    addTearDown(style.dispose);
    addTearDown(input.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder(
        valueListenable: style,
        builder: (_, value, _) => MaterialApp(
          theme: AppTheme.build(
            ColorScheme.fromSeed(seedColor: Colors.blue),
            visualStyle: value,
          ),
          builder: (_, child) => AppLiquidHost(child: child!),
          home: Scaffold(
            body: AppGlassSurface(child: TextField(controller: input)),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    input.selection = const TextSelection(baseOffset: 1, extentOffset: 4);
    final state = tester.state(find.byType(TextField));
    for (final value in [AppVisualStyle.liquid, AppVisualStyle.classic]) {
      style.value = value;
      // A focused caret keeps animating. Allow the theme transition to finish
      // without requiring the entire captured scene to become static.
      await tester.pump(const Duration(milliseconds: 350));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.state(find.byType(TextField)), same(state));
      expect(input.text, 'print');
      expect(
        input.selection,
        const TextSelection(baseOffset: 1, extentOffset: 4),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'dialog uses native materialization and keeps its bounded width',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(
            ColorScheme.fromSeed(seedColor: Colors.blue),
            visualStyle: AppVisualStyle.liquid,
          ),
          builder: (_, child) => AppLiquidHost(child: child!),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AppAlertDialog(
                    title: Text('Title'),
                    content: Text('Content'),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final surface = tester.widget<glass.GlassSurface>(
        find
            .descendant(
              of: find.byType(AppAlertDialog),
              matching: find.byType(glass.GlassSurface),
            )
            .first,
      );
      expect(surface.materialize, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(glass.GlassSurface).last).width,
        lessThanOrEqualTo(560),
      );
      expect(tester.takeException(), isNull);
    },
  );
}

class _Grid extends CustomPainter {
  const _Grid();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xfff2d9bd),
    );
    for (var x = 0.0; x < size.width; x += 18) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, 6, size.height),
        Paint()..color = const Color(0xff366caa),
      );
    }
    for (var y = 0.0; y < size.height; y += 24) {
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, 3),
        Paint()..color = const Color(0xffca7284),
      );
    }
  }

  @override
  bool shouldRepaint(_Grid oldDelegate) => false;
}

Future<ui.Image> _image(GlobalKey key) =>
    (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
        .toImage();
Future<Uint8List> _pixels(WidgetTester tester, GlobalKey key) async {
  return (await tester.runAsync(() async {
    final image = await _image(key);
    try {
      return Uint8List.fromList(
        (await image.toByteData())!.buffer.asUint8List(),
      );
    } finally {
      image.dispose();
    }
  }))!;
}

int _different(Uint8List a, Uint8List b) {
  var count = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) count++;
  }
  return count;
}

Future<void> _record(WidgetTester tester, GlobalKey key, int index) async {
  await tester.runAsync(() async {
    final image = await _image(key);
    try {
      final file = File(
        'build/g1455-demo/frame-${index.toString().padLeft(3, '0')}.png',
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(
        (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
            .asUint8List(),
      );
    } finally {
      image.dispose();
    }
  });
}
