import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:python_runner/features/backup/application/backup_controller.dart';
import 'package:python_runner/features/backup/application/backup_recovery.dart';
import 'package:python_runner/features/backup/domain/backup_manifest.dart';
import 'package:python_runner/features/backup/domain/backup_selection.dart';
import 'package:python_runner/features/backup/domain/restore_plan.dart';
import 'package:python_runner/features/backup/infrastructure/backup_config_store.dart';
import 'package:python_runner/features/backup/infrastructure/backup_native_bridge.dart';
import 'package:python_runner/features/backup/infrastructure/webdav_client.dart';
import 'package:python_runner/services/database_service.dart';
import 'package:python_runner/services/native_bridge.dart';
import 'package:python_runner/services/native_bridge_contract.dart';
import 'package:python_runner/services/workspace_access.dart';
import 'package:python_runner/models/script_group.dart';
import 'package:python_runner/providers/script_project_provider.dart';
import 'package:python_runner/services/script_project_service.dart';

import 'backup_manifest_test.dart' show manifestFixture, fileJson;
import 'backup_config_test.dart' show MemorySecrets;
import 'restore_planner_test.dart' show localScript, localGroup;
import 'project_restore_refresh_test.dart' show ProjectFiles;

class FakeBackupNative extends BackupNativeBridge {
  FakeBackupNative(this.dir);
  final Directory dir;
  bool inventoryUnavailable = false;
  final calls = <String>[];
  final pending = <String>[];
  String? failure;
  String? reservation;
  bool owner = false;
  bool pickerCancelled = false;
  bool legacy = false;
  BackupManifest manifest = BackupManifest.fromJson(manifestFixture());
  Completer<void>? stageWait;
  Completer<void>? commitWait;
  Completer<void>? createWait;
  Future<void> Function()? onFinalize;
  Map<String, dynamic>? metadata;
  final progressEvents = StreamController<BackupProgress>.broadcast(sync: true);

  Future<void> seedScriptFiles() async {
    await Directory('${dir.path}/scripts').create(recursive: true);
    for (final script in manifest.scripts) {
      await File('${dir.path}/scripts/${script.name}')
          .writeAsString('print(1)');
    }
  }

  Future<List<String>> listScriptFiles() async {
    if (inventoryUnavailable) {
      throw const FileSystemException('inventory unavailable');
    }
    final root = Directory('${dir.path}/scripts');
    if (!await root.exists()) return [];
    return (await root.list().toList())
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .toList();
  }

  @override
  Stream<BackupProgress> get progress => progressEvents.stream;
  void check(String call) {
    calls.add(call);
    if (failure == call) {
      throw PlatformException(
        code: call == 'save' ? 'PERMISSION_LOST' : 'INJECTED',
      );
    }
  }

  @override
  Future<BackupDocument?> pickBackupDirectory() async {
    check('pickDirectory');
    return pickerCancelled
        ? null
        : const BackupDocument(uri: 'content://tree', name: 'Backups');
  }

  @override
  Future<BackupDocument?> pickBackupArchive() async {
    check('pickArchive');
    return pickerCancelled
        ? null
        : const BackupDocument(uri: 'content://zip', name: 'test.zip');
  }

  @override
  Future<void> acquireWorkspace(String id) async {
    check('acquire');
    expect(owner, false);
    expect(reservation == null || reservation == id, true);
    owner = true;
    reservation = id;
  }

  @override
  Future<void> releaseWorkspace(String id) async {
    check('release');
    owner = false;
  }

  @override
  Future<CreatedBackupArchive> createArchive(
    String id,
    Map<String, dynamic> value,
  ) async {
    check('create');
    await createWait?.future;
    expect(owner, true);
    reservation = id;
    metadata = value;
    for (final script in value['scripts'] as List) {
      if (!await File('${dir.path}/scripts/${script['name']}').exists()) {
        throw PlatformException(code: 'SOURCE_MISSING');
      }
    }
    final selected = BackupSelection(
      scriptNames: (value['scripts'] as List).map((s) => s['name'] as String),
      groupIds: (value['groups'] as List).map((g) => g['id'] as int),
    ).select(manifest);
    final full = BackupManifest.fromJson({
      ...value,
      'files': selected.files.map((f) => f.toJson()).toList(),
    });
    final path = '${dir.path}/$id.zip';
    await File(path).writeAsString('zip fixture');
    return CreatedBackupArchive(
      path: path,
      fileName: 'python-runner-backup-$id.zip',
      manifest: full,
    );
  }

