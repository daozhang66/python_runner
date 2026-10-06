import '../domain/backup_manifest.dart';
import '../domain/backup_selection.dart';
import '../domain/restore_plan.dart';
import '../infrastructure/backup_native_bridge.dart';
import '../infrastructure/webdav_client.dart';

enum BackupOperationKind {
  chooseDirectory,
  exportLocal,
  upload,
  testConnection,
  saveProfile,
  listRemote,
  stageLocal,
  stageRemote,
  restore,
  discard,
}

enum BackupOperationStage {
  preparing,
  selecting,
  scanning,
  compressing,
  copying,
  uploading,
  downloading,
  validating,
  staging,
  committing,
  finalizing,
}

enum BackupResultKind {
  exportedLocal,
  uploaded,
  connectionVerified,
  profileSaved,
  previewReady,
  previewUpdated,
  restored,
  restoredCleanupPending,
  cancelled,
}

class BackupOperation {
  const BackupOperation({
    required this.id,
    required this.kind,
    this.stage = BackupOperationStage.preparing,
    this.completed = 0,
    this.total,
    this.cancellable = true,
  });
  final String id;
  final BackupOperationKind kind;
  final BackupOperationStage stage;
  final int completed;
  final int? total;
  final bool cancellable;
  double? get fraction =>
      total == null || total! <= 0 ? null : (completed / total!).clamp(0, 1);
}

class BackupResult {
  const BackupResult(this.kind, {this.document, this.remote});
  final BackupResultKind kind;
  final BackupDocument? document;
  final RemoteBackup? remote;
}

class BackupFailure implements Exception {
  const BackupFailure(this.code, {this.httpStatus});
  final String code;
  final int? httpStatus;
  @override
  String toString() => 'Backup operation failed ($code).';
}

class RestorePreview {
  RestorePreview({
    required this.operationId,
    required this.manifest,
    required this.selection,
    required this.policy,
    required this.plan,
    required this.libraryFingerprint,
    required this.workspaceRevision,
    required this.legacy,
    Iterable<String> legacyEntryPoints = const [],
    this.legacyEntryPoint,
    Map<int, String> projectKeys = const {},
  }) : legacyEntryPoints = List.unmodifiable(legacyEntryPoints),
       projectKeys = Map.unmodifiable(projectKeys);
  final String operationId;
  final BackupManifest manifest;
  final BackupSelection selection;
  final RestoreConflictPolicy policy;
  final RestorePlan plan;
  final String libraryFingerprint;
  final int workspaceRevision;
  final bool legacy;
  final List<String> legacyEntryPoints;
  final String? legacyEntryPoint;
  final Map<int, String> projectKeys;
  bool get hasSelection =>
      selection.scriptNames.isNotEmpty || selection.groupIds.isNotEmpty;
  bool get hasChanges => plan.scripts.isNotEmpty || plan.groups.isNotEmpty;
}

const _keep = Object();

class BackupState {
  BackupState({
    this.library,
    BackupSelection? selection,
    this.selectAll = true,
    this.localDirectory,
    this.profile,
    this.operation,
    this.lastResult,
    this.error,
    Iterable<RemoteBackup> remoteBackups = const [],
    this.preview,
  }) : selection = selection ?? BackupSelection(),
       remoteBackups = List.unmodifiable(remoteBackups);
  final BackupLibrarySnapshot? library;
  final BackupSelection selection;
  final bool selectAll;
  final BackupDocument? localDirectory;
  final WebDavConfig? profile;
  final BackupOperation? operation;
  final BackupResult? lastResult;
  final BackupFailure? error;
  final List<RemoteBackup> remoteBackups;
  final RestorePreview? preview;
  bool get busy => operation != null;
  BackupState copyWith({
    BackupLibrarySnapshot? library,
    BackupSelection? selection,
    bool? selectAll,
    Object? localDirectory = _keep,
    Object? profile = _keep,
    Object? operation = _keep,
    Object? lastResult = _keep,
    Object? error = _keep,
    Iterable<RemoteBackup>? remoteBackups,
    Object? preview = _keep,
  }) => BackupState(
    library: library ?? this.library,
    selection: selection ?? this.selection,
    selectAll: selectAll ?? this.selectAll,
    localDirectory: identical(localDirectory, _keep)
        ? this.localDirectory
        : localDirectory as BackupDocument?,
    profile: identical(profile, _keep)
        ? this.profile
        : profile as WebDavConfig?,
    operation: identical(operation, _keep)
        ? this.operation
        : operation as BackupOperation?,
    lastResult: identical(lastResult, _keep)
        ? this.lastResult
        : lastResult as BackupResult?,
    error: identical(error, _keep) ? this.error : error as BackupFailure?,
    remoteBackups: remoteBackups ?? this.remoteBackups,
    preview: identical(preview, _keep)
        ? this.preview
        : preview as RestorePreview?,
  );
}
