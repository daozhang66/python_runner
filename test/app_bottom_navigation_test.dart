import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/l10n/app_localizations.dart';
import 'package:python_runner/ui/app_bottom_navigation.dart';
import 'package:python_runner/ui/app_navigation_destinations.dart';
import 'package:python_runner/ui/classic_bottom_navigation.dart';
import 'package:python_runner/ui/navigation_lens_content.dart';
import 'package:python_runner/ui/navigation_interaction_glow.dart';

Finder _item(int index) => find.byKey(ValueKey('navigation-item-$index'));
Finder get _indicator => find.byKey(const ValueKey('navigation-indicator'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('classic quick tap travels and visibly swells before settling',
      (tester) async {
    final commits = await _pumpNavigation(tester, classic: true);
    final rest = tester.getRect(_indicator);
    final target = tester.getCenter(_item(3)).dx;
    await tester.tap(_item(3));
    await tester.pump();
    expect(tester.getRect(_indicator).center.dx, closeTo(rest.center.dx, 0.01));
    await tester.pump(const Duration(milliseconds: 80));
    final moving = tester.getRect(_indicator);
    expect(moving.center.dx, inExclusiveRange(rest.center.dx, target));
    expect(moving.height, greaterThan(rest.height + 10));
    expect(commits, [3]);
    await tester.pumpAndSettle();
    expect(tester.getRect(_indicator).width, closeTo(rest.width, 0.01));
    expect(tester.getRect(_indicator).height, closeTo(rest.height, 0.01));
    expect(tester.getRect(_indicator).center.dx, closeTo(target, 0.01));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  for (final rtl in [false, true]) {
    for (final cancel in [false, true]) {
      testWidgets(
          'classic masks magnification and restores on release: rtl=$rtl cancel=$cancel',
          (tester) async {
        final commits = await _pumpNavigation(tester, classic: true, rtl: rtl);
        Finder icon(String mask, int index) => find.descendant(
            of: find.byKey(ValueKey(mask)),
            matching: find.byIcon(AppNavigationDestinations.icons[index]));
        final originalTarget = tester.getRect(_item(1));
        final rest = tester.getRect(_indicator);
        final pointer = await tester.startGesture(tester.getCenter(_item(0)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 220));
        await pointer.moveTo(tester.getCenter(_item(1)));
        await tester.pump();
        final inside = icon('navigation-content-inside', 1);
        final outside = icon('navigation-content-outside', 1);
        expect(tester.getRect(inside).height / tester.getRect(outside).height,
            closeTo(1.12, 0.01));
        expect(tester.getRect(_item(1)), originalTarget);
        expect(tester.getRect(_indicator).height, greaterThan(rest.height));
        final content = tester
            .widget<NavigationLensContent>(find.byType(NavigationLensContent));
        final localIndicator = tester
            .getRect(_indicator)
            .shift(-tester.getTopLeft(find.byType(NavigationLensContent)));
        expect((content.lens.topLeft - localIndicator.topLeft).distance,
            lessThan(0.001));
        expect((content.lens.bottomRight - localIndicator.bottomRight).distance,
            lessThan(0.001));
        // Between tabs both covered pieces enlarge a little, while the masks
        // leave the rest of each glyph at its original size and color.
        await pointer.moveTo(Offset.lerp(
            tester.getCenter(_item(1)), tester.getCenter(_item(2)), 0.5)!);
        await tester.pump();
        for (final i in [1, 2]) {
          expect(
              tester.getRect(icon('navigation-content-inside', i)).height /
                  tester.getRect(icon('navigation-content-outside', i)).height,
              closeTo(1.06, 0.01));
        }
        expect(commits, isEmpty);
        expect(find.bySemanticsLabel('网络'), findsOneWidget);
        if (cancel) {
          await pointer.cancel();
        } else {
          await pointer.moveTo(tester.getCenter(_item(2)));
          await pointer.up();
        }
        await tester.pumpAndSettle();
        expect(commits, cancel ? isEmpty : [2]);
        expect(tester.getRect(_indicator).width, closeTo(rest.width, 0.01));
        expect(tester.getRect(_indicator).height, closeTo(rest.height, 0.01));
        expect(tester.getRect(inside).height, tester.getRect(outside).height);
        expect(tester.binding.hasScheduledFrame, isFalse);
      });
    }
  }

  testWidgets(
      'classic external selection interrupts a drag without committing it',
      (tester) async {
    final selection = ValueNotifier(0);
    addTearDown(selection.dispose);
    final commits =
        await _pumpNavigation(tester, classic: true, selection: selection);
    final pointer = await tester.startGesture(tester.getCenter(_item(0)));
    await pointer.moveTo(tester.getCenter(_item(3)));
    await tester.pump(const Duration(milliseconds: 40));
    selection.value = 1;
    await tester.pump();
    await pointer.up();
    await tester.pumpAndSettle();
    expect(commits, isEmpty);
    expect(tester.getRect(_indicator).center.dx,
        closeTo(tester.getCenter(_item(1)).dx, 0.01));
  });

  for (final reduceMotion in [false, true]) {
    for (final locale in ['en', 'zh']) {
      testWidgets(
          'classic remains usable on narrow screens: reduced=$reduceMotion $locale',
          (tester) async {
        final commits = await _pumpNavigation(tester,
            classic: true,
            width: 320,
            textScale: 2,
            locale: Locale(locale),
            reduceMotion: reduceMotion);
        final rest = tester.getRect(_indicator);
        final pointer = await tester.startGesture(tester.getCenter(_item(0)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 180));
        for (final index in [0, 3]) {
          if (index != 0) await pointer.moveTo(tester.getCenter(_item(index)));
          await tester.pump();
          final bounds = tester.getRect(_indicator);
          expect(bounds.left, greaterThanOrEqualTo(0));
          expect(bounds.right, lessThanOrEqualTo(320));
          expect(bounds.bottom, lessThanOrEqualTo(266));
          if (reduceMotion) expect(bounds.size, rest.size);
          expect(tester.takeException(), isNull);
        }
        await pointer.up();
        await tester.pumpAndSettle();
        expect(commits, [3]);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.binding.hasScheduledFrame, isFalse);
      });
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets(
        'classic capsule appearance and covered content: $brightness',
        (tester) => _withShadows(() async {
              await _pumpNavigation(tester,
                  classic: true, brightness: brightness);
              final capture = find.byKey(const ValueKey('navigation-capture'));
              await expectLater(
                  capture,
                  matchesGoldenFile(
                      'goldens/classic_navigation_${brightness.name}.png'));
              final pointer =
                  await tester.startGesture(tester.getCenter(_item(0)));
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 220));
              await pointer.moveTo(Offset.lerp(tester.getCenter(_item(0)),
                  tester.getCenter(_item(1)), 0.5)!);
              await tester.pump();
              await expectLater(
                  capture,
                  matchesGoldenFile(
                      'goldens/classic_navigation_drag_${brightness.name}.png'));
              await pointer.up();
              await tester.pumpAndSettle();
            }),
        tags: const ['golden']);
  }

  for (final rtl in [false, true]) {
    testWidgets('dark contact light follows the lens and fades out: rtl=$rtl',
        (tester) async {
      await _pumpNavigation(tester, brightness: Brightness.dark, rtl: rtl);
      final glowFinder =
          find.byKey(const ValueKey('navigation-interaction-glow'));
      NavigationInteractionGlow glow() =>
          tester.widget<CustomPaint>(glowFinder).painter!
              as NavigationInteractionGlow;
      expect(glow().intensity, 0);
      final pointer = await tester.startGesture(tester.getCenter(_item(0)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      for (final index in [1, 3, 2]) {
        await pointer.moveTo(tester.getCenter(_item(index)));
        await tester.pump();
        expect(glow().intensity, greaterThan(0.9));
        final origin = tester.getTopLeft(glowFinder);
        expect(
            (glow().lens.center + origin - tester.getRect(_indicator).center)
                .distance,
            lessThan(0.01));
      }
      await pointer.cancel();
      await tester.pumpAndSettle();
      expect(glow().intensity, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  }

  testWidgets('moving light brightens the nearby track, not the whole bar',
      (tester) async {
    await _pumpNavigation(tester, brightness: Brightness.dark);
    Future<List<double>> luminance() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('navigation-capture')));
      final origin = boundary.globalToLocal(tester.getTopLeft(
          find.byKey(const ValueKey('navigation-interaction-glow'))));
      // Empty track space outside either end's expanded capsule.
      final points = [
        origin + const Offset(124, 6),
        origin + const Offset(234, 6)
      ];
      return (await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          final bytes =
              (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
          return points.map((p) {
            final i = (p.dy.floor() * image.width + p.dx.floor()) * 4;
            return Color.fromARGB(bytes.getUint8(i + 3), bytes.getUint8(i),
                    bytes.getUint8(i + 1), bytes.getUint8(i + 2))
                .computeLuminance();
          }).toList();
        } finally {
          image.dispose();
        }
      }))!;
    }

    final rest = await luminance();
    final pointer = await tester.startGesture(tester.getCenter(_item(0)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    final left = await luminance();
    await pointer.moveTo(tester.getCenter(_item(3)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    final right = await luminance();
    expect(left[0], greaterThan(left[1] + 0.003));
    expect(right[1], greaterThan(right[0] + 0.003));
    expect(left[0], greaterThan(rest[0] + 0.003));
    await pointer.up();
    await tester.pumpAndSettle();
    final settled = await luminance();
    expect(settled[0], closeTo(rest[0], 0.002));
    expect(settled[1], closeTo(rest[1], 0.002));
  });

  testWidgets('reduced motion keeps the resting fill without animated light',
      (tester) async {
    await _pumpNavigation(tester,
        brightness: Brightness.dark, reduceMotion: true);
    final pointer = await tester.startGesture(tester.getCenter(_item(0)));
    await pointer.moveTo(tester.getCenter(_item(2)));
    await tester.pump();
    final painter = tester
        .widget<CustomPaint>(
            find.byKey(const ValueKey('navigation-interaction-glow')))
        .painter! as NavigationInteractionGlow;
    expect(painter.intensity, 0);
    await pointer.up();
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  for (final brightness in Brightness.values) {
    for (final cancel in [false, true]) {
      testWidgets(
          'resting capsule has visible fill before and after dragging: $brightness cancel=$cancel',
          (tester) async {
        await _pumpNavigation(tester, brightness: brightness);

        Future<void> expectVisibleFill(int selected, int neighbor,
            {double? minimumContrast}) async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('navigation-capture')));
          Offset samplePosition(int index) {
            final rect = tester.getRect(_item(index));
            // Sample the empty space beside the icon, away from text, strokes
            // and the pill's edge. This measures the fill itself.
            return boundary.globalToLocal(
                Offset(rect.left + rect.width * 0.23, rect.center.dy));
          }

          final inside = samplePosition(selected);
          final outside = samplePosition(neighbor);
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            try {
              final bytes =
                  (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
              Color sample(Offset p) {
                final i = (p.dy.floor() * image.width + p.dx.floor()) * 4;
                return Color.fromARGB(bytes.getUint8(i + 3), bytes.getUint8(i),
                    bytes.getUint8(i + 1), bytes.getUint8(i + 2));
              }

              final selectedLuminance = sample(inside).computeLuminance();
              final trackLuminance = sample(outside).computeLuminance();
              final contrast = brightness == Brightness.dark
                  ? (selectedLuminance + 0.05) / (trackLuminance + 0.05)
                  : (trackLuminance + 0.05) / (selectedLuminance + 0.05);
              expect(
                  contrast,
                  greaterThan(minimumContrast ??
                      (brightness == Brightness.dark ? 1.18 : 1.07)),
                  reason:
                      'The selected background must remain distinct from the track');
              if (brightness == Brightness.light) {
                expect(contrast, lessThan(1.20),
                    reason:
                        'Light glass must not look like an opaque gray button');
              }
            } finally {
              image.dispose();
            }
          });
        }

        await expectVisibleFill(0, 1);
        final pointer = await tester.startGesture(tester.getCenter(_item(0)));
        await pointer.moveTo(tester.getCenter(_item(2)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 220));
        final fill = tester.widget<DecoratedBox>(
            find.byKey(const ValueKey('navigation-resting-fill')));
        expect((fill.decoration as ShapeDecoration).color!.a, lessThan(0.15),
            reason: 'Dragging must still reveal the live refractive lens');
        if (brightness == Brightness.light) {
          await expectVisibleFill(2, 0, minimumContrast: 1.07);
        }
        if (cancel) {
          await pointer.cancel();
        } else {
          await pointer.up();
        }
        await tester.pumpAndSettle();
        await expectVisibleFill(cancel ? 0 : 2, 1);
      });
    }
  }

  testWidgets('tap glides across tabs instead of jumping on pointer down',
      (tester) async {
    final commits = await _pumpNavigation(tester);
    final start = tester.getRect(_indicator).center.dx;
    final target = tester.getCenter(_item(3)).dx;
    await tester.tap(_item(3));
    await tester.pump();
    expect(tester.getRect(_indicator).center.dx, closeTo(start, 0.1));
    await tester.pump(const Duration(milliseconds: 60));
    expect(
        tester.getRect(_indicator).center.dx, inExclusiveRange(start, target));
    expect(commits, [3]);
    await tester.pumpAndSettle();
    expect(tester.getRect(_indicator).center.dx, closeTo(target, 0.1));
  });

  for (final reduced in [false, true]) {
    testWidgets(
        'covered glyphs grow and recover with the lens: reduced=$reduced',
        (tester) async {
      await _pumpNavigation(tester, reduceMotion: reduced);
      Finder iconIn(String mask, int index) => find.descendant(
          of: find.byKey(ValueKey(mask)),
          matching: find.byIcon(AppNavigationDestinations.icons[index]));
      final selected = iconIn('navigation-content-inside', 1);
      final outside = iconIn('navigation-content-outside', 1);
      final rest = tester.getSize(selected).height;
      final pointer = await tester.startGesture(tester.getCenter(_item(0)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      await pointer.moveTo(tester.getCenter(_item(1)));
      await tester.pump();
      final coveredHeight = tester.getRect(selected).height;
      expect(coveredHeight,
          reduced ? closeTo(rest, 0.01) : greaterThan(rest * 1.20));
      expect(tester.getRect(outside).height, closeTo(rest, 0.01));
      await pointer.up();
      await tester.pumpAndSettle();
      expect(tester.getRect(selected).height, closeTo(rest, 0.01));
    });
  }

  for (final cancel in [false, true]) {
    testWidgets(
        'background clears only during dragging and blurs after release: cancel=$cancel',
        (tester) async {
      await _pumpNavigation(tester);
      BackdropFilter blur() => tester.widget<BackdropFilter>(
          find.byKey(const ValueKey('navigation-resting-blur')));
      expect(blur().enabled, isTrue);
      expect(blur().filter, ui.ImageFilter.blur(sigmaX: 3.2, sigmaY: 3.2));
      final pointer = await tester.startGesture(tester.getCenter(_item(0)));
      await tester.pump(const Duration(milliseconds: 250));
      expect(blur().filter, ui.ImageFilter.blur(sigmaX: 3.2, sigmaY: 3.2),
          reason: 'A held tap must not expose the script text');
      await pointer.moveBy(const Offset(40, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(blur().enabled, isFalse);
      if (cancel) {
        await pointer.cancel();
      } else {
        await pointer.up();
      }
      await tester.pumpAndSettle();
      expect(blur().enabled, isTrue);
      expect(blur().filter, ui.ImageFilter.blur(sigmaX: 3.2, sigmaY: 3.2));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'moving lens uses one coverage mask for track and two label colors',
      (tester) async {
    final commits = await _pumpNavigation(tester);
    final pointer = await tester.startGesture(tester.getCenter(_item(0)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    final left = tester.getCenter(_item(0));
    final right = tester.getCenter(_item(1));
    await pointer.moveBy(const Offset(24, 0));
    await tester.pump();
    await pointer.moveTo(Offset.lerp(left, right, 0.5)!);
    await tester.pump();
    final content = tester
        .widget<NavigationLensContent>(find.byType(NavigationLensContent));
    expect(content.selected, isNot(isA<SizedBox>()),
        reason: 'Selected labels must be present in the refracted backdrop.');
    expect(find.byKey(const ValueKey('navigation-selected-label-overlay')),
        findsNothing);
    final outside = tester
        .widget<ClipPath>(
            find.byKey(const ValueKey('navigation-content-outside')))
        .clipper! as NavigationLensClipper;
    final inside = tester
        .widget<ClipPath>(
            find.byKey(const ValueKey('navigation-content-inside')))
        .clipper! as NavigationLensClipper;
    final track = tester
        .widget<ClipPath>(
            find.byKey(const ValueKey('navigation-track-surface')))
        .clipper!;
    expect(inside.lens, content.lens);
    expect(outside.lens, content.lens);
    expect(outside.inverse, true);
    expect(track, isA<ShapeBorderClipper>());
    for (var i = 0; i < 4; i++) {
      expect(_item(i), findsOneWidget);
    }
    expect(commits, isEmpty);
    await pointer.cancel();
    await tester.pumpAndSettle();
    expect(commits, isEmpty);
  });

  for (final classic in [false, true]) {
    testWidgets(
        'holding a tab does not let a tooltip cancel the preview: classic=$classic',
        (tester) async {
      final commits = await _pumpNavigation(tester, classic: classic);
      final pointer = await tester.startGesture(tester.getCenter(_item(1)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      expect(tester.getRect(_indicator).center.dx,
          closeTo(tester.getCenter(_item(1)).dx, 3));
      expect(commits, isEmpty);
      await pointer.up();
      await tester.pumpAndSettle();
      expect(commits, [1]);
    });
    testWidgets(
        'drag center stays with pointer without a second catch-up: classic=$classic',
        (tester) async {
      final commits = await _pumpNavigation(tester, classic: classic);
      final pointer = await tester.startGesture(tester.getCenter(_item(0)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final target = tester.getCenter(_item(1));
      await pointer.moveBy(const Offset(24, 0));
      await tester.pump();
      await pointer.moveTo(target);
      await tester.pump();
      final first = tester.getRect(_indicator);
      expect((first.center.dx - target.dx).abs(),
          lessThanOrEqualTo(classic ? 0.1 : 4.1));
      await tester.pump(const Duration(milliseconds: 150));
      final held = tester.getRect(_indicator);
      expect(held.center.dx, closeTo(first.center.dx, 0.1));
      expect(held.width, closeTo(first.width, 1));
      expect(commits, isEmpty);
      await pointer.up();
      await tester.pumpAndSettle();
      expect(commits, [1]);
    });
  }

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
    expect(material.color!.a, inExclusiveRange(0, 1),
        reason: 'The floating glass must keep sampling the page behind it');
    expect(material.shape, isA<StadiumBorder>());
    final indicatorDecoration = tester
        .widget<DecoratedBox>(
            find.byKey(const ValueKey('navigation-resting-fill')))
        .decoration as ShapeDecoration;
    expect(indicatorDecoration.color, isNotNull);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.getRect(surface).left, 16);
    expect(tester.getRect(surface).bottom, 300 - 34 - 12);
    expect(tester.getSize(surface).height, 64);
    expect(tester.getSize(_indicator).height, 52);
    expect(tester.getSize(_indicator).width,
        closeTo((tester.getSize(surface).width - 12) / 4 - 4, 0.01));
  });

  for (final seed in [Colors.blue, Colors.green, Colors.orange]) {
    testWidgets('light glass separates from a pale page: $seed', (tester) async {
      await _pumpNavigation(tester, seedColor: seed);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('navigation-capture')));
      final item = tester.getRect(_item(1));
      // Unselected empty space avoids measuring an icon or selected fill.
      final point = boundary.globalToLocal(
          Offset(item.left + item.width * 0.23, item.center.dy));
      final contrast = await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          final bytes =
              (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
          Color pixel(int x, int y) {
            final i = (y * image.width + x) * 4;
            return Color.fromARGB(bytes.getUint8(i + 3), bytes.getUint8(i),
                bytes.getUint8(i + 1), bytes.getUint8(i + 2));
          }

          final page = pixel(4, 4).computeLuminance();
          final track =
              pixel(point.dx.floor(), point.dy.floor()).computeLuminance();
          return (page + 0.05) / (track + 0.05);
        } finally {
          image.dispose();
        }
      });
      expect(contrast, inInclusiveRange(1.16, 1.5),
          reason: 'Pale glass needs a visible tonal step without a heavy fill');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('zero-width startup viewport recovers without a layout exception',
      (tester) async {
    await _pumpNavigation(tester, width: 0);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(390, 300);
    await tester.pumpAndSettle();
    expect(_item(0), findsOneWidget);
    expect(tester.getSize(_indicator).height, 52);
  });

  testWidgets('taps retain destination order and commit once', (tester) async {
    final commits = await _pumpNavigation(tester);
    for (var index = 0; index < 4; index++) {
      await tester.tap(_item(index));
      await tester.pumpAndSettle();
      expect(find.text('active: $index'), findsOneWidget);
      expect(
          tester.widget<Semantics>(_item(index)).properties.selected, isTrue);
    }
    expect(commits, [1, 2, 3]);
  });

  testWidgets(
      'classic navigation restores theme colors and drag/cancel behavior',
      (tester) async {
    final commits = await _pumpNavigation(tester, classic: true);
    final surface = tester
        .widget<Material>(find.byKey(const ValueKey('navigation-surface')));
    final colors = Theme.of(tester.element(_item(0))).colorScheme;
    expect(surface.color, colors.surfaceContainer);
    final decoration =
        tester.widget<DecoratedBox>(_indicator).decoration as ShapeDecoration;
    expect(decoration.color, colors.secondaryContainer);
    expect(tester.getSize(_indicator).height, 52);
    final pointer = await tester.startGesture(tester.getCenter(_item(0)));
    await pointer.moveTo(tester.getCenter(_item(2)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(commits, isEmpty);
    await pointer.up();
    await tester.pumpAndSettle();
    expect(commits, [2]);
    final canceled = await tester.startGesture(tester.getCenter(_item(2)));
    await canceled.moveTo(tester.getCenter(_item(0)));
    await canceled.cancel();
    await tester.pumpAndSettle();
    expect(commits, [2]);
    await tester.tap(_item(1));
    await tester.pumpAndSettle();
    expect(commits, [2, 1]);
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

  testWidgets('a quick tap pulses once and leaves no animation at rest',
      (tester) async {
    final commits = await _pumpNavigation(tester);
    await tester.tap(_item(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.getSize(_indicator).height, greaterThan(56));
    await tester.pumpAndSettle();
    expect(commits, [1]);
    expect(tester.getSize(_indicator).height, closeTo(52, 0.01));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  for (final width in [320.0, 390.0, 480.0]) {
    for (final brightness in Brightness.values) {
      for (final locale in ['zh', 'en']) {
        testWidgets('pressed glass stays bounded: $width $brightness $locale',
            (tester) async {
          await _pumpNavigation(tester,
              width: width,
              brightness: brightness,
              locale: Locale(locale),
              textScale: 2);
          final sample = '${width.toInt()}_${brightness.name}_$locale';
          await _captureGlassMatrix(tester, '${sample}_0_rest');
          final pointer = await tester.startGesture(tester.getCenter(_item(0)));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 180));
          await _captureGlassMatrix(tester, '${sample}_1_press');
          await pointer.moveTo(tester.getCenter(_item(2)));
          await tester.pump(const Duration(milliseconds: 40));
          await _captureGlassMatrix(tester, '${sample}_2_drag');
          final rect = tester.getRect(_indicator);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
          expect(rect.bottom, lessThanOrEqualTo(300 - 34));
          expect(find.bySemanticsLabel(locale == 'zh' ? '脚本' : 'Scripts'),
              findsOneWidget);
          expect(tester.takeException(), isNull);
          await pointer.cancel();
          await tester.pumpAndSettle();
          await _captureGlassMatrix(tester, '${sample}_3_settled');
        });
      }
    }
  }

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
    expect(commits, [3]);
    pointer = await tester.startGesture(tester.getCenter(_item(3)));
    await pointer.moveTo(tester.getCenter(_item(0)));
    await pointer.moveBy(const Offset(0, -100));
    await pointer.up();
    await tester.pumpAndSettle();
    expect(commits, [3]);
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
        'pressed lens ${brightness.name} keeps the fallback free of artificial slots',
        (tester) => _withShadows(() async {
              await _pumpNavigation(tester, brightness: brightness);
              final pointer =
                  await tester.startGesture(tester.getCenter(_item(0)));
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 180));
              await expectLater(
                find.byKey(const ValueKey('navigation-capture')),
                matchesGoldenFile(
                    'goldens/bottom_navigation_pressed_${brightness.name}.png'),
              );
              await pointer.up();
              await tester.pumpAndSettle();
            }),
        tags: const ['golden']);

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
      'light dragging lens stays distinct against a pale track',
      (tester) => _withShadows(() async {
            await _pumpNavigation(tester);
            final pointer =
                await tester.startGesture(tester.getCenter(_item(0)));
            await pointer.moveTo(tester.getCenter(_item(2)));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 220));
            await expectLater(
              find.byKey(const ValueKey('navigation-capture')),
              matchesGoldenFile('goldens/bottom_navigation_drag_light.png'),
            );
            await pointer.up();
            await tester.pumpAndSettle();
          }),
      tags: const ['golden']);

  testWidgets(
      'dark dragging light illuminates the track around the clear lens',
      (tester) => _withShadows(() async {
            await _pumpNavigation(tester, brightness: Brightness.dark);
            final pointer =
                await tester.startGesture(tester.getCenter(_item(0)));
            await pointer.moveTo(tester.getCenter(_item(2)));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 220));
            await expectLater(
              find.byKey(const ValueKey('navigation-capture')),
              matchesGoldenFile('goldens/bottom_navigation_drag_dark.png'),
            );
            await pointer.up();
            await tester.pumpAndSettle();
          }),
      tags: const ['golden']);

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
              const dark = bool.fromEnvironment('recordNavigationDark');
              const classic = bool.fromEnvironment('recordNavigationClassic');
              await _pumpNavigation(tester,
                  classic: classic,
                  brightness: dark ? Brightness.dark : Brightness.light);
              final directory = Directory(classic
                  ? 'build/navigation-motion-classic'
                  : dark
                      ? 'build/navigation-motion-dark'
                      : 'build/navigation-motion');
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

Future<void> _captureGlassMatrix(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('recordNavigationGlassMatrix')) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('navigation-capture')));
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = File('build/glass-matrix/$name.png');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
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
  Color seedColor = Colors.blue,
  Locale locale = const Locale('zh'),
  double width = 390,
  double textScale = 1,
  bool reduceMotion = false,
  bool rtl = false,
  bool classic = false,
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
        seedColor: seedColor,
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
            child: classic
                ? ClassicBottomNavigation(
                    selectedIndex: selectedIndex,
                    onDestinationSelected: (index) {
                      commits.add(index);
                      current.value = index;
                    },
                  )
                : AppBottomNavigation(
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