  @override
  Future<BackupDocument> saveArchiveToDirectory(
    String id,
    String path,
    String tree,
  ) async {
    check('save');
    expect(owner, false);
    expect(await File(path).exists(), true);
    return const BackupDocument(uri: 'content://saved', name: 'backup.zip');
  }

  @override
  Future<String> createTransferFile(String id) async {
    check('transfer');
    reservation = id;
    return '${dir.path}/$id.zip';
  }

  @override
  Future<StagedBackupArchive> stageArchive(
    String id,
    String source,
    String displayName,
  ) async {
    check('stage');
    reservation = id;
    await stageWait?.future;
    return StagedBackupArchive(
      manifest: manifest,
      legacy: legacy,
      stagingId: id,
    );
  }

  @override
  Future<void> commitStaged(String id, Iterable<RestoreFileMove> moves) async {
    pending.add(id);
    check('commit');
    expect(owner, true);
    await commitWait?.future;
  }

  @override
  Future<void> finalizeRestore(String id) async {
    check('finalize');
    await onFinalize?.call();
    pending.remove(id);
    reservation = null;
  }

  @override
  Future<void> rollbackRestore(String id) async {
    check('rollback');
    pending.remove(id);
    reservation = null;
  }

  @override
  Future<void> discardOperation(String id) async {
    check('discard');
    expect(pending, isNot(contains(id)));
    reservation = null;
    final file = File('${dir.path}/$id.zip');
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> cancelOperation(String id) async {
    check('cancel');
    stageWait?.complete();
    createWait?.complete();
  }

  @override
  Future<List<String>> pendingRestores() async {
    check('pending');
    return List.of(pending);
  }

  @override
  Future<void> cleanupAbandonedOperations() async {
    check('cleanup');
    expect(owner, false);
    expect(reservation, null);
  }

  @override
  Future<String> scriptsRoot() async {
    check('root');
    return '${dir.path}/scripts';
  }
}

class MemoryDav extends WebDavClient {
  MemoryDav(WebDavConfig config) : super(config: config, password: 'unused');
  final calls = <String>[];
  @override
  Future<RemoteBackup> upload(
    File file, {
    required String fileName,
    required String operationId,
    BackupCancellation? cancellation,
    BackupTransferProgress? onProgress,
  }) async {
    calls.add('upload');
    expect(await file.exists(), true);
    return RemoteBackup(
      uri: config.folderUri.resolve(fileName),
      name: fileName,
      size: await file.length(),
    );
  }

  @override
  Future<void> download(
    RemoteBackup backup,
    File destination, {
    BackupCancellation? cancellation,
    BackupTransferProgress? onProgress,
  }) async {
    calls.add('download');
    await destination.writeAsString('zip fixture');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late WorkspaceAccess gate;
  late DatabaseService db;
  late FakeBackupNative native;
  late BackupController controller;
  late BackupConfigStore config;
  late MemoryDav dav;
  var running = false;
  var reloads = 0;
  final refreshedProjects = <ScriptGroup>[];
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('backup_controller_');
    gate = WorkspaceAccess();
    db = DatabaseService(
      databasePath: '${dir.path}/test.db',
      workspaceAccess: gate,
    );
    native = FakeBackupNative(dir);
    SharedPreferences.setMockInitialValues({});
    config = BackupConfigStore(
      preferences: await SharedPreferences.getInstance(),
      storage: MemorySecrets(),
    );
    dav = MemoryDav(
      WebDavConfig(baseUri: Uri.parse('https://dav.example'), username: 'me'),
    );
    running = false;
    reloads = 0;
    refreshedProjects.clear();
    controller = BackupController(
      database: db,
      native: native,
      configStore: config,
      listScriptFiles: native.listScriptFiles,
      workspaceAccess: gate,
      webDavFactory: (_, _) => dav,
      isExecutionRunning: () => running,
      reloadWorkspace: () async {
        reloads++;
      },
      reloadRestoredProjects: (groups) async {
        refreshedProjects.addAll(groups);
        await ScriptProjectProvider.refreshAfterRestore(groups);
      },
    );
  });
  tearDown(() async {
    controller.dispose();
    await native.progressEvents.close();
    await db.closeForTest();
    await dir.delete(recursive: true);
  });
  Future<void> seed() async {
    await native.seedScriptFiles();
    for (final group in native.manifest.groups) {
      await db.createGroup(group);
    }
    for (final script in native.manifest.scripts) {
      await db.upsertScript(script);
    }
  }

