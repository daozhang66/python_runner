import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:pinenacl/ed25519.dart' show SigningKey;

class GeneratedSshKey {
  const GeneratedSshKey({required this.privatePem, required this.publicLine});

  /// Unencrypted OpenSSH private key.
  final String privatePem;

  /// One line to append to `authorized_keys`.
  final String publicLine;
}

/// Generates a new Ed25519 key pair.
GeneratedSshKey generateEd25519Key({String comment = 'python-runner'}) {
  final signingKey = SigningKey.generate();
  // pinenacl 0.6 keys are byte lists: copy them into plain Uint8Lists.
  // The signing key is the 32-byte seed followed by the 32-byte public key.
  final publicKey = Uint8List.fromList(signingKey.verifyKey.toList());
  final privateKey = Uint8List.fromList(signingKey.toList());
  final pair = OpenSSHEd25519KeyPair(publicKey, privateKey, comment);
  return GeneratedSshKey(
    privatePem: pair.toPem(),
    publicLine: publicKeyLine(pair, comment),
  );
}

/// `ssh-ed25519 AAAA… comment` for [pair].
String publicKeyLine(SSHKeyPair pair, [String comment = '']) {
  final blob = pair.toPublicKey().encode();
  final suffix = comment.isEmpty ? '' : ' $comment';
  return '${pair.name} ${base64.encode(blob)}$suffix';
}

/// Derives the public key line from a private key in PEM form, or returns
/// null when the key cannot be read (wrong format or missing passphrase).
String? publicKeyLineFromPem(
  String pem, {
  String? passphrase,
  String comment = 'python-runner',
}) {
  try {
    final pairs = SSHKeyPair.fromPem(pem, passphrase);
    if (pairs.isEmpty) return null;
    return publicKeyLine(pairs.first, comment);
  } catch (_) {
    return null;
  }
}
