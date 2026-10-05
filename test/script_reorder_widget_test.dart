import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/scripts/application/script_workspace_controller.dart';
import 'package:python_runner/features/scripts/application/script_home_item.dart';
import 'package:python_runner/features/scripts/presentation/pages/script_list_page.dart';
import 'package:python_runner/models/script_file.dart';
import 'package:python_runner/models/script_group.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/script_workspace_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final grid in [false, true]) {
    const movable = ['group:3', 'first.py', 'group:2', 'second.py'];
    testWidgets('groups can swap when there are no root scripts: grid=$grid',
        (tester) async {
      final harness = await _pumpWorkspace(tester,
          grid: grid, withProject: true, groupsOnly: true);
      addTearDown(harness.dispose);
      await _enterReorder(tester);
      await _dragTo(tester, 'group:2',
          tester.getCenter(find.byKey(const ValueKey('home_item_group:3'))));
      expect(_homeVisualOrder(tester, ['group:2', 'group:3']),
          ['group:2', 'group:3']);
      await tester.tap(find.byTooltip('结束排序'));
      await tester.pumpAndSettle();
      expect(_homeVisualOrder(tester, ['group:2', 'group:3']),
          ['group:2', 'group:3']);
    });
    for (final source in movable) {
      for (final target in movable.where((key) => key != source)) {
        testWidgets('mixed home swap $source -> $target persists: grid=$grid',
            (tester) async {
          final harness = await _pumpWorkspace(tester,
              grid: grid, withProject: true, pinned: true);
          addTearDown(harness.dispose);
          await _enterReorder(tester);
          final initial = ['pin.py', ...movable];
          expect(_homeVisualOrder(tester, initial), initial);
          final expected = List<String>.of(initial);
          final a = expected.indexOf(source);
          final b = expected.indexOf(target);
          expected[a] = target;
          expected[b] = source;
          await _dragTo(tester, source,
              tester.getCenter(find.byKey(ValueKey('home_item_$target'))));
          expect(_homeVisualOrder(tester, initial), expected);
          final saved = ScriptHomeItem.ordered(
              await harness.database.getAllScripts(),
              await harness.database.getAllGroups());
          expect(saved.map((item) => item.key), expected);
          await tester.tap(find.byTooltip('结束排序'));
          await tester.pumpAndSettle();
          expect(_homeVisualOrder(tester, initial), expected);
          await tester.pumpWidget(const SizedBox.shrink());
          final reopened = ScriptWorkspaceHarness(
            preferences: harness.preferences,
            database: harness.database,
            bridge: FakeScriptNativeBridge(
                scriptNames: ['pin.py', 'first.py', 'second.py']),
          );
          addTearDown(reopened.dispose);
          await tester.pumpWidget(reopened.buildApp());
          await tester.pumpAndSettle();
          expect(_homeVisualOrder(tester, initial), expected);
          expect(tester.takeException(), isNull);
        });
      }
    }
    for (final groupKey in ['group:2', 'group:3']) {
      testWidgets(
          'group drag rejects pinned, self and outside targets: $groupKey grid=$grid',
          (tester) async {
        final harness = await _pumpWorkspace(tester,
            grid: grid, withProject: true, pinned: true);
        addTearDown(harness.dispose);
        await _enterReorder(tester);
        final initial = ['pin.py', ...movable];
        for (final target in [
          tester.getCenter(find.byKey(const ValueKey('home_item_pin.py'))),
          tester.getCenter(find.byKey(ValueKey('home_item_$groupKey'))),
          const Offset(10, 10),
        ]) {
          await _dragTo(tester, groupKey, target);
          expect(_homeVisualOrder(tester, initial), initial);
        }
        await _dragTo(
            tester,
            groupKey,
            tester
                .getCenter(find.byKey(const ValueKey('home_item_second.py'))));
        expect(_homeVisualOrder(tester, initial), isNot(initial));
      });
    }
    for (final inGroup in [false, true]) {
      testWidgets('drop persists and stays visible: grid=$grid group=$inGroup',
          (tester) async {
        final harness =
            await _pumpWorkspace(tester, grid: grid, inGroup: inGroup);
        addTearDown(harness.dispose);
        await _enterReorder(tester);
        if (inGroup) {
          await tester.tap(find.text('Work'));
          await tester.pumpAndSettle();
        }
        expect(_visualOrder(tester), ['first', 'second']);
        await _dragTo(
            tester, 'first.py', tester.getCenter(find.text('second')));
        final saved = (await harness.database.getAllScripts())
            .where((s) => !s.isPinned)
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        expect(saved.map((s) => s.name), ['second.py', 'first.py'],
            reason: 'Dropping on the visible target must persist the swap');
        expect(_visualOrder(tester), ['second', 'first'],
            reason:
                'The UI must render the saved order, even with distinct modification times');
        expect(saved.first.modifiedAt, DateTime(2025, 1, 1));
        await tester.tap(find.byTooltip('结束排序'));
        await tester.pumpAndSettle();
        expect(_visualOrder(tester), ['second', 'first']);
        final container = ProviderScope.containerOf(
            tester.element(find.byType(ScriptListPage)),
            listen: false);
        await container.read(scriptWorkspaceControllerProvider.notifier).load();
        await tester.pumpAndSettle();
        expect(_visualOrder(tester), ['second', 'first']);
        await tester.pumpWidget(const SizedBox.shrink());
        final reopened = ScriptWorkspaceHarness(
          preferences: harness.preferences,
          database: harness.database,
          bridge:
              FakeScriptNativeBridge(scriptNames: ['first.py', 'second.py']),
        );
        addTearDown(reopened.dispose);
        await tester.pumpWidget(reopened.buildApp());
        await tester.pumpAndSettle();
        if (inGroup) {
          await tester.tap(find.text('Work'));
          await tester.pumpAndSettle();
        }
        expect(_visualOrder(tester), ['second', 'first']);
      });
    }
  }

  testWidgets('back exits sorting instead of leaving the workspace',
      (tester) async {
    final controller = ScriptListPageController();
    final harness = await _pumpWorkspace(tester, controller: controller);
    addTearDown(harness.dispose);
    await _enterReorder(tester);
    expect(controller.handleBack(), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(Draggable<String>), findsNothing);
  });

  testWidgets('canceling a folder grid preview leaves drag controls usable',
      (tester) async {
    final harness = await _pumpWorkspace(tester, grid: true, inGroup: true);
    addTearDown(harness.dispose);
    await _enterReorder(tester);
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    final handle = find.byWidgetPredicate(
        (widget) => widget is Draggable<String> && widget.data == 'first.py');
    final offset = tester.widget<Draggable<String>>(handle).feedbackOffset;
    final target = tester.getCenter(find.text('second')) - offset;
    final pointer = await tester.startGesture(tester.getCenter(handle));
    await pointer.moveBy(const Offset(0, 20));
    await tester.pump();
    await pointer.moveTo(target);
    await tester.pump(const Duration(milliseconds: 150));
    await pointer.cancel();
    await tester.pumpAndSettle();
    expect(find.byType(Draggable<String>), findsNWidgets(2));
    expect(_visualOrder(tester), ['first', 'second']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'folder grid preview keeps its active source and drop target alive',
      (tester) async {
    final harness = await _pumpWorkspace(tester, grid: true, inGroup: true);
    addTearDown(harness.dispose);
    await _enterReorder(tester);
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    final handle = find.byWidgetPredicate(
        (widget) => widget is Draggable<String> && widget.data == 'first.py');
    final sourceState = tester.state(handle);
    final targetState = tester.state(find
        .ancestor(
            of: find.text('second'), matching: find.byType(DragTarget<String>))
        .first);
    final target = tester.getCenter(find.text('second'));
    final pointer = await tester.startGesture(tester.getCenter(handle));
    await pointer.moveBy(const Offset(0, 20));
    await tester.pump();
    await pointer.moveTo(target);
    await tester.pump(const Duration(milliseconds: 150));
    final sourceAlive = sourceState.mounted;
    final targetAlive = targetState.mounted;
    await pointer.cancel();
    await tester.pumpAndSettle();
    expect(sourceAlive, isTrue,
        reason: 'Preview must not dispose the active drag');
    expect(targetAlive, isTrue,
        reason: 'The accepting target must survive until release');
  });

  for (final grid in [false, true]) {
    testWidgets('home project position survives tied timestamps: grid=$grid',
        (tester) async {
      final harness = await _pumpWorkspace(tester,
          grid: grid, withProject: true, projectSharesTimestamp: true);
      addTearDown(harness.dispose);
      final browseProjectPosition = tester.getTopLeft(find.text('Project'));
      await _enterReorder(tester);
      final projectPosition = tester.getTopLeft(find.text('Project'));
      await _dragTo(tester, 'first.py', tester.getCenter(find.text('second')));
      expect(_visualOrder(tester), ['second', 'first']);
      expect(tester.getTopLeft(find.text('Project')), projectPosition);
      await tester.tap(find.byTooltip('结束排序'));
      await tester.pumpAndSettle();
      expect(_visualOrder(tester), ['second', 'first']);
      expect(tester.getTopLeft(find.text('Project')), browseProjectPosition);
    });

    testWidgets('home drag retains folder and project positions: grid=$grid',
        (tester) async {
      final harness =
          await _pumpWorkspace(tester, grid: grid, withProject: true);
      addTearDown(harness.dispose);
      await _enterReorder(tester);
      final folderPosition = tester.getTopLeft(find.text('Folder'));
      final projectPosition = tester.getTopLeft(find.text('Project'));
      await _dragTo(tester, 'first.py', tester.getCenter(find.text('second')));
      expect(_visualOrder(tester), ['second', 'first']);
      expect(tester.getTopLeft(find.text('Folder')), folderPosition);
      expect(tester.getTopLeft(find.text('Project')), projectPosition);
      await tester.tap(find.byTooltip('结束排序'));
      await tester.pumpAndSettle();
      expect(_visualOrder(tester), ['second', 'first']);
      final container = ProviderScope.containerOf(
          tester.element(find.byType(ScriptListPage)),
          listen: false);
      await container
          .read(scriptWorkspaceControllerProvider.notifier)
          .incrementRunCount('first.py');
      await tester.pumpAndSettle();
      expect(_visualOrder(tester), ['first', 'second']);
    });

    for (final inGroup in [false, true]) {
      testWidgets('pinned targets stay fixed: grid=$grid group=$inGroup',
          (tester) async {
        final harness = await _pumpWorkspace(tester,
            grid: grid, inGroup: inGroup, pinned: true);
        addTearDown(harness.dispose);
        await _enterReorder(tester);
        if (inGroup) {
          await tester.tap(find.text('Work'));
          await tester.pumpAndSettle();
        }
        expect(
            find.byWidgetPredicate((widget) =>
                widget is Draggable<String> && widget.data == 'pin.py'),
            findsNothing);
        await _dragTo(tester, 'first.py', tester.getCenter(find.text('pin')));
        expect(_visualOrder(tester, ['pin', 'first', 'second']),
            ['pin', 'first', 'second']);
        final saved = await harness.database.getAllScripts();
        expect(saved.firstWhere((s) => s.name == 'pin.py').isPinned, isTrue);
        await _dragTo(
            tester, 'first.py', tester.getCenter(find.text('second')));
        expect(_visualOrder(tester, ['pin', 'first', 'second']),
            ['pin', 'second', 'first']);
      });

      testWidgets(
          'outside drop and repeated drags recover: grid=$grid group=$inGroup',
          (tester) async {
        final harness =
            await _pumpWorkspace(tester, grid: grid, inGroup: inGroup);
        addTearDown(harness.dispose);
        await _enterReorder(tester);
        if (inGroup) {
          await tester.tap(find.text('Work'));
          await tester.pumpAndSettle();
        }
        await _dragTo(tester, 'first.py', const Offset(10, 10));
        expect(_visualOrder(tester), ['first', 'second']);
        await _dragTo(
            tester, 'first.py', tester.getCenter(find.text('second')));
        expect(_visualOrder(tester), ['second', 'first']);
        await _dragTo(
            tester, 'first.py', tester.getCenter(find.text('second')));
        expect(_visualOrder(tester), ['first', 'second']);
      });
    }
  }
}

List<String> _homeVisualOrder(WidgetTester tester, List<String> keys) {
  return List<String>.of(keys)
    ..sort((a, b) {
      final pa = tester.getTopLeft(find.byKey(ValueKey('home_item_$a')));
      final pb = tester.getTopLeft(find.byKey(ValueKey('home_item_$b')));
      final vertical = pa.dy.compareTo(pb.dy);
      return vertical != 0 ? vertical : pa.dx.compareTo(pb.dx);
    });
}

List<String> _visualOrder(WidgetTester tester,
    [List<String> scriptNames = const ['first', 'second']]) {
  final names = List<String>.of(scriptNames);
  names.sort((a, b) {
    final pa = tester.getTopLeft(find.text(a));
    final pb = tester.getTopLeft(find.text(b));
    final vertical = pa.dy.compareTo(pb.dy);
    return vertical != 0 ? vertical : pa.dx.compareTo(pb.dx);
  });
  return names;
}

Future<void> _dragTo(WidgetTester tester, String name, Offset target) async {
  final handle = find.byWidgetPredicate(
      (widget) => widget is Draggable<String> && widget.data == name);
  expect(handle, findsOneWidget);
  final pointer = await tester.startGesture(tester.getCenter(handle));
  await pointer.moveBy(const Offset(0, 20));
  await tester.pump();
  await pointer.moveTo(target);
  await tester.pump(const Duration(milliseconds: 150));
  await pointer.up();
  await tester.pumpAndSettle();
}

Future<void> _enterReorder(WidgetTester tester) async {
  await tester.tap(find.byWidgetPredicate((widget) => widget is PopupMenuButton<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ListTile, '排序脚本'));
  await tester.pumpAndSettle();
}

Future<ScriptWorkspaceHarness> _pumpWorkspace(
  WidgetTester tester, {
  bool grid = false,
  bool inGroup = false,
  bool withProject = false,
  bool projectSharesTimestamp = false,
  bool groupsOnly = false,
  bool pinned = false,
  ScriptListPageController? controller,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final prefs = await SharedPreferences.getInstance();
  final scripts = [
    if (pinned)
      ScriptFile(
        name: 'pin.py',
        path: 'pin.py',
        createdAt: DateTime(2025, 1, 1),
        modifiedAt: DateTime(2025, 1, 3),
        isPinned: true,
        sortOrder: 0,
        groupId: inGroup ? 1 : null,
      ),
    for (var i = 0; i < (groupsOnly ? 0 : 2); i++)
      ScriptFile(
        name: i == 0 ? 'first.py' : 'second.py',
        path: i == 0 ? 'first.py' : 'second.py',
        createdAt: DateTime(2025, 1, 1),
        modifiedAt: DateTime(2025, 1, 2 - i),
        sortOrder: i + (pinned ? 1 : 0),
        groupId: inGroup ? 1 : null,
      ),
  ];
  final harness = ScriptWorkspaceHarness(
    preferences: prefs,
    bridge: FakeScriptNativeBridge(
        scriptNames: scripts.map((s) => s.name).toList()),
    database: InMemoryScriptDatabase(scripts: scripts, groups: [
      if (inGroup)
        ScriptGroup(
          id: 1,
          name: 'Work',
          sortOrder: 0,
          createdAt: DateTime(2025, 1, 1),
          modifiedAt: DateTime(2025, 1, 1),
        ),
      if (withProject) ...[
        ScriptGroup(
            id: 2,
            name: 'Project',
            sortOrder: projectSharesTimestamp ? 0 : 1,
            createdAt: DateTime(2025, 1, 1),
            modifiedAt: projectSharesTimestamp
                ? DateTime(2025, 1, 2)
                : DateTime(2025, 1, 1, 12),
            isProject: true,
            projectKey: 'project_2'),
        ScriptGroup(
            id: 3,
            name: 'Folder',
            sortOrder: 0,
            createdAt: DateTime(2025, 1, 1),
            modifiedAt: DateTime(2025, 1, 1)),
      ],
    ]),
  );
  await tester
      .pumpWidget(harness.buildPage(ScriptListPage(controller: controller)));
  await tester.pumpAndSettle();
  if (grid) {
    await tester.tap(find.byWidgetPredicate((widget) => widget is PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '宫格视图'));
    await tester.pumpAndSettle();
  }
  return harness;
}