  test(
    'backup library excludes deleted script rows without deleting metadata',
    () async {
      await seed();
      final missing = localScript('deleted.py', groupId: 81);
      await db.upsertScript(missing);

      await controller.loadLibrary();

      expect(controller.state.error, isNull);
      expect(
        controller.state.library!.scripts.map((s) => s.name),
        unorderedEquals(['alone.py', '你好.py']),
      );
      expect(
        controller.state.selection.scriptNames,
        isNot(contains('deleted.py')),
      );
      expect(controller.state.library!.groups, hasLength(3));
      expect((await db.getScript('deleted.py'))!.toMap(), missing.toMap());
    },
  );

  for (final cloud in [false, true]) {
    test(
      '${cloud ? 'cloud' : 'local'} backup includes renamed files before workspace reload',
      () async {
        await seed();
        await controller.loadLibrary();
        await File('${dir.path}/scripts/alone.py')
            .rename('${dir.path}/scripts/renamed.py');
        // The archive boundary knows the actual payload, while SQLite retains
        // the old name until the workspace is next loaded.
        final manifestJson = native.manifest.toJson();
        (manifestJson['scripts'] as List).firstWhere(
          (s) => s['name'] == 'alone.py',
        )['name'] = 'renamed.py';
        (manifestJson['files'] as List).firstWhere(
          (f) => f['path'] == 'scripts/alone.py',
        )['path'] = 'scripts/renamed.py';
        native.manifest = BackupManifest.fromJson(manifestJson);
        if (cloud) {
          await controller.saveWebDavProfile(dav.config, password: 'unused');
          await controller.backupWebDav();
        } else {
          await controller.chooseLocalDirectory();
          await controller.exportLocal();
        }
        expect(controller.state.error, isNull);
        expect(
          controller.state.lastResult?.kind,
          cloud ? BackupResultKind.uploaded : BackupResultKind.exportedLocal,
        );
        expect(
          (native.metadata!['scripts'] as List).map((s) => s['name']),
          unorderedEquals(['你好.py', 'renamed.py']),
        );
        expect(
          (native.metadata!['scripts'] as List).firstWhere(
            (s) => s['name'] == '你好.py',
          )['runCount'],
          12,
        );
        expect(await db.getScript('alone.py'), isNotNull);
        expect(await db.getScript('renamed.py'), isNull);
      },
    );

    test(
      '${cloud ? 'cloud' : 'local'} backup refreshes files after selection and aborts on inventory failure',
      () async {
        await seed();
        await controller.loadLibrary();
        await File('${dir.path}/scripts/alone.py').delete();
        if (cloud) {
          await controller.saveWebDavProfile(dav.config, password: 'unused');
        } else {
          await controller.chooseLocalDirectory();
        }
        native.inventoryUnavailable = true;
        if (cloud) {
          await controller.backupWebDav();
        } else {
          await controller.exportLocal();
        }
        expect(controller.state.error, isNotNull);
        expect(controller.state.lastResult, isNull);
        expect(native.metadata, isNull);
        expect(dav.calls, isEmpty);
        expect(native.owner, false);
        expect(native.reservation, isNull);

        native.inventoryUnavailable = false;
        if (cloud) {
          await controller.backupWebDav();
        } else {
          await controller.exportLocal();
        }
        expect(controller.state.error, isNull);
        expect(
          controller.state.lastResult?.kind,
          cloud ? BackupResultKind.uploaded : BackupResultKind.exportedLocal,
        );
        expect((native.metadata!['scripts'] as List).map((s) => s['name']), [
          '你好.py',
        ]);
        expect(await db.getScript('alone.py'), isNotNull);
      },
    );

    test(
      '${cloud ? 'cloud' : 'local'} backup ignores stale rows in a selected group',
      () async {
        await seed();
        await controller.loadLibrary();
        // File-manager deletion/rename leaves metadata behind, even after the
        // workspace stops displaying the old script. Refresh at execution time.
        await db.upsertScript(localScript('deleted.py', groupId: 81));
        controller.selectLibrary(BackupSelection(groupIds: {81}));
        if (cloud) {
          await controller.saveWebDavProfile(dav.config, password: 'unused');
          await controller.backupWebDav();
        } else {
          await controller.chooseLocalDirectory();
          await controller.exportLocal();
        }

        expect(controller.state.error, isNull);
        expect(
          controller.state.lastResult?.kind,
          cloud ? BackupResultKind.uploaded : BackupResultKind.exportedLocal,
        );
        expect((native.metadata!['scripts'] as List).map((s) => s['name']), [
          '你好.py',
        ]);
        expect(await db.getScript('deleted.py'), isNotNull);
        expect(native.owner, false);
        expect(native.reservation, isNull);
      },
    );
  }

