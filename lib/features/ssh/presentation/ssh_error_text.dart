import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart' show SSHAuthFailError, SSHHostkeyError;

import '../application/ssh_connection.dart';
import 'ssh_text.dart';

/// Turns a connection error into a message a person can act on.
String describeSshError(Object error, SshText t) {
  if (error is SshFailure) {
    final detail = error.detail ?? '';
    switch (error.kind) {
      case SshFailureKind.noPrivateKey:
        return t(
          '这个主机没有保存私钥，请编辑主机后粘贴或生成私钥',
          'No private key is saved for this host. Edit it to paste or generate one.',
        );
      case SshFailureKind.badKey:
        return t('无法读取私钥：$detail', 'Cannot read the private key: $detail');
      case SshFailureKind.uploadFailed:
        return t('上传脚本失败：$detail', 'Uploading the script failed: $detail');
    }
  }
  if (error is SSHAuthFailError) {
    return t(
      '认证失败：用户名、密码或密钥不正确（服务器也可能禁用了该认证方式）',
      'Authentication failed: wrong username, password or key (or the server disables that method).',
    );
  }
  if (error is SSHHostkeyError) {
    return t('主机密钥校验失败或已被拒绝', 'Host key verification failed or was rejected');
  }
  if (error is SocketException) {
    return t('无法连接：${error.message}', 'Cannot connect: ${error.message}');
  }
  if (error is TimeoutException) {
    return t('连接超时', 'Connection timed out');
  }
  return error.toString();
}
