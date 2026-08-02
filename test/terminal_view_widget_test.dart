import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/console/presentation/widgets/terminal_view.dart';
import 'package:python_runner/models/log_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'new-output prompt only appears after output arrives away from bottom',
      (tester) async {
    final initialLogs = List.generate(
      80,
      (index) => LogEntry(
        type: LogType.stdout,
        content: 'line $index',
        timestamp: DateTime(2026, 1, 1, 0, 0, index),
        executionId: 'run-1',
      ),
    );

    await tester.pumpWidget(_buildTerminal(initialLogs));
    await tester.pumpAndSettle();

    final outputList = find.byType(ListView);
    await tester.drag(outputList, const Offset(0, -2000));
    await tester.pumpAndSettle();
    await tester.drag(outputList, const Offset(0, 300));
    await tester.pumpAndSettle();

    expect(find.text('有新输出，点击跳转到底部'), findsNothing,
        reason: '只滚动离开底部不能被误判为存在新输出');

    final appendedLogs = [
      ...initialLogs,
      LogEntry(
        type: LogType.stdout,
        content: 'new output',
        timestamp: DateTime(2026, 1, 1, 1),
        executionId: 'run-1',
      ),
    ];
    await tester.pumpWidget(_buildTerminal(appendedLogs));
    await tester.pump();

    expect(find.text('有新输出，点击跳转到底部'), findsOneWidget);

    await tester.pumpWidget(_buildTerminal(appendedLogs.take(2).toList()));
    await tester.pump();
    await tester.pump();

    expect(find.text('有新输出，点击跳转到底部'), findsNothing,
        reason: '内容缩短到不足一屏时，旧的未读提示必须自动清除');

    await tester.pumpWidget(_buildTerminal(const []));
    await tester.pump();

    expect(find.text('有新输出，点击跳转到底部'), findsNothing, reason: '清空输出后不得保留未读输出提示');
  });

  testWidgets('terminal caches filters without changing wrapped log rendering',
      (tester) async {
    final logs = List<LogEntry>.generate(
      5000,
      (index) => LogEntry(
        type: index == 4999 ? LogType.error : LogType.stdout,
        content: index == 4999
            ? 'fatal marker\nwith a wrapped continuation'
            : 'ordinary output $index',
        timestamp: DateTime(2026, 1, 1, 0, 0, index % 60),
        executionId: 'run-1',
      ),
    );

    await tester.pumpWidget(_buildTerminal(logs));
    await tester.pumpAndSettle();

    final list = tester.widget<ListView>(find.byType(ListView));
    final delegate = list.childrenDelegate as SliverChildBuilderDelegate;
    expect(list.scrollCacheExtent, const ScrollCacheExtent.pixels(200));
    expect(delegate.addAutomaticKeepAlives, isFalse);
    expect(delegate.addRepaintBoundaries, isTrue);

    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'fatal marker');
    await tester.pumpAndSettle();

    expect(
      _terminalLogContaining('fatal marker\nwith a wrapped continuation'),
      findsOneWidget,
    );
    expect(_terminalLogContaining('ordinary output 0'), findsNothing);

    await tester.tap(find.byTooltip('仅看错误'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('显示行号'));
    await tester.pumpAndSettle();

    expect(
      _terminalLogContaining('fatal marker'),
      findsOneWidget,
      reason: '字体、工具栏和行号状态变化不能改变已过滤的输出',
    );

    final appendedLogs = [
      ...logs,
      LogEntry(
        type: LogType.error,
        content: 'new fatal marker',
        timestamp: DateTime(2026, 1, 1, 1),
        executionId: 'run-1',
      ),
    ];
    await tester.pumpWidget(_buildTerminal(appendedLogs));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'new fatal marker');
    await tester.pumpAndSettle();

    expect(_terminalLogContaining('new fatal marker'), findsOneWidget,
        reason: '新日志必须使旧过滤快照失效');
  });
}

Finder _terminalLogContaining(String text) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is Text && widget.textSpan?.toPlainText().contains(text) == true,
    description: 'terminal log containing $text',
  );
}

Widget _buildTerminal(List<LogEntry> logs) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 420,
        child: TerminalView(
          logs: logs,
          logVersion: logs.length,
        ),
      ),
    ),
  );
}