  Future<void> cloudProfile() =>
      controller.saveWebDavProfile(dav.config, password: 'secret');

  test(
    'script-only restore preserves an unrelated open project dirty buffer',
    () async {
      final group = localGroup(7, 'Unrelated', project: true, key: 'unrelated');
      await db.createGroup(group);
      final bridge = ProjectFiles();
      final project = ScriptProjectProvider(
        group: group,
        service: ScriptProjectService(bridge),
      );
      addTearDown(project.dispose);
      await project.load();
      await project.selectFile('main.py');
      project.updateContent('unsaved unrelated');
      await controller.pickAndStageLocal();
      await controller.updateRestoreSelection(
        BackupSelection(scriptNames: {'alone.py'}),
      );
      await controller.confirmRestore(confirmed: true);
      expect(refreshedProjects, isEmpty);
      expect(project.content, 'unsaved unrelated');
      expect(project.dirty, true);
      expect(project.selectedPath, 'main.py');
      expect(bridge.loads, 1);
    },
  );
  test(
    'refresh callback receives only overwritten existing project targets',
    () async {
      await db.createGroup(
        localGroup(7, 'Project', project: true, key: 'donor_project'),
      );
      await db.createGroup(
        localGroup(8, 'Unrelated', project: true, key: 'unrelated'),
      );
      await controller.pickAndStageLocal();
      await controller.updateRestorePolicy(RestoreConflictPolicy.overwrite);
      await controller.confirmRestore(confirmed: true);
      expect(refreshedProjects.map((g) => g.id), [7]);
      expect(refreshedProjects.single.mainFilePath, 'src/main.py');
    },
  );
  for (final releaseFailure in [false, true]) {
    test(
      'cancellation preserves ${releaseFailure ? 'release' : 'discard'} recovery error and retry ID',
      () async {
        late Future<void> operation;
        if (releaseFailure) {
          await seed();
          await controller.chooseLocalDirectory();
          native.createWait = Completer<void>();
          native.failure = 'release';
          operation = controller.exportLocal();
        } else {
          native.stageWait = Completer<void>();
          native.failure = 'discard';
          operation = controller.pickAndStageLocal();
        }
        while (!native.calls.contains(releaseFailure ? 'create' : 'stage')) {
          await Future<void>.delayed(Duration.zero);
        }
        final id = controller.state.operation!.id;
        await controller.cancel();
        await operation;
        expect(
          controller.state.error?.code,
          releaseFailure ? 'RECOVERY_REQUIRED' : 'TEMP_CLEANUP_PENDING',
        );
        expect(controller.state.lastResult!.kind, BackupResultKind.cancelled);
        expect(gate.recoveryRequired, true);
        expect(
          releaseFailure
              ? gate.pendingNativeRelease
              : gate.pendingNativeDiscard,
          id,
        );
        await expectLater(
          gate.runMutation(() async {}),
          throwsA(isA<WorkspaceRecoveryRequired>()),
        );
        native.failure = null;
        await BackupRecovery(
          database: db,
          native: native,
          workspaceAccess: gate,
        ).recover();
        expect(gate.isBusy, false);
        expect(native.reservation, null);
        expect(native.owner, false);
      },
    );
  }

