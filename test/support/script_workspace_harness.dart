import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as legacy_provider;
import 'package:python_runner/features/scripts/application/script_repository.dart';
import 'package:python_runner/features/scripts/presentation/pages/script_list_page.dart';
import 'package:python_runner/l10n/app_localizations.dart';
import 'package:python_runner/models/execution_state.dart';
import 'package:python_runner/models/log_entry.dart';
import 'package:python_runner/models/script_file.dart';
import 'package:python_runner/models/script_group.dart';
import 'package:python_runner/providers/execution_provider.dart';
import 'package:python_runner/providers/theme_provider.dart';
import 'package:python_runner/services/database_service.dart';
import 'package:python_runner/services/native_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScriptWorkspaceHarness {
  ScriptWorkspaceHarness({
    required this.preferences,
    required this.bridge,
    required this.database,
  })  : scriptRepository = _HarnessScriptRepository(database: database, bridge: bridge),
        executionProvider = ExecutionProvider(bridge);

  final SharedPreferences preferences;
  final FakeScriptNativeBridge bridge;
  final InMemoryScriptDatabase database;
  final ScriptRepository scriptRepository;
  final ExecutionProvider executionProvider;

  Widget buildApp({
    Brightness brightness = Brightness.light,
    Locale locale = const Locale('zh'),
    double textScaleFactor = 1,
  }) =>
      buildPage(
        const ScriptListPage(),
        brightness: brightness,
        locale: locale,
        textScaleFactor: textScaleFactor,
      );

  Widget buildPage(
    Widget home, {
    Brightness brightness = Brightness.light,
    Locale locale = const Locale('zh'),
    double textScaleFactor = 1,
  }) {
    final baseTheme = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      splashFactory: NoSplash.splashFactory,
      visualDensity: VisualDensity.standard,
    );
    final theme = baseTheme.copyWith(
      textTheme: baseTheme.textTheme.apply(fontFamily: 'MiSans'),
      primaryTextTheme: baseTheme.primaryTextTheme.apply(fontFamily: 'MiSans'),
    );
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        scriptRepositoryProvider.overrideWithValue(scriptRepository),
      ],
      child: legacy_provider.MultiProvider(
        providers: [
          legacy_provider.ChangeNotifierProvider<ExecutionProvider>(
            create: (_) => executionProvider,
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          darkTheme: theme,
          themeMode:
              brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
          locale: locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScaleFactor),
            ),
            child: child ?? const SizedBox.shrink(),
          ),
          home: home,
        ),
      ),
    );
  }

  void dispose() {
    bridge.dispose();
  }
}

/// 包装现有 [InMemoryScriptDatabase] + [FakeScriptNativeBridge] 的 Repository，
/// 供 Controller 在测试中经 `scriptRepositoryProvider.overrideWithValue` 消费，
/// 保留 loadGate、内存脚本/分组与文件系统语义。
class _HarnessScriptRepository implements ScriptRepository {
  _HarnessScriptRepository({required this.database, required this.bridge});

  final InMemoryScriptDatabase database;
  final FakeScriptNativeBridge bridge;

  @override
  Future<List<ScriptFile>> getAllScripts() => database.getAllScripts();

  @override
  Future<ScriptFile?> getScript(String name) => database.getScript(name);

  @override
  Future<void> upsertScript(ScriptFile script) => database.upsertScript(script);

  @override
  Future<void> deleteScript(String name) => database.deleteScript(name);

  @override
  Future<void> renameScript(
          String oldName, String newName, String newPath) =>
      database.renameScript(oldName, newName, newPath);

  @override
  Future<void> incrementRunCount(String name) =>
      database.incrementRunCount(name);

  @override
  Future<void> batchUpdateSortOrders(List<ScriptFile> scripts) =>
      database.batchUpdateSortOrders(scripts);

  @override
  Future<List<ScriptGroup>> getAllGroups() => database.getAllGroups();

  @override
  Future<int> createGroup(ScriptGroup group) => database.createGroup(group);

  @override
  Future<void> renameGroup(int groupId, String name) =>
      database.renameGroup(groupId, name);

  @override
  Future<void> updateProjectMainFile(int groupId, String? mainFilePath) =>
      database.updateProjectMainFile(groupId, mainFilePath);

  @override
  Future<void> touchGroup(int groupId) => database.touchGroup(groupId);

  @override
  Future<void> deleteGroup(int groupId) => database.deleteGroup(groupId);

  @override
  Future<void> moveScriptsToGroup(List<ScriptFile> scripts) =>
      database.moveScriptsToGroup(scripts);

  @override
  Future<List<String>> listScriptFiles() => bridge.listScripts();

  @override
  Future<String> createScriptFile(String name, {String content = ''}) =>
      bridge.createScript(name, content: content);

  @override
  Future<bool> deleteScriptFile(String name) => bridge.deleteScript(name);

