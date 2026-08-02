import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/console/presentation/widgets/terminal_view.dart';
import 'package:python_runner/l10n/app_localizations.dart';
import 'package:python_runner/models/log_entry.dart';
import 'package:python_runner/ui/app_state_views.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('terminal exposes running input and 44dp toolbar targets',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        TerminalView(
          logs: [_log('ready')],
          isRunning: true,
          waitingForInput: true,
          onClear: () {},
          onExport: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('关闭自动滚动'), findsOneWidget);
    expect(find.byTooltip('导出日志'), findsOneWidget);
    expect(find.byTooltip('清空'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);

    for (final icon in [
      Icons.vertical_align_bottom_rounded,
      Icons.file_download_outlined,
      Icons.delete_outline,
    ]) {
      final button = find.ancestor(
        of: find.byIcon(icon),
        matching: find.byType(IconButton),
      );
      final rect = tester.getRect(button);
      expect(rect.width, greaterThanOrEqualTo(44));
      expect(rect.height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('terminal only persists explicit auto-follow changes',
      (tester) async {
    final changes = <bool>[];
    await tester.pumpWidget(
      _testApp(
        TerminalView(
          logs: List<LogEntry>.generate(80, (index) => _log('line $index')),
          onAutoFollowPreferenceChanged: changes.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -260));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);

    await tester.tap(find.byIcon(Icons.pause));
    await tester.pumpAndSettle();
    expect(changes, [true]);
  });

  testWidgets('terminal surfaces export failure without blocking controls',
      (tester) async {
    await tester.pumpWidget(
      _testApp(
        TerminalView(
          logs: [_log('export me')],
          onClear: () {},
          onExport: (_) async => throw StateError('storage unavailable'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('导出日志'));
    await tester.pumpAndSettle();
    expect(find.text('导出失败，请稍后重试'), findsOneWidget);
    expect(find.byTooltip('清空'), findsOneWidget);
  });

  testWidgets('new terminal and error texts use English localization',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _testApp(
        Column(
          children: [
            const Expanded(
              child: AppErrorState(
                message: 'Unable to load packages',
                retryLabel: 'Retry',
                onRetry: _noOp,
              ),
            ),
            Expanded(child: TerminalView(logs: [_log('hello')])),
          ],
        ),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    expect(find.byTooltip('Disable auto-follow'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Unable to load packages')),
      findsOneWidget,
    );
    semantics.dispose();
  });
}

void _noOp() {}

LogEntry _log(String content) => LogEntry(
      type: LogType.stdout,
      content: content,
      timestamp: DateTime(2025, 1, 1),
    );

Widget _testApp(Widget home, {Locale locale = const Locale('zh')}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(useMaterial3: true, splashFactory: NoSplash.splashFactory),
    home: Scaffold(body: home),
  );
}
