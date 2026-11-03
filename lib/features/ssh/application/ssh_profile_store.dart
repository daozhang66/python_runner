import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/ssh_profile.dart';

@immutable
class SshSecrets {
  const SshSecrets({this.password, this.privateKey, this.passphrase});

  static const SshSecrets empty = SshSecrets();

  final String? password;
  final String? privateKey;
  final String? passphrase;

  bool get isEmpty =>
      (password ?? '').isEmpty &&
      (privateKey ?? '').isEmpty &&
      (passphrase ?? '').isEmpty;
}

/// Persists SSH hosts (SharedPreferences), their secrets (secure storage) and
/// the host keys the user has trusted.
class SshProfileStore {
  SshProfileStore._();

  static final SshProfileStore instance = SshProfileStore._();

  static const String _profilesKey = 'ssh_profiles_v1';
  static const String _knownHostsKey = 'ssh_known_hosts_v1';
  static const String _lastProfileKey = 'ssh_last_profile_v1';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  Future<List<SshProfile>> loadProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profilesKey);
    if (raw == null || raw.isEmpty) return <SshProfile>[];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map(
            (item) => SshProfile.fromJson(
              Map<String, dynamic>.from(item as Map<dynamic, dynamic>),
            ),
          )
          .toList();
    } catch (_) {
      return <SshProfile>[];
    }
  }

  Future<void> _writeProfiles(List<SshProfile> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _profilesKey,
      jsonEncode(profiles.map((p) => p.toJson()).toList()),
    );
  }

  Future<void> upsertProfile(SshProfile profile) async {
    final profiles = await loadProfiles();
    final index = profiles.indexWhere((p) => p.id == profile.id);
    if (index >= 0) {
      profiles[index] = profile;
    } else {
      profiles.add(profile);
    }
    await _writeProfiles(profiles);
  }

  Future<void> deleteProfile(String id) async {
    final profiles = await loadProfiles();
    profiles.removeWhere((p) => p.id == id);
    await _writeProfiles(profiles);
    await saveSecrets(id, SshSecrets.empty);
  }

  String _secretKey(String id, String field) => 'ssh.$id.$field';

  Future<SshSecrets> loadSecrets(String id) async {
    try {
      return SshSecrets(
        password: await _secure.read(key: _secretKey(id, 'password')),
        privateKey: await _secure.read(key: _secretKey(id, 'key')),
        passphrase: await _secure.read(key: _secretKey(id, 'passphrase')),
      );
    } catch (_) {
      return SshSecrets.empty;
    }
  }

  /// Returns false when the secure storage refused the write.
  Future<bool> saveSecrets(String id, SshSecrets secrets) async {
    try {
      await _put(id, 'password', secrets.password);
      await _put(id, 'key', secrets.privateKey);
      await _put(id, 'passphrase', secrets.passphrase);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _put(String id, String field, String? value) async {
    final key = _secretKey(id, field);
    if (value == null || value.isEmpty) {
      await _secure.delete(key: key);
    } else {
      await _secure.write(key: key, value: value);
    }
  }

  Map<String, String> _readKnownHosts(SharedPreferences prefs) {
    final raw = prefs.getString(_knownHostsKey);
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(key, value.toString()));
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<String?> knownFingerprint(String host, int port) async {
    final prefs = await SharedPreferences.getInstance();
    return _readKnownHosts(prefs)['$host:$port'];
  }

  Future<void> rememberFingerprint(
    String host,
    int port,
    String fingerprint,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final hosts = _readKnownHosts(prefs);
    hosts['$host:$port'] = fingerprint;
    await prefs.setString(_knownHostsKey, jsonEncode(hosts));
  }

  Future<String?> lastProfileId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastProfileKey);
  }

  Future<void> setLastProfileId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastProfileKey, id);
  }
}
