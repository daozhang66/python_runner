import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/ui/app_liquid_host.dart';
import 'package:python_runner/ui/app_popup_menu.dart';
import 'package:python_runner/ui/app_theme.dart';
import 'package:python_runner/ui/app_visual_style.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('liquid icon controls have no persistent ring: $brightness', (
      tester,
    ) async {
      final shot = GlobalKey();
      var taps = 0;
      int? selected;
      final colors = ColorScheme.fromSeed(
        seedColor: Colors.indigo,
        brightness: brightness,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(colors, visualStyle: AppVisualStyle.liquid),
          builder: (_, child) => AppLiquidHost(child: child!),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: shot,
                child: ColoredBox(
                  color: colors.surface,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => taps++,
                        icon: const Icon(Icons.arrow_back),
                      ),
                      IconButton(
                        onPressed: () => taps++,
                        icon: const Icon(Icons.refresh),
                      ),
                      IconButton(
                        onPressed: () => taps++,
                        icon: const Icon(Icons.delete_outline),
                      ),
                      AppPopupMenuButton<int>(
                        onSelected: (value) => selected = value,
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 1, child: Text('Edit')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image =
            await (shot.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        try {
          final bytes = (await image.toByteData())!;
          final width = image.width;
          // The upper strip lies outside the glyphs but crosses every old rim.
          for (var y = 0; y < 7; y++) {
            for (var x = 0; x < width; x++) {
              final i = (y * width + x) * 4;
              expect(
                (bytes.getUint8(i) - colors.surface.r * 255).abs(),
                lessThanOrEqualTo(1),
              );
              expect(
                (bytes.getUint8(i + 1) - colors.surface.g * 255).abs(),
                lessThanOrEqualTo(1),
              );
              expect(
                (bytes.getUint8(i + 2) - colors.surface.b * 255).abs(),
                lessThanOrEqualTo(1),
              );
            }
          }
        } finally {
          image.dispose();
        }
      });
      for (final icon in [
        Icons.arrow_back,
        Icons.refresh,
        Icons.delete_outline,
      ]) {
        final button = find.widgetWithIcon(IconButton, icon);
        expect(tester.getSize(button).shortestSide, greaterThanOrEqualTo(48));
        await tester.tap(button);
      }
      expect(taps, 3);
      await tester.tap(find.byType(AppPopupMenuButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
