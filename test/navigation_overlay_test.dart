import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/scripts/presentation/pages/script_list_page.dart';
import 'package:python_runner/main.dart' show HomePage;
import 'package:python_runner/models/script_file.dart';
import 'package:python_runner/ui/app_theme.dart';
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

  for (final brightness in Brightness.values) {
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
    {Brightness brightness = Brightness.light}) async {
  SharedPreferences.setMockInitialValues(
      {'app_update_auto_check_enabled': false});
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
    ),
    child: const HomePage(currentThemeMode: ThemeMode.system),
  )));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}
