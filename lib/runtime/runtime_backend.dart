import 'dart:async';

import '../models/execution_state.dart';
import 'runtime_health.dart';
import 'runtime_output.dart';
import 'runtime_package.dart';
import 'runtime_request.dart';
import 'runtime_session.dart';
import 'runtime_stdin_request.dart';

/// Runtime-specific adapter used by [RuntimeManager].
///
/// Implementations translate the app's execution/package operations into a
/// concrete runtime such as Chaquopy or the Linux-like environment. They must
/// keep streams broadcast-safe and report terminal execution states with the
/// same execution id from the original [RuntimeRequest].
abstract class RuntimeBackend {
  /// Stable backend id persisted in settings and sent to scripts.
  String get id;

  /// Human-readable backend name for diagnostics and settings UI.
  String get name;

  /// Script stdout/stderr and informational output.
  Stream<RuntimeOutput> get outputStream;

  /// Execution lifecycle updates for the active runtime session.
  Stream<ExecutionState> get stateStream;

  /// Requests emitted when the running script needs stdin.
  Stream<RuntimeStdinRequest> get stdinRequestStream;

  /// Package install progress updates.
  Stream<PackageInstallProgress> get packageInstallProgressStream;

  /// Starts a script or project execution and returns a controllable session.
  Future<RuntimeSession> startScript(RuntimeRequest request);

  /// Sends a single stdin line to the active process when supported.
  Future<void> sendStdin(String input);

  /// Requests termination of the active process.
  Future<void> stopExecution();

  /// Installs one package in this runtime.
  Future<PackageInstallResult> installPackage(PackageInstallRequest request);

  /// Reinstalls one package to repair missing files in this runtime.
  Future<PackageInstallResult> repairPackage(PackageInstallRequest request);

  /// Installs requirements content or file for this runtime.
  Future<PackageInstallResult> installRequirements(
    RequirementsInstallRequest request,
  );

  /// Removes one installed package.
  Future<PackageUninstallResult> uninstallPackage(String packageName);

  /// Lists installed packages known to this runtime.
  Future<List<RuntimePackage>> listPackages();

  /// Checks whether this runtime can execute scripts right now.
  Future<RuntimeHealth> checkHealth();
}
