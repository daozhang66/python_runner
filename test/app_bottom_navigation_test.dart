import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/l10n/app_localizations.dart';
import 'package:python_runner/ui/app_bottom_navigation.dart';

Finder _item(int index) => find.byKey(ValueKey('navigation-item-$index'));
Finder get _indicator => find.byKey(const ValueKey('navigation-indicator'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    for (final font in {
      'MiSans': 'assets/fonts/MiSansVF.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final loader = FontLoader(font.key);
      loader.addFont(rootBundle.load(font.value));
      await loader.load();
    }
  });

  testWidgets('floating surface leaves room for growth and the system inset',
      (tester) async {
    await _pumpNavigation(tester);
    final surface = find.byKey(const ValueKey('navigation-surface'));
    final material = tester.widget<Material>(surface);
    final colors = Theme.of(tester.element(surface)).colorScheme;
    expect(material.color, colors.surfaceContainer);
    expect(material.shape, isA<StadiumBorder>());
    expect(tester.getRect(surface).left, 16);
    expect(tester.getRect(surface).bottom, 300 - 34 - 12);
    expect(tester.getSize(surface).height, 64);
    expect(tester.getSize(_indicator).height, 52);
  });

  testWidgets('taps retain destination order and commit once', (tester) async {
    final commits = await _pumpNavigation(tester);
    for (var index = 0; index < 3; index++) {
      await tester.tap(_item(index));
      await tester.pumpAndSettle();
      expect(find.text('active: $index'), findsOneWidget);
      expect(
          tester.widget<Semantics>(_item(index)).properties.selected, isTrue);
    }
    expect(commits, [1, 2]);
  });

  testWidgets(
      'drag stretches and previews without committing intermediate tabs',
      (tester) async {
    final commits = await _pumpNavigation(tester);
    final rest = tester.getRect(_indicator);
    final pointer = await tester.startGesture(tester.getCenter(_item(0)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    expect(tester.getRect(_indicator).height, greaterThan(rest.height));
    await pointer.moveTo(tester.getCenter(_item(1)));
    await tester.pump(const Duration(milliseconds: 16));
    expect(commits, isEmpty);
    expect(find.text('active: 0'), findsOneWidget);
    expect(tester.widget<Semantics>(_item(0)).properties.selected, isTrue);
    expect(tester.getRect(_indicator).width, greaterThan(rest.width));
    expect(tester.getRect(_indicator).center.dx, greaterThan(rest.center.dx));
    await pointer.moveTo(tester.getCenter(_item(2)));
    await tester.pump(const Duration(milliseconds: 16));
    expect(commits, isEmpty);
    await pointer.up();
    await tester.pumpAndSettle();
    expect(commits, [2]);
    expect(tester.getRect(_indicator).center.dx,
        closeTo(tester.getCenter(_item(2)).dx, 0.1));
    expect(tester.getRect(_indicator).width, closeTo(rest.width, 0.01));
    expect(tester.getRect(_indicator).height, closeTo(rest.height, 0.01));
  });

  testWidgets('cancel restores the committed tab without a callback',
      (tester) async {
    final commits = await _pumpNavigation(tester);
    final rest = tester.getRect(_indicator);
    final pointer = await tester.startGesture(tester.getCenter(_item(0)));
    await pointer.moveTo(tester.getCenter(_item(2)));
    await tester.pump(const Duration(milliseconds: 40));
    await pointer.cancel();
    await tester.pumpAndSettle();
    expect(commits, isEmpty);
    expect(tester.getRect(_indicator).left, closeTo(rest.left, 0.01));
    expect(tester.getRect(_indicator).top, closeTo(rest.top, 0.01));
    expect(tester.getRect(_indicator).width, closeTo(rest.width, 0.01));
    expect(tester.getRect(_indicator).height, closeTo(rest.height, 0.01));
  });

  testWidgets('reverse drag and a tap during settling end on the latest tab',
      (tester) async {
    final commits = await _pumpNavigation(tester);
    final pointer = await tester.startGesture(tester.getCenter(_item(0)));
    await pointer.moveTo(tester.getCenter(_item(2)));
    await tester.pump(const Duration(milliseconds: 16));
    await pointer.moveTo(tester.getCenter(_item(1)));
    await tester.pump(const Duration(milliseconds: 16));
    await pointer.up();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.tap(_item(2));
    await tester.pumpAndSettle();
    expect(commits, [1, 2]);
    expect(tester.getRect(_indicator).center.dx,
        closeTo(tester.getCenter(_item(2)).dx, 0.1));
  });

  testWidgets('horizontal overscroll clamps, vertical escape cancels',
      (tester) async {
    final commits = await _pumpNavigation(tester);
    var pointer = await tester.startGesture(tester.getCenter(_item(0)));
    await pointer.moveBy(const Offset(1000, 0));
    await pointer.up();
    await tester.pumpAndSettle();
    expect(commits, [2]);
    pointer = await tester.startGesture(tester.getCenter(_item(2)));
    await pointer.moveTo(tester.getCenter(_item(0)));
    await pointer.moveBy(const Offset(0, -100));
    await pointer.up();
    await tester.pumpAndSettle();
    expect(commits, [2]);
  });

  testWidgets('external selection cancels an in-flight preview',
      (tester) async {
    final selection = ValueNotifier(0);
    addTearDown(selection.dispose);
    final commits = await _pumpNavigation(tester, selection: selection);
    final pointer = await tester.startGesture(tester.getCenter(_item(0)));
    await pointer.moveTo(tester.getCenter(_item(2)));
    await tester.pump(const Duration(milliseconds: 20));
    selection.value = 1;
    await tester.pump();
    await pointer.up();
    await tester.pumpAndSettle();
    expect(commits, isEmpty);
    expect(tester.getRect(_indicator).center.dx,
        closeTo(tester.getCenter(_item(1)).dx, 0.1));
  });

  testWidgets('RTL drag follows visual order and commits the logical index',
      (tester) async {
    final commits = await _pumpNavigation(tester, rtl: true);
    expect(tester.getCenter(_item(0)).dx,
        greaterThan(tester.getCenter(_item(2)).dx));
    final pointer = await tester.startGesture(tester.getCenter(_item(0)));
    await pointer.moveTo(tester.getCenter(_item(2)));
    await pointer.up();
    await tester.pumpAndSettle();
    expect(commits, [2]);
    expect(tester.getRect(_indicator).center.dx,
        closeTo(tester.getCenter(_item(2)).dx, 0.1));
  });

  testWidgets('reduced motion keeps dragging usable without inflation',
      (tester) async {
    final commits = await _pumpNavigation(tester, reduceMotion: true);
    final rest = tester.getRect(_indicator);
    final pointer = await tester.startGesture(tester.getCenter(_item(0)));
    await tester.pump(const Duration(milliseconds: 160));
    await pointer.moveTo(tester.getCenter(_item(2)));
    await tester.pump();
    expect(tester.getRect(_indicator).width, closeTo(rest.width, 0.01));
    expect(tester.getRect(_indicator).height, closeTo(rest.height, 0.01));
    await pointer.up();
    await tester.pumpAndSettle();
    expect(commits, [2]);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('keyboard activation and disposal remain safe', (tester) async {
    final commits = await _pumpNavigation(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(commits, [1]);

    final pointer = await tester.startGesture(tester.getCenter(_item(1)));
    await pointer.moveTo(tester.getCenter(_item(2)));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpWidget(const SizedBox.shrink());
    await pointer.cancel();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    for (final locale in ['en', 'zh']) {
      testWidgets('narrow navigation fits 2x text: $brightness $locale',
          (tester) async {
        await _pumpNavigation(tester,
            brightness: brightness,
            locale: Locale(locale),
            width: 320,
            textScale: 2);
        expect(tester.takeException(), isNull);
        for (var index = 0; index < 3; index++) {
          expect(tester.getSize(_item(index)).shortestSide,
              greaterThanOrEqualTo(48));
          expect(_item(index).hitTestable(), findsOneWidget);
        }
      });
    }

    testWidgets(
        'bottom navigation ${brightness.name} appearance',
        (tester) => _withShadows(() async {
              await _pumpNavigation(tester, brightness: brightness);
              await expectLater(
                find.byKey(const ValueKey('navigation-capture')),
                matchesGoldenFile(
                    'goldens/bottom_navigation_${brightness.name}.png'),
              );
            }),
        tags: const ['golden']);
  }

  testWidgets(
      'dragged capsule appearance',
      (tester) => _withShadows(() async {
            await _pumpNavigation(tester);
            final pointer =
                await tester.startGesture(tester.getCenter(_item(0)));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 160));
            await pointer.moveTo(tester.getCenter(_item(1)));
            await tester.pump(const Duration(milliseconds: 16));
            await expectLater(
              find.byKey(const ValueKey('navigation-capture')),
              matchesGoldenFile('goldens/bottom_navigation_drag.png'),
            );
            await pointer.up();
            await tester.pumpAndSettle();
          }),
      tags: const ['golden']);

  if (const bool.fromEnvironment('recordNavigation')) {
    testWidgets(
        'record actual navigation motion frames',
        (tester) => _withShadows(() async {
              await _pumpNavigation(tester);
              final directory = Directory('build/navigation-motion');
              directory.createSync(recursive: true);
              var frame = 0;
              Future<void> capture() async {
                await tester.pump(const Duration(milliseconds: 33));
                await tester.runAsync(() async {
                  final boundary = tester.renderObject<RenderRepaintBoundary>(
                      find.byKey(const ValueKey('navigation-capture')));
                  final image = await boundary.toImage(pixelRatio: 2);
                  final bytes =
                      await image.toByteData(format: ui.ImageByteFormat.png);
                  final path =
                      '${directory.path}/frame${frame.toString().padLeft(3, '0')}.png';
                  await File(path).writeAsBytes(bytes!.buffer.asUint8List());
                  image.dispose();
                  frame++;
                });
              }

              for (var i = 0; i < 12; i++) {
                await capture();
              }
              final start = tester.getCenter(_item(0));
              final end = tester.getCenter(_item(2));
              final pointer = await tester.startGesture(start);
              for (var i = 0; i < 8; i++) {
                await capture();
              }
              for (var i = 1; i <= 24; i++) {
                await pointer.moveTo(Offset.lerp(start, end, i / 24)!);
                await capture();
              }
              await pointer.up();
              for (var i = 0; i < 24; i++) {
                await capture();
              }
              await tester.tap(_item(0));
              for (var i = 0; i < 24; i++) {
                await capture();
              }
            }));
  }
}

Future<void> _withShadows(Future<void> Function() run) async {
  final previous = debugDisableShadows;
  debugDisableShadows = false;
  try {
    await run();
  } finally {
    debugDisableShadows = previous;
  }
}

Future<List<int>> _pumpNavigation(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('zh'),
  double width = 390,
  double textScale = 1,
  bool reduceMotion = false,
  bool rtl = false,
  ValueNotifier<int>? selection,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 300);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final current = selection ?? ValueNotifier(0);
  if (selection == null) addTearDown(current.dispose);
  final commits = <int>[];
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'MiSans',
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: brightness,
      ),
    ),
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        padding: const EdgeInsets.only(bottom: 34),
        textScaler: TextScaler.linear(textScale),
        disableAnimations: reduceMotion,
      ),
      child: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
    ),
    home: ValueListenableBuilder<int>(
      valueListenable: current,
      builder: (context, selectedIndex, _) => Scaffold(
        body: Text('active: $selectedIndex'),
        bottomNavigationBar: RepaintBoundary(
          key: const ValueKey('navigation-capture'),
          child: ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: AppBottomNavigation(
              selectedIndex: selectedIndex,
              onDestinationSelected: (index) {
                commits.add(index);
                current.value = index;
              },
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return commits;
}
