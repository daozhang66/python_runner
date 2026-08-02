import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RequestOverridePreview {
  const RequestOverridePreview({
    required this.headers,
    required this.userAgent,
    required this.cookie,
    this.matchedRuleIndex,
  });

  final Map<String, String> headers;
  final String userAgent;
  final String cookie;
  final int? matchedRuleIndex;
}

/// Stores user-defined request override settings.
/// These are injected into Python HTTP hooks to override default behavior.
class RequestOverrideConfig extends ChangeNotifier {
  RequestOverrideConfig._();
  static final RequestOverrideConfig instance = RequestOverrideConfig._();
  static const _bundleKey = 'req_override_config_v2';
  static const exportVersion = 1;

  bool _overrideEnabled = false;
  bool _recordRequests = true;
  bool _recordResponseBody = false;
  String _globalUserAgent = '';
  String _globalHeaders = ''; // JSON string: {"key":"value",...}
  String _globalCookie = '';
  int _defaultTimeout = 30;
  bool _followRedirects = true;
  bool _forceProxy = false;
  String _domainRulesJson = '[]';
  List<Map<String, dynamic>> _domainRules = [];
  Map<String, String> _parsedHeaders = const {};
  String? _globalHeadersError;
  String? _domainRulesError;

  bool get overrideEnabled => _overrideEnabled;
  bool get recordRequests => _recordRequests;
  bool get recordResponseBody => _recordResponseBody;
  String get globalUserAgent => _globalUserAgent;
  String get globalHeaders => _globalHeaders;
  String get globalCookie => _globalCookie;
  int get defaultTimeout => _defaultTimeout;
  bool get followRedirects => _followRedirects;
  bool get forceProxy => _forceProxy;
  String get domainRulesJson => _domainRulesJson;
  List<Map<String, dynamic>> get domainRules => List.unmodifiable(
        _domainRules.map((rule) => Map<String, dynamic>.from(rule)),
      );
  String? get configError {
    final errors = [
      _globalHeadersError,
      _domainRulesError,
    ].whereType<String>().where((e) => e.isNotEmpty).toList();
    if (errors.isEmpty) return null;
    return errors.join('\n');
  }

  bool get hasConfigError => configError != null;

  /// Headers parsed during [load] or [setGlobalHeaders]. Invalid persisted
  /// JSON is represented by [configError], never silently reparsed here.
  Map<String, String> get parsedHeaders => Map.unmodifiable(_parsedHeaders);

  /// Validate JSON string. Returns null if valid, error message otherwise.
  static String? validateJson(String jsonStr) {
    if (jsonStr.trim().isEmpty) return null;
    try {
      jsonDecode(jsonStr);
      return null;
    } catch (e) {
      return 'Invalid JSON: ${e.toString()}';
    }
  }

