import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:python_runner/features/backup/application/backup_controller.dart';
import 'package:python_runner/features/backup/application/backup_recovery.dart';
import 'package:python_runner/features/backup/domain/backup_selection.dart';
import 'package:python_runner/features/backup/domain/restore_plan.dart';
import 'package:python_runner/features/backup/infrastructure/backup_config_store.dart';
import 'package:python_runner/services/database_service.dart';
import 'package:python_runner/services/workspace_access.dart';

import 'backup_config_test.dart' show MemorySecrets;
import 'backup_controller_test.dart' show FakeBackupNative;
import 'restore_planner_test.dart' show localScript;

/// Models the native boundary where journal deletion succeeds but deleting the
/// operation directory fails, leaving the plugin's same-process reservation.
class CleanupFailureNative extends FakeBackupNative {
  CleanupFailureNative(super.dir);

  String? failAfterJournalRemoval;
  File get live => File('${dir.path}/scripts/alone.py');
  Directory operation(String id) => Directory('${dir.path}/operations/$id');
  File journal(String id) => File('${operation(id).path}/journal.json');
  File original(String id) => File('${operation(id).path}/original.py');

  @override
  Future<void> commitStaged(String id, Iterable<RestoreFileMove> moves) async {
    expect(moves.single.toJson(), {
      'sourceRoot': 'scripts/alone.py',
      'targetRoot': 'scripts/alone.py',
      'overwrite': true,
    });
    await super.commitStaged(id, moves);
    await operation(id).create(recursive: true);
    await journal(id).writeAsString('awaitingMetadata');
    await live.copy(original(id).path);
    await live.writeAsString('replacement');
  }

  @override
  Future<void> finalizeRestore(String id) async {
    reservation = id;
    check('finalize');
    if (await journal(id).exists()) {
      await original(id).delete();
      await _removeJournal(id, 'finalize');
    }
    reservation = null;
  }

  @override
  Future<void> rollbackRestore(String id) async {
    reservation = id;
    check('rollback');
    if (await journal(id).exists()) {
      await live.writeAsString(await original(id).readAsString());
      await original(id).delete();
      await _removeJournal(id, 'rollback');
    }
    reservation = null;
  }

  Future<void> _removeJournal(String id, String action) async {
    await journal(id).delete();
    pending.remove(id);
    if (failAfterJournalRemoval == action) {
      failAfterJournalRemoval = null;
      throw PlatformException(code: 'IO_ERROR');
    }
    await operation(id).delete();
  }

  @override
  Future<void> discardOperation(String id) async {
    if (await journal(id).exists()) {
      throw PlatformException(code: 'RECOVERY_REQUIRED');
    }
    await super.discardOperation(id);
    if (await operation(id).exists()) await operation(id).delete();
  }

