import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:python_runner/providers/theme_provider.dart';
import 'package:python_runner/ui/app_bottom_navigation.dart';
import 'package:python_runner/ui/classic_bottom_navigation.dart';
import 'package:python_runner/features/scripts/presentation/pages/script_list_page.dart';
import 'package:python_runner/main.dart' show HomePage;
import 'package:python_runner/models/script_file.dart';
import 'package:python_runner/ui/app_theme.dart';
import 'package:python_runner/pages/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/script_workspace_harness.dart';

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

  testWidgets(
      'home extends behind the capsule but its last script remains reachable',
      (tester) async {
    await _pumpHome(tester);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.extendBody, isTrue);
    expect(tester.getBottomLeft(find.byType(ScriptListPage)).dy, 844);
    final capsule = find.byKey(const ValueKey('navigation-surface'));
    expect(tester.widget<Material>(capsule).shape, isA<StadiumBorder>());
    expect(find.byKey(const ValueKey('navigation-indicator')), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2400));
    await tester.pumpAndSettle();
    expect(find.text('demo_19').hitTestable(), findsOneWidget);
    expect(tester.getBottomLeft(find.text('demo_19')).dy,
        lessThan(tester.getTopLeft(capsule).dy));
  });

  testWidgets(
      'live style switching retains page state and restores classic surface',
      (tester) async {
    await _pumpHome(tester);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(HomePage)));
    final notifier = container.read(themeProvider.notifier);
    final pageState = tester.state(find.byType(ScriptListPage));
    await tester.tap(find.byKey(const ValueKey('navigation-item-1')));
    // Network loading can animate indefinitely with the fake native bridge.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await notifier.setLiquidNavigation(false);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(AppBottomNavigation), findsNothing);
    expect(
        tester
            .widget<ClassicBottomNavigation>(
                find.byType(ClassicBottomNavigation))
            .selectedIndex,
        1);
    final surface = tester
        .widget<Material>(find.byKey(const ValueKey('navigation-surface')));
    expect(surface.color!.a, 1);
    await notifier.setLiquidNavigation(true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(
        tester
            .widget<AppBottomNavigation>(find.byType(AppBottomNavigation))
            .selectedIndex,
        1);
    await tester.tap(find.byKey(const ValueKey('navigation-item-0')));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(ScriptListPage)), same(pageState));
    expect(tester.takeException(), isNull);
  });

  for (final liquid in [false, true]) {
    testWidgets(
        'settings is the fourth destination and switching back preserves workspace: liquid=$liquid',
        (tester) async {
      await _pumpHome(tester);
      final container =
          ProviderScope.containerOf(tester.element(find.byType(HomePage)));
      await container.read(themeProvider.notifier).setLiquidNavigation(liquid);
      await tester.pumpAndSettle();
      final workspace = tester.state(find.byType(ScriptListPage));
      expect(
          find.descendant(
              of: find.byType(AppBar),
              matching: find.byIcon(Icons.settings_outlined)),
          findsNothing);
      await tester.tap(find.byKey(const ValueKey('navigation-item-3')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(
          tester
              .widget<Semantics>(
                  find.byKey(const ValueKey('navigation-item-3')))
              .properties
              .selected,
          true);
      for (var i = 0; i < 8; i++) {
        await tester.drag(
            find.byType(CustomScrollView).first, const Offset(0, -600));
        await tester.pumpAndSettle();
      }
      final view =
          tester.state<ScrollableState>(find.byType(Scrollable).last).position;
      expect(view.pixels, closeTo(view.maxScrollExtent, 1));
      await tester.tap(find.byKey(const ValueKey('navigation-item-0')));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(ScriptListPage)), same(workspace));
      await tester.tap(find.byKey(const ValueKey('navigation-item-3')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tester.widget<Semantics>(find.byKey(const ValueKey('navigation-item-0'))).properties.selected, true);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('light capsule blends with the script grid behind it',
      (tester) async {
    final previous = debugDisableShadows;
    debugDisableShadows = false;
    try {
      await _pumpHome(tester, liquidTheme: true, grid: true);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('goldens/navigation_grid_light.png'));
    } finally {
      debugDisableShadows = previous;
    }
  }, tags: const ['golden']);

  for (final brightness in Brightness.values) {
    testWidgets('four-tab liquid home has continuous top surface: $brightness',
        (tester) async {
      await _pumpHome(tester, brightness: brightness, liquidTheme: true);
      final bar = tester.widget<AppBar>(find.byType(AppBar).first);
      expect(bar.flexibleSpace, isNotNull);
      expect(find.byKey(const ValueKey('navigation-item-3')), findsOneWidget);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('goldens/glass_four_home_${brightness.name}.png'));
    }, tags: const ['golden']);
    testWidgets(
        'floating capsule has no rectangular backing: ${brightness.name}',
        (tester) async {
      final previous = debugDisableShadows;
      debugDisableShadows = false;
      try {
        await _pumpHome(tester, brightness: brightness);
        await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
                'goldens/navigation_overlay_${brightness.name}.png'));
      } finally {
        debugDisableShadows = previous;
      }
    }, tags: const ['golden']);
  }
}

Future<void> _pumpHome(WidgetTester tester,
    {Brightness brightness = Brightness.light,
    bool liquidTheme = false,
    bool grid = false}) async {
  SharedPreferences.setMockInitialValues(
      {'app_update_auto_check_enabled': false, 'liquid_navigation': true,
        'script_grid_view': grid});
  final preferences = await SharedPreferences.getInstance();
  final scripts = List.generate(20, (index) {
    final name = 'demo_${index.toString().padLeft(2, '0')}.py';
    return ScriptFile(
      name: name,
      path: name,
      sortOrder: index,
      createdAt: DateTime(2026, 1, 1),
      modifiedAt: DateTime(2026, 1, 2),
    );
  });
  final harness = ScriptWorkspaceHarness(
    preferences: preferences,
    bridge: FakeScriptNativeBridge(
        scriptNames: scripts.map((s) => s.name).toList()),
    database: InMemoryScriptDatabase(scripts: scripts),
  );
  addTearDown(harness.dispose);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(harness.buildPage(Theme(
    data: AppTheme.build(
      ColorScheme.fromSeed(seedColor: Colors.blue, brightness: brightness),
      fontFamily: 'MiSans',
      visualStyle: liquidTheme ? AppVisualStyle.liquid : AppVisualStyle.classic,
    ),
    child: const HomePage(currentThemeMode: ThemeMode.system),
  )));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}
