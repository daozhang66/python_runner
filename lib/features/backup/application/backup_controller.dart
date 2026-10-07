import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../models/script_file.dart';
import '../../../models/script_group.dart';
import '../../../services/database_service.dart';
import '../../../services/workspace_access.dart';
import '../domain/backup_manifest.dart';
import '../domain/backup_selection.dart';
import '../domain/restore_plan.dart';
import '../domain/restore_planner.dart';
import '../infrastructure/backup_config_store.dart';
import '../infrastructure/backup_native_bridge.dart';
import '../infrastructure/webdav_client.dart';
import 'backup_state.dart';
export 'backup_state.dart';

typedef WebDavClientFactory = WebDavClient Function(
  WebDavConfig config,
  String password,
);

class _OperationContext {
  _OperationContext(this.id, this.kind);
  final String id;
  final BackupOperationKind kind;
  final cancellation = BackupCancellation();
  bool cancellable = true;
  bool nativeReserved = false;
}

/// The single persistent operation owner, shared by local and cloud entrypoints.
/// Commands publish typed failures in state; no server body or password escapes.
class BackupController extends ChangeNotifier {
  BackupController({
    required this.database,
    required this.native,
    required this.configStore,
    required Future<List<String>> Function() listScriptFiles,
    WorkspaceAccess? workspaceAccess,
    WebDavClientFactory? webDavFactory,
    bool Function()? isExecutionRunning,
    Future<void> Function()? reloadWorkspace,
    Future<void> Function(Iterable<ScriptGroup> groups)? reloadRestoredProjects,
  }) : workspaceAccess = workspaceAccess ?? WorkspaceAccess.instance,
       _listScriptFiles = listScriptFiles,
       _webDavFactory =
           webDavFactory ??
           ((config, password) =>
               WebDavClient(config: config, password: password)),
       _isExecutionRunning = isExecutionRunning ?? (() => false),
       _reloadWorkspace = reloadWorkspace ?? (() async {}),
       _reloadRestoredProjects = reloadRestoredProjects ?? ((_) async {}) {
    _progress = native.progress.listen(_onNativeProgress, onError: (_) {});
  }
  final DatabaseService database;
  final BackupNativeBridge native;
  final BackupConfigStore configStore;
  final WorkspaceAccess workspaceAccess;
  final Future<List<String>> Function() _listScriptFiles;
  final WebDavClientFactory _webDavFactory;
  final bool Function() _isExecutionRunning;
  final Future<void> Function() _reloadWorkspace;
  final Future<void> Function(Iterable<ScriptGroup>) _reloadRestoredProjects;
  late final StreamSubscription<BackupProgress> _progress;
  BackupState _state = BackupState();
  BackupState get state => _state;
  _OperationContext? _active;
  Timer? _savedNoticeTimer;
  bool _disposed = false;
  int _previewGeneration = 0;
  Future<void> _previewTail = Future.value();

  void _set(BackupState state) {
    _state = state;
    if (!_disposed) notifyListeners();
  }

  void _result(BackupResult result) =>
      _set(_state.copyWith(lastResult: result, error: null));
  void _stage(
    _OperationContext op,
    BackupOperationStage stage, {
    int completed = 0,
    int? total,
  }) {
    if (!identical(_active, op) || _disposed) return;
    _set(
      _state.copyWith(
        operation: BackupOperation(
          id: op.id,
          kind: op.kind,
          stage: stage,
          completed: completed,
          total: total,
          cancellable: op.cancellable,
        ),
      ),
    );
  }

