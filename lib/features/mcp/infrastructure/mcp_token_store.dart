import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Recoverable local credentials. Authentication still uses a constant-time
/// digest comparison; only the OS-backed encrypted store contains plaintext.
class McpTokenStore extends ChangeNotifier {
  McpTokenStore({
    required SharedPreferences preferences,
    FlutterSecureStorage? storage,
  })  : _prefs = preferences,
        _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                storageNamespace: 'mcp_pairing',
                resetOnError: false,
              ),
            ) {
    final legacy = _prefs.getString(hashKey);
    if (legacy != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(legacy)) {
      _hash = legacy;
    }
  }

  static const hashKey = 'mcp.pairing.token_hash';
  static const hintKey = 'mcp.pairing.token_hint';
  static const tokenKey = 'mcp.pairing.token';
  static const tokenHexLength = 64;
  static const minCustomLength = 16;
  static const maxCustomLength = 256;

  final SharedPreferences _prefs;
  final FlutterSecureStorage _storage;
  final Random _random = Random.secure();
  String? _hash;
  String? _token;
  Future<void>? _initializing;
  Future<void> _pending = Future.value();
  bool _initialized = false;
  bool _loadFailed = false;
  bool _disposed = false;

  bool get hasToken => _hash != null;
  String? get token => _token;
  bool get isInitialized => _initialized;
  bool get loadFailed => _loadFailed;
  bool get isLegacyToken => _initialized && hasToken && _token == null;

  String? get tokenHint => _token == null
      ? _prefs.getString(hintKey)
      : '${_token!.substring(0, 4)}…${_token!.substring(_token!.length - 4)}';

  static bool isValidCustomToken(String value) {
    final token = value.trim();
    return token.length >= minCustomLength &&
        token.length <= maxCustomLength &&
        RegExp(r'^[A-Za-z0-9._~+/\-]+={0,2}$').hasMatch(token);
  }

  Future<void> initialize() {
    if (_initialized) return Future.value();
    return _initializing ??=
        Future<void>.sync(_load).whenComplete(() => _initializing = null);
  }

  Future<void> _load() async {
    try {
      final stored = await _storage.read(key: tokenKey);
      if (stored != null) {
        if (!isValidCustomToken(stored)) {
          throw const FormatException('Invalid stored credential');
        }
        _token = stored;
        _hash = _digest(stored);
      }
      _initialized = true;
      _loadFailed = false;
    } catch (_) {
      _loadFailed = true;
      throw StateError('Pairing credential storage is unavailable');
    } finally {
      _notify();
    }
  }

  Future<String> regenerate() => _serialize(() async {
        await initialize();
        final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
        final token =
            bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
        return _save(token);
      });

  Future<String> setCustomToken(String value) {
    if (!isValidCustomToken(value)) {
      throw ArgumentError('Invalid pairing credential format');
    }
    return _serialize(() async {
      await initialize();
      return _save(value.trim());
    });
  }

  Future<String> _save(String value) async {
    // Publish only after durable storage succeeds; failed writes retain the
    // previous visible token and the previous authentication digest.
    try {
      await _storage.write(key: tokenKey, value: value);
    } catch (_) {
      throw StateError('Unable to save pairing credential');
    }
    _token = value;
    _hash = _digest(value);
    _notify();
    // The encrypted value is authoritative. These keys are upgrade-only data.
    try {
      await _prefs.remove(hashKey);
      await _prefs.remove(hintKey);
    } catch (_) {
      // A preference cleanup failure must not roll back a durable credential.
    }
    return value;
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final next = _pending.then((_) => operation());
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  bool verify(String? bearerToken) {
    final token = bearerToken?.trim();
    if (token == null || token.isEmpty || token.length > maxCustomLength) {
      return false;
    }
    final expected = _hash;
    if (expected == null) return false;
    final provided = _digest(token);
    var diff = 0;
    for (var i = 0; i < expected.length; i++) {
      diff |= expected.codeUnitAt(i) ^ provided.codeUnitAt(i);
    }
    return diff == 0;
  }

  String get auditFingerprint => _hash?.substring(0, 8) ?? 'none';

  String _digest(String token) => sha256.convert(utf8.encode(token)).toString();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
