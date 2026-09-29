import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/mcp/application/mcp_facade_impl.dart';
import 'package:python_runner/features/mcp/application/mcp_operation_registry.dart';
import 'package:python_runner/features/mcp/domain/mcp_error_codes.dart';
import 'package:python_runner/features/mcp/domain/mcp_facade_models.dart';
import 'package:python_runner/features/scripts/application/script_repository.dart';
import 'package:python_runner/features/scripts/application/script_workspace_controller.dart';
import 'package:python_runner/models/script_file.dart';
import 'package:python_runner/models/script_group.dart';
import 'package:python_runner/pigeon/native_runtime_api.g.dart' as pigeon;
import 'package:python_runner/runtime/runtime_package.dart';
import 'package:python_runner/runtime/runtime_manager.dart';
import 'package:python_runner/services/http_inspector_store.dart'
    show HttpRecord;
import 'package:python_runner/services/native_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/mcp_test_helper.dart';
import '../../support/package_test_helper.dart';
import '../../support/script_test_helper.dart';

const _methodChannel = MethodChannel('com.daozhang.py/native_bridge');

final _listDirectoryChannel = BasicMessageChannel<Object?>(
  'dev.flutter.pigeon.python_runner.FilePickerHostApi.listFilePickerDirectory',
  pigeon.FilePickerHostApi.pigeonChannelCodec,
);

class GatedSaveRepository extends FakeScriptRepository {
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<bool> saveScriptFile(String name, String content) async {
    if (!entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    return super.saveScriptFile(name, content);
  }
}

/// 安装被闸门阻塞的包仓库，用于验证互斥。
class GatedInstallRepository extends FakePackageRepository {
  GatedInstallRepository({
    super.activeBackendId = 'chaquopy',
    super.supportsRequirementsInstall = false,
  });

  final Completer<void> gate = Completer<void>();

