import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/ui/navigation_glass.dart';

void main() {
  for (final lens in [false, true]) {
    testWidgets('only the track has a blur pass, lens=$lens', (tester) async {
      final resources = NavigationGlassResources(supported: false);
      addTearDown(resources.dispose);
      await tester.pumpWidget(MaterialApp(
          home: Center(
              child: SizedBox(
        width: 150,
        height: 64,
        child: NavigationGlassBackdrop(
            resources: resources,
            lens: lens,
            progress: 1,
            pixelRatio: 1,
            viewport: const Size(800, 600),
            child: const ColoredBox(color: Colors.transparent)),
      ))));
      final filters = tester.layers.whereType<BackdropFilterLayer>().toList();
      expect(filters.length, lens ? 0 : 1);
      if (!lens) {
        expect(
            filters.single.filter,
            ui.ImageFilter.blur(
                sigmaX: NavigationGlassResources.trackBlurSigma,
                sigmaY: NavigationGlassResources.trackBlurSigma));
      }
    });
  }
  testWidgets('lens receives current global bounds, viewport and pixel ratio',
      (tester) async {
    final resources = _RecordingGlass();
    final translation = ValueNotifier(const Offset(3, -6));
    addTearDown(resources.dispose);
    addTearDown(translation.dispose);
    tester.view.physicalSize = const Size(1170, 900);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Align(
      alignment: Alignment.bottomCenter,
      child: ValueListenableBuilder<Offset>(
        valueListenable: translation,
        builder: (context, offset, child) => Transform.translate(
          offset: offset,
          child: SizedBox(
            width: 120,
            height: 76,
            child: NavigationGlassBackdrop(
              key: const ValueKey('lens'),
              resources: resources,
              lens: true,
              progress: 1,
              pixelRatio: MediaQuery.devicePixelRatioOf(context),
              viewport: MediaQuery.sizeOf(context),
              child: const ColoredBox(color: Colors.blue),
            ),
          ),
        ),
      ),
    ))));
    expect(resources.rect, tester.getRect(find.byKey(const ValueKey('lens'))));
    expect(resources.viewport, const Size(390, 300));
    expect(resources.ratio, 3);
    final previous = resources.rect!;
    translation.value = const Offset(-4, -12);
    await tester.pump();
    expect(resources.rect, previous.shift(const Offset(-7, -6)));
    expect(resources.rect, tester.getRect(find.byKey(const ValueKey('lens'))));
    expect(tester.takeException(), isNull);
  });
}

class _RecordingGlass extends NavigationGlassResources {
  _RecordingGlass() : super(supported: false);
  Rect? rect;
  Size? viewport;
  double? ratio;

  @override
  ui.ImageFilter? filter(
      {required bool lens,
      required double pixelRatio,
      required double progress,
      required Rect rect,
      required Size viewport}) {
    this.rect = rect;
    this.viewport = viewport;
    ratio = pixelRatio;
    return null;
  }
}
