import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 配对令牌存储（计划 §8.2）。
///
/// - 令牌由密码学安全随机数生成（256 bit / 64 个十六进制字符）；
/// - 磁盘只保存 sha256 摘要与提示片段，不保存明文；生成时一次性返回明文；
/// - 重新生成后旧令牌立即失效（摘要被替换）；
/// - 令牌是否强制由 MCP 服务设置决定；令牌本身仍只保存摘要。
///
/// 说明：当前存储介质为项目已有的 SharedPreferences。迁移到 Android
/// Keystore 属于后续加固项（见 docs/mcp-development-log.md），摘要化保证
/// 明文令牌不出现在持久化与日志中。
class McpTokenStore {
  McpTokenStore({required SharedPreferences preferences})
      : _prefs = preferences;

  static const String hashKey = 'mcp.pairing.token_hash';
  static const String hintKey = 'mcp.pairing.token_hint';
  static const int tokenHexLength = 64; // 256 bit

  final SharedPreferences _prefs;
  final Random _random = Random.secure();

  bool get hasToken {
    final hash = _prefs.getString(hashKey);
    return hash != null && hash.length == 64;
  }

  /// 令牌提示片段（如 `a1b2…9f8e`），用于设置页展示。
  String? get tokenHint => _prefs.getString(hintKey);

  /// 生成新令牌：返回明文（仅此一次），并使旧令牌立即失效。
  Future<String> regenerate() async {
    final bytes =
        List<int>.generate(tokenHexLength ~/ 2, (_) => _random.nextInt(256));
    const hex = '0123456789abcdef';
    final token = bytes.map((byte) => hex[byte >> 4] + hex[byte & 15]).join();
    await _prefs.setString(hashKey, sha256.convert(token.codeUnits).toString());
    await _prefs.setString(
      hintKey,
      '${token.substring(0, 4)}…${token.substring(tokenHexLength - 4)}',
    );
    return token;
  }

  /// 校验 Bearer 令牌；无令牌或令牌不匹配返回 false。
  bool verify(String? bearerToken) {
    if (bearerToken == null || bearerToken.isEmpty) return false;
    final expected = _prefs.getString(hashKey);
    if (expected == null || expected.isEmpty) return false;
    // 掐头去尾空白，兼容客户端拼接差异。
    final provided = sha256.convert(bearerToken.trim().codeUnits).toString();
    return _constantTimeEquals(expected, provided);
  }

  /// 令牌指纹（前 8 位摘要），仅用于审计日志。
  String get auditFingerprint {
    final hash = _prefs.getString(hashKey);
    if (hash == null || hash.isEmpty) return 'none';
    return hash.substring(0, 8);
  }

  /// 常数时间比较，避免按位提前退出造成的时间侧信道。
  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