  void _onNativeProgress(BackupProgress progress) {
    final op = _active;
    if (op == null || op.id != progress.operationId) return;
    // A staged operation keeps its native ID through confirmation. Delayed
    // preparation events must not replace the later commit/transfer stage.
    if (op.kind == BackupOperationKind.restore &&
        (progress.stage != BackupStage.committing ||
            _state.operation?.stage == BackupOperationStage.finalizing)) {
      return;
    }
    if (op.kind == BackupOperationKind.upload &&
        _state.operation?.stage == BackupOperationStage.uploading) {
      return;
    }
    if (op.kind == BackupOperationKind.exportLocal &&
        _state.operation?.stage == BackupOperationStage.copying &&
        progress.stage != BackupStage.copying) {
      return;
    }
    _stage(
      op,
      switch (progress.stage) {
        BackupStage.scanning => BackupOperationStage.scanning,
        BackupStage.compressing => BackupOperationStage.compressing,
        BackupStage.copying => BackupOperationStage.copying,
        BackupStage.validating => BackupOperationStage.validating,
        BackupStage.staging => BackupOperationStage.staging,
        BackupStage.committing => BackupOperationStage.committing,
      },
      completed: progress.completed,
      total: progress.total <= 0 ? null : progress.total,
    );
  }

  BackupFailure _failure(Object error) => switch (error) {
    BackupFailure() => error,
    PlatformException() => BackupFailure(error.code),
    WebDavException() => BackupFailure(
      'WEBDAV_${error.kind.name.toUpperCase()}',
      httpStatus: error.statusCode,
    ),
    WorkspaceRecoveryRequired() => const BackupFailure('RECOVERY_REQUIRED'),
    WorkspaceBusyException() => const BackupFailure('WORKSPACE_BUSY'),
    BackupConfigurationException() => const BackupFailure(
      'CONFIGURATION_UNAVAILABLE',
    ),
    UnsupportedBackupVersion() => const BackupFailure('UNSUPPORTED_VERSION'),
    FormatException() => const BackupFailure('INVALID_BACKUP'),
    _ => const BackupFailure('OPERATION_FAILED'),
  };
  Future<void> _perform(
    BackupOperationKind kind,
    Future<void> Function(_OperationContext op) action, {
    String? id,
    bool allowPreview = false,
  }) async {
    if (_disposed) return;
    if (_active != null || (!allowPreview && _state.preview != null)) {
      _set(_state.copyWith(error: const BackupFailure('OPERATION_BUSY')));
      return;
    }
    final op = _OperationContext(id ?? newBackupOperationId(), kind);
    _savedNoticeTimer?.cancel();
    _active = op;
    _set(
      _state.copyWith(
        error: null,
        lastResult: null,
        operation: BackupOperation(id: op.id, kind: kind),
      ),
    );
    try {
      await action(op);
    } catch (error) {
      final cancelled =
          error is BackupCancelledException || op.cancellation.isCancelled;
      final failure = _failure(error);
      if (failure.code == 'RECOVERY_REQUIRED' ||
          failure.code == 'TEMP_CLEANUP_PENDING') {
        // Cancellation may initiate unwind, but failed release/discard still
        // blocks the workspace and must retain the UI's recovery signal.
        _set(
          _state.copyWith(
            error: failure,
            lastResult:
                _state.lastResult ??
                (cancelled
                    ? const BackupResult(BackupResultKind.cancelled)
                    : null),
          ),
        );
      } else if (cancelled) {
        _result(const BackupResult(BackupResultKind.cancelled));
      } else {
        _set(_state.copyWith(error: failure));
      }
    } finally {
      if (identical(_active, op)) {
        _active = null;
        _set(_state.copyWith(operation: null));
        final result = _state.lastResult;
        if (!_disposed &&
            _state.error == null &&
            (result?.kind == BackupResultKind.exportedLocal ||
                result?.kind == BackupResultKind.uploaded)) {
          // Start after cleanup so slow exports still get a full visible notice.
          _savedNoticeTimer = Timer(const Duration(seconds: 4), () {
            if (!_disposed && identical(_state.lastResult, result)) {
              _set(_state.copyWith(lastResult: null));
            }
          });
        }
      }
    }
  }

