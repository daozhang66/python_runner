import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/ui/navigation_glass.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unsupported backends never attempt to load shader resources', () async {
    var loads = 0;
    final resources = NavigationGlassResources(
        supported: false,
        loadProgram: () {
          loads++;
          throw StateError('must not load');
        });
    await resources.initialize();
    expect(resources.available, isFalse);
    expect(
        resources.filter(
            lens: true,
            pixelRatio: 3,
            progress: 1,
            rect: ui.Rect.zero,
            viewport: ui.Size.zero),
        isNull);
    expect(loads, 0);
    resources.dispose();
  });

  test('load failure falls back once instead of repeatedly scheduling frames',
      () async {
    var loads = 0;
    var updates = 0;
    final resources = NavigationGlassResources(
        supported: true,
        loadProgram: () async {
          loads++;
          throw StateError('missing shader');
        })
      ..addListener(() => updates++);
    await resources.initialize();
    await resources.initialize();
    expect(loads, 1);
    expect(updates, 1);
    expect(resources.available, isFalse);
    expect(
        resources.filter(
            lens: false,
            pixelRatio: 1,
            progress: 0,
            rect: ui.Rect.zero,
            viewport: ui.Size.zero),
        isNull);
    resources.dispose();
  });

  test('disposal during shader loading does not notify or leak errors',
      () async {
    final load = Completer<ui.FragmentProgram>();
    var updates = 0;
    final resources = NavigationGlassResources(
        supported: true, loadProgram: () => load.future)
      ..addListener(() => updates++);
    final initialized = resources.initialize();
    resources.dispose();
    load.completeError(StateError('late load failure'));
    await initialized;
    expect(updates, 0);
    expect(resources.available, isFalse);
  });

  test('packaged shader compiles and exposes the complete float interface',
      () async {
    final program =
        await ui.FragmentProgram.fromAsset(NavigationGlassResources.asset);
    final shader = program.fragmentShader();
    for (var i = 0; i < 13; i++) {
      shader.setFloat(i, 1);
    }
    shader.dispose();
  });
}
