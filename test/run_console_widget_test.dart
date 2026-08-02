import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/console/presentation/pages/run_console_page.dart';
import 'package:python_runner/models/execution_state.dart';
import 'package:python_runner/models/log_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/script_workspace_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('run console displays active output and waiting input',
      (tester) async {
    final harness = await _createHarness();
    addTearDown(harness.dispose);
    await harness.executionProvider.executeScript('interactive.py');
    final executionId = harness.executionProvider.state.executionId!;

    await tester.pumpWidget(
      harness.buildPage(const RunConsolePage(scriptName: 'interactive.py')),
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('运行中'), findsOneWidget);

    harness.bridge.emitLog(
      LogEntry(
        type: LogType.stdout,
        content: 'ready for input',
        timestamp: DateTime(2025, 1, 1),
        executionId: executionId,
      ),
    );
    harness.bridge.emitStdin(executionId: executionId, prompt: 'name:');
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('等待输入'), findsOneWidget);
    expect(find.text('ready for input'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
  });

  testWidgets('run console preserves completed history for the selected script',
      (tester) async {
    final harness = await _createHarness();
    addTearDown(harness.dispose);
    await harness.executionProvider.executeScript('history.py');
    final executionId = harness.executionProvider.state.executionId!;
    harness.bridge.emitLog(
      LogEntry(
        type: LogType.stdout,
        content: 'historical output',
        timestamp: DateTime(2025, 1, 1),
        executionId: executionId,
      ),
    );
    harness.bridge.emitState(
      ExecutionState(
        executionId: executionId,
        status: ExecutionStatus.completed,
        exitCode: 0,
      ),
    );

    await tester.pumpWidget(
      harness.buildPage(const RunConsolePage(scriptName: 'history.py')),
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('已结束'), findsOneWidget);
    expect(find.text('historical output'), findsOneWidget);
    expect(find.byTooltip('重新运行'), findsOneWidget);
  });

  testWidgets('run console reads persisted auto-follow preference',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'console_auto_follow_output': false});
    final harness = await _createHarness();
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      harness.buildPage(const RunConsolePage(scriptName: 'idle.py')),
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byTooltip('开启自动滚动'), findsOneWidget);
  });
}

Future<ScriptWorkspaceHarness> _createHarness() async {
  final preferences = await SharedPreferences.getInstance();
  return ScriptWorkspaceHarness(
    preferences: preferences,
    bridge: FakeScriptNativeBridge(),
    database: InMemoryScriptDatabase(),
  );
}
