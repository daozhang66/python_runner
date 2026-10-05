import '../../../services/database_service.dart';

import 'package:flutter/services.dart';

import '../../../services/workspace_access.dart';
import '../infrastructure/backup_native_bridge.dart';

class BackupRecoveryException implements Exception {
  const BackupRecoveryException();
  @override
  String toString() =>
      'Backup recovery could not finish. Workspace files and recovery evidence were preserved. Check available storage, then retry recovery.';
}

class BackupRecovery {
  BackupRecovery({
    required this.database,
    required this.native,
    WorkspaceAccess? workspaceAccess,
  }) : workspaceAccess = workspaceAccess ?? WorkspaceAccess.instance;
  final DatabaseService database;
  final BackupNativeBridge native;
  final WorkspaceAccess workspaceAccess;
  Future<void>? _running;

  Future<void> recover() {
    if (_running != null) return _running!;
    workspaceAccess.blockForRecovery();
    final future = workspaceAccess.runExclusive(() async {
      try {
        final owner = workspaceAccess.pendingNativeRelease;
        if (owner != null) {
          try {
            await native.releaseWorkspace(owner);
          } on PlatformException catch (error) {
            if (error.code != 'WORKSPACE_NOT_LOCKED') rethrow;
          }
          workspaceAccess.completeNativeRelease();
        }
        final pending = (await native.pendingRestores()).toSet();
        database.preserveRestoreEvidence = pending.isNotEmpty;
        final committed = await database.committedRestoreIds();
        final retained = workspaceAccess.pendingNativeDiscard;
        // A failed cleanup may already have deleted its journal while the
        // native reservation survives. Resolve that ID before another journal
        // can attempt to reserve the native worker. Existing journals always
        // use SQLite commit proof before any temporary data is discarded.
        for (final id in {if (retained != null) retained, ...pending}) {
          try {
            if (pending.contains(id)) {
              if (committed.contains(id)) {
                await native.finalizeRestore(id);
                await database.forgetRestoreCommit(id);
              } else {
                await native.rollbackRestore(id);
              }
            } else {
              await native.discardOperation(id);
            }
            if (workspaceAccess.pendingNativeDiscard == id) {
              workspaceAccess.completeNativeDiscard();
            }
          } catch (_) {
            workspaceAccess.retainNativeDiscard(id);
            rethrow;
          }
        }
        // A crash after successful finalize but before forgetting is harmless.
        for (final id in committed.difference(pending)) {
          await database.forgetRestoreCommit(id);
        }
        await native.cleanupAbandonedOperations();
        database.preserveRestoreEvidence = false;
        workspaceAccess.completeRecovery();
      } catch (_) {
        throw const BackupRecoveryException();
      }
    }, recovery: true);
    _running = future;
    return future.whenComplete(() {
      _running = null;
    });
  }
}
