import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/models/execution_state.dart';
import 'package:python_runner/runtime/chaquopy_backend.dart';
import 'package:python_runner/runtime/runtime_output.dart';
import 'package:python_runner/runtime/runtime_request.dart';
import 'package:python_runner/services/native_bridge.dart';

void main() {
  test('ChaquopyRuntimeSession ignores terminal status from another execution',
      () async {
    final bridge = _ChaquopyBridgeFake();
    final backend = ChaquopyBackend(bridge);
    final session = ChaquopyRuntimeSession(
      backend: backend,
      request: const RuntimeRequest(
        scriptName: 'demo.py',
        executionId: 'run-active',
      ),
    );

    bridge.emitStatus(
      executionId: 'run-stale',
      status: ExecutionStatus.error,
      exitCode: 1,
    );

    await expectLater(
      session.waitExit().timeout(const Duration(milliseconds: 30)),
      throwsA(isA<TimeoutException>()),
    );

    bridge.emitStatus(
      executionId: 'run-active',
      status: ExecutionStatus.completed,
      exitCode: 0,
    );

    await expectLater(session.waitExit(), completion(0));
  });

  test('RuntimeOutput carries execution id through map conversion', () {
    final output = RuntimeOutput.fromMap({
      'type': 'stdout',
      'content': 'hello',
      'timestamp': 1710000000000,
      'executionId': 'run-123',
    });

    expect(output.executionId, 'run-123');
    expect(output.toLogEntry().executionId, 'run-123');
  });

  test('ChaquopyRuntimeSession disposal cancels its status subscription',
      () async {
    final bridge = _ChaquopyBridgeFake();
    final session = ChaquopyRuntimeSession(
      backend: ChaquopyBackend(bridge),
      request: const RuntimeRequest(scriptName: 'demo.py', executionId: 'run'),
    );

    await session.dispose();
    bridge.emitStatus(
      executionId: 'run',
      status: ExecutionStatus.completed,
      exitCode: 0,
    );
    await expectLater(
      session.waitExit().timeout(const Duration(milliseconds: 30)),
      throwsA(isA<TimeoutException>()),
    );
  });
}

class _ChaquopyBridgeFake extends NativeBridge {
  _ChaquopyBridgeFake() : super.named();

  final StreamController<Map<dynamic, dynamic>> _statusController =
      StreamController<Map<dynamic, dynamic>>.broadcast();
  final Stream<Map<dynamic, dynamic>> _emptyStream =
      const Stream<Map<dynamic, dynamic>>.empty().asBroadcastStream();

  @override
  Stream<Map<dynamic, dynamic>> get logStream => _emptyStream;

  @override
  Stream<Map<dynamic, dynamic>> get executionStatusStream =>
      _statusController.stream;

  @override
  Stream<Map<dynamic, dynamic>> get stdinRequestStream => _emptyStream;

  @override
  Stream<Map<dynamic, dynamic>> get installProgressStream => _emptyStream;

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
}
