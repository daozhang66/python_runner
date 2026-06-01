import 'dart:async';

import '../models/execution_state.dart';
import 'runtime_health.dart';
import 'runtime_output.dart';
import 'runtime_package.dart';
import 'runtime_request.dart';
import 'runtime_session.dart';
import 'runtime_stdin_request.dart';

abstract class RuntimeBackend {
  String get id;
  String get name;

  Stream<RuntimeOutput> get outputStream;
  Stream<ExecutionState> get stateStream;
  Stream<RuntimeStdinRequest> get stdinRequestStream;
  Stream<PackageInstallProgress> get packageInstallProgressStream;

  Future<RuntimeSession> startScript(RuntimeRequest request);
  Future<void> sendStdin(String input);
  Future<void> stopExecution();

  Future<PackageInstallResult> installPackage(PackageInstallRequest request);
  Future<PackageUninstallResult> uninstallPackage(String packageName);
  Future<List<RuntimePackage>> listPackages();
  Future<RuntimeHealth> checkHealth();
}
