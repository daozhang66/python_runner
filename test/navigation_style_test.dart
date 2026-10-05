import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/l10n/app_localizations.dart';
import 'package:python_runner/pages/theme_settings_page.dart';
import 'package:python_runner/providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'navigation preference defaults to follow and survives reload and theme edits',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final notifier = ThemeNotifier(prefs);
    addTearDown(notifier.dispose);
    expect(notifier.state.liquidNavigation, isFalse);
    await notifier.setLiquidNavigation(false);
    await notifier.setThemeMode(ThemeMode.dark);
    await notifier.setUseDynamicColor(true);
    await notifier.setEnableBlurEffect(true);
    expect(notifier.state.liquidNavigation, isFalse);
    final restored = ThemeNotifier(prefs);
    addTearDown(restored.dispose);
    expect(restored.state.liquidNavigation, isFalse);
    await restored.setLiquidNavigation(true);
    expect(prefs.getBool('liquid_navigation'), isTrue);
  });

  for (final dynamicColor in [false, true]) {
    testWidgets(
        'theme page toggles navigation independently of Material You: $dynamicColor',
        (tester) async {
      SharedPreferences.setMockInitialValues(
          {'use_dynamic_color': dynamicColor});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ThemeSettingsPage(),
        ),
      ));
      await tester.pumpAndSettle();
      final style = find.byKey(const ValueKey('interface-style'));
      await tester.ensureVisible(style);
      await tester.tap(find.descendant(of: style, matching: find.text('液态玻璃')));
      await tester.pumpAndSettle();
      expect(prefs.getString('app_visual_style'), 'liquid');
      final menu = find.byKey(const ValueKey('navigation-style'));
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('经典 Material').last);
      await tester.pumpAndSettle();
      expect(prefs.getString('navigation_style'), 'classic');
    });
  }

  for (final locale in ['en', 'zh']) {
    testWidgets('style controls fit narrow screen with large text: $locale',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(
              locale: Locale(locale),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(2)),
                  child: child!),
              home: const ThemeSettingsPage())));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('navigation-style')), 160,
          scrollable: find.byType(Scrollable).first);
      await tester
          .ensureVisible(find.byKey(const ValueKey('navigation-style')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('navigation-style')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final liquidOption = find.byWidgetPredicate((widget) =>
          widget is RadioListTile<NavigationStyle> &&
          widget.value == NavigationStyle.liquid);
      await tester.ensureVisible(liquidOption);
      await tester.tap(liquidOption);
      await tester.pumpAndSettle();
      expect(prefs.getString('navigation_style'), 'liquid');
      expect(tester.takeException(), isNull);
    });
  }
}
