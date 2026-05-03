import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:python_runner/models/log_entry.dart';
import 'package:python_runner/pages/network_inspector_page.dart';
import 'package:python_runner/pages/script_editor_page.dart';
import 'package:python_runner/providers/execution_provider.dart';
import 'package:python_runner/providers/script_provider.dart';
import 'package:python_runner/services/database_service.dart';
import 'package:python_runner/services/http_inspector_store.dart';
import 'package:python_runner/services/native_bridge.dart';
import 'package:python_runner/widgets/terminal_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Font gesture controls', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(const {});
      HttpInspectorStore.instance.clear();
    });

    tearDown(() {
      HttpInspectorStore.instance.clear();
    });

    testWidgets('terminal view uses pinch-to-zoom instead of font buttons', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: TerminalView(
                logs: [
                  LogEntry(
                    type: LogType.stdout,
                    content: 'hello from terminal',
                    timestamp: DateTime(2024),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.text_decrease_rounded), findsNothing);
      expect(find.byIcon(Icons.text_increase_rounded), findsNothing);

      final before = _selectableFontSize(tester, find.byType(SelectableText).first);

      await _pinchOut(
        tester,
        find.byType(TerminalView),
      );
      await tester.pumpAndSettle();

      final after = _selectableFontSize(tester, find.byType(SelectableText).first);
      expect(after, greaterThan(before));
    });

    testWidgets('script editor uses pinch-to-zoom instead of format size menu', (
      WidgetTester tester,
    ) async {
      SharedPreferences.setMockInitialValues(const {
        'editor_font_size_demo.py': 14.0,
      });

      final bridge = _FakeNativeBridge(scriptContents: {
        'demo.py': 'print("hello")\nprint("world")',
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => ScriptProvider(bridge, _FakeDatabaseService()),
            ),
            ChangeNotifierProvider(
              create: (_) => ExecutionProvider(bridge),
            ),
          ],
          child: const MaterialApp(
            home: ScriptEditorPage(scriptName: 'demo.py'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.format_size), findsNothing);

      final before = _codeEditorFontSize(tester);

      await _pinchOut(
        tester,
        find.byType(CodeEditor),
      );
      await tester.pumpAndSettle();

      final after = _codeEditorFontSize(tester);
      expect(after, greaterThan(before));
    });

    testWidgets('network full body view supports pinch-to-zoom', (
      WidgetTester tester,
    ) async {
      HttpInspectorStore.instance.addFromJson({
        'id': 'req-zoom',
        'timestamp': 1710000000000,
        'method': 'get',
        'url': 'https://example.com/data',
        'request_headers': {'accept': 'application/json'},
        'status_code': 200,
        'response_headers': {'content-type': 'application/json'},
        'response_body_preview': '{"message":"hello","items":[1,2,3]}',
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: NetworkInspectorPage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('example.com'));
      await tester.pumpAndSettle();

      final openFullView = find.byIcon(Icons.open_in_full);
      await tester.ensureVisible(openFullView.first);
      await tester.pumpAndSettle();
      await tester.tap(openFullView.first, warnIfMissed: false);
      await tester.pumpAndSettle();

      final fullBodyText = find.byType(SelectableText).last;
      final before = _selectableFontSize(tester, fullBodyText);

      final fullBodyGesture = find.byType(GestureDetector).last;
      await _pinchOut(
        tester,
        fullBodyGesture,
      );
      await tester.pumpAndSettle();
      final after = _selectableFontSize(tester, fullBodyText);
      expect(after, greaterThan(before));
    });
  });
}

double _selectableFontSize(WidgetTester tester, Finder finder) {
  final widget = tester.widget<SelectableText>(finder);
  final style = widget.style;
  if (style?.fontSize != null) {
    return style!.fontSize!;
  }
  final span = widget.textSpan;
  if (span == null) {
    throw StateError('SelectableText has neither style nor textSpan.');
  }
  return _firstSpanFontSize(span);
}

double _firstSpanFontSize(InlineSpan span) {
  if (span is TextSpan) {
    final ownSize = span.style?.fontSize;
    if (ownSize != null) {
      return ownSize;
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      final childSize = _firstSpanFontSize(child);
      if (childSize > 0) return childSize;
    }
  }
  return 0;
}

double _codeEditorFontSize(WidgetTester tester) {
  final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
  return editor.style?.fontSize ?? 0;
}

Future<void> _pinchOut(WidgetTester tester, Finder finder) async {
  final center = tester.getCenter(finder);
  final gesture1 = await tester.startGesture(
    center + const Offset(-24, 0),
    pointer: 1,
    kind: PointerDeviceKind.touch,
  );
  final gesture2 = await tester.startGesture(
    center + const Offset(24, 0),
    pointer: 2,
    kind: PointerDeviceKind.touch,
  );
  await tester.pump();

  await gesture1.moveTo(center + const Offset(-72, 0));
  await gesture2.moveTo(center + const Offset(72, 0));
  await tester.pump(const Duration(milliseconds: 16));

  await gesture1.up();
  await gesture2.up();
}

class _FakeNativeBridge extends NativeBridge {
  _FakeNativeBridge({Map<String, String>? scriptContents})
      : _scriptContents = scriptContents ?? <String, String>{};

  final Map<String, String> _scriptContents;
  final Stream<Map<dynamic, dynamic>> _emptyStream =
      const Stream<Map<dynamic, dynamic>>.empty().asBroadcastStream();

  @override
  Stream<Map<dynamic, dynamic>> get logStream => _emptyStream;

  @override
  Stream<Map<dynamic, dynamic>> get executionStatusStream => _emptyStream;

  @override
  Stream<Map<dynamic, dynamic>> get stdinRequestStream => _emptyStream;

  @override
  Future<String> readScript(String name) async {
    return _scriptContents[name] ?? '';
  }

  @override
  Future<bool> saveScript(String name, String content) async {
    _scriptContents[name] = content;
    return true;
  }

  @override
  Future<void> stopExecution() async {}

  @override
  Future<void> executeScript(
    String name,
    String executionId, {
    String? workingDir,
    Map<String, String>? hookEnv,
    int? timeoutSeconds,
  }) async {}

  @override
  Future<void> sendStdin(String input) async {}
}

class _FakeDatabaseService extends DatabaseService {
  @override
  Future<void> incrementRunCount(String name) async {}
}
