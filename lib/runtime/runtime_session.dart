import 'dart:async';

import '../models/execution_state.dart';
import 'runtime_output.dart';
import 'runtime_request.dart';

abstract class RuntimeSession {
  String get id;
  String get backendId;
  RuntimeRequest get request;

  Stream<RuntimeOutput> get stdout;
  Stream<RuntimeOutput> get stderr;
  Stream<ExecutionState> get stateStream;

  Future<void> writeStdin(String data);
  Future<void> interrupt();
  Future<void> terminate();
  Future<int?> waitExit();
}

bool isTerminalRuntimeState(ExecutionStatus status) {
  return status != ExecutionStatus.running &&
      status != ExecutionStatus.stopping;
}
