import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/packages/application/package_controller.dart';
import 'package:python_runner/features/packages/application/package_repository.dart';
import 'package:python_runner/models/package_info.dart';
import 'package:python_runner/providers/infrastructure_providers.dart';
import 'package:python_runner/providers/theme_provider.dart';
import 'package:python_runner/runtime/runtime_manager.dart';
import 'package:python_runner/runtime/runtime_package.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/package_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  ProviderContainer makeContainer(FakePackageRepository repository) {
    final container = buildPackageContainer(repository: repository);
    addTearDown(container.dispose);
    // 触发 build() 以建立流订阅。
    container.read(packageControllerProvider);
    return container;
  }

  test('runtime invalidation switches package controller backend', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      RuntimeManager.prefsKey,
      RuntimeManager.chaquopyBackendId,
    );
    final invalidatorProvider = Provider<void Function()>((ref) {
      return () => invalidateRuntimeBackend(ref);
    });
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(packageControllerProvider).activeBackendId,
      RuntimeManager.chaquopyBackendId,
    );

    await preferences.setString(
      RuntimeManager.prefsKey,
      RuntimeManager.linuxLikeBackendId,
    );
    container.read(invalidatorProvider)();

    expect(
      container.read(packageControllerProvider).activeBackendId,
      RuntimeManager.linuxLikeBackendId,
    );
  });

  group('load', () {
    test('ensureLoaded loads packages once and distinguishes first load',
        () async {
      final repo = FakePackageRepository(packages: const [
        RuntimePackage(name: 'requests', version: '2.32.0', source: 'user'),
      ]);
      final container = makeContainer(repo);

      await container.read(packageControllerProvider.notifier).ensureLoaded();
      final stateAfterFirst = container.read(packageControllerProvider);
      expect(stateAfterFirst.isInitialLoading, isFalse);
      expect(stateAfterFirst.packages.single.name, 'requests');
      expect(repo.listPackagesCallCount, 1);

      // 第二次 ensureLoaded 不应再次触发加载。
      await container.read(packageControllerProvider.notifier).ensureLoaded();
      expect(repo.listPackagesCallCount, 1);
    });

    test('refresh re-fetches and preserves existing packages during load',
        () async {
      final firstLoad = Completer<List<RuntimePackage>>();
      final repo = FakePackageRepository(
        packages: const [
          RuntimePackage(name: 'cached', version: '1.0', source: 'user'),
        ],
        listPackagesCompleter: firstLoad,
      );
      final container = makeContainer(repo);

      // 先完成首次加载（用 firstLoad 让 listPackages 返回）。
      final ensureFuture =
          container.read(packageControllerProvider.notifier).ensureLoaded();
      await Future<void>.delayed(Duration.zero);
      firstLoad.complete(const [
        RuntimePackage(name: 'cached', version: '1.0', source: 'user'),
      ]);
      await ensureFuture;

      // 再发起刷新；刷新过程中应显示 isRefreshing 而非全屏 loading。
      final refreshCompleter = Completer<List<RuntimePackage>>();
      repo.listPackagesCompleter = refreshCompleter;
      final refreshFuture =
          container.read(packageControllerProvider.notifier).refresh();
      await Future<void>.delayed(Duration.zero);
      expect(container.read(packageControllerProvider).isRefreshing, isTrue);
      expect(
        container.read(packageControllerProvider).isInitialLoading,
        isFalse,
        reason: '已有数据时刷新不应覆盖列表',
      );
      // 原有数据仍在，避免空闪。
      expect(
        container.read(packageControllerProvider).packages.map((p) => p.name),
        contains('cached'),
      );

      refreshCompleter.complete(const [
        RuntimePackage(name: 'fresh', version: '2.0', source: 'user'),
      ]);
      await refreshFuture;
      expect(
        container.read(packageControllerProvider).packages.single.name,
        'fresh',
      );
    });

    test('concurrent refreshes share one in-flight package query', () async {
      final repo = FakePackageRepository(
        packages: const [
          RuntimePackage(name: 'cached', version: '1.0', source: 'user'),
        ],
      );
      final container = makeContainer(repo);
      await container.read(packageControllerProvider.notifier).ensureLoaded();

      final refreshCompleter = Completer<List<RuntimePackage>>();
      repo.listPackagesCompleter = refreshCompleter;
      final first =
          container.read(packageControllerProvider.notifier).refresh();
      final second =
          container.read(packageControllerProvider.notifier).refresh();
      await Future<void>.delayed(Duration.zero);

      expect(repo.listPackagesCallCount, 2, reason: '首次加载后，两次并发刷新应只新增一次真实查询');
      refreshCompleter.complete(const [
        RuntimePackage(name: 'fresh', version: '2.0', source: 'user'),
      ]);
      await Future.wait([first, second]);
      expect(
        container.read(packageControllerProvider).packages.single.name,
        'fresh',
      );
    });

    test('loaded empty package list refreshes in the background', () async {
      final repo = FakePackageRepository(
        packages: const [
          RuntimePackage(name: 'requests', version: '2.32.0', source: 'user'),
        ],
      );
      final container = makeContainer(repo);
      await container.read(packageControllerProvider.notifier).ensureLoaded();

      final refreshCompleter = Completer<List<RuntimePackage>>();
      repo.listPackagesCompleter = refreshCompleter;
      final uninstall = container
          .read(packageControllerProvider.notifier)
          .uninstall('requests');
      await Future<void>.delayed(Duration.zero);
      repo.emitProgress(
        const PackageInstallProgress(status: 'success', message: 'installed'),
      );
      await Future<void>.delayed(Duration.zero);

      final duringRefresh = container.read(packageControllerProvider);
      expect(duringRefresh.packages, isEmpty);
      expect(duringRefresh.isInitialLoading, isFalse);
      expect(duringRefresh.isRefreshing, isTrue);
      expect(repo.listPackagesCallCount, 2, reason: '卸载刷新与进度刷新应共享同一查询');

      refreshCompleter.complete(const []);
      await uninstall;
      expect(container.read(packageControllerProvider).packages, isEmpty);
      expect(
          container.read(packageControllerProvider).isInitialLoading, isFalse);
    });

    test('first empty package load still uses initial loading', () async {
      final firstLoad = Completer<List<RuntimePackage>>();
      final repo = FakePackageRepository(listPackagesCompleter: firstLoad);
      final container = makeContainer(repo);

      final initial =
          container.read(packageControllerProvider.notifier).ensureLoaded();
      await Future<void>.delayed(Duration.zero);
      expect(
          container.read(packageControllerProvider).isInitialLoading, isTrue);
      firstLoad.complete(const []);
      await initial;

      final refreshLoad = Completer<List<RuntimePackage>>();
      repo.listPackagesCompleter = refreshLoad;
      final refresh =
          container.read(packageControllerProvider.notifier).refresh();
      await Future<void>.delayed(Duration.zero);
      expect(
          container.read(packageControllerProvider).isInitialLoading, isFalse);
      expect(container.read(packageControllerProvider).isRefreshing, isTrue);
      refreshLoad.complete(const []);
      await refresh;
    });

    test('restore cached packages before slow first load', () async {
      final completer = Completer<List<RuntimePackage>>();
      final repo = FakePackageRepository(
        packages: const [],
        listPackagesCompleter: completer,
        cachedPackages: {
          'cached': PackageInfo(
            name: 'cached',
            integrityStatus: 'broken',
            missingImports: ['dns'],
          ),
        },
      );
      final container = makeContainer(repo);

      final loadFuture =
          container.read(packageControllerProvider.notifier).ensureLoaded();
      await Future<void>.delayed(Duration.zero);

      // 首次加载期间已有缓存可见。
      final midState = container.read(packageControllerProvider);
      expect(midState.isInitialLoading, isFalse,
          reason: '缓存恢复后不再是空数据全屏 loading');
      expect(midState.packages.single.name, 'cached');
      expect(midState.packages.single.integrityStatus, 'broken');

      completer.complete(const [
        RuntimePackage(name: 'fresh', version: '2.0', source: 'user'),
      ]);
      await loadFuture;

      final state = container.read(packageControllerProvider);
      expect(state.packages.single.name, 'fresh');
      expect(state.packages.single.integrityStatus, 'unknown');
    });

    test('load error is exposed and cleared on retry', () async {
      final repo = FakePackageRepository(
        packages: const [
          RuntimePackage(name: 'requests', version: '2.32.0', source: 'user'),
        ],
        listPackagesError: StateError('runtime unavailable'),
      );
      final container = makeContainer(repo);

      await container.read(packageControllerProvider.notifier).refresh();

      expect(
        container.read(packageControllerProvider).loadError,
        contains('runtime unavailable'),
      );
      expect(container.read(packageControllerProvider).packages, isEmpty);

      repo.listPackagesError = null;
      await container.read(packageControllerProvider.notifier).refresh();
      expect(container.read(packageControllerProvider).loadError, isNull);
      expect(
        container.read(packageControllerProvider).packages.single.name,
        'requests',
      );
    });

    test('same-backend repository rebuild keeps loaded packages without reload',
        () async {
      final repositorySlot = StateProvider<int>((ref) => 0);
      final firstRepository = FakePackageRepository(
        activeBackendId: RuntimeManager.chaquopyBackendId,
        packages: const [
          RuntimePackage(name: 'requests', version: '2.32.0', source: 'user'),
        ],
      );
      final reboundRepository = FakePackageRepository(
        activeBackendId: RuntimeManager.chaquopyBackendId,
        packages: const [
          RuntimePackage(name: 'requests', version: '2.32.0', source: 'user'),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          packageRepositoryProvider.overrideWith((ref) {
            return ref.watch(repositorySlot) == 0
                ? firstRepository
                : reboundRepository;
          }),
        ],
      );
      addTearDown(container.dispose);
      container.listen(packageControllerProvider, (_, __) {});

      await container.read(packageControllerProvider.notifier).ensureLoaded();
      expect(firstRepository.listPackagesCallCount, 1);

      container.read(repositorySlot.notifier).state = 1;
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(packageControllerProvider).packages.single.name,
        'requests',
      );
      await container.read(packageControllerProvider.notifier).ensureLoaded();
      expect(firstRepository.listPackagesCallCount, 1);
      expect(reboundRepository.listPackagesCallCount, 0);
    });

    test('same-backend rebuild preserves the install-log cleanup timer',
        () async {
      final repositorySlot = StateProvider<int>((ref) => 0);
      final firstRepository = FakePackageRepository(
        activeBackendId: RuntimeManager.chaquopyBackendId,
      );
      final reboundRepository = FakePackageRepository(
        activeBackendId: RuntimeManager.chaquopyBackendId,
      );
      final container = ProviderContainer(
        overrides: [
          packageRepositoryProvider.overrideWith((ref) {
            return ref.watch(repositorySlot) == 0
                ? firstRepository
                : reboundRepository;
          }),
        ],
      );
      addTearDown(container.dispose);
      container.listen(packageControllerProvider, (_, __) {});

      await container
          .read(packageControllerProvider.notifier)
          .install('requests');
      expect(container.read(packageControllerProvider).installLog, isNotEmpty);

      container.read(repositorySlot.notifier).state = 1;
      await Future<void>.delayed(
        PackageController.installLogClearDelay +
            const Duration(milliseconds: 50),
      );

      expect(container.read(packageControllerProvider).installLog, isEmpty);
    });

    test('backend switch automatically loads the new backend', () async {
      final repositorySlot = StateProvider<int>((ref) => 0);
      final chaquopyRepository = FakePackageRepository(
        activeBackendId: RuntimeManager.chaquopyBackendId,
        packages: const [
          RuntimePackage(name: 'requests', version: '2.32.0', source: 'user'),
        ],
      );
      final linuxRepository = FakePackageRepository(
        activeBackendId: RuntimeManager.linuxLikeBackendId,
        supportsRequirementsInstall: true,
        packages: const [
          RuntimePackage(name: 'uvicorn', version: '0.30.0', source: 'user'),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          packageRepositoryProvider.overrideWith((ref) {
            return ref.watch(repositorySlot) == 0
                ? chaquopyRepository
                : linuxRepository;
          }),
        ],
      );
      addTearDown(container.dispose);

      container.listen(packageControllerProvider, (_, __) {});
      await container.read(packageControllerProvider.notifier).ensureLoaded();
      container.read(repositorySlot.notifier).state = 1;
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final state = container.read(packageControllerProvider);
      expect(state.activeBackendId, RuntimeManager.linuxLikeBackendId);
      expect(state.supportsRequirementsInstall, isTrue);
      expect(state.packages.single.name, 'uvicorn');
      expect(linuxRepository.listPackagesCallCount, 1);
    });

    test('late package results from the old backend cannot overwrite new state',
        () async {
      final repositorySlot = StateProvider<int>((ref) => 0);
      final oldLoad = Completer<List<RuntimePackage>>();
      final oldRepository = FakePackageRepository(
        activeBackendId: RuntimeManager.chaquopyBackendId,
        listPackagesCompleter: oldLoad,
      );
      final newRepository = FakePackageRepository(
        activeBackendId: RuntimeManager.linuxLikeBackendId,
        supportsRequirementsInstall: true,
        packages: const [
          RuntimePackage(name: 'uvicorn', version: '0.30.0', source: 'user'),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          packageRepositoryProvider.overrideWith((ref) {
            return ref.watch(repositorySlot) == 0
                ? oldRepository
                : newRepository;
          }),
        ],
      );
      addTearDown(container.dispose);
      container.listen(packageControllerProvider, (_, __) {});

      final oldEnsure =
          container.read(packageControllerProvider.notifier).ensureLoaded();
      await Future<void>.delayed(Duration.zero);
      container.read(repositorySlot.notifier).state = 1;
      await Future<void>.delayed(const Duration(milliseconds: 10));

      oldLoad.complete(const [
        RuntimePackage(name: 'old-package', version: '1.0.0', source: 'user'),
      ]);
      await oldEnsure;

      final state = container.read(packageControllerProvider);
      expect(state.activeBackendId, RuntimeManager.linuxLikeBackendId);
      expect(state.packages.single.name, 'uvicorn');
      expect(state.loadError, isNull);
    });
  });

  group('install', () {
    test('install updates log and refreshes on success', () async {
      final repo = FakePackageRepository(
        packages: const [],
        packagesAfterInstall: const [
          RuntimePackage(name: 'requests', version: '2.32.0', source: 'user'),
        ],
      );
      final container = makeContainer(repo);

      await container.read(packageControllerProvider.notifier).install(
            'requests',
            version: '2.32.0',
            indexUrl: 'https://example.invalid/simple',
          );

      expect(repo.installCallCount, 1);
      expect(repo.lastInstallRequest?.packageName, 'requests');
      expect(repo.lastInstallRequest?.version, '2.32.0');
      expect(
          repo.lastInstallRequest?.indexUrl, 'https://example.invalid/simple');
      final state = container.read(packageControllerProvider);
      expect(state.isInstalling, isFalse);
      expect(state.packages.map((p) => p.name), contains('requests'));
      expect(state.installLog.last, contains('安装成功'));
    });

    test('install records error message on repository failure', () async {
      final repo = FakePackageRepository(
        packages: const [],
        installResult: const PackageInstallResult(
          success: false,
          message: '安装失败: requests',
        ),
      );
      final container = makeContainer(repo);

      await container
          .read(packageControllerProvider.notifier)
          .install('requests');

      final state = container.read(packageControllerProvider);
      expect(state.isInstalling, isFalse);
      expect(state.installLog.last, contains('安装失败'));
    });

    test('install records exception text when repository throws', () async {
      final repo = _ThrowingInstallRepository();
      final container = makeContainer(repo);

      await container
          .read(packageControllerProvider.notifier)
          .install('requests');

      final state = container.read(packageControllerProvider);
      expect(state.isInstalling, isFalse);
      expect(state.installLog.last, contains('Error'));
    });

    test('concurrent install requests are rejected without double work',
        () async {
      final blocker = Completer<PackageInstallResult>();
      final repo = _BlockingInstallRepository(blocker);
      final container = makeContainer(repo);

      // 第一个安装挂起未完成。
      final first = container
          .read(packageControllerProvider.notifier)
          .install('requests');
      // 第二个安装应在入口被拒绝，记录提示但不调用 repository。
      await container
          .read(packageControllerProvider.notifier)
          .install('urllib3');

      expect(repo.installCallCount, 1, reason: '不应在安装进行中再次调用后端');
      expect(
        container.read(packageControllerProvider).installLog.last,
        contains('已有安装任务进行中'),
      );

      blocker.complete(const PackageInstallResult(success: true));
      await first;
    });
  });

  group('install progress stream', () {
    test('success event refreshes packages and clears installing', () async {
      final repo = FakePackageRepository(packages: const []);
      final container = makeContainer(repo);

      // 模拟安装中。
      await container
          .read(packageControllerProvider.notifier)
          .install('requests');

      repo.emitProgress(
        const PackageInstallProgress(
            status: 'success', message: 'Collecting requests'),
      );
      // 等待 stream 事件 + 触发的 refresh。
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final state = container.read(packageControllerProvider);
      expect(state.isInstalling, isFalse);
      expect(state.installLog, contains('Collecting requests'));
    });

    test(
        'regression: stream success arriving before repair future does not '
        'double-load or double-log', () async {
      // 复刻 Linux-like 后端：原生在 MethodChannel future 完成前先发送 success
      // 进度事件。修复前的 Controller 会因此触发两次 listPackages 并重复追加
      // 完成日志。本用例锁定流先完成、repository future 后完成时只刷新一次。
      final repo = _StreamFirstRepairRepository();
      final container = makeContainer(repo);

      // repair 挂起在 repository 上，等待我们在发出 success 进度后再放行。
      final repairFuture = container
          .read(packageControllerProvider.notifier)
          .repair('dnspython');
      await Future<void>.delayed(Duration.zero);

      // 模拟原生先发 success 进度（携带完成消息）：流处理把 isInstalling 置 false、
      // 追加完成消息并触发刷新。
      repo.emitProgress(
        const PackageInstallProgress(
          status: 'success',
          message: '修复成功: dnspython',
        ),
      );
      // 给流处理 + fire-and-forget 刷新足够的微任务时间触发 listPackages。
      await Future<void>.delayed(const Duration(milliseconds: 15));

      // 放行 repository future（带相同的完成消息，模拟若守卫缺失会重复追加）。
      repo.completeRepair(
        const PackageInstallResult(success: true, message: '修复成功: dnspython'),
      );
      await repairFuture;
      await Future<void>.delayed(Duration.zero);

      // 关键断言：流成功事件已把 isInstalling 置 false，repository 完成路径
      // (_handleInstallResult) 因守卫跳过，因此完成日志只出现一次、listPackages
      // 只被流路径调用一次。
      expect(repo.listPackagesCallCount, 1,
          reason: '流成功事件已刷新，repository 完成路径不应再触发第二次 listPackages');
      final installLog = container.read(packageControllerProvider).installLog;
      expect(installLog.where((line) => line.contains('修复成功')).length, 1,
          reason: '完成日志不应被重复追加');
      expect(container.read(packageControllerProvider).isInstalling, isFalse);
    });
  });

  group('requirements', () {
    test('installRequirementsFromContent maps request and refreshes', () async {
      final repo = FakePackageRepository(
        packages: const [],
        supportsRequirementsInstall: true,
        packagesAfterRequirements: const [
          RuntimePackage(name: 'requests', version: '2.32.0', source: 'user'),
        ],
      );
      final container = makeContainer(repo);

      await container
          .read(packageControllerProvider.notifier)
          .installRequirementsFromContent(
            content: 'requests==2.32.0',
            displayName: 'requirements.txt',
            indexUrl: 'https://example.invalid/simple',
          );

      expect(repo.requirementsInstallCount, 1);
      expect(repo.lastRequirementsRequest?.content, 'requests==2.32.0');
      expect(
        repo.lastRequirementsRequest?.indexUrl,
        'https://example.invalid/simple',
      );
      expect(
        container.read(packageControllerProvider).packages.map((p) => p.name),
        contains('requests'),
      );
    });

    test('requirements rejected on non-linux-like backend', () async {
      final repo = FakePackageRepository(
        packages: const [],
        supportsRequirementsInstall: false,
      );
      final container = makeContainer(repo);

      await container
          .read(packageControllerProvider.notifier)
          .installRequirementsFromContent(content: 'requests==2.32.0');

      expect(repo.requirementsInstallCount, 0);
      expect(
        container.read(packageControllerProvider).installLog.last,
        contains('仅支持 Linux-like'),
      );
    });
  });

  group('repair', () {
    test('repair maps version with unknown normalization', () async {
      final repo = FakePackageRepository(
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
        supportsRequirementsInstall: true,
        packagesAfterRepair: const [
          RuntimePackage(
            name: 'dnspython',
            version: '2.6.1',
            source: 'user',
            integrityStatus: 'ok',
          ),
        ],
      );
      final container = makeContainer(repo);

      await container.read(packageControllerProvider.notifier).ensureLoaded();
      expect(
        container
            .read(packageControllerProvider)
            .packages
            .single
            .hasBrokenIntegrity,
        isTrue,
      );

      await container.read(packageControllerProvider.notifier).repair(
            'dnspython',
            version: 'unknown',
            indexUrl: 'https://example.invalid/simple',
          );

      expect(repo.repairCallCount, 1);
      // unknown 版本应归一化为 null。
      expect(repo.lastRepairRequest?.version, isNull);
      expect(
        repo.lastRepairRequest?.indexUrl,
        'https://example.invalid/simple',
      );
      expect(
        container
            .read(packageControllerProvider)
            .packages
            .single
            .integrityStatus,
        'ok',
      );
      expect(
        container.read(packageControllerProvider).installLog.last,
        contains('修复成功'),
      );
    });
  });

  group('uninstall', () {
    test('optimistic removal then refresh, returns cleanup details', () async {
      final repo = FakePackageRepository(
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
      final container = makeContainer(repo);

      await container.read(packageControllerProvider.notifier).ensureLoaded();
      final result = await container
          .read(packageControllerProvider.notifier)
          .uninstall('requests');

      expect(result.success, isTrue);
      expect(result.removedDependencies, ['certifi', 'urllib3']);
      expect(
        container.read(packageControllerProvider).packages.map((p) => p.name),
        isNot(contains('requests')),
      );
      expect(
        container.read(packageControllerProvider).packages.map((p) => p.name),
        isNot(contains('urllib3')),
      );
    });
  });

  group('install log', () {
    test('clearInstallLog empties the log immediately', () async {
      final repo = FakePackageRepository(packages: const []);
      final container = makeContainer(repo);

      await container
          .read(packageControllerProvider.notifier)
          .install('requests');
      expect(container.read(packageControllerProvider).installLog, isNotEmpty);

      container.read(packageControllerProvider.notifier).clearInstallLog();
      expect(container.read(packageControllerProvider).installLog, isEmpty);
    });

    test('install log auto-clears after delay', () async {
      final repo = FakePackageRepository(packages: const []);
      final container = makeContainer(repo);

      await container
          .read(packageControllerProvider.notifier)
          .install('requests');
      expect(container.read(packageControllerProvider).installLog, isNotEmpty);

      await Future<void>.delayed(
        PackageController.installLogClearDelay +
            const Duration(milliseconds: 50),
      );
      expect(container.read(packageControllerProvider).installLog, isEmpty);
    });
  });

  group('dispose', () {
    test('disposing container cancels stream subscription', () async {
      final repo = FakePackageRepository(packages: const []);
      final container = buildPackageContainer(repository: repo);
      container.read(packageControllerProvider);

      // 触发 controller build 完成后销毁容器。
      await Future<void>.delayed(Duration.zero);
      container.dispose();

      // 销毁后再向流推送事件不应抛出（订阅已取消）。
      repo.emitProgress(
        const PackageInstallProgress(status: 'success', message: 'done'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      // 无断言失败即表示订阅已释放、无泄漏。
    });
  });
}

class _ThrowingInstallRepository extends FakePackageRepository {
  _ThrowingInstallRepository() : super(packages: const []);

  @override
  Future<PackageInstallResult> installPackage(
    PackageInstallRequest request,
  ) async {
    throw StateError('network down');
  }
}

class _BlockingInstallRepository extends FakePackageRepository {
  _BlockingInstallRepository(this._blocker) : super(packages: const []);

  final Completer<PackageInstallResult> _blocker;

  @override
  Future<PackageInstallResult> installPackage(
    PackageInstallRequest request,
  ) {
    lastInstallRequest = request;
    installCallCount++;
    return _blocker.future;
  }
}

/// 复刻 Linux-like 后端修复路径：repairPackage 在被 [completeRepair] 放行前
/// 一直挂起，期间可经 [emitProgress] 发送 success 进度，模拟原生先发进度、
/// 后完成 MethodChannel future 的时序。
class _StreamFirstRepairRepository extends FakePackageRepository {
  _StreamFirstRepairRepository() : super(packages: const []);

  final Completer<PackageInstallResult> _repairBlocker =
      Completer<PackageInstallResult>();

  @override
  Future<PackageInstallResult> repairPackage(
    PackageInstallRequest request,
  ) {
    lastRepairRequest = request;
    repairCallCount++;
    return _repairBlocker.future;
  }

  void completeRepair(PackageInstallResult result) {
    if (!_repairBlocker.isCompleted) _repairBlocker.complete(result);
  }
}