  /// Validate headers JSON. Returns null if valid, error message otherwise.
  static String? validateHeadersJson(String jsonStr) {
    if (jsonStr.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map) {
        return 'Headers must be a JSON object, not ${decoded.runtimeType}';
      }
      return null;
    } catch (e) {
      return 'Invalid JSON: ${e.toString()}';
    }
  }

  /// A rule targets a DNS host or a subdomain wildcard such as
  /// `*.example.com`. URLs, ports and paths are intentionally not accepted.
  static String? validateDomainPattern(String value) {
    if (value.isEmpty || value != value.trim()) {
      return 'Domain is required and cannot contain surrounding whitespace';
    }
    final pattern = value.startsWith('*.') ? value.substring(2) : value;
    if (pattern.isEmpty || value.contains(RegExp(r'[/:?#\\\s]'))) {
      return 'Domain must be a hostname or *.hostname';
    }
    final hostname = RegExp(
      r'^(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$',
    );
    return hostname.hasMatch(pattern)
        ? null
        : 'Domain must be a valid hostname';
  }

  static Map<String, String>? _parseHeadersJson(String jsonStr) {
    if (jsonStr.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map) return null;
      return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return null;
    }
  }

  static Map<String, String> _normalizeHeaders(Object? value) {
    if (value == null) return const {};
    if (value is! Map) {
      throw const FormatException('Headers must be a JSON object');
    }
    return Map.unmodifiable(
      value.map((key, item) => MapEntry(key.toString(), item.toString())),
    );
  }

  static List<Map<String, dynamic>> _normalizeRules(Object? value) {
    if (value == null) return const [];
    if (value is! List) {
      throw const FormatException('Domain rules must be a JSON array');
    }
    return List.unmodifiable(value.map((item) {
      if (item is! Map) {
        throw const FormatException('Each domain rule must be an object');
      }
      final domainValue = item['domain'];
      if (domainValue is! String) {
        throw const FormatException('Each domain rule requires a domain');
      }
      final domain = domainValue.toLowerCase();
      final domainError = validateDomainPattern(domain);
      if (domainError != null) throw FormatException(domainError);
      final headers = _normalizeHeaders(item['headers']);
      final rule = <String, dynamic>{'domain': domain};
      final userAgent = item['user_agent'];
      final cookie = item['cookie'];
      if (userAgent is String && userAgent.trim().isNotEmpty) {
        rule['user_agent'] = userAgent.trim();
      }
      if (cookie is String && cookie.trim().isNotEmpty) {
        rule['cookie'] = cookie.trim();
      }
      if (headers.isNotEmpty) rule['headers'] = headers;
      return rule;
    }).toList());
  }

  Map<String, dynamic> _bundle() => <String, dynamic>{
        'override_enabled': _overrideEnabled,
        'record_requests': _recordRequests,
        'record_response_body': _recordResponseBody,
        'global_user_agent': _globalUserAgent,
        'global_headers': _globalHeaders,
        'global_cookie': _globalCookie,
        'default_timeout': _defaultTimeout,
        'follow_redirects': _followRedirects,
        'force_proxy': _forceProxy,
        'domain_rules': _domainRules,
      };

  void _applyBundle(Map<dynamic, dynamic> data) {
    _overrideEnabled = data['override_enabled'] is bool
        ? data['override_enabled'] as bool
        : false;
    _recordRequests = data['record_requests'] is bool
        ? data['record_requests'] as bool
        : true;
    _recordResponseBody = data['record_response_body'] is bool
        ? data['record_response_body'] as bool
        : false;
    _globalUserAgent = (data['global_user_agent'] as String? ?? '').trim();
    _globalHeaders = (data['global_headers'] as String? ?? '').trim();
    final headersError = validateHeadersJson(_globalHeaders);
    _globalHeadersError =
        headersError == null ? null : '全局请求头配置错误: $headersError';
    _parsedHeaders = headersError == null
        ? (_parseHeadersJson(_globalHeaders) ?? const {})
        : const {};
    _globalCookie = (data['global_cookie'] as String? ?? '').trim();
    final timeout = data['default_timeout'];
    _defaultTimeout = timeout is int && timeout >= 0 ? timeout : 30;
    _followRedirects = data['follow_redirects'] is bool
        ? data['follow_redirects'] as bool
        : true;
    _forceProxy =
        data['force_proxy'] is bool ? data['force_proxy'] as bool : false;
    try {
      _domainRules = _normalizeRules(data['domain_rules']);
      _domainRulesJson = jsonEncode(_domainRules);
      _domainRulesError = null;
    } on FormatException catch (error) {
      _domainRules = [];
      _domainRulesJson = data['domain_rules'] is String
          ? data['domain_rules'] as String
          : jsonEncode(data['domain_rules'] ?? const []);
      _domainRulesError = '域名规则配置错误: ${error.message}';
    }
  }

  Future<void> _persistBundle(SharedPreferences prefs) async {
    await prefs.setString(_bundleKey, jsonEncode(_bundle()));
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bundled = prefs.getString(_bundleKey);
      if (bundled != null) {
        final decoded = jsonDecode(bundled);
        if (decoded is! Map) {
          throw const FormatException(
              'Saved request override bundle is invalid');
        }
        _applyBundle(decoded);
      } else {
        _applyBundle(<String, dynamic>{
          'override_enabled': prefs.getBool('req_override_enabled') ?? false,
          'record_requests': prefs.getBool('req_record_enabled') ?? true,
          'record_response_body': prefs.getBool('req_record_body') ?? false,
          'global_user_agent': prefs.getString('req_global_ua') ?? '',
          'global_headers': prefs.getString('req_global_headers') ?? '',
          'global_cookie': prefs.getString('req_global_cookie') ?? '',
          'default_timeout': prefs.getInt('req_default_timeout') ?? 30,
          'follow_redirects': prefs.getBool('req_follow_redirects') ?? true,
          'force_proxy': prefs.getBool('req_force_proxy') ?? false,
          'domain_rules': prefs.getString('req_domain_rules') ?? '[]',
        });
        try {
          final decodedRules = jsonDecode(_domainRulesJson);
          if (decodedRules is List) {
            _applyBundle(<String, dynamic>{
              ..._bundle(),
              'domain_rules': decodedRules,
            });
          }
        } catch (_) {}
        if (!hasConfigError) {
          await _persistBundle(prefs);
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('RequestOverrideConfig load error: $e');
    }
  }

  Future<void> _save(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
    await _persistBundle(prefs);
    notifyListeners();
  }

  Future<void> setOverrideEnabled(bool v) async {
    _overrideEnabled = v;
    await _save('req_override_enabled', v);
  }

  Future<void> setRecordRequests(bool v) async {
    _recordRequests = v;
    await _save('req_record_enabled', v);
  }

  Future<void> setRecordResponseBody(bool v) async {
    _recordResponseBody = v;
    await _save('req_record_body', v);
  }

  Future<void> setGlobalUserAgent(String v) async {
    _globalUserAgent = v.trim();
    await _save('req_global_ua', _globalUserAgent);
  }

  Future<void> setGlobalHeaders(String v) async {
    final trimmed = v.trim();
    final error = validateHeadersJson(trimmed);
    if (error != null) {
      throw FormatException(error);
    }
    _globalHeaders = trimmed;
    _globalHeadersError = null;
    _parsedHeaders = _parseHeadersJson(trimmed) ?? const {};
    await _save('req_global_headers', _globalHeaders);
  }

  Future<void> setGlobalCookie(String v) async {
    _globalCookie = v.trim();
    await _save('req_global_cookie', _globalCookie);
  }

  Future<void> setDefaultTimeout(int v) async {
    _defaultTimeout = v;
    await _save('req_default_timeout', v);
  }

  Future<void> setFollowRedirects(bool v) async {
    _followRedirects = v;
    await _save('req_follow_redirects', v);
  }

  Future<void> setForceProxy(bool v) async {
    _forceProxy = v;
    await _save('req_force_proxy', v);
  }

  Future<void> setDomainRules(List<Map<String, dynamic>> rules) async {
    final normalized = _normalizeRules(rules);
    _domainRules = normalized;
    _domainRulesJson = jsonEncode(normalized);
    _domainRulesError = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('req_domain_rules', _domainRulesJson);
    await _persistBundle(prefs);
    notifyListeners();
  }

  Future<void> addDomainRule(Map<String, dynamic> rule) async {
    _domainRules.add(rule);
    await _saveDomainRules();
  }

  Future<void> removeDomainRule(int index) async {
    if (index >= 0 && index < _domainRules.length) {
      _domainRules.removeAt(index);
      await _saveDomainRules();
    }
  }

  Future<void> updateDomainRule(int index, Map<String, dynamic> rule) async {
    if (index >= 0 && index < _domainRules.length) {
      _domainRules[index] = rule;
      await _saveDomainRules();
    }
  }

  Future<void> _saveDomainRules() async {
    _domainRulesJson = jsonEncode(_domainRules);
    _domainRulesError = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('req_domain_rules', _domainRulesJson);
    await _persistBundle(prefs);
    notifyListeners();
  }

  /// Validates every field before replacing the active override configuration.
  /// The persisted v2 bundle is a single preference value, so readers never
  /// observe a partially edited configuration.
  Future<void> applyOverrides({
    required String userAgent,
    required String headersJson,
    required String cookie,
    required int timeoutSeconds,
    required bool followRedirects,
    required bool useDebugProxyWhenUnset,
    required List<Map<String, dynamic>> domainRules,
  }) async {
    if (timeoutSeconds < 0) {
      throw const FormatException('Timeout cannot be negative');
    }
    final headersError = validateHeadersJson(headersJson.trim());
    if (headersError != null) throw FormatException(headersError);
    final parsedHeaders = _parseHeadersJson(headersJson.trim()) ?? const {};
    final normalizedRules = _normalizeRules(domainRules);

    final previous = _bundle();
    _globalUserAgent = userAgent.trim();
    _globalHeaders = jsonEncode(parsedHeaders);
    _parsedHeaders = parsedHeaders;
    _globalHeadersError = null;
    _globalCookie = cookie.trim();
    _defaultTimeout = timeoutSeconds;
    _followRedirects = followRedirects;
    _forceProxy = useDebugProxyWhenUnset;
    _domainRules = normalizedRules;
    _domainRulesJson = jsonEncode(normalizedRules);
    _domainRulesError = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      await _persistBundle(prefs);
      // The v2 bundle is authoritative and is written atomically above. The
      // individual values only serve older installations, so a mirror failure
      // must not make memory disagree with the successfully saved bundle.
      try {
        await Future.wait([
          prefs.setString('req_global_ua', _globalUserAgent),
          prefs.setString('req_global_headers', _globalHeaders),
          prefs.setString('req_global_cookie', _globalCookie),
          prefs.setInt('req_default_timeout', _defaultTimeout),
          prefs.setBool('req_follow_redirects', _followRedirects),
          prefs.setBool('req_force_proxy', _forceProxy),
          prefs.setString('req_domain_rules', _domainRulesJson),
        ]);
      } catch (error) {
        debugPrint('RequestOverrideConfig legacy mirror error: $error');
      }
    } catch (_) {
      _applyBundle(previous);
      rethrow;
    }
    notifyListeners();
  }

  /// Builds a preview for an arbitrary candidate configuration without
  /// mutating or persisting the active settings.
  static RequestOverridePreview previewForValues({
    required String host,
    required String userAgent,
    required String headersJson,
    required String cookie,
    required List<Map<String, dynamic>> domainRules,
  }) {
    final normalizedHost = host.trim().toLowerCase();
    final headers = Map<String, String>.from(
      _parseHeadersJson(headersJson.trim()) ?? const {},
    );
    var effectiveUserAgent = userAgent.trim();
    var effectiveCookie = cookie.trim();
    int? matchedRuleIndex;
    for (var index = 0; index < domainRules.length; index++) {
      final rule = domainRules[index];
      final pattern = rule['domain'] as String;
      final suffix = pattern.startsWith('*.') ? pattern.substring(2) : pattern;
      final matches = pattern.startsWith('*.')
          ? normalizedHost == suffix || normalizedHost.endsWith('.$suffix')
          : normalizedHost == suffix || normalizedHost.endsWith('.$suffix');
      if (!matches) continue;
      matchedRuleIndex = index;
      final ruleHeaders = rule['headers'];
      if (ruleHeaders is Map) {
        headers.addAll(_normalizeHeaders(ruleHeaders));
      }
      effectiveUserAgent =
          (rule['user_agent'] as String?) ?? effectiveUserAgent;
      effectiveCookie = (rule['cookie'] as String?) ?? effectiveCookie;
      break;
    }
    return RequestOverridePreview(
      headers: Map.unmodifiable(headers),
      userAgent: effectiveUserAgent,
      cookie: effectiveCookie,
      matchedRuleIndex: matchedRuleIndex,
    );
  }

  RequestOverridePreview previewForHost(String host) => previewForValues(
        host: host,
        userAgent: _globalUserAgent,
        headersJson: _globalHeaders,
        cookie: _globalCookie,
        domainRules: _domainRules,
      );

  String exportOverrides() => jsonEncode(<String, dynamic>{
        'version': exportVersion,
        'globalUserAgent': _globalUserAgent,
        'headers': _parsedHeaders,
        'cookie': _globalCookie,
        'defaultTimeout': _defaultTimeout,
        'followRedirects': _followRedirects,
        'useDebugProxyWhenUnset': _forceProxy,
        'domainRules': _domainRules,
      });

  Future<void> importOverrides(String rawJson) async {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map || decoded['version'] != exportVersion) {
      throw const FormatException('Unsupported request override export');
    }
    final userAgent = decoded['globalUserAgent'];
    final cookie = decoded['cookie'];
    final timeout = decoded['defaultTimeout'];
    final followRedirects = decoded['followRedirects'];
    final useProxy = decoded['useDebugProxyWhenUnset'];
    if (userAgent is! String ||
        cookie is! String ||
        timeout is! int ||
        followRedirects is! bool ||
        useProxy is! bool) {
      throw const FormatException('Request override export has invalid fields');
    }
    final headers = _normalizeHeaders(decoded['headers']);
    final rules = _normalizeRules(decoded['domainRules']);
    await applyOverrides(
      userAgent: userAgent,
      headersJson: jsonEncode(headers),
      cookie: cookie,
      timeoutSeconds: timeout,
      followRedirects: followRedirects,
      useDebugProxyWhenUnset: useProxy,
      domainRules: rules,
    );
  }

  /// Export current config as a JSON map (for passing to Python hook via env).
  Map<String, dynamic> toJson() {
    return {
      'override_enabled': _overrideEnabled,
      'record_requests': _recordRequests,
      'record_response_body': _recordResponseBody,
      'global_user_agent': _globalUserAgent,
      'global_headers': _globalHeaders,
      'global_cookie': _globalCookie,
      'default_timeout': _defaultTimeout,
      'follow_redirects': _followRedirects,
      'force_proxy': _forceProxy,
      'domain_rules': _domainRules,
    };
  }

  String toJsonString() => jsonEncode(toJson());
}
