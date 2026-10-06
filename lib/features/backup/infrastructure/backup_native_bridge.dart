import 'package:flutter/services.dart';

import '../domain/backup_manifest.dart';
import '../domain/restore_plan.dart';

Map<String, dynamic> _map(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Invalid native backup response');
  }
  return value.map((key, value) => MapEntry(key as String, _value(value)));
}

Object? _value(Object? value) => switch (value) {
  Map() => _map(value),
  List() => value.map(_value).toList(),
  _ => value,
};

String _string(Map<String, dynamic> value, String key) {
  final result = value[key];
  if (result is! String || result.isEmpty) {
    throw FormatException('Invalid native $key');
  }
  return result;
}

class BackupDocument {
  final String uri;
  final String name;
  const BackupDocument({required this.uri, required this.name});
  factory BackupDocument.fromJson(Object? value) {
    final json = _map(value);
    return BackupDocument(
      uri: _string(json, 'uri'),
      name: _string(json, 'name'),
    );
  }
}

class CreatedBackupArchive {
  final String path;
  final String fileName;
  final BackupManifest manifest;
  const CreatedBackupArchive({
    required this.path,
    required this.fileName,
    required this.manifest,
  });
  factory CreatedBackupArchive.fromJson(Object? value) {
    final json = _map(value);
    return CreatedBackupArchive(
      path: _string(json, 'path'),
      fileName: _string(json, 'fileName'),
      manifest: BackupManifest.fromJson(_map(json['manifest'])),
    );
  }
}

class StagedBackupArchive {
  final BackupManifest manifest;
  final bool legacy;
  final String stagingId;
  const StagedBackupArchive({
    required this.manifest,
    required this.legacy,
    required this.stagingId,
  });
  factory StagedBackupArchive.fromJson(Object? value) {
    final json = _map(value);
    if (json['legacy'] is! bool) {
      throw const FormatException('Invalid native legacy flag');
    }
    return StagedBackupArchive(
      manifest: BackupManifest.fromJson(_map(json['manifest'])),
      legacy: json['legacy'] as bool,
      stagingId: _string(json, 'stagingId'),
    );
  }
}

enum BackupStage {
  scanning,
  compressing,
  copying,
  validating,
  staging,
  committing,
}

class BackupProgress {
  final String operationId;
  final BackupStage stage;
  final int completed;
  final int total;
  const BackupProgress({
    required this.operationId,
    required this.stage,
    required this.completed,
    required this.total,
  });
  double? get fraction =>
      total == 0 ? null : (completed / total).clamp(0.0, 1.0);
  factory BackupProgress.fromJson(Object? value) {
    final json = _map(value);
    final stageName = _string(json, 'stage');
    final stages = BackupStage.values.where((s) => s.name == stageName);
    final completed = json['completed'];
    final total = json['total'];
    if (stages.isEmpty ||
        completed is! int ||
        total is! int ||
        completed < 0 ||
        total < 0 ||
        (total > 0 && completed > total)) {
      throw const FormatException('Invalid native backup progress');
    }
    return BackupProgress(
      operationId: _string(json, 'operationId'),
      stage: stages.single,
      completed: completed,
      total: total,
    );
  }
}

/// Native owns archive paths, staging and the durable file journal. The caller
/// holds the workspace across snapshot or file + SQLite commit and cleanup.
class BackupNativeBridge {
  final MethodChannel _channel;
  final EventChannel _events;
  BackupNativeBridge({MethodChannel? channel, EventChannel? events})
    : _channel = channel ?? const MethodChannel('com.daozhang.py/backup'),
      _events = events ?? const EventChannel('com.daozhang.py/backup_progress');

  Stream<BackupProgress> get progress =>
      _events.receiveBroadcastStream().map(BackupProgress.fromJson);
  Future<BackupDocument?> pickBackupDirectory() => _pick('pickBackupDirectory');
  Future<BackupDocument?> pickBackupArchive() => _pick('pickBackupArchive');
  Future<BackupDocument?> _pick(String method) async {
    final result = await _channel.invokeMethod<Object?>(method);
    return result == null ? null : BackupDocument.fromJson(result);
  }

  Future<void> _operation(
    String method,
    String id, [
    Map<String, Object?> extra = const {},
  ]) async {
    await _channel.invokeMethod<void>(method, {'operationId': id, ...extra});
  }

  Future<void> acquireWorkspace(String operationId) =>
      _operation('acquireWorkspace', operationId);
  Future<void> cleanupAbandonedOperations() async {
    await _channel.invokeMethod<void>('cleanupAbandonedOperations');
  }

  Future<void> releaseWorkspace(String operationId) =>
      _operation('releaseWorkspace', operationId);
  Future<void> cancelOperation(String operationId) =>
      _operation('cancelOperation', operationId);
  Future<void> discardOperation(String operationId) =>
      _operation('discardOperation', operationId);
  Future<void> finalizeRestore(String operationId) =>
      _operation('finalizeRestore', operationId);
  Future<void> rollbackRestore(String operationId) =>
      _operation('rollbackRestore', operationId);
  Future<void> commitStaged(
    String operationId,
    Iterable<RestoreFileMove> fileMoves,
  ) => _operation('commitStaged', operationId, {
    'fileMoves': fileMoves.map((m) => m.toJson()).toList(),
  });
  Future<CreatedBackupArchive> createArchive(
    String operationId,
    Map<String, dynamic> metadata,
  ) async => CreatedBackupArchive.fromJson(
    await _channel.invokeMethod<Object?>('createArchive', {
      'operationId': operationId,
      'metadata': metadata,
    }),
  );
  Future<String> createTransferFile(String operationId) async {
    final result = await _channel.invokeMethod<Object?>('createTransferFile', {
      'operationId': operationId,
    });
    return _string(_map(result), 'path');
  }

  Future<BackupDocument> saveArchiveToDirectory(
    String operationId,
    String archivePath,
    String treeUri,
  ) async => BackupDocument.fromJson(
    await _channel.invokeMethod<Object?>('saveArchiveToDirectory', {
      'operationId': operationId,
      'archivePath': archivePath,
      'treeUri': treeUri,
    }),
  );
  Future<StagedBackupArchive> stageArchive(
    String operationId,
    String source,
    String displayName,
  ) async => StagedBackupArchive.fromJson(
    await _channel.invokeMethod<Object?>('stageArchive', {
      'operationId': operationId,
      'source': source,
      'displayName': displayName,
    }),
  );
  Future<List<String>> pendingRestores() async {
    final value = await _channel.invokeMethod<Object?>('pendingRestores');
    if (value is! List || value.any((v) => v is! String || v.isEmpty)) {
      throw const FormatException('Invalid pending restore IDs');
    }
    return List<String>.unmodifiable(value.cast<String>());
  }

  Future<String> scriptsRoot() async {
    final value = await _channel.invokeMethod<Object?>('scriptsRoot');
    if (value is! String || value.isEmpty) {
      throw const FormatException('Invalid scripts root');
    }
    return value;
  }
}
