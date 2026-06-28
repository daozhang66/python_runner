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
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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

  test('package provider restores cached packages before slow refresh',
      () async {
    SharedPreferences.setMockInitialValues({
      'package_cache_fake':
          '[{"name":"cached","version":"1.0","isUserPackage":true,'
              '"integrityStatus":"broken","integrityMessage":"缺少 dns",'
              '"missingImports":["dns"]}]',
    });
    final listCompleter = Completer<List<RuntimePackage>>();
    final backend = _FakeRuntimeBackend(
      packages: const [],
      uninstallResult: const PackageUninstallResult(success: true),
      listPackagesCompleter: listCompleter,
    );
    final provider = PackageProvider(
      NativeBridge(),
      runtimeManager: RuntimeManager(backend),
    );

    final loadFuture = provider.loadPackages();
    await Future<void>.delayed(Duration.zero);

    expect(provider.loadingPackages, isTrue);
    expect(provider.packages.map((item) => item.name), contains('cached'));
    expect(provider.packages.first.integrityStatus, 'broken');
    expect(provider.packages.first.missingImports, ['dns']);

    listCompleter.complete(const [
      RuntimePackage(name: 'fresh', version: '2.0', source: 'user'),
    ]);
    await loadFuture;

    expect(provider.loadingPackages, isFalse);
    expect(provider.packages.map((item) => item.name), contains('fresh'));
    expect(provider.packages.first.integrityStatus, 'unknown');
    expect(
        provider.packages.map((item) => item.name), isNot(contains('cached')));
  });

  test('package provider maps broken package integrity and repairs package',
      () async {
    final backend = _FakeRuntimeBackend(
      packages: const [
        RuntimePackage(
          name: 'dnspython',
          version: '2.6.1',
          source: 'user',
          integrityStatus: 'broken',
          integrityMessage: '缺少 dns',
          missingImports: ['dns'],
        ),
      ],
      uninstallResult: const PackageUninstallResult(success: true),
      packagesAfterRepair: const [
        RuntimePackage(
          name: 'dnspython',
          version: '2.6.1',
          source: 'user',
          integrityStatus: 'ok',
        ),
      ],
    );
    final provider = PackageProvider(
      NativeBridge(),
      runtimeManager: RuntimeManager(backend),
    );

    await provider.loadPackages();

    expect(provider.packages.single.hasBrokenIntegrity, isTrue);
    expect(provider.packages.single.integrityMessage, '缺少 dns');
    expect(provider.packages.single.missingImports, ['dns']);

    await provider.repairPackage(
      'dnspython',
      version: '2.6.1',
      indexUrl: 'https://example.invalid/simple',
    );

    expect(backend.repairCount, 1);
    expect(backend.lastRepairRequest?.packageName, 'dnspython');
    expect(backend.lastRepairRequest?.version, '2.6.1');
    expect(
        backend.lastRepairRequest?.indexUrl, 'https://example.invalid/simple');
    expect(provider.installing, isFalse);
    expect(provider.packages.single.integrityStatus, 'ok');
    expect(provider.installLog.last, contains('修复成功'));
  });

  test('package provider only loads once when packages are already ready',
      () async {
    final backend = _FakeRuntimeBackend(
      packages: const [
        RuntimePackage(name: 'requests', version: '2.32.0', source: 'user'),
      ],
      uninstallResult: const PackageUninstallResult(success: true),
    );
    final provider = PackageProvider(
      NativeBridge(),
      runtimeManager: RuntimeManager(backend),
    );

    await provider.ensurePackagesLoaded();
    await provider.ensurePackagesLoaded();

    expect(backend.listPackagesCallCount, 1);
  });
}

class _FakeRuntimeBackend implements RuntimeBackend {
  _FakeRuntimeBackend({
    required List<RuntimePackage> packages,
    required this.uninstallResult,
    this.packagesAfterRequirements = const [],
    this.packagesAfterRepair = const [],
    this.listPackagesCompleter,
  }) : _packages = List<RuntimePackage>.from(packages);

  final List<RuntimePackage> _packages;
  final PackageUninstallResult uninstallResult;
  final List<RuntimePackage> packagesAfterRequirements;
  final List<RuntimePackage> packagesAfterRepair;
  final Completer<List<RuntimePackage>>? listPackagesCompleter;
  RequirementsInstallRequest? lastRequirementsRequest;
  PackageInstallRequest? lastRepairRequest;
  int requirementsInstallCount = 0;
  int repairCount = 0;
  int listPackagesCallCount = 0;

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
  Future<PackageInstallResult> repairPackage(
    PackageInstallRequest request,
  ) async {
    lastRepairRequest = request;
    repairCount++;
    _packages
      ..clear()
      ..addAll(packagesAfterRepair);
    return PackageInstallResult(
      success: true,
      message: '修复成功: ${request.packageName}',
    );
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
  Future<List<RuntimePackage>> listPackages() async {
    listPackagesCallCount++;
    return listPackagesCompleter?.future ??
        List<RuntimePackage>.from(_packages);
  }

  @override
  Future<RuntimeHealth> checkHealth() async => const RuntimeHealth(ok: true);
}