  @override
  Future<bool> renameScriptFile(String oldName, String newName) =>
      bridge.renameScript(oldName, newName);

  @override
  Future<String> readScriptFile(String name) => bridge.readScript(name);

  @override
  Future<bool> saveScriptFile(String name, String content) =>
      bridge.saveScript(name, content);

  @override
  Future<String> importScriptFromUri(String uri, String name) =>
      bridge.importScriptFromUri(uri, name);

  @override
  Future<bool> deleteScriptProject(String projectKey) =>
      bridge.deleteScriptProject(projectKey);
}

class FakeScriptNativeBridge extends NativeBridge {
  FakeScriptNativeBridge({List<String>? scriptNames})
      : _scriptNames = List<String>.from(scriptNames ?? const []),
        super.named();

  final List<String> _scriptNames;
  final _logs = StreamController<Map<dynamic, dynamic>>.broadcast();
  final _states = StreamController<Map<dynamic, dynamic>>.broadcast();
  final _stdin = StreamController<Map<dynamic, dynamic>>.broadcast();

  @override
  Stream<Map<dynamic, dynamic>> get logStream => _logs.stream;

  @override
  Stream<Map<dynamic, dynamic>> get executionStatusStream => _states.stream;

  @override
  Stream<Map<dynamic, dynamic>> get stdinRequestStream => _stdin.stream;

  @override
  Future<List<String>> listScripts() async => List<String>.from(_scriptNames);

  @override
  Future<String> createScript(String name, {String content = ''}) async {
    _scriptNames.add(name);
    return name;
  }

  @override
  Future<bool> deleteScript(String name) async {
    _scriptNames.remove(name);
    return true;
  }

  @override
  Future<bool> renameScript(String oldName, String newName) async {
    final index = _scriptNames.indexOf(oldName);
    if (index < 0) return false;
    _scriptNames[index] = newName;
    return true;
  }

  @override
  Future<String> readScript(String name) async => '';

  @override
  Future<bool> saveScript(String name, String content) async => true;

  @override
  Future<String> importScriptFromUri(String uri, String name) async {
    _scriptNames.add(name);
    return name;
  }

  @override
  Future<bool> deleteScriptProject(String projectKey) async => true;

  @override
  Future<void> executeScript(
    String name,
    String executionId, {
    String? workingDir,
    Map<String, String>? hookEnv,
    int? timeoutSeconds,
  }) async {}

  @override
  Future<void> stopExecution() async {}

  @override
  Future<void> sendStdin(String input) async {}

  @override
  Future<Map<String, String>> getLinuxLikeRuntimeInfo() async =>
      const {'available': 'false'};

  void emitLog(LogEntry entry) {
    _logs.add({
      'type': entry.type.name,
      'content': entry.content,
      'timestamp': entry.timestamp.millisecondsSinceEpoch,
      'executionId': entry.executionId,
    });
  }

  void emitState(ExecutionState state) {
    _states.add({
      'executionId': state.executionId,
      'status': state.status.name,
      'exitCode': state.exitCode,
    });
  }

  void emitStdin({String? executionId, required String prompt}) {
    _stdin.add({
      'executionId': executionId,
      'prompt': prompt,
    });
  }

  void dispose() {
    _logs.close();
    _states.close();
    _stdin.close();
  }
}

class InMemoryScriptDatabase extends DatabaseService {
  InMemoryScriptDatabase({
    List<ScriptFile>? scripts,
    List<ScriptGroup>? groups,
    this.loadGate,
  })  : _scripts = List<ScriptFile>.from(scripts ?? const []),
        _groups = List<ScriptGroup>.from(groups ?? const []);

  final List<ScriptFile> _scripts;
  final List<ScriptGroup> _groups;
  final Completer<void>? loadGate;

  Future<void> _waitForLoad() => loadGate?.future ?? Future<void>.value();

  @override
  Future<List<ScriptFile>> getAllScripts() async {
    await _waitForLoad();
    return List<ScriptFile>.from(_scripts);
  }

  @override
  Future<List<ScriptGroup>> getAllGroups() async {
    await _waitForLoad();
    return List<ScriptGroup>.from(_groups);
  }

  @override
  Future<void> upsertScript(ScriptFile script) async {
    _scripts.removeWhere((item) => item.name == script.name);
    _scripts.add(script);
  }

  @override
  Future<void> deleteScript(String name) async {
    _scripts.removeWhere((item) => item.name == name);
  }

  @override
  Future<void> incrementRunCount(String name) async {
    final index = _scripts.indexWhere((item) => item.name == name);
    if (index < 0) return;
    _scripts[index] = _scripts[index].copyWith(
      runCount: _scripts[index].runCount + 1,
    );
  }

  @override
  Future<void> batchUpdateSortOrders(List<ScriptFile> scripts) async {
    for (final script in scripts) {
      await upsertScript(script);
    }
  }
}
