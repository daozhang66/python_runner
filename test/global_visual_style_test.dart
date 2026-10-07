import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/l10n/app_localizations.dart';
import 'package:python_runner/providers/theme_provider.dart';
import 'package:python_runner/ui/app_materials.dart';
import 'package:python_runner/ui/app_glass_press.dart';
import 'package:python_runner/ui/app_theme.dart';
import 'package:python_runner/ui/app_toolbars.dart';
import 'package:python_runner/widgets/app_dialogs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final legacy in [null, false, true]) {
    test('migration preserves legacy navigation $legacy', () async {
      SharedPreferences.setMockInitialValues(
          {if (legacy != null) 'liquid_navigation': legacy});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeNotifier(prefs);
      expect(theme.state.visualStyle, AppVisualStyle.classic);
      expect(
          theme.state.navigationStyle,
          legacy == null
              ? NavigationStyle.followInterface
              : legacy
                  ? NavigationStyle.liquid
                  : NavigationStyle.classic);
      theme.dispose();
      final reopened = ThemeNotifier(prefs);
      expect(reopened.state.liquidNavigation, legacy ?? false);
      reopened.dispose();
    });
  }
  test('invalid new values fall back without resurrecting the legacy override',
      () async {
    SharedPreferences.setMockInitialValues({
      'liquid_navigation': true,
      'navigation_style': 'invalid',
      'app_visual_style': 4
    });
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeNotifier(prefs);
    expect(theme.state.visualStyle, AppVisualStyle.classic);
    expect(theme.state.navigationStyle, NavigationStyle.followInterface);
    expect(theme.state.liquidNavigation, false);
    theme.dispose();
  });
  for (final visual in AppVisualStyle.values) {
    for (final navigation in NavigationStyle.values) {
      test(
          'style combination $visual $navigation survives color/font changes and reload',
          () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final theme = ThemeNotifier(prefs);
        await theme.setVisualStyle(visual);
        await theme.setNavigationStyle(navigation);
        await theme.setSeedColor(Colors.teal);
        await theme.setUseDynamicColor(true);
        await theme.setFontFamily(AppFontFamily.miSans);
        await theme.setEnableBlurEffect(true);
        await theme.setThemeMode(ThemeMode.dark);
        theme.dispose();
        final restored = ThemeNotifier(prefs);
        expect(restored.state.visualStyle, visual);
        expect(restored.state.navigationStyle, navigation);
        expect(
            restored.state.liquidNavigation,
            navigation == NavigationStyle.liquid ||
                navigation == NavigationStyle.followInterface &&
                    visual == AppVisualStyle.liquid);
        expect(restored.state.enableBlurEffect, true);
        restored.dispose();
      });
    }
  }

  testWidgets('switching material retains input state, selection and geometry',
      (tester) async {
    final style = ValueNotifier(AppVisualStyle.classic);
    final input = TextEditingController(text: 'requests');
    addTearDown(style.dispose);
    addTearDown(input.dispose);
    await tester.pumpWidget(ValueListenableBuilder<AppVisualStyle>(
        valueListenable: style,
        builder: (_, value, __) => MaterialApp(
            theme: AppTheme.build(ColorScheme.fromSeed(seedColor: Colors.blue),
                visualStyle: value),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
                body: AppSearchBar(
                    controller: input,
                    onChanged: (_) {},
                    trailingActions: [
                  IconButton(onPressed: () {}, icon: const Icon(Icons.refresh))
                ])))));
    await tester.tap(find.byType(TextField));
    input.selection = const TextSelection(baseOffset: 1, extentOffset: 5);
    final state = tester.state(find.byType(TextField));
    final rect = tester.getRect(find.byType(TextField));
    for (final value in [AppVisualStyle.liquid, AppVisualStyle.classic]) {
      style.value = value;
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(TextField)), same(state));
      expect(tester.getRect(find.byType(TextField)), rect);
      expect(input.text, 'requests');
      expect(
          input.selection, const TextSelection(baseOffset: 1, extentOffset: 5));
      expect(tester.takeException(), isNull);
    }
  });

  for (final contrast in [false, true]) {
    testWidgets('glass prevents nested blur and respects contrast=$contrast',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.build(ColorScheme.fromSeed(seedColor: Colors.blue),
              visualStyle: AppVisualStyle.liquid),
          home: MediaQuery(
              data: MediaQueryData(highContrast: contrast),
              child: const Scaffold(
                  body: AppGlassSurface(
                      sampleBackdrop: true,
                      child: AppGlassSurface(
                          sampleBackdrop: true,
                          child: SizedBox(width: 100, height: 50)))))));
      final filters =
          tester.widgetList<BackdropFilter>(find.byType(BackdropFilter));
      expect(filters.where((f) => f.enabled).length, contrast ? 0 : 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'liquid dialog material stays bounded rather than covering the screen',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(ColorScheme.fromSeed(seedColor: Colors.blue),
            visualStyle: AppVisualStyle.liquid),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => const AppAlertDialog(
                            title: Text('Title'), content: Text('Content'))),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final filter = find.byType(BackdropFilter);
    expect(filter, findsOneWidget);
    expect(tester.getSize(filter).height, lessThan(300));
    expect(tester.getSize(filter).width, lessThan(600));
  });

  for (final visual in AppVisualStyle.values) {
    testWidgets('simple dialog width does not grow with liquid style: $visual',
        (tester) async {
      double? width;
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.build(ColorScheme.fromSeed(seedColor: Colors.blue),
              visualStyle: visual),
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => AppAlertDialog(
                                  title: const Text('标题'),
                                  content: const Text('一段简短的确认内容'),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(),
                                        child: const Text('取消')),
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(),
                                        child: const Text('确定')),
                                  ])),
                      child: const Text('Open'))))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      // AlertDialog is a layout-only wrapper; Material carries the visible
      // dialog surface. Measure it, not the outer route shell.
      // The first Material under the alert is its dialog surface; later ones
      // belong to action buttons.
      width = tester
          .getSize(find
              .descendant(
                  of: find.byType(AppAlertDialog),
                  matching: find.byType(Material))
              .first)
          .width;
      tester.printToConsole('dialog width $visual: $width');
      expect(width, greaterThanOrEqualTo(280));
      expect(width, lessThanOrEqualTo(560),
          reason: '$visual dialog must not balloon horizontally');
      expect(tester.takeException(), isNull);
    });
  }

  for (final reduced in [false, true]) {
    testWidgets(
        'liquid menu keeps selection, cancellation and reduced motion=$reduced',
        (tester) async {
      int? selected;
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.build(ColorScheme.fromSeed(seedColor: Colors.blue),
              visualStyle: AppVisualStyle.liquid),
          home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Builder(
                  builder: (context) => Scaffold(
                        appBar: AppBar(actions: [
                          PopupMenuButton<int>(
                              popUpAnimationStyle: appMenuAnimation(context),
                              onSelected: (value) => selected = value,
                              itemBuilder: (_) => const [
                                    PopupMenuItem(value: 1, child: Text('Run')),
                                    PopupMenuItem(value: 2, child: Text('Edit'))
                                  ])
                        ]),
                      )))));
      final button =
          find.byWidgetPredicate((widget) => widget is PopupMenuButton<int>);
      expect(tester.widget<PopupMenuButton<int>>(button).popUpAnimationStyle,
          reduced ? AnimationStyle.noAnimation : isNotNull);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(selected, 2);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 400));
      await tester.pumpAndSettle();
      expect(selected, 2);
      expect(find.text('Edit'), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  }

  for (final visual in [AppVisualStyle.liquid, AppVisualStyle.classic]) {
    for (final reduceMotion in [false, true]) {
      testWidgets(
          'glass press ripple appears only when active: $visual reduce=$reduceMotion',
          (tester) async {
        bool pressed = false;
        Widget buildHarness() => MaterialApp(
              theme: AppTheme.build(
                  ColorScheme.fromSeed(seedColor: Colors.blue),
                  visualStyle: visual),
              home: MediaQuery(
                data: MediaQueryData(disableAnimations: reduceMotion),
                child: Scaffold(
                  body: Center(
                    child: AppGlassSurface(
                      radius: BorderRadius.circular(12),
                      child: AppGlassPress(
                        child: InkWell(
                          onTap: () => pressed = true,
                          child: const SizedBox(width: 120, height: 48),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
        await tester.pumpWidget(buildHarness());
        final pressFinder = find.byType(AppGlassPress);
        expect(pressFinder, findsOneWidget);

        // Pointer down starts the wave; liquid animates it.
        final gesture =
            await tester.startGesture(tester.getCenter(find.byType(InkWell)));
        await tester.pump(const Duration(milliseconds: 120));
        expect(tester.takeException(), isNull);

        // Release settles the wave so no painter remains.
        await gesture.up();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(pressed, isTrue);
      });
    }
  }
}