  BackupSelection _all(BackupLibrarySnapshot snapshot) => BackupSelection(
    scriptNames: snapshot.scripts.map((s) => s.name),
    groupIds: snapshot.groups.map((g) => g.id!).toList(),
  );
  BackupSelection _retain(
    BackupSelection selected,
    BackupLibrarySnapshot snapshot,
  ) => BackupSelection(
    scriptNames: selected.scriptNames.where(
      (name) => snapshot.scripts.any((s) => s.name == name),
    ),
    groupIds: selected.groupIds.where(
      (id) => snapshot.groups.any((g) => g.id == id),
    ),
  );
  Future<BackupLibrarySnapshot> _readBackupLibrary() async {
    final snapshot = await database.readBackupSnapshot();
    // File-manager edits can leave metadata for scripts which no longer exist.
    // Match the workspace's live inventory without deleting historical metadata
    // or filtering the separate snapshots used for restore conflict planning.
    final names = (await _listScriptFiles()).toSet();
    final byName = {for (final script in snapshot.scripts) script.name: script};
    var nextOrder = snapshot.scripts.fold<int>(
      0,
      (order, script) => script.sortOrder > order ? script.sortOrder : order,
    );
    final now = DateTime.now();
    return BackupLibrarySnapshot(
      scripts: [
        ...snapshot.scripts.where((script) => names.contains(script.name)),
        // Discover scripts renamed/imported through the file manager even if
        // the workspace has not yet persisted metadata for their new names.
        for (final name in names.where((name) => !byName.containsKey(name)))
          ScriptFile(
            name: name,
            path: name,
            createdAt: now,
            modifiedAt: now,
            sortOrder: ++nextOrder,
          ),
      ],
      groups: snapshot.groups,
    );
  }

  Future<void> loadLibrary() async {
    try {
      final snapshot = await _readBackupLibrary();
      if (_disposed) return;
      _set(
        _state.copyWith(
          library: snapshot,
          selection: _state.selectAll
              ? _all(snapshot)
              : _retain(_state.selection, snapshot),
          localDirectory: configStore.loadLocalDirectory(),
          profile: configStore.loadProfile(),
        ),
      );
    } catch (error) {
      _set(_state.copyWith(error: _failure(error)));
    }
  }

  Future<void> loadConfiguration() async {
    try {
      _set(
        _state.copyWith(
          localDirectory: configStore.loadLocalDirectory(),
          profile: configStore.loadProfile(),
        ),
      );
    } catch (error) {
      _set(_state.copyWith(error: _failure(error)));
    }
  }

  void selectLibrary(BackupSelection selection) {
    if (_active != null) return;
    final library = _state.library;
    _set(
      _state.copyWith(
        selection: library == null ? selection : _retain(selection, library),
        selectAll: false,
      ),
    );
  }

  void selectAllLibrary() {
    if (_active != null) return;
    _set(
      _state.copyWith(
        selectAll: true,
        selection: _state.library == null
            ? BackupSelection()
            : _all(_state.library!),
      ),
    );
  }

  Future<void> chooseLocalDirectory() =>
      _perform(BackupOperationKind.chooseDirectory, (op) async {
        _stage(op, BackupOperationStage.selecting);
        final directory = await native.pickBackupDirectory();
        op.cancellation.check();
        if (directory == null) {
          _result(const BackupResult(BackupResultKind.cancelled));
          return;
        }
        await configStore.saveLocalDirectory(directory);
        _set(_state.copyWith(localDirectory: directory));
      }, allowPreview: true);
  void _checkExecution() {
    if (_isExecutionRunning()) throw const BackupFailure('EXECUTION_RUNNING');
  }

