import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/console/presentation/widgets/terminal_view.dart';
import 'package:python_runner/l10n/app_localizations.dart';
import 'package:python_runner/models/log_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'bottom reaches the last virtualized line with varying row heights',
    (tester) async {
      final logs = List.generate(
        400,
        (i) => LogEntry(
          type: LogType.stdout,
          content: i < 40 ? 'short $i' : 'line $i\ncontinued\nagain\nmore\nend',
          timestamp: DateTime(2026),
          executionId: 'run',
        ),
      );
      await tester.pumpWidget(_app(TerminalView(logs: logs)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Jump to bottom'));
      await tester.pumpAndSettle();
      expect(_position(tester).extentAfter, lessThan(2));
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.textSpan?.toPlainText().contains('line 399') == true,
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'top pauses following and bottom resumes without persisting navigation',
    (tester) async {
      final changes = <bool>[];
      var logs = _logs(80);
      Widget app() => _app(
        TerminalView(logs: logs, onAutoFollowPreferenceChanged: changes.add),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Jump to bottom'));
      await tester.pumpAndSettle();
      expect(_position(tester).extentAfter, lessThan(2));
      await tester.tap(find.byTooltip('Jump to top'));
      await tester.pumpAndSettle();
      expect(_position(tester).pixels, 0);
      logs = _logs(90);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(_position(tester).pixels, 0);
      expect(
        find.text('New output. Tap to jump to the bottom.'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Jump to bottom'));
      await tester.pumpAndSettle();
      logs = _logs(100);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(_position(tester).extentAfter, lessThan(2));
      expect(changes, isEmpty);
    },
  );

  testWidgets(
    'disabled preference survives short output, manual navigation and appends',
    (tester) async {
      final changes = <bool>[];
      var logs = _logs(1);
      Widget app() => _app(
        TerminalView(
          logs: logs,
          autoFollowInitiallyEnabled: false,
          onAutoFollowPreferenceChanged: changes.add,
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      logs = _logs(80);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(_position(tester).pixels, 0);
      await tester.tap(find.byTooltip('Jump to bottom'));
      await tester.pumpAndSettle();
      final previous = _position(tester).pixels;
      logs = _logs(100);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(_position(tester).pixels, previous);
      expect(_position(tester).extentAfter, greaterThan(60));
      expect(changes, isEmpty);
      await tester.tap(find.byTooltip('Output options'));
      await tester.pumpAndSettle();
      final toggle = tester.widget<CheckedPopupMenuItem<Object>>(
        find.ancestor(
          of: find.text('Auto-follow output'),
          matching: find.byType(CheckedPopupMenuItem<Object>),
        ),
      );
      expect(toggle.checked, isFalse);
      await tester.tap(
        find.ancestor(
          of: find.text('Auto-follow output'),
          matching: find.byType(CheckedPopupMenuItem<Object>),
        ),
      );
      await tester.pumpAndSettle();
      expect(changes, [true]);
      expect(_position(tester).extentAfter, lessThan(2));
    },
  );

  for (final locale in ['en', 'zh']) {
    testWidgets('320px toolbar and output options fit 2x text in $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _app(
          TerminalView(logs: _logs(20), onExport: (_) async {}, onClear: () {}),
          locale: locale,
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final icon in [
        Icons.vertical_align_top_rounded,
        Icons.vertical_align_bottom_rounded,
      ]) {
        final button = find.ancestor(
          of: find.byIcon(icon),
          matching: find.byType(IconButton),
        );
        expect(tester.getSize(button).width, greaterThanOrEqualTo(44));
        expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
        expect(tester.getRect(button).right, lessThanOrEqualTo(320));
      }
      await tester.tap(
        find.byTooltip(locale == 'en' ? 'Output options' : '输出选项'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.text(locale == 'en' ? 'Auto-follow output' : '自动跟随输出'),
        findsOneWidget,
      );
    });
  }
}

ScrollPosition _position(WidgetTester tester) =>
    tester.widget<ListView>(find.byType(ListView)).controller!.position;
List<LogEntry> _logs(int count) => List.generate(
  count,
  (i) => LogEntry(
    type: LogType.stdout,
    content: 'line $i',
    timestamp: DateTime(2026, 1, 1, 0, 0, i),
    executionId: 'run',
  ),
);
Widget _app(Widget terminal, {String locale = 'en', double scale = 1}) =>
    MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: SizedBox(height: 420, child: terminal)),
      ),
    );
