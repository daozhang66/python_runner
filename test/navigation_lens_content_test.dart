import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/ui/navigation_lens_content.dart';

void main() {
  test(
      'inner and outer masks partition one capsule, including its expanded edges',
      () {
    const lens = Rect.fromLTWH(-8, -10, 100, 84);
    const size = Size(320, 64);
    final inside = const NavigationLensClipper(lens: lens).getClip(size);
    final outside =
        const NavigationLensClipper(lens: lens, inverse: true).getClip(size);
    for (final p in [
      const Offset(20, 20),
      const Offset(0, 0),
      const Offset(95, 30),
      const Offset(250, 30)
    ]) {
      expect(inside.contains(p), !outside.contains(p));
    }
    expect(inside.contains(const Offset(42, -5)), true);
    expect(outside.contains(const Offset(160, -2)), true,
        reason:
            'Track expansion must not be clipped to its unexpanded rectangle');
  });

  testWidgets(
      'coverage recolors only the covered pixels without a second hit target',
      (tester) async {
    final lens = ValueNotifier(const Rect.fromLTWH(30, 0, 60, 60));
    addTearDown(lens.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: RepaintBoundary(
      key: const ValueKey('capture'),
      child: SizedBox(
        width: 180,
        height: 60,
        child: ValueListenableBuilder<Rect>(
          valueListenable: lens,
          builder: (_, rect, __) => NavigationLensContent(
              lens: rect,
              unselected: const ColoredBox(color: Colors.black),
              selected: const ColoredBox(color: Colors.red)),
        ),
      ),
    ))));
    Future<Color> pixel(int x, int y) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture')));
      final image = await boundary.toImage();
      try {
        final bytes =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        final offset = (y * image.width + x) * 4;
        return Color.fromARGB(
            bytes.getUint8(offset + 3),
            bytes.getUint8(offset),
            bytes.getUint8(offset + 1),
            bytes.getUint8(offset + 2));
      } finally {
        image.dispose();
      }
    }

    await tester.runAsync(() async {
      expect(await pixel(20, 30), Colors.black);
      expect(await pixel(45, 30), const Color(0xfff44336));
      expect(await pixel(110, 30), Colors.black);
      expect(await pixel(31, 1), Colors.black,
          reason: 'Color mask must follow the curved cap');
    });
    lens.value = const Rect.fromLTWH(75, 0, 60, 60);
    await tester.pump();
    await tester.runAsync(() async {
      expect(await pixel(45, 30), Colors.black);
      expect(await pixel(110, 30), const Color(0xfff44336));
    });
    expect(find.byType(IgnorePointer), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