  Future<CreatedBackupArchive> _snapshot(_OperationContext op) =>
      workspaceAccess.runExclusive(() async {
        op.cancellation.check();
        _checkExecution();
        await native.acquireWorkspace(op.id);
        op.nativeReserved = true;
        try {
          final snapshot = await _readBackupLibrary();
          final selection = _state.selectAll
              ? _all(snapshot)
              : _retain(_state.selection, snapshot);
          _set(_state.copyWith(library: snapshot, selection: selection));
          if (selection.scriptNames.isEmpty && selection.groupIds.isEmpty) {
            throw const BackupFailure('NOTHING_SELECTED');
          }
          final metadata = selection
              .selectSnapshot(snapshot)
              .toMetadataJson(createdAt: DateTime.now().toUtc());
          op.cancellation.check();
          op.nativeReserved = true;
          final archive = await native.createArchive(op.id, metadata);
          BackupManifest.fromJson(archive.manifest.toJson());
          op.cancellation.check();
          return archive;
        } finally {
          await _releaseWorkspace(op);
        }
      });
  Future<void> _releaseWorkspace(_OperationContext op) async {
    try {
      await native.releaseWorkspace(op.id);
    } catch (_) {
      workspaceAccess.retainNativeRelease(op.id);
      if (_state.lastResult?.kind == BackupResultKind.restored) {
        _result(const BackupResult(BackupResultKind.restoredCleanupPending));
      }
      throw const BackupFailure('RECOVERY_REQUIRED');
    }
  }

  Future<void> _discard(_OperationContext op) async {
    if (!op.nativeReserved) return;
    try {
      await native.discardOperation(op.id);
      op.nativeReserved = false;
    } catch (_) {
      workspaceAccess.retainNativeDiscard(op.id);
      throw const BackupFailure('TEMP_CLEANUP_PENDING');
    }
  }

  Future<void> exportLocal() => _perform(BackupOperationKind.exportLocal, (
    op,
  ) async {
    final directory = _state.localDirectory ?? configStore.loadLocalDirectory();
    if (directory == null) {
      throw const BackupFailure('LOCAL_DIRECTORY_REQUIRED');
    }
    try {
      final archive = await _snapshot(op);
      _stage(op, BackupOperationStage.copying);
      final document = await native.saveArchiveToDirectory(
        op.id,
        archive.path,
        directory.uri,
      );
      op.cancellation.check();
      _result(BackupResult(BackupResultKind.exportedLocal, document: document));
    } finally {
      await _discard(op);
    }
  });
  Future<WebDavClient> _client() async {
    final profile = configStore.loadProfile();
    if (profile == null) throw const BackupFailure('WEBDAV_PROFILE_REQUIRED');
    return _webDavFactory(profile, await configStore.readPassword());
  }

  Future<void> backupWebDav() =>
      _perform(BackupOperationKind.upload, (op) async {
        final client = await _client();
        try {
          final archive = await _snapshot(op);
          _stage(op, BackupOperationStage.uploading);
          final remote = await client.upload(
            File(archive.path),
            fileName: archive.fileName,
            operationId: op.id,
            cancellation: op.cancellation,
            onProgress: (done, total) => _stage(
              op,
              BackupOperationStage.uploading,
              completed: done,
              total: total,
            ),
          );
          _result(BackupResult(BackupResultKind.uploaded, remote: remote));
        } finally {
          await _discard(op);
        }
      });
  Future<void> saveWebDavProfile(WebDavConfig profile, {String? password}) =>
      _perform(BackupOperationKind.saveProfile, (op) async {
        op.cancellable = false;
        _stage(op, BackupOperationStage.preparing);
        await configStore.saveProfile(
          profile,
          password: password ?? await configStore.readPassword(),
        );
        _set(_state.copyWith(profile: profile, remoteBackups: []));
        _result(const BackupResult(BackupResultKind.profileSaved));
      }, allowPreview: true);
  Future<void> testWebDavConnection({
    WebDavConfig? profile,
    String? password,
  }) => _perform(BackupOperationKind.testConnection, (op) async {
    final client = profile == null
        ? await _client()
        : _webDavFactory(profile, password ?? await configStore.readPassword());
    await client.testConnection(
      operationId: op.id,
      cancellation: op.cancellation,
    );
    _result(const BackupResult(BackupResultKind.connectionVerified));
  }, allowPreview: true);
  Future<void> refreshRemoteBackups() =>
      _perform(BackupOperationKind.listRemote, (op) async {
        final client = await _client();
        final backups = await client.listBackups(cancellation: op.cancellation);
        _set(_state.copyWith(remoteBackups: backups));
      }, allowPreview: true);

