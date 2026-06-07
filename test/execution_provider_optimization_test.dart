import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:python_runner/models/execution_state.dart';
import 'package:python_runner/providers/execution_provider.dart';
import 'package:python_runner/services/native_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const {
      'floating_ball_enabled': false,
    });
    ExecutionProvider.setNavigateToConsoleHandler(null);
  });

  tearDown(() {
    ExecutionProvider.setNavigateToConsoleHandler(null);
  });

  testWidgets(
      'execution provider trims current and history logs to bounded sizes',
      (tester) async {
    final bridge = _ExecutionBridgeFake();
    final provider = ExecutionProvider(bridge);

    await provider.executeScript('demo.py');
    for (var i = 0; i < 6005; i++) {
      bridge.emitLog(
        type: 'stdout',
        content: 'line $i',
        timestamp: DateTime(2026, 1, 1, 0, 0, i),
      );
    }
    await tester.pump(const Duration(milliseconds: 150));

    expect(provider.logs.length, ExecutionProvider.maxCurrentLogs);
    expect(
      provider.logs.first.content,
      'line ${6005 - ExecutionProvider.maxCurrentLogs}',
    );
    expect(
      provider.logHistory.single.logs.length,
      ExecutionProvider.maxLogsPerHistoryRecord,
    );

    provider.dispose();
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('execution provider trims retained history runs', (tester) async {
    final bridge = _ExecutionBridgeFake();
    final provider = ExecutionProvider(bridge);

    for (var i = 0; i < 25; i++) {
      await provider.executeScript('demo_$i.py');
    }
    await tester.pump();

    expect(provider.logHistory.length, ExecutionProvider.maxHistoryRecords);
    expect(provider.logHistory.first.scriptName, 'demo_5.py');
    expect(provider.logHistory.last.scriptName, 'demo_24.py');

    provider.dispose();
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('execution provider ignores terminal status from stale run',
      (tester) async {
    final bridge = _ExecutionBridgeFake();
    final provider = ExecutionProvider(bridge);

    await provider.executeScript('demo.py');
    final activeId = provider.state.executionId;
    expect(activeId, isNotNull);

    bridge.emitStatus(
      executionId: '$activeId-stale',
      status: ExecutionStatus.error,
      exitCode: 1,
    );
    await tester.pump(const Duration(milliseconds: 150));

    expect(provider.state.executionId, activeId);
    expect(provider.state.status, ExecutionStatus.running);
    expect(provider.logHistory.single.status, ExecutionStatus.running);

    bridge.emitStatus(
      executionId: activeId!,
      status: ExecutionStatus.completed,
      exitCode: 0,
    );
    await tester.pump(const Duration(milliseconds: 150));

    expect(provider.state.status, ExecutionStatus.completed);
    expect(provider.logHistory.single.status, ExecutionStatus.completed);

    provider.dispose();
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('linux-like preference falls back to Chaquopy when unavailable',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {
      'floating_ball_enabled': false,
      'runtime_backend': 'linux_like',
    });
    final bridge = _ExecutionBridgeFake(linuxLikeAvailable: false);
    final provider = ExecutionProvider(bridge);

    await provider.executeScript('demo.py');
    await tester.pump();

    expect(bridge.linuxLikeExecuteScriptCalls, 0);
    expect(bridge.chaquopyExecuteScriptCalls, 1);
    expect(provider.state.status, ExecutionStatus.running);
    expect(bridge.lastHookEnv?['PYRUNNER_RUNTIME_BACKEND'], 'chaquopy');
    expect(bridge.lastHookEnv?['PYRUNNER_PREFERRED_RUNTIME_BACKEND'],
        'linux_like');

    provider.dispose();
    await tester.pump(const Duration(milliseconds: 600));
  });
}

class _ExecutionBridgeFake extends NativeBridge {
  _ExecutionBridgeFake({this.linuxLikeAvailable = true});

  final bool linuxLikeAvailable;
  int chaquopyExecuteScriptCalls = 0;
  int linuxLikeExecuteScriptCalls = 0;
  Map<String, String>? lastHookEnv;

  final StreamController<Map<dynamic, dynamic>> _logController =
      StreamController<Map<dynamic, dynamic>>.broadcast();
  final StreamController<Map<dynamic, dynamic>> _statusController =
      StreamController<Map<dynamic, dynamic>>.broadcast();
  final Stream<Map<dynamic, dynamic>> _emptyStream =
      const Stream<Map<dynamic, dynamic>>.empty().asBroadcastStream();

  @override
  Stream<Map<dynamic, dynamic>> get logStream => _logController.stream;

  @override
  Stream<Map<dynamic, dynamic>> get executionStatusStream =>
      _statusController.stream;

  @override
  Stream<Map<dynamic, dynamic>> get stdinRequestStream => _emptyStream;

  void emitLog({
    required String type,
    required String content,
    required DateTime timestamp,
  }) {
    _logController.add({
      'type': type,
      'content': content,
      'timestamp': timestamp.millisecondsSinceEpoch,
    });
  }

  void emitStatus({
    required String executionId,
    required ExecutionStatus status,
    int? exitCode,
  }) {
    _statusController.add({
      'executionId': executionId,
      'status': status.name,
      'exitCode': exitCode,
    });
  }

  @override
  Future<void> executeScript(
    String name,
    String executionId, {
    String? workingDir,
    Map<String, String>? hookEnv,
    int? timeoutSeconds,
  }) async {
    chaquopyExecuteScriptCalls++;
    lastHookEnv = hookEnv;
  }

  @override
  Future<Map<String, String>> getLinuxLikeRuntimeInfo() async => {
        'available': linuxLikeAvailable ? 'true' : 'false',
        'message': linuxLikeAvailable ? 'ready' : 'not installed',
      };

  @override
  Future<void> executeLinuxLikeScript(
    String name,
    String executionId, {
    String? workingDir,
    Map<String, String>? environment,
    int? timeoutSeconds,
    String? projectKey,
    String? projectMainFilePath,
  }) async {
    linuxLikeExecuteScriptCalls++;
  }

  @override
  Future<void> stopExecution() async {}

  @override
  Future<String?> consumePendingRunScript() async => null;
}
