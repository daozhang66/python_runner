import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final workspaceAccessProvider = Provider<WorkspaceAccess>(
  (ref) => WorkspaceAccess.instance,
);

class WorkspaceBusyException implements Exception {
  const WorkspaceBusyException();
  @override
  String toString() => 'The workspace is busy with a backup or restore.';
}

class WorkspaceRecoveryRequired implements Exception {
  const WorkspaceRecoveryRequired();
  @override
  String toString() =>
      'Workspace recovery must finish before continuing. Retry recovery.';
}

class _AccessLease {
  _AccessLease({this.exclusive = false});
  final bool exclusive;
  bool active = true;
  int pending = 0;
}

/// Process-wide admission gate. Reservations happen before the first await.
/// Accepted writes retain their lease while queued and may call nested writers.
class WorkspaceAccess extends ChangeNotifier {
  static final instance = WorkspaceAccess();
  final Object _zoneKey = Object();
  int _mutations = 0;
  int _revision = 0;
  bool _exclusive = false;
  bool _recoveryRequired = false;
  String? _pendingNativeRelease;
  String? _pendingNativeDiscard;
  Completer<void>? _drained;

  int get revision => _revision;
  bool get isBusy => _exclusive || _recoveryRequired;
  bool get recoveryRequired => _recoveryRequired;
  String? get pendingNativeRelease => _pendingNativeRelease;
  void retainNativeRelease(String operationId) {
    _pendingNativeRelease = operationId;
    blockForRecovery();
  }

  void completeNativeRelease() {
    _pendingNativeRelease = null;
  }

  String? get pendingNativeDiscard => _pendingNativeDiscard;
  void retainNativeDiscard(String operationId) {
    _pendingNativeDiscard = operationId;
    blockForRecovery();
  }

  void completeNativeDiscard() {
    _pendingNativeDiscard = null;
  }

  _AccessLease? get _lease => Zone.current[_zoneKey] as _AccessLease?;

  void assertReadable() {
    if (_recoveryRequired && !(_lease?.active == true && _lease!.exclusive)) {
      throw const WorkspaceRecoveryRequired();
    }
  }

  void blockForRecovery() {
    _recoveryRequired = true;
    notifyListeners();
  }

  void completeRecovery() {
    _recoveryRequired = false;
    notifyListeners();
  }

  Future<T> runMutation<T>(Future<T> Function() operation) async {
    final inherited = _lease;
    if (inherited?.active == true && inherited!.exclusive) return operation();
    final nested = inherited?.active == true;
    if (!nested) {
      assertReadable();
      if (_exclusive) throw const WorkspaceBusyException();
    }
    _mutations++;
    final lease = nested ? inherited! : _AccessLease();
    lease.pending++;
    try {
      return await runZoned(operation, zoneValues: {_zoneKey: lease});
    } finally {
      if (--lease.pending == 0) {
        lease.active = false;
        _revision++;
      }
      if (--_mutations == 0) {
        _drained?.complete();
        _drained = null;
      }
    }
  }

  Future<T> runExclusive<T>(
    Future<T> Function() operation, {
    bool recovery = false,
  }) async {
    final inherited = _lease;
    if (inherited?.active == true && inherited!.exclusive) return operation();
    if (inherited?.active == true) throw const WorkspaceBusyException();
    if (!recovery) assertReadable();
    if (_exclusive) throw const WorkspaceBusyException();
    _exclusive = true;
    notifyListeners();
    final lease = _AccessLease(exclusive: true);
    try {
      if (_mutations != 0) await (_drained ??= Completer<void>()).future;
      return await runZoned(operation, zoneValues: {_zoneKey: lease});
    } finally {
      lease.active = false;
      _exclusive = false;
      notifyListeners();
    }
  }
}
