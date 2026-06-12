import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores user-defined request override settings.
/// These are injected into Python HTTP hooks to override default behavior.
class RequestOverrideConfig extends ChangeNotifier {
  RequestOverrideConfig._();
  static final RequestOverrideConfig instance = RequestOverrideConfig._();

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
  List<Map<String, dynamic>> get domainRules => List.unmodifiable(_domainRules);
  String? get configError {
    final errors = [
      _globalHeadersError,
      _domainRulesError,
    ].whereType<String>().where((e) => e.isNotEmpty).toList();
    if (errors.isEmpty) return null;
    return errors.join('\n');
  }

  bool get hasConfigError => configError != null;

  /// Parse globalHeaders JSON into a Map. Invalid saved JSON is reported by configError.
  Map<String, String> get parsedHeaders {
    if (_globalHeaders.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(_globalHeaders);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {}
    return {};
  }

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

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _overrideEnabled = prefs.getBool('req_override_enabled') ?? false;
      _recordRequests = prefs.getBool('req_record_enabled') ?? true;
      _recordResponseBody = prefs.getBool('req_record_body') ?? false;
      _globalUserAgent = prefs.getString('req_global_ua') ?? '';
      _globalHeaders = prefs.getString('req_global_headers') ?? '';
      final headersError = validateHeadersJson(_globalHeaders);
      _globalHeadersError =
          headersError == null ? null : '全局请求头配置错误: $headersError';
      _globalCookie = prefs.getString('req_global_cookie') ?? '';
      _defaultTimeout = prefs.getInt('req_default_timeout') ?? 30;
      _followRedirects = prefs.getBool('req_follow_redirects') ?? true;
      _forceProxy = prefs.getBool('req_force_proxy') ?? false;
      _domainRulesJson = prefs.getString('req_domain_rules') ?? '[]';
      try {
        final decoded = jsonDecode(_domainRulesJson);
        if (decoded is! List) {
          throw FormatException(
            'Domain rules must be a JSON array, not ${decoded.runtimeType}',
          );
        }
        _domainRules = decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _domainRulesError = null;
      } catch (e) {
        _domainRules = [];
        _domainRulesError = '域名规则配置错误: $e';
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
    final String encoded;
    try {
      encoded = jsonEncode(rules);
    } catch (e) {
      throw FormatException('Invalid domain rules JSON: $e');
    }
    final error = validateJson(encoded);
    if (error != null) {
      throw FormatException(error);
    }
    _domainRules = List.from(rules);
    _domainRulesJson = encoded;
    _domainRulesError = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('req_domain_rules', encoded);
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
    notifyListeners();
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
