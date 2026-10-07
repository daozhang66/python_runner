import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:python_runner/features/files/application/script_file_manager_operations.dart';
import 'package:python_runner/features/scripts/application/script_repository.dart';
import 'package:python_runner/features/scripts/application/script_workspace_controller.dart';
import 'package:python_runner/models/app_file_entry.dart';
import 'package:python_runner/models/script_file.dart';
import 'package:python_runner/models/script_group.dart';
import 'package:python_runner/services/database_service.dart';
import 'package:python_runner/services/native_bridge.dart';
import 'package:python_runner/services/workspace_access.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DiskBridge extends NativeBridge {
  DiskBridge(this.root, WorkspaceAccess gate)
    : super.named(workspaceAccess: gate);
  final Directory root;
  bool failMutation = false;
  File script(String name) => File(p.join(root.path, 'files', 'scripts', name));
  @override
  Future<List<AppFileEntry>> getFileManagerAppDataRoots() async => [
    AppFileEntry(
      path: root.path,
      name: 'PythonRunner',
      isDirectory: true,
      size: 0,
      modifiedAt: DateTime(2026),
    ),
  ];
  @override
  Future<List<String>> listScripts() async =>
      (await script('a.py').parent.list().toList())
          .whereType<File>()
          .map((f) => p.basename(f.path))
          .where((n) => n.endsWith('.py'))
          .toList();
  @override
  Future<void> renameFileManagerEntry(String path, String newName) async {
    if (failMutation) throw const FileSystemException('rename rejected');
    final target = File(p.join(p.dirname(path), newName));
    if (await target.exists()) throw const FileSystemException('target exists');
    await File(path).rename(target.path);
  }

  @override
  Future<void> deleteFileManagerEntry(String path) async {
    if (failMutation) throw const FileSystemException('delete rejected');
    await File(path).delete();
  }

  @override
  Future<bool> renameScript(String oldName, String newName) async {
    if (failMutation) return false;
    await renameFileManagerEntry(script(oldName).path, newName);
    return true;
  }

  @override
  Future<bool> deleteScript(String name) async {
    if (failMutation) return false;
    await deleteFileManagerEntry(script(name).path);
    return true;
  }
}