  @override
  Future<PackageInstallResult> installPackage(
      PackageInstallRequest request) async {
    lastInstallRequest = request;
    installCallCount++;
    await gate.future;
    return const PackageInstallResult(success: true);
  }
}

/// createGroup 抛异常的脚本仓库，用于验证项目组回滚。
class FailingCreateGroupRepository extends FakeScriptRepository {
  @override
  Future<int> createGroup(ScriptGroup group) async {
    throw StateError('db write failed');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final bridgeCalls = <String>[];
  List<int> fileBytes = [];
  bool rejectBoundedRead = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    bridgeCalls.clear();
    fileBytes = [];
    rejectBoundedRead = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_methodChannel, (call) async {
      bridgeCalls.add(call.method);
      switch (call.method) {
        case 'readFileBounded':
          expect(call.arguments['maxBytes'], 4 * 1024 * 1024);
          if (rejectBoundedRead) throw PlatformException(code: '1046');
          return Uint8List.fromList(fileBytes);
        case 'createScriptProject':
          return {'path': '/files/script_projects/test'};
        case 'saveProjectFile':
          return true;
        case 'deleteScriptProject':
          return true;
      }
      throw PlatformException(code: 'missing', message: call.method);
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(_listDirectoryChannel, null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_methodChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(_listDirectoryChannel, null);
  });

  AppMcpApplicationFacade buildFacade({
    FakeScriptRepository? repository,
    FakePackageRepository? packageRepository,
    List<HttpRecord> networkRecords = const [],
    McpOperationRegistry? operationRegistry,
  }) {
    final repo = repository ?? FakeScriptRepository();
    final container = ProviderContainer(
      overrides: [scriptRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final workspace =
        container.read(scriptWorkspaceControllerProvider.notifier);
    return AppMcpApplicationFacade(
      scriptRepository: repo,
      workspaceController: workspace,
      bridge: NativeBridge(),
      networkRepository:
          FakeNetworkInspectorRepository(records: networkRecords),
      packageRepository: packageRepository ??
          FakePackageRepository(activeBackendId: 'chaquopy'),
      runtimeManager: RuntimeManager.chaquopy(NativeBridge()),
      operationRegistry: operationRegistry,
    );
  }

  group('脚本写操作（文件 + 元数据 + UI 状态一致）', () {
    test('concurrent saves check the revision inside the shared queue',
        () async {
      final repo = GatedSaveRepository();
      final facade = buildFacade(repository: repo);
      final initial =
          await facade.createScript(name: 'race.py', content: 'old');
      final revision = initial.modifiedAt.millisecondsSinceEpoch;
      final first = facade.saveScript(
          name: 'race.py', content: 'first', expectedModifiedAt: revision);
      await repo.entered.future;
      final second = expectLater(
        facade.saveScript(
            name: 'race.py', content: 'second', expectedModifiedAt: revision),
        throwsA(isA<McpToolException>()
            .having((e) => e.code, 'code', McpErrorCodes.writeConflict)),
      );
      repo.release.complete();
      await first;
      await second;
      expect(repo.saveScriptFileCount, 1);
      expect((await facade.readScript('race.py')).content, 'first');
    });
    test('createScript 同时写入文件、元数据并出现在工作台状态', () async {
      final repo = FakeScriptRepository();
      final facade = buildFacade(repository: repo);

      final summary =
          await facade.createScript(name: 'hello.py', content: 'print(1)');

      expect(summary.name, 'hello.py');
      expect(repo.createScriptFileCount, 1, reason: '脚本文件已创建');
      expect(repo.upsertScriptCount, greaterThanOrEqualTo(1), reason: '元数据已写入');
      expect((await repo.getScript('hello.py'))!.name, 'hello.py');
      // 工作台（首页列表）能看到 MCP 创建的脚本。
      final container = ProviderContainer(
        overrides: [scriptRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      final workspace =
          container.read(scriptWorkspaceControllerProvider.notifier);
      await workspace.load();
      expect(
        workspace.scripts.map((s) => s.name),
        contains('hello.py'),
      );
    });

    test('createScript 重复创建返回 SCRIPT_ALREADY_EXISTS，不覆盖原文件', () async {
      final facade = buildFacade();
      await facade.createScript(name: 'hello.py', content: 'v1');
      await expectLater(
        facade.createScript(name: 'hello.py', content: 'v2'),
        throwsA(isA<McpToolException>()
            .having((e) => e.code, 'code', McpErrorCodes.scriptAlreadyExists)),
      );
      final content = await facade.readScript('hello.py');
      expect(content.content, 'v1', reason: '原文件未被覆盖');
    });

    test('readScript 不存在返回 SCRIPT_NOT_FOUND', () async {
      final facade = buildFacade();
      await expectLater(
        facade.readScript('missing.py'),
        throwsA(isA<McpToolException>()
            .having((e) => e.code, 'code', McpErrorCodes.scriptNotFound)),
      );
    });

    test('saveScript 携带过期 modified_at 返回 WRITE_CONFLICT', () async {
      final facade = buildFacade();
      final created = await facade.createScript(name: 'a.py', content: 'v1');
      await facade.saveScript(name: 'a.py', content: 'v2-user-edit');

      await expectLater(
        facade.saveScript(
          name: 'a.py',
          content: 'v3-ai-overwrite',
          expectedModifiedAt: created.modifiedAt.millisecondsSinceEpoch - 60000,
        ),
        throwsA(isA<McpToolException>()
            .having((e) => e.code, 'code', McpErrorCodes.writeConflict)),
      );
      final latest = await facade.readScript('a.py');
      expect(latest.content, 'v2-user-edit', reason: '用户最新修改未被覆盖');
    });

    test('saveScript 携带当前 modified_at 成功写入', () async {
      final facade = buildFacade();
      await facade.createScript(name: 'a.py', content: 'v1');
      final before = (await facade.readScript('a.py'));
      await facade.saveScript(
        name: 'a.py',
        content: 'v2',
        expectedModifiedAt: before.modifiedAt.millisecondsSinceEpoch,
      );
      expect((await facade.readScript('a.py')).content, 'v2');
    });

    test('冲突检测为严格比较：毫秒级偏差也拒绝（无时间容差）', () async {
      final facade = buildFacade();
      await facade.createScript(name: 'a.py', content: 'v1');
      final current =
          (await facade.readScript('a.py')).modifiedAt.millisecondsSinceEpoch;

      await expectLater(
        facade.saveScript(
          name: 'a.py',
          content: 'overwrite',
          expectedModifiedAt: current - 1,
        ),
        throwsA(isA<McpToolException>()
            .having((e) => e.code, 'code', McpErrorCodes.writeConflict)),
      );
    });

    test('写入限制按 UTF-8 字节数计算：中文字符数未超但字节超限时拒绝', () async {
      final facade = buildFacade();
      // 800000 个三字节中文字符 = 2,400,000 字节 > 2 MiB，
      // 但 UTF-16 长度 800000 < 2,097,152（旧实现会漏判）。
      final content = '你' * 800000;
      await expectLater(
        facade.createScript(name: 'big.py', content: content),
        throwsA(isA<McpToolException>()
            .having((e) => e.code, 'code', McpErrorCodes.fileTooLarge)),
      );
      await expectLater(
        facade.saveScript(name: 'big.py', content: content),
        throwsA(isA<McpToolException>()
            .having((e) => e.code, 'code', McpErrorCodes.fileTooLarge)),
        reason: '超限内容在任何写操作前即被拒绝',
      );
    });
  });

  group('列表与分页', () {
    test('listScripts 支持名称过滤与 cursor 分页', () async {
      final repo = FakeScriptRepository(scripts: [
        for (var i = 1; i <= 5; i++)
          ScriptFile(
            name: 'script$i.py',
            path: 'script$i.py',
            createdAt: DateTime.now(),
            modifiedAt: DateTime.now(),
            sortOrder: i,
          ),
      ]);
      final facade = buildFacade(repository: repo);

      final page1 = await facade.listScripts(query: 'script', limit: 2);
      expect(page1.items, hasLength(2));
      expect(page1.nextCursor, isNotNull);

      final page2 = await facade.listScripts(
          query: 'script', limit: 2, cursor: page1.nextCursor);
      expect(page2.items, hasLength(2));

      final page3 = await facade.listScripts(
          query: 'script', limit: 2, cursor: page2.nextCursor);
      expect(page3.items, hasLength(1));
      expect(page3.nextCursor, isNull);
    });

    test('非法 cursor 返回 INVALID_ARGUMENT', () async {
      final facade = buildFacade();
      await expectLater(
        facade.listScripts(cursor: 'bad-cursor'),
        throwsA(isA<McpToolException>()
            .having((e) => e.code, 'code', McpErrorCodes.invalidArgument)),
      );
    });

    test('limit 超过 500 返回 INVALID_ARGUMENT', () async {
      final facade = buildFacade();
      await expectLater(
        facade.listScripts(limit: 501),
        throwsA(isA<McpToolException>()
            .having((e) => e.code, 'code', McpErrorCodes.invalidArgument)),
      );
    });
  });

  group('项目组', () {
    test('createProjectGroup 创建目录、主程序与分组记录', () async {
      final repo = FakeScriptRepository();
      final facade = buildFacade(repository: repo);

      final group = await facade.createProjectGroup(
        name: 'weather-tool',
        projectKey: 'weather_tool',
        mainFileContent: 'print("weather")',
      );

      expect(group.isProject, isTrue);
      expect(group.projectKey, 'weather_tool');
      expect(group.mainFilePath, 'main.py');
      expect(
          bridgeCalls, containsAll(['createScriptProject', 'saveProjectFile']));
      expect(
          (await repo.getAllGroups())
              .any((g) => g.projectKey == 'weather_tool'),
          isTrue);
    });

    test('数据库写入失败时回滚项目目录，不留半成品', () async {
      final repo = FailingCreateGroupRepository();
      final facade = buildFacade(repository: repo);

      await expectLater(
        facade.createProjectGroup(name: 'broken', projectKey: 'broken_key'),
        throwsA(isA<McpToolException>()),
      );

      expect(bridgeCalls, contains('deleteScriptProject'),
          reason: '目录创建成功但 DB 失败后必须回滚目录');
      final groups = await repo.getAllGroups();
      expect(groups.where((g) => g.projectKey == 'broken_key'), isEmpty,
          reason: '不能留下数据库半成品');
    });

    test('project_key 重复返回 GROUP_ALREADY_EXISTS', () async {
      final repo = FakeScriptRepository(groups: [
        ScriptGroup(
          name: 'existing',
          sortOrder: 1,
          createdAt: DateTime.now(),
          modifiedAt: DateTime.now(),
          projectKey: 'dup_key',
          isProject: true,
        ),
      ]);
      final facade = buildFacade(repository: repo);
      await expectLater(
        facade.createProjectGroup(name: 'another', projectKey: 'dup_key'),
        throwsA(isA<McpToolException>()
            .having((e) => e.code, 'code', McpErrorCodes.groupAlreadyExists)),
      );
    });

    test('saveProjectFile 越界路径返回 PROJECT_PATH_INVALID', () async {
      final repo = FakeScriptRepository(groups: [
        ScriptGroup(
          id: 1,
          name: 'p',
          sortOrder: 1,
          createdAt: DateTime.now(),
          modifiedAt: DateTime.now(),
          projectKey: 'proj',
          mainFilePath: 'main.py',
          isProject: true,
        ),
      ]);
      final facade = buildFacade(repository: repo);
      await expectLater(
        facade.saveProjectFile(
            projectKey: 'proj', path: '../escape.py', content: 'x'),
        throwsA(isA<McpToolException>()
            .having((e) => e.code, 'code', McpErrorCodes.projectPathInvalid)),
      );
      await expectLater(
        facade.saveProjectFile(
            projectKey: 'proj', path: r'lib\client.py', content: 'x'),
        throwsA(isA<McpToolException>()
            .having((e) => e.code, 'code', McpErrorCodes.projectPathInvalid)),
      );
    });
  });

  group('网络记录脱敏', () {
    HttpRecord record() => HttpRecord(
          id: 'rec-1',
          timestamp: DateTime.utc(2026, 9, 29),
          method: 'GET',
          url: 'https://api.example.com/v1/data'
              '?api_key=secret123&page=2&x-github-token=gh_abc#frag',
          requestHeaders: {
            'Authorization': 'Bearer top-secret',
            'X-Api-Key': 'key-123',
            'Accept': 'application/json',
          },
          requestBody: 'request-body-content',
          statusCode: 200,
          responseBodyPreview: 'response-body-content',
          responseBodyBytes: 100,
        );

    test('默认摘要不包含请求头与请求体', () async {
      final facade = buildFacade(networkRecords: [record()]);
      final page = await facade.listNetworkRecords(McpNetworkQuery());
      final summary = page.items.single;
      expect(summary.containsKey('request_headers'), isFalse);
      expect(summary.containsKey('request_body'), isFalse);
      expect(summary['redacted'], isTrue);
      expect(summary['status_code'], 200);
    });

    test('URL 脱敏：敏感查询参数打码、非敏感保留、fragment 丢弃', () async {
      final facade = buildFacade(networkRecords: [record()]);
      final page = await facade.listNetworkRecords(McpNetworkQuery());
      final url = page.items.single['url'] as String;
      expect(url, contains('api_key=<redacted>'));
      expect(url, contains('page=2'));
      expect(url, contains('x-github-token=<redacted>'));
      expect(url, isNot(contains('secret123')));
      expect(url, isNot(contains('gh_abc')));
      expect(url, isNot(contains('#frag')));
    });

    test('URL 脱敏：userinfo（user:pass@）被移除', () async {
      final record = HttpRecord(
        id: 'rec-2',
        timestamp: DateTime.utc(2026, 9, 29),
        method: 'GET',
        url: 'https://user:secret%20pass@files.example.com/download?a=1',
        requestHeaders: const {},
      );
      final facade = buildFacade(networkRecords: [record]);
      final detail = await facade.getNetworkRecord('rec-2');
      expect(detail.url, 'https://files.example.com/download?a=1');
      expect(detail.url, isNot(contains('user:')));
      expect(detail.url, isNot(contains('secret')));
    });

    test('详情脱敏 Authorization 与 X-Api-Key', () async {
      final facade = buildFacade(networkRecords: [record()]);
      final detail = await facade.getNetworkRecord('rec-1', includeBody: true);

      expect(detail.requestHeaders!['Authorization'], '<redacted>');
      expect(detail.requestHeaders!['X-Api-Key'], '<redacted>');
      expect(detail.requestHeaders!['Accept'], 'application/json');
      expect(detail.requestBody, 'request-body-content');
      expect(detail.redacted, isTrue);
    });

    test('记录不存在返回 NETWORK_RECORD_NOT_FOUND', () async {
      final facade = buildFacade(networkRecords: [record()]);
      await expectLater(
        facade.getNetworkRecord('nope'),
        throwsA(isA<McpToolException>().having(
            (e) => e.code, 'code', McpErrorCodes.networkRecordNotFound)),
      );
    });
  });

  group('包安装', () {
    test('async installation failure remains queryable with the accepted id',
        () async {
      final registry = McpOperationRegistry();
      final packages = FakePackageRepository(
          installResult:
              const PackageInstallResult(success: false, message: 'failed'));
      final accepted = await buildFacade(
              operationRegistry: registry, packageRepository: packages)
          .installPackage(packageName: 'missing');
      expect(accepted.accepted, isTrue);
      await Future<void>.delayed(Duration.zero);
      final operation = registry.find(accepted.operationId!)!;
      expect(operation.status.name, 'failed');
      expect(operation.result!['success'], isFalse);
    });
    test('请求非当前后端返回 PACKAGE_BACKEND_UNAVAILABLE', () async {
      final facade = buildFacade(
          packageRepository:
              FakePackageRepository(activeBackendId: 'chaquopy'));
      await expectLater(
        facade.installPackage(packageName: 'requests', backend: 'linux_like'),
        throwsA(isA<McpToolException>().having(
            (e) => e.code, 'code', McpErrorCodes.packageBackendUnavailable)),
      );
    });

    test('并发安装返回 PACKAGE_INSTALL_BUSY，且排队串行执行', () async {
      final packages = GatedInstallRepository();
      final facade = buildFacade(packageRepository: packages);

      final first = facade.installPackage(packageName: 'requests');
      // 微任务让第一个安装进入队列后再发第二个。
      await Future<void>.delayed(Duration.zero);
      await expectLater(
        facade.installPackage(packageName: 'flask'),
        throwsA(isA<McpToolException>()
            .having((e) => e.code, 'code', McpErrorCodes.packageInstallBusy)),
      );

      packages.gate.complete();
      final result = await first;
      expect(result.accepted, isTrue);
      await Future<void>.delayed(Duration.zero);
    });

    test('包名非法返回 INVALID_ARGUMENT', () async {
      final facade = buildFacade();
      await expectLater(
        facade.installPackage(packageName: 'bad name!'),
        throwsA(isA<McpToolException>()
            .having((e) => e.code, 'code', McpErrorCodes.invalidArgument)),
      );
      await expectLater(
        facade.installPackage(packageName: 'requests', version: '1..bad..'),
        throwsA(isA<McpToolException>()
            .having((e) => e.code, 'code', McpErrorCodes.invalidArgument)),
      );
      await expectLater(
        facade.installPackage(packageName: 'requests', indexUrl: 'ftp://x'),
        throwsA(isA<McpToolException>()
            .having((e) => e.code, 'code', McpErrorCodes.invalidArgument)),
      );
    });

    test('index_url 携带 userinfo（user:pass@）被拒绝', () async {
      final facade = buildFacade();
      await expectLater(
        facade.installPackage(
          packageName: 'requests',
          indexUrl: 'https://user:password@pypi.example.com/simple',
        ),
        throwsA(isA<McpToolException>()
            .having((e) => e.code, 'code', McpErrorCodes.invalidArgument)),
      );
    });

    test('安装登记长任务：返回 operation_id 并在注册表可查', () async {
      final registry = McpOperationRegistry();
      final packages = GatedInstallRepository();
      final facade =
          buildFacade(operationRegistry: registry, packageRepository: packages);

      final result = await facade.installPackage(packageName: 'requests');

      expect(result.operationId, isNotNull);
      final operation = registry.find(result.operationId!);
      expect(operation, isNotNull);
      expect(result.toMap()['accepted'], isTrue);
      expect(result.toMap().containsKey('success'), isFalse);
      expect(operation!.status.name, 'running');
      expect(operation.description, contains('requests'));
      packages.emitProgress(const PackageInstallProgress(
          status: 'running', message: 'downloading'));
      await Future<void>.delayed(Duration.zero);
      expect(operation.progressMessages.last, contains('downloading'));
      packages.gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(operation.status.name, 'succeeded');
      expect(operation.result!['success'], isTrue);
    });
  });

  group('文件系统只读访问', () {
    test('content:// 与相对路径被拒绝', () async {
      final facade = buildFacade();
      await expectLater(
        facade.listAccessibleDirectory(path: 'content://media/external'),
        throwsA(isA<McpToolException>()
            .having((e) => e.code, 'code', McpErrorCodes.invalidArgument)),
      );
      await expectLater(
        facade.listAccessibleDirectory(path: 'relative/path'),
        throwsA(isA<McpToolException>()
            .having((e) => e.code, 'code', McpErrorCodes.invalidArgument)),
      );
      await expectLater(
        facade.readAccessibleFile(path: '/a/../../etc/passwd'),
        throwsA(isA<McpToolException>()
            .having((e) => e.code, 'code', McpErrorCodes.invalidArgument)),
      );
    });

    test('二进制文件（含 NUL 字节）返回 isBinary 且不带内容', () async {
      fileBytes = [0x50, 0x4b, 0x00, 0x03];
      final facade = buildFacade();
      final content =
          await facade.readAccessibleFile(path: '/storage/emulated/0/a.zip');
      expect(content.isBinary, isTrue);
      expect(content.content, isNull);
      expect(content.size, 4);
    });

    test('文本文件按 UTF-8 解码（含中文）', () async {
      fileBytes = utf8.encode('print("你好")');
      final facade = buildFacade();
      final content =
          await facade.readAccessibleFile(path: '/storage/emulated/0/a.py');
      expect(content.isBinary, isFalse);
      expect(content.content, 'print("你好")');
    });

    test('超过 max_bytes 截断并标记 truncated', () async {
      fileBytes = utf8.encode('abcdefghij');
      final facade = buildFacade();
      final content = await facade.readAccessibleFile(
          path: '/storage/emulated/0/a.txt', maxBytes: 4);
      expect(content.truncated, isTrue);
      expect(content.size, 10, reason: 'size 是原始文件大小');
      expect(content.content, 'abcd');
    });

    test('先探测文件大小：超过硬上限直接拒绝，不触发文件读取', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(
        _listDirectoryChannel,
        (message) async {
          final parent = (message as List<Object?>).single as String;
          expect(parent, '/storage/emulated/0/Download');
          return <Object?>[
            [
              _pigeonEntry('/storage/emulated/0/Download/huge.bin', false,
                  5 * 1024 * 1024)
            ],
          ];
        },
      );
      final facade = buildFacade();
      await expectLater(
        facade.readAccessibleFile(
            path: '/storage/emulated/0/Download/huge.bin'),
        throwsA(isA<McpToolException>()
            .having((e) => e.code, 'code', McpErrorCodes.fileTooLarge)),
      );
      expect(bridgeCalls, isNot(contains('readFileBounded')));
    });

    test(
        'unknown file size uses native bounded read without unbounded fallback',
        () async {
      rejectBoundedRead = true;
      await expectLater(
          buildFacade().readAccessibleFile(path: '/unknown/file'),
          throwsA(isA<McpToolException>()
              .having((e) => e.code, 'code', McpErrorCodes.fileTooLarge)));
      expect(bridgeCalls, contains('readFileBounded'));
      expect(bridgeCalls, isNot(contains('readFilePickerFile')));
    });

    test(
        'directory native error is not reported as an accessible empty directory',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(_listDirectoryChannel,
              (_) async => <Object?>['1043', 'permission denied', null]);
      await expectLater(
          buildFacade().listAccessibleDirectory(path: '/denied'),
          throwsA(isA<McpToolException>().having(
              (e) => e.code, 'code', McpErrorCodes.directoryNotAccessible)));
    });

    test('目标是目录时返回 FILE_NOT_FOUND 而不是读取', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(
        _listDirectoryChannel,
        (message) async {
          return <Object?>[
            [_pigeonEntry('/storage/emulated/0/docs', true, 0)],
          ];
        },
      );
      final facade = buildFacade();
      await expectLater(
        facade.readAccessibleFile(path: '/storage/emulated/0/docs'),
        throwsA(isA<McpToolException>()
            .having((e) => e.code, 'code', McpErrorCodes.fileNotFound)),
      );
    });

    test('listAccessibleDirectory 显式返回 accessible：空目录不为权限受限', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(
        _listDirectoryChannel,
        (message) async => <Object?>[<Object?>[]],
      );
      final facade = buildFacade();
      final listing = await facade.listAccessibleDirectory(
          path: '/storage/emulated/0/empty');
      expect(listing.accessible, isTrue);
      expect(listing.page.items, isEmpty);
      expect(listing.page.nextCursor, isNull);
    });
  });
}

pigeon.NativeAppFileEntry _pigeonEntry(
    String path, bool isDirectory, int size) {
  return pigeon.NativeAppFileEntry(
    path: path,
    name: path.split('/').last,
    isDirectory: isDirectory,
    size: size,
    modifiedAtMillis: 1000,
  );
}
