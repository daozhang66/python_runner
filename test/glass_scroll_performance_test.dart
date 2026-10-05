import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_test/flutter_test.dart';
import 'package:g1455/g1455.dart' as glass;
import 'package:g1455/glass_diagnostics.dart' as diagnostics;
import 'package:python_runner/ui/app_liquid_host.dart';
import 'package:python_runner/ui/app_surfaces.dart';
import 'package:python_runner/ui/app_theme.dart';
import 'package:python_runner/ui/app_visual_style.dart';

void main() {
  testWidgets('last culled surface is republished on exact-position reentry', (
    tester,
  ) async {
    final offset = ValueNotifier(Offset.zero);
    addTearDown(offset.dispose);
    await tester.pumpWidget(
      _app(
        Center(
          child: RepaintBoundary(
            child: ValueListenableBuilder(
              valueListenable: offset,
              child: const RepaintBoundary(
                child: SizedBox(
                  width: 160,
                  height: 100,
                  child: AppSurface(
                    key: ValueKey('single'),
                    child: Text('Card'),
                  ),
                ),
              ),
              builder: (_, delta, child) =>
                  Transform.translate(offset: delta, child: child),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final card = _surface(tester, 'single');
    final handle = diagnostics.GlassProxyScope.maybeOf(
      tester.element(find.byKey(const ValueKey('single'))),
    )!;
    expect(handle.frameFor(card)?.slotForKey(card), isNotNull);
    offset.value = const Offset(2000, 0);
    await tester.pumpAndSettle();
    expect(handle.frame, isNull);
    offset.value = Offset.zero;
    await tester.pumpAndSettle();
    expect(
      handle.frameFor(card)?.slotForKey(card),
      isNotNull,
      reason: 'Clearing the displayed frame must invalidate a previously retained capture',
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'touch wave does not recapture or repaint unchanged card content every tick',
    (tester) async {
      var paints = 0;
      await tester.pumpWidget(
        _app(
          Center(
            child: SizedBox(
              width: 260,
              height: 120,
              child: AppSurface(
                onTap: () {},
                child: CustomPaint(painter: _PaintCounter(() => paints++)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final handle = diagnostics.GlassProxyScope.maybeOf(
        tester.element(find.byType(AppSurface)),
      )!;
      final pointer = await tester.startGesture(
        tester.getCenter(find.byType(AppSurface)),
      );
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(microseconds: 8333));
      }
      final snapshots = handle.snapshots;
      final beforePaints = paints;
      for (var i = 0; i < 35; i++) {
        await tester.pump(const Duration(microseconds: 8333));
      }
      tester.printToConsole(
        'wave35: snapshots=${handle.snapshots - snapshots}, contentPaints=${paints - beforePaints}',
      );
      expect(
        handle.snapshots - snapshots,
        lessThanOrEqualTo(1),
        reason: 'The moving wave must not become its own backdrop',
      );
      expect(
        paints - beforePaints,
        lessThan(10),
        reason: 'Only the short Material highlight may repaint; the wave must not repaint the label every tick',
      );
      await pointer.up();
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );
  testWidgets('offscreen cached cards do not occupy the glass atlas', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final offset = ValueNotifier(900.0);
    addTearDown(offset.dispose);
    await tester.pumpWidget(
      _app(
        ValueListenableBuilder(
          valueListenable: offset,
          builder: (_, x, _) => Stack(
            clipBehavior: Clip.none,
            children: [
              const Positioned(
                left: 10,
                top: 40,
                width: 160,
                height: 100,
                child: AppSurface(
                  key: ValueKey('visible'),
                  child: Text('Visible'),
                ),
              ),
              Positioned(
                left: x,
                top: 160,
                width: 160,
                height: 100,
                child: const AppSurface(
                  key: ValueKey('cached'),
                  child: Text('Cached'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final visible = _surface(tester, 'visible');
    final cached = _surface(tester, 'cached');
    final handle = diagnostics.GlassProxyScope.maybeOf(
      tester.element(find.byKey(const ValueKey('visible'))),
    )!;
    expect(handle.frameFor(visible)?.slotForKey(visible), isNotNull);
    expect(
      handle.frameFor(cached)?.slotForKey(cached),
      isNull,
      reason: 'A fully offscreen cached page must not allocate a texture slot',
    );
    for (final x in [380.0, 180.0, -150.0]) {
      offset.value = x;
      await tester.pumpAndSettle();
      expect(
        handle.frameFor(cached)?.slotForKey(cached),
        isNotNull,
        reason: 'Partially visible cards on either edge must retain the full sampling slot',
      );
    }
    offset.value = 900;
    await tester.pumpAndSettle();
    expect(handle.frameFor(cached)?.slotForKey(cached), isNull);
    offset.value = 180;
    await tester.pumpAndSettle();
    expect(handle.frameFor(cached)?.slotForKey(cached), isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scroll capture workload at 120Hz sample cadence', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _app(
        ListView.builder(
          controller: scroll,
          scrollCacheExtent: const ScrollCacheExtent.pixels(500),
          itemCount: 50,
          itemBuilder: (_, i) => AppSurface(
            onTap: () {},
            child: SizedBox(
              height: 90,
              child: Row(
                children: [
                  Expanded(child: Text('Script $i')),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.play_arrow),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final handle = diagnostics.GlassProxyScope.maybeOf(
      tester.element(find.byType(AppSurface).first),
    )!;
    final dynamic host = tester.state(find.byType(glass.GlassHost));
    final before = handle.snapshots;
    final recorded = host.recorded as int;
    final packs = handle.repacks;
    var maxSlots = 0;
    var maxPixels = 0.0;
    final watch = Stopwatch()..start();
    for (var i = 1; i <= 60; i++) {
      scroll.jumpTo(i * 6.0);
      await tester.pump(const Duration(microseconds: 8333));
      final frame = handle.frame;
      if (frame != null) {
        final count = frame.layout.slots.length;
        if (count > maxSlots) maxSlots = count;
        final area = frame.image.width * frame.image.height.toDouble();
        if (area > maxPixels) maxPixels = area;
      }
    }
    watch.stop();
    expect(
      maxSlots,
      lessThanOrEqualTo(10),
      reason: 'The cache extent must not double the visible 600px viewport workload',
    );
    tester.printToConsole(
      'scroll60: captures=${(host.recorded as int) - recorded}, '
      'snapshots=${handle.snapshots - before}, repacks=${handle.repacks - packs}, '
      'maxBaseSlots=$maxSlots maxBasePixels=$maxPixels wallMs=${watch.elapsedMilliseconds}',
    );
    await tester.pumpAndSettle();
    final settled = host.recorded as int;
    await tester.pump(const Duration(seconds: 1));
    expect(host.recorded as int, settled);
    expect(tester.takeException(), isNull);
  });
}

glass.RenderGlassSurface _surface(WidgetTester tester, String key) =>
    tester.renderObject(
      find
          .descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(glass.GlassSurface),
          )
          .first,
    );

Widget _app(Widget body) => MaterialApp(
  theme: AppTheme.build(
    ColorScheme.fromSeed(seedColor: Colors.blue),
    visualStyle: AppVisualStyle.liquid,
  ),
  builder: (_, child) => AppLiquidHost(child: child!),
  home: Scaffold(body: body),
);

class _PaintCounter extends CustomPainter {
  _PaintCounter(this.onPaint);
  final VoidCallback onPaint;
  @override
  void paint(Canvas canvas, Size size) {
    onPaint();
    canvas.drawRect(
      const Rect.fromLTWH(25, 25, 80, 12),
      Paint()..color = Colors.blue,
    );
  }

  @override
  bool shouldRepaint(_PaintCounter oldDelegate) => false;
}