  String _fingerprint(BackupLibrarySnapshot library) {
    final scripts = library.scripts.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final groups = library.groups.toList()
      ..sort((a, b) => a.id!.compareTo(b.id!));
    return sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'scripts': scripts.map((s) => s.toMap()).toList(),
              'groups': groups.map((g) => g.toMap()).toList(),
            }),
          ),
        )
        .toString();
  }

  List<String> _legacyCandidates(BackupManifest manifest) {
    final root = 'projects/${manifest.groups.single.projectKey}/';
    final paths = manifest.files
        .where(
          (f) =>
              !f.isDirectory &&
              f.path.startsWith(root) &&
              f.path.endsWith('.py'),
        )
        .map((f) => f.path.substring(root.length))
        .toList();
    const preferred = ['main.py', 'app.py', 'run.py', '__main__.py'];
    int rank(String path) {
      final index = preferred.indexOf(path.split('/').last);
      return index < 0 ? preferred.length : index;
    }

    return paths..sort((a, b) {
      final ranked = rank(a).compareTo(rank(b));
      return ranked == 0 ? a.compareTo(b) : ranked;
    });
  }

  Future<RestorePreview> _plan({
    required String id,
    required BackupManifest manifest,
    required BackupSelection selection,
    required RestoreConflictPolicy policy,
    required bool legacy,
    Map<int, String> keys = const {},
    String? entryPoint,
    BackupLibrarySnapshot? snapshot,
  }) async {
    final candidates = legacy ? _legacyCandidates(manifest) : <String>[];
    if (legacy) {
      // An ordinary ZIP is always a new project, including after name edits.
      policy = RestoreConflictPolicy.keepBoth;
      if (entryPoint != null && !candidates.contains(entryPoint)) {
        throw const BackupFailure('INVALID_ENTRYPOINT');
      }
      final json = manifest.toJson();
      (json['groups'] as List).single['mainFilePath'] = entryPoint;
      manifest = BackupManifest.fromJson(json);
    }
    final library = snapshot ?? await database.readBackupSnapshot();
    final allocated = Map<int, String>.of(keys);
    final unavailable = {
      ...library.groups.map((g) => g.projectKey).nonNulls,
      ...manifest.groups.map((g) => g.projectKey).nonNulls,
    };
    final planner = RestorePlanner(
      projectKeyForGroup: (source) {
        var key = allocated[source.id];
        if (key == null || unavailable.contains(key)) {
          do {
            key = 'restored_${newBackupOperationId()}';
          } while (unavailable.contains(key) || allocated.containsValue(key));
          allocated[source.id!] = key;
        }
        return key;
      },
    );
    final plan = planner.plan(
      manifest: manifest,
      selection: selection,
      existingScripts: library.scripts,
      existingGroups: library.groups,
      policy: policy,
    );
    return RestorePreview(
      operationId: id,
      manifest: manifest,
      selection: selection,
      policy: policy,
      plan: plan,
      libraryFingerprint: _fingerprint(library),
      workspaceRevision: workspaceAccess.revision,
      legacy: legacy,
      legacyEntryPoints: candidates,
      legacyEntryPoint: entryPoint,
      projectKeys: allocated,
    );
  }

  Future<void> _stageArchive(
    _OperationContext op,
    String source,
    String displayName,
  ) async {
    _stage(op, BackupOperationStage.validating);
    op.nativeReserved = true;
    final staged = await native.stageArchive(op.id, source, displayName);
    op.cancellation.check();
    final manifest = BackupManifest.fromJson(staged.manifest.toJson());
    if (staged.stagingId != op.id) {
      throw const BackupFailure('INVALID_STAGING_ID');
    }
    final candidates = staged.legacy ? _legacyCandidates(manifest) : <String>[];
    final preview = await _plan(
      id: op.id,
      manifest: manifest,
      selection: BackupSelection.all(manifest),
      policy: RestoreConflictPolicy.keepBoth,
      legacy: staged.legacy,
      entryPoint: candidates.firstOrNull,
    );
    op.cancellation.check();
    _set(_state.copyWith(preview: preview));
    _result(const BackupResult(BackupResultKind.previewReady));
  }

  Future<void> pickAndStageLocal() =>
      _perform(BackupOperationKind.stageLocal, (op) async {
        try {
          _stage(op, BackupOperationStage.selecting);
          final document = await native.pickBackupArchive();
          op.cancellation.check();
          if (document == null) {
            _result(const BackupResult(BackupResultKind.cancelled));
            return;
          }
          await _stageArchive(op, document.uri, document.name);
        } finally {
          if (_state.preview?.operationId != op.id) await _discard(op);
        }
      });
  Future<void> downloadAndStageRemote(RemoteBackup remote) =>
      _perform(BackupOperationKind.stageRemote, (op) async {
        try {
          final client = await _client();
          op.cancellation.check();
          op.nativeReserved = true;
          final path = await native.createTransferFile(op.id);
          _stage(op, BackupOperationStage.downloading);
          await client.download(
            remote,
            File(path),
            cancellation: op.cancellation,
            onProgress: (done, total) => _stage(
              op,
              BackupOperationStage.downloading,
              completed: done,
              total: total,
            ),
          );
          await _stageArchive(op, path, remote.name);
        } finally {
          if (_state.preview?.operationId != op.id) await _discard(op);
        }
      });
  Future<void> updateRestoreSelection(BackupSelection selection) =>
      _updatePreview(selection: selection);
  Future<void> updateRestorePolicy(RestoreConflictPolicy policy) =>
      _updatePreview(policy: policy);
  Future<void> updateLegacyEntryPoint(String? entryPoint) =>
      _updatePreview(entryPoint: entryPoint, changeEntryPoint: true);
  Future<void> updateLegacyProjectName(String name) =>
      _updatePreview(projectName: name);
  Future<void> _updatePreview({
    BackupSelection? selection,
    RestoreConflictPolicy? policy,
    String? entryPoint,
    bool changeEntryPoint = false,
    String? projectName,
  }) {
    final next = _previewTail.then(
      (_) => _updatePreviewNow(
        selection: selection,
        policy: policy,
        entryPoint: entryPoint,
        changeEntryPoint: changeEntryPoint,
        projectName: projectName,
      ),
    );
    _previewTail = next;
    return next;
  }

  Future<void> _updatePreviewNow({
    BackupSelection? selection,
    RestoreConflictPolicy? policy,
    String? entryPoint,
    bool changeEntryPoint = false,
    String? projectName,
  }) async {
    final before = _state.preview;
    if (before == null || _active != null || _disposed) return;
    final generation = ++_previewGeneration;
    try {
      var manifest = before.manifest;
      if (projectName != null) {
        if (!before.legacy ||
            projectName.trim().isEmpty ||
            projectName.length > 255 ||
            RegExp(r'[\x00-\x1f\x7f]').hasMatch(projectName)) {
          throw const BackupFailure('INVALID_PROJECT_NAME');
        }
        final json = manifest.toJson();
        (json['groups'] as List).single['name'] = projectName.trim();
        manifest = BackupManifest.fromJson(json);
      }
      final preview = await _plan(
        id: before.operationId,
        manifest: manifest,
        selection: selection ?? before.selection,
        policy: policy ?? before.policy,
        legacy: before.legacy,
        keys: before.projectKeys,
        entryPoint: changeEntryPoint ? entryPoint : before.legacyEntryPoint,
      );
      if (_previewGeneration == generation &&
          identical(_state.preview, before) &&
          _active == null &&
          !_disposed) {
        _set(_state.copyWith(preview: preview, error: null));
      }
    } catch (error) {
      if (_previewGeneration == generation) {
        _set(_state.copyWith(error: _failure(error)));
      }
    }
  }

  Future<void> confirmRestore({required bool confirmed}) async {
    await _previewTail;
    final preview = _state.preview;
    if (!confirmed || preview == null) return;
    await _perform(
      BackupOperationKind.restore,
      (op) async {
        op.nativeReserved = true;
        if (!preview.hasSelection || !preview.hasChanges) {
          throw const BackupFailure('NOTHING_SELECTED');
        }
        var restored = false;
        await workspaceAccess.runExclusive(() async {
          op.cancellation.check();
          _checkExecution();
          await native.acquireWorkspace(op.id);
          var commitAttempted = false;
          var databaseCommitted = false;
          try {
            final snapshot = await database.readBackupSnapshot();
            if (preview.libraryFingerprint != _fingerprint(snapshot) ||
                preview.workspaceRevision != workspaceAccess.revision) {
              final refreshed = await _plan(
                id: op.id,
                manifest: preview.manifest,
                selection: preview.selection,
                policy: preview.policy,
                legacy: preview.legacy,
                keys: preview.projectKeys,
                entryPoint: preview.legacyEntryPoint,
                snapshot: snapshot,
              );
              _set(_state.copyWith(preview: refreshed, library: snapshot));
              _result(const BackupResult(BackupResultKind.previewUpdated));
              return;
            }
            final root = await native.scriptsRoot();
            op.cancellation.check();
            op.cancellable = false;
            _stage(op, BackupOperationStage.committing);
            commitAttempted = true;
            await native.commitStaged(op.id, preview.plan.fileMoves);
            await database.applyRestorePlan(preview.plan, op.id, root);
            databaseCommitted = true;
            restored = true;
            _stage(op, BackupOperationStage.finalizing);
            try {
              await native.finalizeRestore(op.id);
              op.nativeReserved = false;
              await database.forgetRestoreCommit(op.id);
              _result(const BackupResult(BackupResultKind.restored));
            } catch (_) {
              database.preserveRestoreEvidence = true;
              workspaceAccess.retainNativeDiscard(op.id);
              _result(
                const BackupResult(BackupResultKind.restoredCleanupPending),
              );
            }
            _set(_state.copyWith(preview: null));
          } catch (error) {
            if (commitAttempted && !databaseCommitted) {
              try {
                await native.rollbackRestore(op.id);
                op.nativeReserved = false;
                _set(_state.copyWith(preview: null));
              } catch (_) {
                database.preserveRestoreEvidence = true;
                workspaceAccess.retainNativeDiscard(op.id);
                _set(_state.copyWith(preview: null));
                throw const BackupFailure('RECOVERY_REQUIRED');
              }
            }
            rethrow;
          } finally {
            await _releaseWorkspace(op);
          }
        });
        if (restored && !workspaceAccess.recoveryRequired && !_disposed) {
          await _reloadWorkspace();
          await _reloadRestoredProjects(
            preview.plan.groups
                .where(
                  (planned) =>
                      planned.group.isProject &&
                      planned.action == RestoreAction.overwrite,
                )
                .map((planned) => planned.group),
          );
          await loadLibrary();
        }
      },
      id: preview.operationId,
      allowPreview: true,
    );
  }

  Future<void> cancel() async {
    final op = _active;
    if (op == null || !op.cancellable) return;
    op.cancellation.cancel();
    if (op.nativeReserved) {
      try {
        await native.cancelOperation(op.id);
      } catch (_) {}
    }
  }

  Future<void> discardPreview() async {
    final preview = _state.preview;
    if (preview == null) return;
    await _perform(
      BackupOperationKind.discard,
      (op) async {
        op.cancellable = false;
        _stage(op, BackupOperationStage.preparing);
        await native.discardOperation(op.id);
        ++_previewGeneration;
        _set(_state.copyWith(preview: null));
      },
      id: preview.operationId,
      allowPreview: true,
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _savedNoticeTimer?.cancel();
    unawaited(cancel());
    if (_active == null && _state.preview != null) {
      unawaited(
        native.discardOperation(_state.preview!.operationId).catchError((_) {}),
      );
    }
    _disposed = true;
    unawaited(_progress.cancel());
    super.dispose();
  }
}
