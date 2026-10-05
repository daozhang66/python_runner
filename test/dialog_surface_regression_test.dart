import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g1455/g1455.dart' as glass;
import 'package:python_runner/l10n/app_localizations.dart';
import 'package:python_runner/ui/app_liquid_host.dart';
import 'package:python_runner/ui/app_materials.dart';
import 'package:python_runner/ui/app_theme.dart';
import 'package:python_runner/ui/app_visual_style.dart';
import 'package:python_runner/widgets/app_dialogs.dart';

void main() {
  setUpAll(() async {
    for (final entry in {
      'MiSans': 'assets/fonts/MiSansVF.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load(entry.value))).load();
    }
  });
  for (final brightness in Brightness.values) {
    testWidgets(
      'dialog has a readable surface over busy content: $brightness',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 650);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final shot = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.build(
              ColorScheme.fromSeed(
                seedColor: Colors.indigo,
                brightness: brightness,
              ),
              visualStyle: AppVisualStyle.liquid,
              fontFamily: 'MiSans',
            ),
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (_, child) => AppLiquidHost(
              child: RepaintBoundary(key: shot, child: child!),
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: Stack(
                  children: [
                    const Positioned.fill(
                      child: CustomPaint(painter: _Stripes()),
                    ),
                    Center(
                      child: TextButton(
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => AppAlertDialog(
                            title: const Text('删除脚本？'),
                            content: const SizedBox(
                              width: 250,
                              height: 160,
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: Text('删除后无法恢复，请确认是否继续。'),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('取消'),
                              ),
                            ],
                          ),
                        ),
                        child: const Text('Open'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        for (var i = 0; i < 8; i++) {
          await tester.pump();
        }
        final surface = find
            .descendant(
              of: find.byType(AppAlertDialog),
              matching: find.byType(AppGlassSurface),
            )
            .first;
        final rect = tester.getRect(surface);
        final data = await tester.runAsync(() async {
          final image =
              await (shot.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final file = File('build/dialog-surface-fix/${brightness.name}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(
            (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
                .asUint8List(),
          );
          final pixels = await image.toByteData();
          image.dispose();
          return pixels;
        });
        // Inside the blank content area, background stripes must be suppressed.
        var low = 1.0, high = 0.0;
        for (var x = rect.left.toInt() + 32; x < rect.right.toInt() - 32; x++) {
          final color = _pixel(data!, 390, x, rect.center.dy.toInt());
          final luma = color.computeLuminance();
          if (luma < low) low = luma;
          if (luma > high) high = luma;
        }
        tester.printToConsole(
          'dialog $brightness content luminance=$low..$high rect=$rect',
        );
        expect(
          high - low,
          lessThan(0.08),
          reason: 'The page must not show through the dialog content',
        );
        if (brightness == Brightness.light) {
          expect(low, greaterThan(0.7));
        } else {
          expect(high, lessThan(0.15));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final brightness in Brightness.values) {
    for (final visual in AppVisualStyle.values) {
      testWidgets(
        'overlay stays opaque without a captured frame: $brightness $visual',
        (tester) async {
          final key = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.build(
                ColorScheme.fromSeed(
                  seedColor: Colors.indigo,
                  brightness: brightness,
                ),
                visualStyle: visual,
              ),
              home: glass.GlassHost(
                maxCaptures: 0,
                child: Scaffold(
                  body: Center(
                    child: RepaintBoundary(
                      key: key,
                      child: AppGlassSurface(
                        enabled: true,
                        overlay: true,
                        sampleBackdrop: true,
                        materialize: 0,
                        child: const SizedBox(width: 200, height: 140),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          final center = await tester.runAsync(() async {
            final image =
                await (key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            try {
              return _pixel((await image.toByteData())!, 200, 100, 70);
            } finally {
              image.dispose();
            }
          });
          expect(
            center!.a,
            1,
            reason: 'The first frame needs its own surface without the shader',
          );
          expect(
            center.computeLuminance(),
            brightness == Brightness.light ? greaterThan(0.7) : lessThan(0.15),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets('bottom sheet content hides page stripes: $brightness', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(
            ColorScheme.fromSeed(
              seedColor: Colors.indigo,
              brightness: brightness,
            ),
            visualStyle: AppVisualStyle.liquid,
          ),
          builder: (_, child) => AppLiquidHost(child: child!),
          home: Builder(
            builder: (context) => Scaffold(
              body: Stack(
                children: [
                  const Positioned.fill(
                    child: CustomPaint(painter: _Stripes()),
                  ),
                  TextButton(
                    onPressed: () => showAppModalBottomSheet<void>(
                      context: context,
                      builder: (_) =>
                          const SizedBox(height: 220, width: double.infinity),
                    ),
                    child: const Text('Open'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final background = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(AppGlassSurface),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((w) => w.decoration)
          .whereType<BoxDecoration>();
      expect(
        background.any(
          (d) => d.gradient?.colors.every((c) => c.a == 1) ?? false,
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  }
}

ui.Color _pixel(ByteData data, int width, int x, int y) {
  final i = (y * width + x) * 4;
  return ui.Color.fromARGB(
    data.getUint8(i + 3),
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
}

class _Stripes extends CustomPainter {
  const _Stripes();
  @override
  void paint(Canvas canvas, Size size) {
    for (var x = 0.0; x < size.width; x += 10) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, 10, size.height),
        Paint()..color = (x.toInt() % 20 == 0 ? Colors.white : Colors.black),
      );
    }
  }

  @override
  bool shouldRepaint(_Stripes oldDelegate) => false;
}
