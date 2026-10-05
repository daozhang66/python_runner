import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/ui/app_liquid_host.dart';
import 'package:python_runner/ui/app_materials.dart';
import 'package:python_runner/ui/app_theme.dart';
import 'package:python_runner/ui/app_visual_style.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('settings header has no rectangular rim: $brightness', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 640);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final shot = GlobalKey();
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final colors = ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: brightness,
      );
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          scrollBehavior: const MaterialScrollBehavior().copyWith(
            scrollbars: false,
          ),
          theme: AppTheme.build(colors, visualStyle: AppVisualStyle.liquid),
          builder: (_, child) => AppLiquidHost(
            child: RepaintBoundary(key: shot, child: child!),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: CustomScrollView(
                controller: scroll,
                slivers: [
                  SliverAppBar(
                    pinned: true,
                    title: const Text('Settings'),
                    flexibleSpace: appGlassBarBackground(
                      context,
                      sampleBackdrop: true,
                    ),
                  ),
                  // A uniform field distinguishes an unwanted frame from legitimate
                  // background changes underneath the scrolling glass.
                  SliverToBoxAdapter(
                    child: ColoredBox(
                      color: colors.surface,
                      child: const SizedBox(height: 1800),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      for (final offset in [0.0, 200.0]) {
        scroll.jumpTo(offset);
        await tester.pumpAndSettle();
        final rect = tester.getRect(find.byType(AppGlassBarBackground));
        await tester.runAsync(() async {
          final image =
              await (shot.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          try {
            final bytes = (await image.toByteData())!;
            ui.Color pixel(int x, int y) {
              final i = (y * image.width + x) * 4;
              return ui.Color.fromARGB(
                bytes.getUint8(i + 3),
                bytes.getUint8(i),
                bytes.getUint8(i + 1),
                bytes.getUint8(i + 2),
              );
            }

            final interior = pixel(300, rect.center.dy.floor());
            final points = [
              Offset(300, rect.top),
              Offset(300, rect.bottom - 1),
              Offset(rect.left, rect.center.dy),
              Offset(rect.right - 1, rect.center.dy),
            ];
            for (final point in points) {
              final edge = pixel(point.dx.floor(), point.dy.floor());
              for (final channel in [
                (edge.r, interior.r),
                (edge.g, interior.g),
                (edge.b, interior.b),
              ]) {
                expect(
                  (channel.$1 - channel.$2).abs(),
                  lessThanOrEqualTo(2 / 255),
                  reason:
                      'Header edge $point must merge with its surface at scroll $offset',
                );
              }
            }
          } finally {
            image.dispose();
          }
        });
        expect(tester.takeException(), isNull);
      }
    });
  }
}
