import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/models/script_file.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/script_workspace_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final fontLoader = FontLoader('MiSans');
    fontLoader.addFont(rootBundle.load('assets/fonts/MiSansVF.ttf'));
    await fontLoader.load();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('phone light workspace matches baseline', (tester) async {
    final harness = await _pumpGoldenWorkspace(
      tester,
      scripts: [_script('daily.py'), _script('report.py', sortOrder: 1)],
    );
    addTearDown(harness.dispose);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/script_workspace_phone_light.png'),
    );
  }, tags: const ['golden']);

  testWidgets('phone dark empty workspace matches baseline', (tester) async {
    final harness = await _pumpGoldenWorkspace(
      tester,
      brightness: Brightness.dark,
    );
    addTearDown(harness.dispose);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/script_workspace_phone_dark_empty.png'),
    );
  }, tags: const ['golden']);

  testWidgets('phone reorder mode matches baseline', (tester) async {
    final harness = await _pumpGoldenWorkspace(
      tester,
      scripts: [
        _script('pinned.py', isPinned: true),
        _script('daily.py', sortOrder: 1),
        _script('report.py', sortOrder: 2),
      ],
    );
    addTearDown(harness.dispose);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '排序脚本'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/script_workspace_phone_reorder.png'),
    );
  }, tags: const ['golden']);

  testWidgets('tablet light details matches baseline', (tester) async {
    final harness = await _pumpGoldenWorkspace(
      tester,
      size: const Size(1024, 768),
      scripts: [_script('daily.py')],
    );
    addTearDown(harness.dispose);
    await tester.tap(find.text('daily'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/script_workspace_tablet_light_details.png'),
    );
  }, tags: const ['golden']);

  testWidgets('tablet dark details matches baseline', (tester) async {
    final harness = await _pumpGoldenWorkspace(
      tester,
      size: const Size(1024, 768),
      brightness: Brightness.dark,
      scripts: [_script('daily.py')],
    );
    addTearDown(harness.dispose);
    await tester.tap(find.text('daily'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/script_workspace_tablet_dark_details.png'),
    );
  }, tags: const ['golden']);
}

Future<ScriptWorkspaceHarness> _pumpGoldenWorkspace(
  WidgetTester tester, {
  List<ScriptFile> scripts = const [],
  Brightness brightness = Brightness.light,
  Size size = const Size(390, 844),
}) async {
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  final preferences = await SharedPreferences.getInstance();
  await preferences.remove('script_tablet_selected_name');
  final harness = ScriptWorkspaceHarness(
    preferences: preferences,
    bridge: FakeScriptNativeBridge(
      scriptNames: scripts.map((script) => script.name).toList(),
    ),
    database: InMemoryScriptDatabase(scripts: scripts),
  );
  await tester.pumpWidget(harness.buildApp(brightness: brightness));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return harness;
}

ScriptFile _script(
  String name, {
  bool isPinned = false,
  int sortOrder = 0,
}) {
  return ScriptFile(
    name: name,
    path: name,
    createdAt: DateTime(2025, 1, 1),
    modifiedAt: DateTime(2025, 1, 2),
    runCount: 3,
    isPinned: isPinned,
    sortOrder: sortOrder,
  );
}
