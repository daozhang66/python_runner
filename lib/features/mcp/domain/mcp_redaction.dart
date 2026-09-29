/// 网络记录敏感头脱敏（计划 §6.3）。
///
/// 默认不返回完整请求头；即使返回，敏感值也必须替换为占位符。
class McpRedactor {
  const McpRedactor._();

  static const _exactSensitiveHeaders = {
    'authorization',
    'proxy-authorization',
    'cookie',
    'set-cookie',
    'x-api-key',
    'x-auth-token',
  };

  static const _sensitiveFragments = [
    'token',
    'secret',
    'password',
    'credential',
  ];

  static const String redactedValue = '<redacted>';

  static bool isSensitiveHeader(String name) {
    final normalized = name.trim().toLowerCase();
    if (_exactSensitiveHeaders.contains(normalized)) return true;
    return _sensitiveFragments.any(normalized.contains);
  }

  /// 返回脱敏后的头副本；原 Map 不被修改。
  static Map<String, String> redactHeaders(Map<String, String> headers) {
    return headers.map((name, value) {
      return MapEntry(name, isSensitiveHeader(name) ? redactedValue : value);
    });
  }

  /// URL 查询参数中的敏感键（精确匹配，小写比较）。
  static const _sensitiveQueryKeys = {
    'token',
    'access_token',
    'api_key',
    'apikey',
    'key',
    'password',
    'passwd',
    'secret',
    'signature',
    'sig',
    'auth',
    'credential',
    'session_id',
    'sessionid',
  };

  static bool isSensitiveQueryParam(String key) {
    final normalized = key.trim().toLowerCase();
    if (_sensitiveQueryKeys.contains(normalized)) return true;
    // 名称片段匹配（x-github-token 等），与请求头规则一致。
    return _sensitiveFragments.any(normalized.contains);
  }

  /// 清洗 URL：去掉 userinfo（user:pass@）与 fragment，敏感查询参数值
  /// 替换为占位符；非敏感参数保留。
  static String sanitizeUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      // 无 host 的相对/异常 URL：保守丢弃查询串。
      final queryStart = url.indexOf('?');
      return queryStart >= 0 ? url.substring(0, queryStart) : url;
    }
    final hostPart = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
    final schemePart = uri.scheme.isEmpty ? '' : '${uri.scheme}://';
    var result = '$schemePart$hostPart${uri.path}';
    if (uri.hasQuery) {
      final kept = <String>[];
      uri.queryParametersAll.forEach((key, values) {
        final sensitive = isSensitiveQueryParam(key);
        for (final value in values) {
          kept.add(
            '${Uri.encodeQueryComponent(key)}='
            '${sensitive ? redactedValue : Uri.encodeQueryComponent(value)}',
          );
        }
      });
      if (kept.isNotEmpty) result += '?${kept.join('&')}';
    }
    // fragment 一律丢弃。
    return result;
  }

  /// 文本体截断到预算内，返回内容与是否截断。
  static (String?, bool) truncateBody(String? body, int maxChars) {
    if (body == null) return (null, false);
    if (body.length <= maxChars) return (body, false);
    return (body.substring(0, maxChars), true);
  }
}
