import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/models/script_file.dart';
import 'package:python_runner/providers/script_workspace_ui_provider.dart';
import 'package:python_runner/ui/app_skeleton.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/script_workspace_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('workspace shows skeleton during first script load',
      (tester) async {
    final loadGate = Completer<void>();
    final harness = await _pumpWorkspace(
      tester,
      scripts: [_script('daily.py')],
      loadGate: loadGate,
    );
    addTearDown(harness.dispose);

    expect(find.byType(AppListSkeleton), findsOneWidget);

    loadGate.complete();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('daily'), findsOneWidget);
    expect(find.byType(CustomScrollView), findsOneWidget);
  });

  testWidgets('workspace exposes empty and search-empty states',
      (tester) async {
    final emptyHarness = await _pumpWorkspace(tester);
    addTearDown(emptyHarness.dispose);

    expect(find.text('还没有脚本'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());

    final harness =
        await _pumpWorkspace(tester, scripts: [_script('daily.py')]);
    addTearDown(harness.dispose);
    await _openWorkspaceMenu(tester);
    await tester.tap(find.widgetWithText(ListTile, '搜索脚本'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('无匹配结果'), findsOneWidget);
  });

  testWidgets('workspace limits drag controls to explicit reorder mode',
      (tester) async {
    final harness = await _pumpWorkspace(
      tester,
      scripts: [
        _script('pinned.py', isPinned: true),
        _script('daily.py', sortOrder: 1),
        _script('report.py', sortOrder: 2),
      ],
    );
    addTearDown(harness.dispose);

    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(find.byType(Draggable<String>), findsNothing);

    await _openWorkspaceMenu(tester);
    await tester.tap(find.widgetWithText(ListTile, '排序脚本'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('排序脚本'), findsAtLeastNWidgets(1));
    expect(find.byType(Draggable<String>), findsNWidgets(2));

    await tester.tap(find.byTooltip('结束排序'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(CustomScrollView), findsOneWidget);
  });

  testWidgets('tablet selection opens details and clears after deletion',
      (tester) async {
    final harness = await _pumpWorkspace(
      tester,
      size: const Size(1024, 768),
      scripts: [_script('daily.py')],
    );
    addTearDown(harness.dispose);

    expect(
      MediaQuery.sizeOf(tester.element(find.byType(Scaffold))).width,
      greaterThanOrEqualTo(600),
    );
    await tester.tap(find.text('daily'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('脚本详情'), findsOneWidget);
    expect(find.byTooltip('查看控制台'), findsOneWidget);
    expect(find.byTooltip('置顶'), findsOneWidget);

    await tester.longPress(find.text('daily').first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('删除').first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('删除').last);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('还没有脚本'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
      listen: false,
    );
    expect(
        container.read(scriptWorkspaceUiProvider).selectedScriptName, isNull);
  });

  testWidgets('tablet details localize new actions and tolerate large text',
      (tester) async {
    const longName =
        'an_exceptionally_long_script_name_that_must_not_overflow_the_tablet_panel.py';
    final harness = await _pumpWorkspace(
      tester,
      size: const Size(1024, 768),
      locale: const Locale('en'),
      textScaleFactor: 2,
      scripts: [_script(longName)],
    );
    addTearDown(harness.dispose);

    await tester.tap(find.byType(InkWell).first);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Script details'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<ScriptWorkspaceHarness> _pumpWorkspace(
  WidgetTester tester, {
  List<ScriptFile> scripts = const [],
  Completer<void>? loadGate,
  Size size = const Size(390, 844),
  Locale locale = const Locale('zh'),
  double textScaleFactor = 1,
}) async {
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;

  final preferences = await SharedPreferences.getInstance();
  await preferences.remove('script_tablet_selected_name');
  final bridge = FakeScriptNativeBridge(
    scriptNames: scripts.map((script) => script.name).toList(),
  );
  final harness = ScriptWorkspaceHarness(
    preferences: preferences,
    bridge: bridge,
    database: InMemoryScriptDatabase(scripts: scripts, loadGate: loadGate),
  );
  await tester.pumpWidget(
    harness.buildApp(
      locale: locale,
      textScaleFactor: textScaleFactor,
    ),
  );
  await tester.pump();
  if (loadGate == null) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
  return harness;
}

Future<void> _openWorkspaceMenu(WidgetTester tester) async {
  await tester.tap(find.byType(PopupMenuButton<String>));
  await tester.pump();
  await tester.pumpAndSettle();
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