  test('local export defaults to whole library including empty groups and releases before copy', () async {
    await seed();
    await controller.loadLibrary();
    await controller.chooseLocalDirectory();
    await controller.exportLocal();
    expect(native.metadata!['groups'], hasLength(3));
    expect(native.calls, [
      'pickDirectory',
      'acquire',
      'create',
      'release',
      'save',
      'discard',
    ]);
    expect(controller.state.lastResult!.kind, BackupResultKind.exportedLocal);
  });
  test('explicit selection survives reload by identity and cloud uses same validated manifest', () async {
    await seed();
    await controller.loadLibrary();
    controller.selectLibrary(BackupSelection(scriptNames: {'alone.py'}));
    await cloudProfile();
    await controller.backupWebDav();
    expect((native.metadata!['scripts'] as List).single['name'], 'alone.py');
    expect(native.metadata!['groups'], isEmpty);
    expect(dav.calls, ['upload']);
    expect(native.calls, ['acquire', 'create', 'release', 'discard']);
  });
  test(
    'empty selection releases acquire reservation without creating archive',
    () async {
      await seed();
      await controller.chooseLocalDirectory();
      await controller.loadLibrary();
      controller.selectLibrary(BackupSelection());
      await controller.exportLocal();
      expect(controller.state.error!.code, 'NOTHING_SELECTED');
      expect(native.reservation, isNull);
      expect(native.calls, ['pickDirectory', 'acquire', 'release', 'discard']);
    },
  );
  test('empty ordinary group restores with no file moves', () async {
    await controller.pickAndStageLocal();
    await controller.updateRestoreSelection(BackupSelection(groupIds: {82}));
    await controller.confirmRestore(confirmed: true);
    expect((await db.getAllGroups()).single.name, 'Empty');
    expect(await db.getAllScripts(), isEmpty);
  });
  test('generated project identity stays attached to donor across selection and policy changes', () async {
    final json = native.manifest.toJson();
    (json['groups'] as List).add(<String, dynamic>{
      ...((json['groups'] as List).last as Map<String, dynamic>),
      'id': 84,
      'name': 'Other project',
      'projectKey': 'other_donor',
      'mainFilePath': null,
    });
    (json['files'] as List).add({
      'path': 'projects/other_donor',
      'isDirectory': true,
      'size': 0,
      'sha256': null,
      'modifiedAt': 1,
    });
    native.manifest = BackupManifest.fromJson(json);
    await db.createGroup(
      localGroup(7, 'Project', project: true, key: 'donor_project'),
    );
    await controller.pickAndStageLocal();
    final initial = {
      for (final g in controller.state.preview!.plan.groups.where(
        (g) => g.group.isProject,
      ))
        g.sourceId: g.group.projectKey,
    };
    await controller.updateRestoreSelection(BackupSelection(groupIds: {84}));
    expect(
      controller.state.preview!.plan.groups.single.group.projectKey,
      initial[84],
    );
    await controller.updateRestoreSelection(
      BackupSelection.all(native.manifest),
    );
    await controller.updateRestorePolicy(RestoreConflictPolicy.skip);
    expect(
      controller.state.preview!.plan.groups
          .singleWhere((g) => g.sourceId == 84)
          .group
          .projectKey,
      initial[84],
    );
    await controller.updateRestorePolicy(RestoreConflictPolicy.keepBoth);
    expect(
      controller.state.preview!.plan.groups
          .singleWhere((g) => g.sourceId == 83)
          .group
          .projectKey,
      initial[83],
    );
  });
  test('cancelled directory permission keeps existing tree; stale tree gives specific error', () async {
    await seed();
    await controller.chooseLocalDirectory();
    native.pickerCancelled = true;
    await controller.chooseLocalDirectory();
    expect(controller.state.localDirectory!.uri, 'content://tree');
    native.failure = 'save';
    await controller.exportLocal();
    expect(controller.state.error!.code, 'PERMISSION_LOST');
    expect(native.calls.last, 'discard');
  });
  test('restore commits files then metadata marker then finalizes before forgetting', () async {
    await controller.pickAndStageLocal();
    final id = controller.state.preview!.operationId;
    native.onFinalize = () async {
      expect(await db.committedRestoreIds(), {id});
    };
    await controller.confirmRestore(confirmed: true);
    expect(native.calls, [
      'pickArchive',
      'stage',
      'acquire',
      'root',
      'commit',
      'finalize',
      'release',
    ]);
    expect(await db.getAllScripts(), hasLength(2));
    expect(await db.committedRestoreIds(), isEmpty);
    expect(controller.state.preview, isNull);
    expect(reloads, 1);
  });
  test('remote download stages through native-owned transfer using the same operation', () async {
    await cloudProfile();
    await controller.downloadAndStageRemote(
      RemoteBackup(
        uri: dav.config.folderUri.resolve('python-runner-backup-remote.zip'),
        name: 'python-runner-backup-remote.zip',
        size: 10,
      ),
    );
    expect(native.calls, ['transfer', 'stage']);
    expect(dav.calls, ['download']);
    expect(
      controller.state.preview!.manifest.toJson(),
      native.manifest.toJson(),
    );
    await controller.discardPreview();
    expect(native.reservation, isNull);
  });
  test('changed DB and file-only revision refresh preview and require another confirmation', () async {
    await controller.pickAndStageLocal();
    await db.upsertScript(localScript('alone.py'));
    await controller.confirmRestore(confirmed: true);
    expect(controller.state.lastResult!.kind, BackupResultKind.previewUpdated);
    expect(native.calls, isNot(contains('commit')));
    expect(
      controller.state.preview!.plan.scripts.any(
        (s) => s.script.name == 'alone (restored 1).py',
      ),
      true,
    );
    final snapshot = (await db.readBackupSnapshot()).toMetadataJson(
      createdAt: DateTime.utc(2020),
    );
    const channel = MethodChannel(NativeBridgeContract.channelName);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => true);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await NativeBridge.named(workspaceAccess: gate).saveProjectFile(
      'project',
      'main.py',
      'modified by direct native/MCP route',
    );
    expect(
      (await db.readBackupSnapshot()).toMetadataJson(
        createdAt: DateTime.utc(2020),
      ),
      snapshot,
    );
    await controller.confirmRestore(confirmed: true);
    expect(controller.state.lastResult!.kind, BackupResultKind.previewUpdated);
    expect(native.calls, isNot(contains('commit')));
    await controller.confirmRestore(confirmed: true);
    expect(native.calls, contains('commit'));
  });
  test('requires explicit confirmation and rejects active tasks without discarding preview', () async {
    await controller.pickAndStageLocal();
    await controller.confirmRestore(confirmed: false);
    expect(native.calls, isNot(contains('commit')));
    running = true;
    await controller.confirmRestore(confirmed: true);
    expect(controller.state.error!.code, 'EXECUTION_RUNNING');
    expect(controller.state.preview, isNotNull);
    expect(native.calls, isNot(contains('acquire')));
  });
  test(
    'SQLite failure rolls back native before release and leaves no metadata',
    () async {
      await controller.pickAndStageLocal();
      await (await db.database).execute(
        "CREATE TRIGGER fail_restore BEFORE INSERT ON scripts BEGIN SELECT RAISE(ABORT, 'fail'); END",
      );
      await controller.confirmRestore(confirmed: true);
      expect(native.calls, [
        'pickArchive',
        'stage',
        'acquire',
        'root',
        'commit',
        'rollback',
        'release',
      ]);
      expect(await db.getAllScripts(), isEmpty);
      expect(await db.getAllGroups(), isEmpty);
      expect(await db.committedRestoreIds(), isEmpty);
    },
  );
  test('native commit failure rolls back before release', () async {
    await controller.pickAndStageLocal();
    native.failure = 'commit';
    await controller.confirmRestore(confirmed: true);
    expect(native.calls, [
      'pickArchive',
      'stage',
      'acquire',
      'root',
      'commit',
      'rollback',
      'release',
    ]);
    expect(await db.getAllScripts(), isEmpty);
  });
  test(
    'committed cleanup failure never rolls back; keeps journal and marker',
    () async {
      await controller.pickAndStageLocal();
      final id = controller.state.preview!.operationId;
      native.failure = 'finalize';
      await controller.confirmRestore(confirmed: true);
      expect(
        controller.state.lastResult!.kind,
        BackupResultKind.restoredCleanupPending,
      );
      expect(native.calls, isNot(contains('rollback')));
      expect(native.pending, [id]);
      await gate.runExclusive(() async {
        expect(await db.committedRestoreIds(), {id});
      }, recovery: true);
      expect(gate.recoveryRequired, true);
    },
  );
  test('rollback failure preserves journal and blocks workspace', () async {
    await controller.pickAndStageLocal();
    native.failure = 'rollback';
    await (await db.database).execute(
      "CREATE TRIGGER fail_restore BEFORE INSERT ON scripts BEGIN SELECT RAISE(ABORT, 'fail'); END",
    );
    await controller.confirmRestore(confirmed: true);
    expect(gate.recoveryRequired, true);
    expect(native.pending, isNotEmpty);
    await expectLater(
      gate.runMutation(() async {}),
      throwsA(isA<WorkspaceRecoveryRequired>()),
    );
  });
  test(
    'cancel staging discards reservation and cannot publish stale preview',
    () async {
      native.stageWait = Completer<void>();
      final staging = controller.pickAndStageLocal();
      while (!native.calls.contains('stage')) {
        await Future<void>.delayed(Duration.zero);
      }
      await controller.cancel();
      await staging;
      expect(controller.state.preview, isNull);
      expect(native.calls, ['pickArchive', 'stage', 'cancel', 'discard']);
      expect(native.reservation, isNull);
    },
  );
  test('legacy ZIP recommends Python entrypoint and allows validated choice or none', () async {
    final json = native.manifest.toJson();
    json['scripts'] = <Map<String, dynamic>>[];
    json['groups'] = [
      <String, dynamic>{
        ...(json['groups'] as List).last as Map<String, dynamic>,
        'mainFilePath': null,
      },
    ];
    json['files'] = [
      'z.py',
      'src/main.py',
      'app.py',
      'run.py',
      '__main__.py',
    ].map((p) => fileJson('projects/donor_project/$p')).toList();
    native.manifest = BackupManifest.fromJson(json);
    native.legacy = true;
    await controller.pickAndStageLocal();
    expect(controller.state.preview!.legacyEntryPoint, 'src/main.py');
    expect(controller.state.preview!.legacyEntryPoints, [
      'src/main.py',
      'app.py',
      'run.py',
      '__main__.py',
      'z.py',
    ]);
    await controller.updateLegacyEntryPoint('app.py');
    expect(
      controller.state.preview!.plan.groups.single.group.mainFilePath,
      'app.py',
    );
    await controller.updateLegacyEntryPoint(null);
    expect(
      controller.state.preview!.plan.groups.single.group.mainFilePath,
      isNull,
    );
    await controller.updateLegacyEntryPoint('../bad.py');
    expect(controller.state.error!.code, 'INVALID_ENTRYPOINT');
  });
  test(
    'editing a profile without password preserves the secure credential',
    () async {
      await cloudProfile();
      await controller.saveWebDavProfile(
        WebDavConfig(
          baseUri: Uri.parse('https://other.example'),
          username: 'changed',
        ),
      );
      expect(await config.readPassword(), 'secret');
      expect(config.loadProfile()!.username, 'changed');
    },
  );
  test('legacy name edit queues with entrypoint and never overwrites a same-name project', () async {
    final json = native.manifest.toJson();
    json['scripts'] = [];
    json['groups'] = [(json['groups'] as List).last];
    json['files'] = (json['files'] as List)
        .where((f) => (f['path'] as String).startsWith('projects/'))
        .toList();
    native.manifest = BackupManifest.fromJson(json);
    native.legacy = true;
    await db.createGroup(
      localGroup(3, 'Existing', project: true, key: 'existing'),
    );
    await controller.pickAndStageLocal();
    await Future.wait([
      controller.updateLegacyProjectName('Existing'),
      controller.updateLegacyEntryPoint(null),
      controller.updateRestorePolicy(RestoreConflictPolicy.overwrite),
    ]);
    final preview = controller.state.preview!;
    expect(preview.manifest.groups.single.name, 'Existing');
    expect(preview.plan.groups.single.group.name, isNot('Existing'));
    expect(preview.plan.groups.single.action, RestoreAction.create);
    expect(preview.plan.groups.single.group.mainFilePath, isNull);
    expect(preview.plan.fileMoves.single.overwrite, false);
    await controller.updateLegacyProjectName('');
    expect(controller.state.error!.code, 'INVALID_PROJECT_NAME');
    expect(controller.state.preview!.manifest.groups.single.name, 'Existing');
  });
  test('selection and policy changes queued rapidly both survive', () async {
    await controller.pickAndStageLocal();
    final selected = controller.updateRestoreSelection(
      BackupSelection(groupIds: {82}),
    );
    final policy = controller.updateRestorePolicy(
      RestoreConflictPolicy.overwrite,
    );
    await Future.wait([selected, policy]);
    expect(controller.state.preview!.selection.groupIds, {82});
    expect(controller.state.preview!.policy, RestoreConflictPolicy.overwrite);
  });
  test(
    'dispose and cancel cannot interrupt committed restore safe terminal state',
    () async {
      await controller.pickAndStageLocal();
      native.commitWait = Completer<void>();
      final restoring = controller.confirmRestore(confirmed: true);
      while (!native.calls.contains('commit')) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(controller.state.operation!.cancellable, false);
      native.progressEvents.add(
        BackupProgress(
          operationId: controller.state.operation!.id,
          stage: BackupStage.validating,
          completed: 1,
          total: 1,
        ),
      );
      expect(
        controller.state.operation!.stage,
        BackupOperationStage.committing,
      );
      await controller.cancel();
      controller.dispose();
      native.commitWait!.complete();
      await restoring;
      expect(native.calls, isNot(contains('cancel')));
      expect(native.calls.sublist(native.calls.length - 2), [
        'finalize',
        'release',
      ]);
      expect(await db.committedRestoreIds(), isEmpty);
      expect(await db.getAllScripts(), hasLength(2));
    },
  );
  test(
    'failed boot cleanup preserves commit proof and retries roll forward',
    () async {
      await (await db.database).insert('backup_restore_commits', {
        'operationId': 'yes',
        'committedAt': 1,
      });
      native.pending.add('yes');
      native.failure = 'finalize';
      final recovery = BackupRecovery(
        database: db,
        native: native,
        workspaceAccess: gate,
      );
      await expectLater(
        recovery.recover(),
        throwsA(isA<BackupRecoveryException>()),
      );
      expect(gate.recoveryRequired, true);
      expect(native.pending, ['yes']);
      await gate.runExclusive(() async {
        expect(await db.committedRestoreIds(), {'yes'});
      }, recovery: true);
      native.failure = null;
      await recovery.recover();
      expect(gate.recoveryRequired, false);
      expect(await db.committedRestoreIds(), isEmpty);
    },
  );
  test(
    'failed native owner release blocks writes until recovery retries release',
    () async {
      await seed();
      await controller.chooseLocalDirectory();
      native.failure = 'release';
      await controller.exportLocal();
      expect(gate.recoveryRequired, true);
      expect(native.owner, true);
      native.failure = null;
      await BackupRecovery(
        database: db,
        native: native,
        workspaceAccess: gate,
      ).recover();
      expect(native.owner, false);
      expect(gate.isBusy, false);
    },
  );
  test(
    'failed export temp cleanup can be retried without losing saved backup',
    () async {
      await seed();
      await controller.chooseLocalDirectory();
      native.failure = 'discard';
      await controller.exportLocal();
      expect(controller.state.lastResult!.kind, BackupResultKind.exportedLocal);
      expect(gate.recoveryRequired, true);
      native.failure = null;
      await BackupRecovery(
        database: db,
        native: native,
        workspaceAccess: gate,
      ).recover();
      expect(native.reservation, isNull);
      expect(gate.isBusy, false);
    },
  );
  test('recovery finalizes committed sessions and rolls back uncommitted before cleanup', () async {
    final raw = await db.database;
    await raw.insert('backup_restore_commits', {
      'operationId': 'yes',
      'committedAt': 1,
    });
    native.pending.addAll(['yes', 'no']);
    gate.blockForRecovery();
    await BackupRecovery(
      database: db,
      native: native,
      workspaceAccess: gate,
    ).recover();
    expect(native.calls, ['pending', 'finalize', 'rollback', 'cleanup']);
    expect(await db.committedRestoreIds(), isEmpty);
    expect(gate.recoveryRequired, false);
    await BackupRecovery(
      database: db,
      native: native,
      workspaceAccess: gate,
    ).recover();
    expect(native.calls.last, 'cleanup');
  });
}
