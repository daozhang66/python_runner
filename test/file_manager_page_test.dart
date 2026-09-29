import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/files/application/file_manager_controller.dart';
import 'package:python_runner/features/files/presentation/pages/file_manager_page.dart';
import 'package:python_runner/l10n/app_localizations.dart';
import 'package:re_editor/re_editor.dart';
import 'package:python_runner/models/app_file_entry.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'support/script_workspace_harness.dart';

AppFileEntry _dir(String path) => AppFileEntry(
      path: path,
      name: path.split('/').last,
      isDirectory: true,
      size: 0,
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

AppFileEntry _file(String path) => AppFileEntry(
      path: path,
      name: path.split('/').last,
      isDirectory: false,
      size: 12,
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

class _FakeBridge {
  Map<String, List<AppFileEntry>> directories;
  Object? listError;
  final created = <String>[];
  final deleted = <String>[];
  Map<String, List<int>> files = {};
  final written = <String, String>{};
  final transfers = <String>[];

  _FakeBridge(this.directories);

  Future<List<AppFileEntry>> list(String path) async {
    if (listError != null) throw listError!;
    return directories[path] ?? const [];
  }

  Future<List<int>> readFile(String path) async => files[path] ?? const [];

  Future<void> createDirectory(String parent, String name) async {
    created.add('$parent/$name');
  }

  Future<void> rename(String path, String newName) async {}

  Future<void> delete(String path) async {
    deleted.add(path);
  }

  Future<void> writeFile(String path, String content) async {
    written[path] = content;
  }
}

Future<FileManagerController> _pumpManager(
  WidgetTester tester,
  _FakeBridge bridge, {
  String? configuredWorkingDir = '/work',
}) async {
  final controller = FileManagerController(
    listDirectory: bridge.list,
    readFile: bridge.readFile,
    createDirectory: bridge.createDirectory,
    renameEntry: bridge.rename,
    deleteEntry: bridge.delete,
    transferEntry: (path, destination, move) async {
      bridge.transfers.add('$path->$destination:$move');
    },
    workingDirectoryProvider: () async => configuredWorkingDir,
    isPathAccessible: (_) async => true,
  );
  addTearDown(controller.dispose);
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
      home: FileManagerPage(controller: controller),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  menuTests();
  viewerTests();

  testWidgets('compact toolbar keeps title visible at 320px and menus work', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final bridge = _FakeBridge({'/work': [_file('/work/a.txt')]});
    await _pumpManager(tester, bridge);
    final title = find.text('文件管理');
    expect(title, findsOneWidget);
    final titleSize = tester.getSize(title);
    final text = tester.widget<Text>(title);
    final style = DefaultTextStyle.of(tester.element(title)).style.merge(text.style);
    final painter = TextPainter(text: TextSpan(text: '文件管理', style: style),
      textDirection: TextDirection.ltr)..layout();
    expect(titleSize.width, greaterThanOrEqualTo(painter.width));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('file-manager-actions')));
    await tester.pumpAndSettle();
    expect(find.text('刷新'), findsOneWidget);
    expect(find.text('搜索'), findsOneWidget);
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('long press offers file tools and paste follows destination',
      (tester) async {
    final bridge = _FakeBridge({
      '/work': [_file('/work/a.txt'), _dir('/work/target')],
      '/work/target': [],
    });
    await _pumpManager(tester, bridge);
    await tester.longPress(find.text('a.txt'));
    await tester.pumpAndSettle();
    for (final label in ['复制', '剪切', '复制路径', '属性', '重命名', '删除']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();
    expect(find.text('粘贴'), findsOneWidget);
    await tester.tap(find.text('target'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('粘贴'));
    await tester.pumpAndSettle();
    expect(bridge.transfers, ['/work/a.txt->/work/target:false']);
    expect(find.text('粘贴'), findsNothing);
  });

  testWidgets('root up button and back navigate one level at a time',
      (tester) async {
    const root = '/data/user/0/com.daozhang.py';
    final bridge = _FakeBridge({
      '/work': [],
      '/': [_dir(root)],
      root: [_dir('$root/files')],
      '$root/files': [_dir('$root/files/projects')],
      '$root/files/projects': [],
    });
    final controller = await _pumpManager(tester, bridge);
    await tester.tap(find.byTooltip('切换到根目录'));
    await tester.pumpAndSettle();
    for (final name in ['com.daozhang.py', 'files', 'projects']) {
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('上一级'));
    await tester.pumpAndSettle();
    expect(controller.location.path, '$root/files');
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(controller.location.path, root);
    await tester.tap(find.byTooltip('上一级'));
    await tester.pumpAndSettle();
    expect(controller.location.path, '/');
    final up = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.arrow_upward));
    expect(up.onPressed, isNull);
  });

  testWidgets('file manager starts in work mode and offers root switch',
      (tester) async {
    final bridge = _FakeBridge({
      '/work': [_file('/work/main.py')],
    });

    await _pumpManager(tester, bridge);

    expect(find.text('工作目录'), findsOneWidget);
    expect(find.text('/work'), findsOneWidget);
    expect(find.text('main.py'), findsOneWidget);
    expect(find.byTooltip('切换到根目录'), findsOneWidget);
  });

  testWidgets('root switch changes path and action label', (tester) async {
    final bridge = _FakeBridge({
      '/work': [],
      '/': [_dir('/storage')],
    });

    await _pumpManager(tester, bridge);

    await tester.tap(find.byTooltip('切换到根目录'));
    await tester.pumpAndSettle();

    expect(find.text('/'), findsOneWidget);
    expect(find.text('根目录'), findsOneWidget);
    expect(find.text('storage'), findsOneWidget);
    expect(find.byTooltip('切换到工作目录'), findsOneWidget);

    await tester.tap(find.byTooltip('切换到工作目录'));
    await tester.pumpAndSettle();

    expect(find.text('/work'), findsOneWidget);
    expect(find.text('工作目录'), findsOneWidget);
  });

  testWidgets('directory tap navigates and back goes up one level',
      (tester) async {
    final bridge = _FakeBridge({
      '/work': [_dir('/work/src')],
      '/work/src': [_file('/work/src/a.py')],
    });

    await _pumpManager(tester, bridge);

    await tester.tap(find.text('src'));
    await tester.pumpAndSettle();
    expect(find.text('a.py'), findsOneWidget);

    await tester.tap(find.byTooltip('上一级'));
    await tester.pumpAndSettle();
    expect(find.text('src'), findsOneWidget);
  });

  testWidgets('permission error shows retryable message', (tester) async {
    final bridge = _FakeBridge({'/work': []});
    bridge.listError = const FileManagerError(
      code: FileManagerErrorCode.permissionDenied,
      message: '没有权限读取此目录',
    );

    await _pumpManager(tester, bridge);

    expect(find.text('无权限访问此目录'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    bridge.listError = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('此目录为空'), findsOneWidget);
  });

  testWidgets('empty directory shows empty state', (tester) async {
    final bridge = _FakeBridge({'/work': []});

    await _pumpManager(tester, bridge);

    expect(find.text('此目录为空'), findsOneWidget);
  });
}

Future<ScriptWorkspaceHarness> _pumpWorkspace(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final harness = ScriptWorkspaceHarness(
    preferences: preferences,
    bridge: FakeScriptNativeBridge(scriptNames: const []),
    database: InMemoryScriptDatabase(scripts: const []),
  );
  await tester.pumpWidget(harness.buildApp(locale: const Locale('zh')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return harness;
}

Future<void> _openScriptMenu(WidgetTester tester) async {
  await tester.tap(find.byType(PopupMenuButton<String>).first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void viewerTests() {
  testWidgets('tapping a file opens the code viewer', (tester) async {
    final bridge = _FakeBridge({
      '/work': [_file('/work/main.py')],
    });
    bridge.files['/work/main.py'] = 'print("hi")'.codeUnits;

    final controller = FileManagerController(
      listDirectory: bridge.list,
      readFile: bridge.readFile,
      createDirectory: bridge.createDirectory,
      renameEntry: bridge.rename,
      deleteEntry: bridge.delete,
      writeFile: bridge.writeFile,
      workingDirectoryProvider: () async => '/work',
      isPathAccessible: (_) async => true,
    );
    addTearDown(controller.dispose);
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
        home: FileManagerPage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('main.py'));
    await tester.pumpAndSettle();

    expect(find.text('main.py'), findsWidgets);
    expect(find.byType(CodeEditor), findsOneWidget);
  });
}

void menuTests() {
  testWidgets('script home menu exposes file manager entry', (tester) async {
    final harness = await _pumpWorkspace(tester);
    addTearDown(harness.dispose);

    await _openScriptMenu(tester);

    expect(find.widgetWithText(ListTile, '文件管理'), findsOneWidget);
  });
}
