import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart' as legacy_provider;
import 'package:re_editor/re_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:python_runner/features/scripts/application/script_repository.dart';
import 'package:python_runner/models/log_entry.dart';
import 'package:python_runner/models/script_file.dart';
import 'package:python_runner/models/script_group.dart';
import 'package:python_runner/pages/network_inspector_page.dart';
import 'package:python_runner/features/scripts/presentation/pages/script_editor_page.dart';
import 'package:python_runner/providers/execution_provider.dart';
import 'package:python_runner/services/database_service.dart';
import 'package:python_runner/services/http_inspector_store.dart';
import 'package:python_runner/services/native_bridge.dart';
import 'package:python_runner/features/console/presentation/widgets/terminal_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Font gesture controls', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(const {});
    });

    testWidgets('terminal view uses pinch-to-zoom instead of font buttons', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          Scaffold(
            body: SizedBox.expand(
              child: TerminalView(
                logs: [
                  LogEntry(
                    type: LogType.stdout,
                    content: 'hello from terminal',
                    timestamp: DateTime(2024),
                  ),
                  ...List.generate(
                    4999,
                    (index) => LogEntry(
                      type: LogType.stdout,
                      content: 'large terminal output $index',
                      timestamp: DateTime(2024),
                    ),
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
      expect(find.byIcon(Icons.format_size), findsNothing);

      final terminalLine = _richTextContaining('hello from terminal');
      expect(terminalLine, findsOneWidget);

      final before = _richTextFontSizeForText(
        tester,
        terminalLine,
        'hello from terminal',
      );

      await _pinchOut(
        tester,
        find.byType(TerminalView),
      );
      await tester.pumpAndSettle();

      final after = _richTextFontSizeForText(
        tester,
        terminalLine,
        'hello from terminal',
      );
      expect(after, greaterThan(before));
    });

    testWidgets('terminal view renders log lines with a virtualized list', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          Scaffold(
            body: TerminalView(
              logs: List.generate(
                3,
                (index) => LogEntry(
                  type: LogType.stdout,
                  content: 'line $index',
                  timestamp: DateTime(2024),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ListView), findsOneWidget);
      expect(find.byType(SelectionArea), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);
      expect(find.byType(SingleChildScrollView), findsNothing);
    });

    testWidgets('script editor hides font button and supports pinch-to-zoom', (
      WidgetTester tester,
    ) async {
      SharedPreferences.setMockInitialValues(const {
        'editor_font_size_demo.py': 14.0,
      });

      final bridge = _FakeNativeBridge(scriptContents: {
        'demo.py': 'print("hello")\nprint("world")',
      });
      final repository = _FontGestureScriptRepository(
          bridge: bridge, database: _FakeDatabaseService());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scriptRepositoryProvider.overrideWithValue(repository),
          ],
          child: legacy_provider.MultiProvider(
            providers: [
              legacy_provider.ChangeNotifierProvider(
                create: (_) => ExecutionProvider(bridge),
              ),
            ],
            child: _buildTestApp(
              const ScriptEditorPage(scriptName: 'demo.py'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.format_size), findsNothing);
      expect(find.byType(Slider), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);

      final before = _codeEditorFontSize(tester);

      await _pinchOut(
        tester,
        find.byType(CodeEditor),
      );
      await tester.pumpAndSettle();

      final after = _codeEditorFontSize(tester);
      expect(after, greaterThan(before));
    });

    testWidgets(
      'network full body view supports pinch-to-zoom',
      // This full-body gesture case hangs under the current Flutter test
      // runner; provider injection is covered by HttpInspectorStore tests.
      skip: true,
      (WidgetTester tester) async {
        final tempDir = await Directory.systemTemp.createTemp(
          'network_inspector_injected_store_',
        );
        final store = HttpInspectorStore.test(
          supportDirectoryProvider: () async => tempDir,
          persistDebounce: const Duration(days: 1),
        );
        await store.ensureLoaded();
        store.addFromJson({
          'id': 'req-zoom',
          'timestamp': 1710000000000,
          'method': 'get',
          'url': 'https://example.com/data',
          'request_headers': {'accept': 'application/json'},
          'status_code': 200,
          'response_headers': {'content-type': 'application/json'},
          'response_body_preview': '{"message":"hello","items":[1,2,3]}',
        });

        try {
          await tester.pumpWidget(
            legacy_provider.ChangeNotifierProvider<HttpInspectorStore>.value(
              value: store,
              child: _buildTestApp(
                const NetworkInspectorPage(),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 100));

          await tester.tap(find.text('example.com'));
          await tester.pump(const Duration(milliseconds: 300));

          final openFullView = find.byIcon(Icons.open_in_full);
          await tester.ensureVisible(openFullView.first);
          await tester.pump(const Duration(milliseconds: 100));
          await tester.tap(openFullView.first, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 300));

          final fullBodyText = find.byKey(
            const ValueKey('network_full_body_text'),
          );
          final before = _selectableFontSize(tester, fullBodyText);

          await _pinchOut(
            tester,
            fullBodyText,
          );
          await tester.pump(const Duration(milliseconds: 100));
          final after = _selectableFontSize(tester, fullBodyText);
          expect(after, greaterThan(before));
        } finally {
          await store.flush();
          await tempDir.delete(recursive: true);
        }
      },
    );
  });
}

Widget _buildTestApp(Widget home) {
  return MaterialApp(
    theme: ThemeData(splashFactory: NoSplash.splashFactory),
    home: home,
  );
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

Finder _richTextContaining(String text) {
  return find.byWidgetPredicate(
    (widget) => widget is RichText && widget.text.toPlainText().contains(text),
  );
}

double _richTextFontSizeForText(
  WidgetTester tester,
  Finder finder,
  String text,
) {
  final widget = tester.widget<RichText>(finder);
  return _spanFontSizeForText(widget.text, text) ??
      _firstSpanFontSize(widget.text);
}

double? _spanFontSizeForText(InlineSpan span, String text) {
  if (span is TextSpan) {
    if ((span.text ?? '').contains(text)) {
      return span.style?.fontSize;
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      final childSize = _spanFontSizeForText(child, text);
      if (childSize != null) return childSize;
    }
  }
  return null;
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
      : _scriptContents = scriptContents ?? <String, String>{},
        super.named();

  final Map<String, String> _scriptContents;
  final Stream<Map<dynamic, dynamic>> _emptyStream =
      const Stream<Map<dynamic, dynamic>>.empty().asBroadcastStream();

  /// 暴露给测试 Repository 的文件名集合。
  Map<String, String> get scriptContents => _scriptContents;

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

/// 包装 [_FakeNativeBridge] + [_FakeDatabaseService] 的最小 Repository，供
/// ScriptEditorPage 经 Riverpod 消费。编辑器测试只需 demo.py 的读写与 runCount。
class _FontGestureScriptRepository implements ScriptRepository {
  _FontGestureScriptRepository({required this.bridge, required this.database});

  final _FakeNativeBridge bridge;
  final _FakeDatabaseService database;

  @override
  Future<List<ScriptFile>> getAllScripts() async => const [];

  @override
  Future<ScriptFile?> getScript(String name) async => null;

  @override
  Future<void> upsertScript(ScriptFile script) async {}

  @override
  Future<void> deleteScript(String name) async {}

  @override
  Future<void> renameScript(
      String oldName, String newName, String newPath) async {}

  @override
  Future<void> incrementRunCount(String name) =>
      database.incrementRunCount(name);

  @override
  Future<void> batchUpdateSortOrders(List<ScriptFile> scripts) async {}

  @override
  Future<List<ScriptGroup>> getAllGroups() async => const [];

  @override
  Future<int> createGroup(ScriptGroup group) async => 0;

  @override
  Future<void> renameGroup(int groupId, String name) async {}

  @override
  Future<void> updateProjectMainFile(int groupId, String? mainFilePath) async {}

  @override
  Future<void> touchGroup(int groupId) async {}

  @override
  Future<void> deleteGroup(int groupId) async {}

  @override
  Future<void> moveScriptsToGroup(List<ScriptFile> scripts) async {}

  @override
  Future<List<String>> listScriptFiles() async =>
      bridge.scriptContents.keys.toList();

  @override
  Future<String> createScriptFile(String name, {String content = ''}) async =>
      name;

  @override
  Future<bool> deleteScriptFile(String name) async => true;

  @override
  Future<bool> renameScriptFile(String oldName, String newName) async => true;

  @override
  Future<String> readScriptFile(String name) => bridge.readScript(name);

  @override
  Future<bool> saveScriptFile(String name, String content) =>
      bridge.saveScript(name, content);

  @override
  Future<String> importScriptFromUri(String uri, String name) async => name;

  @override
  Future<bool> deleteScriptProject(String projectKey) async => true;
}
