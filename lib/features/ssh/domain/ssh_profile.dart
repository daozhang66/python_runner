enum SshAuthType { password, privateKey }

/// A saved SSH host.
///
/// Secrets (password, private key, passphrase) live in secure storage and are
/// never part of this object.
class SshProfile {
  const SshProfile({
    required this.id,
    required this.name,
    required this.host,
    required this.username,
    this.port = 22,
    this.authType = SshAuthType.password,
    this.remoteDir = defaultRemoteDir,
    this.pythonCommand = defaultPythonCommand,
  });

  factory SshProfile.fromJson(Map<String, dynamic> json) {
    final auth = json['authType'] == SshAuthType.privateKey.name
        ? SshAuthType.privateKey
        : SshAuthType.password;
    return SshProfile(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      host: (json['host'] as String?) ?? '',
      username: (json['username'] as String?) ?? '',
      port: (json['port'] as num?)?.toInt() ?? 22,
      authType: auth,
      remoteDir: (json['remoteDir'] as String?) ?? defaultRemoteDir,
      pythonCommand:
          (json['pythonCommand'] as String?) ?? defaultPythonCommand,
    );
  }

  static const String defaultRemoteDir = '~/python_runner';
  static const String defaultPythonCommand = 'python3';

  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final SshAuthType authType;

  /// Remote directory scripts are uploaded to. A leading `~` means `$HOME`.
  final String remoteDir;

  /// Command used to start Python on the remote side, e.g. `python3`.
  final String pythonCommand;

  String get endpoint => '$username@$host${port == 22 ? '' : ':$port'}';

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'authType': authType.name,
        'remoteDir': remoteDir,
        'pythonCommand': pythonCommand,
      };
}