class RenameFailureDatabase extends DatabaseService {
  RenameFailureDatabase({
    required super.databasePath,
    required super.workspaceAccess,
  });
  bool failRename = false;
  @override
  Future<void> renameScript(
    String oldName,
    String newName,
    String newPath,
  ) async {
    if (failRename) throw StateError('metadata write failed');
    await super.renameScript(oldName, newName, newPath);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  late Directory root;
  late DiskBridge bridge;
  late RenameFailureDatabase db;
  late ProviderContainer container;
  late ScriptFileManagerOperations operations;
  late ScriptFile original;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('script_sync_');
    final gate = WorkspaceAccess();
    bridge = DiskBridge(root, gate);
    await bridge.script('a.py').parent.create(recursive: true);
    await bridge.script('a.py').writeAsString('print(42)');
    db = RenameFailureDatabase(
      databasePath: p.join(root.path, 'metadata.db'),
      workspaceAccess: gate,
    );
    final group = await db.createGroup(
      ScriptGroup(
        name: 'Tools',
        sortOrder: 0,
        createdAt: DateTime(2026),
        modifiedAt: DateTime(2026),
      ),
    );
    original = ScriptFile(
      name: 'a.py',
      path: bridge.script('a.py').path,
      createdAt: DateTime(2026),
      modifiedAt: DateTime(2026),
      groupId: group,
      runCount: 7,
      isPinned: true,
      sortOrder: 5,
      homeSortOrder: 8,
    );
    await db.upsertScript(original);
    container = ProviderContainer(
      overrides: [
        workspaceAccessProvider.overrideWithValue(gate),
        scriptRepositoryProvider.overrideWithValue(
          DatabaseScriptRepository(database: db, bridge: bridge),
        ),
      ],
    );
    final workspace = container.read(
      scriptWorkspaceControllerProvider.notifier,
    );
    await workspace.load();
    operations = ScriptFileManagerOperations(
      bridge: bridge,
      workspace: workspace,
    );
  });
  tearDown(() async {
    container.dispose();
    await db.closeForTest();
    await root.delete(recursive: true);
  });

  test(
    'file manager rename preserves metadata and updates the live workspace',
    () async {
      await operations.renameEntry(bridge.script('a.py').path, 'renamed.py');
      expect(await db.getScript('a.py'), isNull);
      final renamed = (await db.getScript('renamed.py'))!;
      expect(renamed.groupId, original.groupId);
      expect(renamed.runCount, 7);
      expect(renamed.isPinned, true);
      expect(renamed.sortOrder, 5);
      expect(renamed.homeSortOrder, 8);
      expect(renamed.createdAt, original.createdAt);
      expect(await bridge.script('renamed.py').readAsString(), 'print(42)');
      expect(
        container.read(scriptWorkspaceControllerProvider).scripts.single.name,
        'renamed.py',
      );
    },
  );

  test(
    'file manager deletion removes only the deleted script metadata',
    () async {
      await operations.deleteEntry(bridge.script('a.py').path);
      expect(await db.getScript('a.py'), isNull);
      expect(await bridge.script('a.py').exists(), false);
      expect(await db.getAllGroups(), hasLength(1));
      expect(
        container.read(scriptWorkspaceControllerProvider).scripts,
        isEmpty,
      );
    },
  );

  test(
    'same named files outside the library never modify script metadata',
    () async {
      final file = File(p.join(root.path, 'work', 'files', 'scripts', 'a.py'));
      await file.parent.create(recursive: true);
      await file.writeAsString('external');
      await operations.renameEntry(file.path, 'outside.py');
      await operations.deleteEntry(p.join(file.parent.path, 'outside.py'));
      expect((await db.getScript('a.py'))!.toMap(), original.toMap());
      expect(await bridge.script('a.py').readAsString(), 'print(42)');
    },
  );

  test(
    'failed file mutation preserves metadata and is not reported as success',
    () async {
      bridge.failMutation = true;
      await expectLater(
        operations.renameEntry(bridge.script('a.py').path, 'renamed.py'),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        operations.deleteEntry(bridge.script('a.py').path),
        throwsA(isA<Exception>()),
      );
      expect((await db.getScript('a.py'))!.toMap(), original.toMap());
      expect(await bridge.script('a.py').exists(), true);
    },
  );

  for (final rename in [false, true]) {
    test(
      'exact whitespace filename is used for ${rename ? 'rename' : 'delete'}',
      () async {
        final unusual = bridge.script(' a.py');
        await unusual.writeAsString('unusual');
        await db.upsertScript(
          original.copyWith(name: ' a.py', path: unusual.path),
        );
        if (rename) {
          await operations.renameEntry(unusual.path, 'renamed.py');
          expect(await bridge.script('renamed.py').readAsString(), 'unusual');
        } else {
          await operations.deleteEntry(unusual.path);
        }
        expect(await unusual.exists(), false);
        expect(await bridge.script('a.py').readAsString(), 'print(42)');
        expect((await db.getScript('a.py'))!.toMap(), original.toMap());
        expect(await db.getScript(' a.py'), isNull);
      },
    );
  }

  test('metadata rename failure rolls back the file name', () async {
    db.failRename = true;
    await expectLater(
      operations.renameEntry(bridge.script('a.py').path, 'renamed.py'),
      throwsA(isA<Exception>()),
    );
    expect(await bridge.script('a.py').readAsString(), 'print(42)');
    expect(await bridge.script('renamed.py').exists(), false);
    expect((await db.getScript('a.py'))!.toMap(), original.toMap());
  });

  test(
    'backup exclusivity blocks file-manager mutation before changing data',
    () async {
      final gate = container.read(workspaceAccessProvider);
      final release = Completer<void>();
      final reserved = gate.runExclusive(() => release.future);
      try {
        await expectLater(
          operations.deleteEntry(bridge.script('a.py').path),
          throwsA(isA<WorkspaceBusyException>()),
        );
        expect(await bridge.script('a.py').exists(), true);
        expect((await db.getScript('a.py'))!.toMap(), original.toMap());
      } finally {
        release.complete();
        await reserved;
      }
    },
  );

  test(
    'renaming away from Python removes metadata but preserves the file',
    () async {
      await operations.renameEntry(bridge.script('a.py').path, 'notes.txt');
      expect(await db.getAllScripts(), isEmpty);
      expect(await bridge.script('notes.txt').readAsString(), 'print(42)');
    },
  );
}
