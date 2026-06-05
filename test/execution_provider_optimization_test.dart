import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  testWidgets('execution provider trims current and history logs to bounded sizes',
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

  testWidgets('execution provider trims retained history runs',
      (tester) async {
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
}

class _ExecutionBridgeFake extends NativeBridge {
  final StreamController<Map<dynamic, dynamic>> _logController =
      StreamController<Map<dynamic, dynamic>>.broadcast();
  final Stream<Map<dynamic, dynamic>> _emptyStream =
      const Stream<Map<dynamic, dynamic>>.empty().asBroadcastStream();

  @override
  Stream<Map<dynamic, dynamic>> get logStream => _logController.stream;

  @override
  Stream<Map<dynamic, dynamic>> get executionStatusStream => _emptyStream;

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
  Future<String?> consumePendingRunScript() async => null;
}