  @override
  Future<void> cleanupAbandonedOperations() async {
    check('cleanup');
    if (reservation != null) throw PlatformException(code: 'OPERATION_BUSY');
    expect(owner, false);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late WorkspaceAccess gate;
  late DatabaseService db;
  late CleanupFailureNative native;
  late BackupController controller;
  late BackupRecovery recovery;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('backup_cleanup_recovery_');
    gate = WorkspaceAccess();
    db = DatabaseService(
      databasePath: '${dir.path}/test.db',
      workspaceAccess: gate,
    );
    native = CleanupFailureNative(dir);
    await native.live.parent.create(recursive: true);
    await native.live.writeAsString('original');
    await db.upsertScript(localScript('alone.py', pinned: true));
    SharedPreferences.setMockInitialValues({});
    controller = BackupController(
      database: db,
      native: native,
      listScriptFiles: native.listScriptFiles,
      workspaceAccess: gate,
      configStore: BackupConfigStore(
        preferences: await SharedPreferences.getInstance(),
        storage: MemorySecrets(),
      ),
    );
    recovery = BackupRecovery(
      database: db,
      native: native,
      workspaceAccess: gate,
    );
  });
  tearDown(() async {
    controller.dispose();
    await native.progressEvents.close();
    await db.closeForTest();
    await dir.delete(recursive: true);
  });

  for (final origin in ['controller', 'boot']) {
    for (final committed in [true, false]) {
      for (final journalRemoved in [true, false]) {
        final action = committed ? 'finalize' : 'rollback';
        test('$origin retries $action in the same process with journal '
            '${journalRemoved ? 'removed' : 'preserved'}', () async {
          await controller.pickAndStageLocal();
          await controller.updateRestoreSelection(
            BackupSelection(scriptNames: {'alone.py'}),
          );
          await controller.updateRestorePolicy(RestoreConflictPolicy.overwrite);
          final preview = controller.state.preview!;
          final id = preview.operationId;
          if (journalRemoved) {
            native.failAfterJournalRemoval = action;
          } else {
            native.failure = action;
          }

          if (origin == 'controller') {
            if (!committed) {
              await (await db.database).execute(
                'CREATE TRIGGER fail_restore BEFORE UPDATE ON scripts '
                "BEGIN SELECT RAISE(ABORT, 'fail'); END",
              );
            }
            await controller.confirmRestore(confirmed: true);
            if (committed) {
              expect(
                controller.state.lastResult!.kind,
                BackupResultKind.restoredCleanupPending,
              );
            } else {
              expect(controller.state.error?.code, 'RECOVERY_REQUIRED');
            }
          } else {
            // An interrupted restore reaches startup with installed files;
            // only the SQLite transaction decides whether they stay.
            await native.acquireWorkspace(id);
            await native.commitStaged(id, preview.plan.fileMoves);
            if (committed) {
              await db.applyRestorePlan(
                preview.plan,
                id,
                native.live.parent.path,
              );
            }
            await native.releaseWorkspace(id);
            await expectLater(
              recovery.recover(),
              throwsA(isA<BackupRecoveryException>()),
            );
          }

          expect(gate.recoveryRequired, true);
          expect(native.reservation, id);
          expect(native.owner, false);
          expect(await native.journal(id).exists(), !journalRemoved);
          expect(native.pending, journalRemoved ? isEmpty : [id]);
          expect(await native.operation(id).exists(), true);
          expect(
            await native.live.readAsString(),
            !committed && journalRemoved ? 'original' : 'replacement',
          );
          await gate.runExclusive(() async {
            expect(await db.committedRestoreIds(), committed ? {id} : isEmpty);
            expect((await db.getAllScripts()).single.isPinned, !committed);
          }, recovery: true);
          await expectLater(
            gate.runMutation(() async {}),
            throwsA(isA<WorkspaceRecoveryRequired>()),
          );

          if (!journalRemoved) {
            // Persistent journal errors must stop recovery before discard,
            // preserving both rollback data and commit proof for the retry.
            await expectLater(
              recovery.recover(),
              throwsA(isA<BackupRecoveryException>()),
            );
            expect(native.calls, isNot(contains('discard')));
            expect(await native.original(id).exists(), true);
            await gate.runExclusive(() async {
              expect(
                await db.committedRestoreIds(),
                committed ? {id} : isEmpty,
              );
            }, recovery: true);
          }
          native.failure = null;
          await recovery.recover();

          expect(gate.isBusy, false);
          expect(gate.pendingNativeDiscard, isNull);
          expect(native.reservation, isNull);
          expect(native.pending, isEmpty);
          expect(await native.operation(id).exists(), false);
          expect(await db.committedRestoreIds(), isEmpty);
          final script = (await db.getAllScripts()).single;
          expect(script.name, 'alone.py');
          expect(script.isPinned, !committed);
          expect(script.sortOrder, 30);
          expect(await db.getAllGroups(), isEmpty);
          expect(
            await native.live.readAsString(),
            committed ? 'replacement' : 'original',
          );
          expect(
            native.calls,
            isNot(contains(committed ? 'rollback' : 'finalize')),
          );
          await gate.runMutation(() async {});
          await native.acquireWorkspace('next-operation');
          await native.releaseWorkspace('next-operation');
          await native.discardOperation('next-operation');
        });
      }
    }
  }
}
