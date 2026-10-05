import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backup_native_bridge.dart';
import 'webdav_client.dart';

String newBackupOperationId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class BackupConfigurationException implements Exception {
  const BackupConfigurationException();
  @override
  String toString() =>
      'Backup settings could not be saved or unlocked. Retry after unlocking the device.';
}

/// One atomic preference points to an immutable credential generation. Writing
/// secure storage first means a failed replacement never destroys the old pair.
class BackupConfigStore {
  BackupConfigStore({
    required SharedPreferences preferences,
    FlutterSecureStorage? storage,
  }) : _prefs = preferences,
       _storage =
           storage ?? const FlutterSecureStorage(aOptions: androidOptions);
  static const androidOptions = AndroidOptions(
    storageNamespace: 'backup_webdav',
    resetOnError: false,
  );
  static const profileKey = 'backup.webdav.profile';
  final SharedPreferences _prefs;
  final FlutterSecureStorage _storage;
  Future<void> _pending = Future.value();

  Map<String, dynamic>? _bundle() {
    final value = _prefs.getString(profileKey);
    return value == null ? null : jsonDecode(value) as Map<String, dynamic>;
  }

  WebDavConfig? loadProfile() {
    final json = _bundle();
    return json == null
        ? null
        : WebDavConfig(
            baseUri: Uri.parse(json['baseUri'] as String),
            username: json['username'] as String,
            remoteDirectory: json['remoteDirectory'] as String,
          );
  }

  Future<String> readPassword() async {
    try {
      final key = _bundle()?['credentialKey'] as String?;
      if (key == null) throw const BackupConfigurationException();
      final value = await _storage.read(key: key);
      if (value == null) throw const BackupConfigurationException();
      return value;
    } catch (_) {
      throw const BackupConfigurationException();
    }
  }

  Future<void> saveProfile(WebDavConfig profile, {required String password}) {
    final operation = _pending.then((_) => _save(profile, password));
    _pending = operation.then<void>((_) {}, onError: (_, __) {});
    return operation;
  }

  Future<void> _save(WebDavConfig profile, String password) async {
    final previous = _prefs.getString(profileKey);
    final oldKey = _bundle()?['credentialKey'] as String?;
    final key = 'backup_webdav.password.${newBackupOperationId()}';
    var preferenceAttempted = false;
    try {
      await _storage.write(key: key, value: password);
      preferenceAttempted = true;
      if (!await _prefs.setString(
        profileKey,
        jsonEncode({...profile.toJson(), 'credentialKey': key}),
      )) {
        throw const BackupConfigurationException();
      }
    } catch (_) {
      // SharedPreferences updates its in-memory cache even when disk write fails.
      if (preferenceAttempted) {
        try {
          if (previous == null) {
            await _prefs.remove(profileKey);
          } else {
            await _prefs.setString(profileKey, previous);
          }
        } catch (_) {}
      }
      // Keep the new secret if preference persistence is uncertain. It contains
      // no profile pointer and is harmless; deleting could break a persisted pair.
      throw const BackupConfigurationException();
    }
    if (oldKey != null) {
      try {
        await _storage.delete(key: oldKey);
      } catch (_) {}
    }
  }

  BackupDocument? loadLocalDirectory() {
    final uri = _prefs.getString('backup.localTreeUri');
    final name = _prefs.getString('backup.localTreeName');
    return uri == null ? null : BackupDocument(uri: uri, name: name ?? uri);
  }

  Future<void> saveLocalDirectory(BackupDocument directory) async {
    if (!await _prefs.setString('backup.localTreeName', directory.name) ||
        !await _prefs.setString('backup.localTreeUri', directory.uri)) {
      throw const BackupConfigurationException();
    }
  }
}
