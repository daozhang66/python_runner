import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/models/execution_state.dart';
import 'package:python_runner/providers/package_provider.dart';
import 'package:python_runner/runtime/runtime_backend.dart';
import 'package:python_runner/runtime/runtime_health.dart';
import 'package:python_runner/runtime/runtime_manager.dart';
import 'package:python_runner/runtime/runtime_output.dart';
import 'package:python_runner/runtime/runtime_package.dart';
import 'package:python_runner/runtime/runtime_request.dart';
import 'package:python_runner/runtime/runtime_session.dart';
import 'package:python_runner/runtime/runtime_stdin_request.dart';
import 'package:python_runner/services/native_bridge.dart';

void main() {
  test('package provider returns orphan cleanup details after uninstall',
      () async {
    final backend = _FakeRuntimeBackend(
      packages: const [
        RuntimePackage(name: 'requests', version: '2.32.0', source: 'user'),
        RuntimePackage(name: 'urllib3', version: '2.0.0', source: 'user'),
      ],
      uninstallResult: const PackageUninstallResult(
        success: true,
        message: '卸载成功',
        removedDependencies: ['certifi', 'urllib3'],
      ),
    );
    final provider = PackageProvider(
      NativeBridge(),
      runtimeManager: RuntimeManager(backend),
    );

    await provider.loadPackages();
    final result = await provider.uninstallPackage('requests');

    expect(result.success, isTrue);
    expect(result.removedDependencies, ['certifi', 'urllib3']);
    expect(
      provider.packages.map((item) => item.name),
      isNot(contains('requests')),
    );
    expect(
      provider.packages.map((item) => item.name),
      isNot(contains('urllib3')),
    );
  });

  test('package provider installs requirements and refreshes packages',
      () async {
    final backend = _FakeRuntimeBackend(
      packages: const [],
      uninstallResult: const PackageUninstallResult(success: true),
      packagesAfterRequirements: const [
        RuntimePackage(name: 'requests', version: '2.32.0', source: 'user'),
      ],
    );
    final provider = PackageProvider(
      NativeBridge(),
      runtimeManager: RuntimeManager(backend),
    );

    await provider.installRequirementsFromContent(
      content: 'requests==2.32.0',
      displayName: 'requirements.txt',
      indexUrl: 'https://example.invalid/simple',
    );

    expect(backend.requirementsInstallCount, 1);
    expect(backend.lastRequirementsRequest?.content, 'requests==2.32.0');
    expect(
      backend.lastRequirementsRequest?.indexUrl,
      'https://example.invalid/simple',
    );
    expect(provider.installing, isFalse);
    expect(provider.packages.map((item) => item.name), contains('requests'));
  });
}

class _FakeRuntimeBackend implements RuntimeBackend {
  _FakeRuntimeBackend({
    required List<RuntimePackage> packages,
    required this.uninstallResult,
    this.packagesAfterRequirements = const [],
  }) : _packages = List<RuntimePackage>.from(packages);

  final List<RuntimePackage> _packages;
  final PackageUninstallResult uninstallResult;
  final List<RuntimePackage> packagesAfterRequirements;
  RequirementsInstallRequest? lastRequirementsRequest;
  int requirementsInstallCount = 0;

  @override
  String get id => 'fake';

  @override
  String get name => 'Fake';

  @override
  Stream<RuntimeOutput> get outputStream => const Stream<RuntimeOutput>.empty();

  @override
  Stream<ExecutionState> get stateStream =>
      const Stream<ExecutionState>.empty();

  @override
  Stream<RuntimeStdinRequest> get stdinRequestStream =>
      const Stream<RuntimeStdinRequest>.empty();

  @override
  Stream<PackageInstallProgress> get packageInstallProgressStream =>
      const Stream<PackageInstallProgress>.empty();

  @override
  Future<RuntimeSession> startScript(RuntimeRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<void> sendStdin(String input) async {}

  @override
  Future<void> stopExecution() async {}

  @override
  Future<PackageInstallResult> installPackage(PackageInstallRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<PackageInstallResult> installRequirements(
    RequirementsInstallRequest request,
  ) async {
    lastRequirementsRequest = request;
    requirementsInstallCount++;
    _packages
      ..clear()
      ..addAll(packagesAfterRequirements);
    return const PackageInstallResult(
      success: true,
      message: 'requirements.txt 安装成功',
    );
  }

  @override
  Future<PackageUninstallResult> uninstallPackage(String packageName) async {
    _packages.removeWhere((item) => item.name == packageName);
    for (final dependency in uninstallResult.removedDependencies) {
      _packages.removeWhere((item) => item.name == dependency);
    }
    return uninstallResult;
  }

  @override
  Future<List<RuntimePackage>> listPackages() async =>
      List<RuntimePackage>.from(_packages);

  @override
  Future<RuntimeHealth> checkHealth() async => const RuntimeHealth(ok: true);
}
