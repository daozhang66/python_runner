import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/files/application/file_manager_controller.dart';
import 'package:python_runner/features/files/presentation/pages/file_manager_file_viewer_page.dart';
import 'package:python_runner/l10n/app_localizations.dart';
import 'package:python_runner/models/app_file_entry.dart';
import 'package:re_editor/re_editor.dart';

AppFileEntry _file(String path, {int size = 10}) => AppFileEntry(
      path: path,
      name: path.split('/').last,
      isDirectory: false,
      size: size,
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

class _Harness {
  final Map<String, List<int>> files;
  final written = <String, String>{};

  _Harness(this.files);

  FileManagerController buildController() {
    return FileManagerController(
      listDirectory: (_) async => const [],
      readFile: (path) async => files[path] ?? const [],
      createDirectory: (_, __) async {},
      renameEntry: (_, __) async {},
      deleteEntry: (_) async {},
      writeFile: (path, content) async => written[path] = content,
      workingDirectoryProvider: () async => '/work',
      isPathAccessible: (_) async => true,
    );
  }
}

Future<void> _pumpViewerWithEditor(
  WidgetTester tester,
  _Harness harness,
  AppFileEntry entry,
  CodeLineEditingController editorController,
) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: FileManagerFileViewerPage(
        entry: entry,
        controller: harness.buildController(),
        editorController: editorController,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpViewer(
  WidgetTester tester,
  _Harness harness,
  AppFileEntry entry,
) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: FileManagerFileViewerPage(
        entry: entry,
        controller: harness.buildController(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens python file with highlighted code editor',
      (tester) async {
    final harness = _Harness({
      '/work/main.py': utf8.encode('print("hello")\n'),
    });

    await _pumpViewer(tester, harness, _file('/work/main.py'));

    expect(find.byType(CodeEditor), findsOneWidget);
    expect(find.text('已保存'), findsOneWidget);
    expect(find.text('只读'), findsOneWidget);
  });

  testWidgets('binary file shows unsupported state', (tester) async {
    final harness = _Harness({
      '/work/data.bin': [0x00, 0x01, 0x02, 0x03],
    });

    await _pumpViewer(tester, harness, _file('/work/data.bin'));

    expect(find.byType(CodeEditor), findsNothing);
    expect(find.text('二进制文件，暂不支持查看'), findsOneWidget);
  });

  testWidgets('edit mode and save write through the controller', (tester) async {
    final harness = _Harness({
      '/work/config.json': utf8.encode('{"a": 1}'),
    });
    final editorController = CodeLineEditingController();
    addTearDown(editorController.dispose);

    await _pumpViewerWithEditor(
      tester,
      harness,
      _file('/work/config.json'),
      editorController,
    );

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('进入编辑'));
    await tester.pumpAndSettle();
    expect(find.text('编辑'), findsOneWidget);

    editorController.text = '{"a": 2}';
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.save), findsOneWidget);

    await tester.tap(find.byIcon(Icons.save));
    await tester.pumpAndSettle();

    expect(harness.written['/work/config.json'], '{"a": 2}');
    expect(find.byIcon(Icons.save), findsNothing);
  });

  testWidgets('protected files stay readonly without edit toggle',
      (tester) async {
    final harness = _Harness({
      '/system/build.prop': utf8.encode('ro.build=1'),
    });
    final controller = FileManagerController(
      listDirectory: (_) async => const [],
      readFile: (path) async => harness.files[path] ?? const [],
      createDirectory: (_, __) async {},
      renameEntry: (_, __) async {},
      deleteEntry: (_) async {},
      writeFile: (path, content) async =>
          harness.written[path] = content,
      workingDirectoryProvider: () async => '/work',
      isPathAccessible: (_) async => true,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: FileManagerFileViewerPage(
          entry: _file('/system/build.prop'),
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    expect(find.text('进入编辑模式'), findsNothing);
  });
}
