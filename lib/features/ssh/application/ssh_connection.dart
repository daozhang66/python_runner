import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../domain/ssh_profile.dart';
import 'ssh_profile_store.dart';

enum SshFailureKind { noPrivateKey, badKey, uploadFailed }

class SshFailure implements Exception {
  const SshFailure(this.kind, [this.detail]);

  final SshFailureKind kind;
  final String? detail;

  @override
  String toString() => 'SshFailure($kind, $detail)';
}

/// Thrown when the user dismisses a password / passphrase prompt.
class SshCancelled implements Exception {
  const SshCancelled();
}

class HostKeyPrompt {
  const HostKeyPrompt({
    required this.host,
    required this.port,
    required this.keyType,
    required this.fingerprint,
    this.previousFingerprint,
  });

  final String host;
  final int port;
  final String keyType;
  final String fingerprint;

  /// Fingerprint trusted earlier for this host, if it differs from the new one.
  final String? previousFingerprint;
}

typedef HostKeyConfirm = Future<bool> Function(HostKeyPrompt prompt);
typedef SecretPrompt = Future<String?> Function();

/// One SSH connection to a [SshProfile].
class SshConnection {
  SshConnection(this.profile);

  final SshProfile profile;
  SSHClient? _client;

  Future<void> connect({
    required SshSecrets secrets,
    required SecretPrompt askPassword,
    required SecretPrompt askPassphrase,
    required HostKeyConfirm confirmHostKey,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    List<SSHKeyPair>? identities;
    String? password;

    if (profile.authType == SshAuthType.privateKey) {
      final pem = secrets.privateKey?.trim() ?? '';
      if (pem.isEmpty) throw const SshFailure(SshFailureKind.noPrivateKey);
      var passphrase = secrets.passphrase;
      if (SSHKeyPair.isEncryptedPem(pem) &&
          (passphrase == null || passphrase.isEmpty)) {
        passphrase = await askPassphrase();
        if (passphrase == null) throw const SshCancelled();
      }
      try {
        identities = SSHKeyPair.fromPem(pem, passphrase);
      } catch (error) {
        throw SshFailure(SshFailureKind.badKey, error.toString());
      }
    } else {
      password = secrets.password;
      if (password == null || password.isEmpty) {
        password = await askPassword();
        if (password == null) throw const SshCancelled();
      }
    }

    final socket = await SSHSocket.connect(
      profile.host,
      profile.port,
      timeout: timeout,
    );
    final store = SshProfileStore.instance;
    final secret = password;
    final client = SSHClient(
      socket,
      username: profile.username,
      identities: identities,
      onPasswordRequest: secret == null ? null : () => secret,
      onVerifyHostKey: (type, fingerprint) async {
        final shown = utf8.decode(fingerprint, allowMalformed: true);
        final known = await store.knownFingerprint(profile.host, profile.port);
        if (known == shown) return true;
        final accepted = await confirmHostKey(
          HostKeyPrompt(
            host: profile.host,
            port: profile.port,
            keyType: type,
            fingerprint: shown,
            previousFingerprint: known,
          ),
        );
        if (accepted) {
          await store.rememberFingerprint(profile.host, profile.port, shown);
        }
        return accepted;
      },
      keepAliveInterval: const Duration(seconds: 15),
      authTimeout: const Duration(seconds: 30),
    );
    _client = client;
    try {
      await client.authenticated;
    } catch (_) {
      close();
      rethrow;
    }
  }

  SSHClient get _ready {
    final client = _client;
    if (client == null) throw StateError('SSH connection is not open');
    return client;
  }

  Future<SSHSession> openShell(int cols, int rows) {
    return _ready.shell(
      pty: SSHPtyConfig(type: 'xterm-256color', width: cols, height: rows),
    );
  }

  /// Runs [command] with a pseudo terminal so interactive scripts work.
  Future<SSHSession> execPty(String command, int cols, int rows) {
    return _ready.execute(
      command,
      pty: SSHPtyConfig(type: 'xterm-256color', width: cols, height: rows),
    );
  }

  /// Runs [command] and feeds [content] to its stdin (used to upload a file).
  Future<void> uploadText(String command, String content) async {
    final session = await _ready.execute(command);
    final stderrText = session.stderr
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    unawaited(session.stdout.drain<void>());
    session.write(Uint8List.fromList(utf8.encode(content)));
    await session.stdin.close();
    await session.done;
    final message = (await stderrText).trim();
    final code = session.exitCode;
    if (code != null && code != 0) {
      throw SshFailure(
        SshFailureKind.uploadFailed,
        message.isEmpty ? 'exit code $code' : message,
      );
    }
  }

  void close() {
    final client = _client;
    _client = null;
    client?.close();
  }
}
