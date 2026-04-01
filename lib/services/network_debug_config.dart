import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_logger.dart';

/// Network debug configuration — controls proxy and SSL trust settings.
/// Default: debug mode OFF, strict SSL, no proxy.
class NetworkDebugConfig {
  NetworkDebugConfig._();
  static final NetworkDebugConfig instance = NetworkDebugConfig._();

  bool _debugModeEnabled = false;
  bool _allowInsecureCerts = false;
  String _proxyHost = '';
  int _proxyPort = 0;

  bool get debugModeEnabled => _debugModeEnabled;
  bool get allowInsecureCerts => _debugModeEnabled && _allowInsecureCerts;
  String get proxyHost => _proxyHost;
  int get proxyPort => _proxyPort;
  bool get hasProxy => _debugModeEnabled && _proxyHost.isNotEmpty && _proxyPort > 0;
  String get proxyAddress => '$_proxyHost:$_proxyPort';

  /// Load configuration from SharedPreferences.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _debugModeEnabled = prefs.getBool('net_debug_mode') ?? false;
      _allowInsecureCerts = prefs.getBool('net_allow_insecure') ?? false;
      _proxyHost = prefs.getString('net_proxy_host') ?? '';
      _proxyPort = prefs.getInt('net_proxy_port') ?? 0;

      if (_debugModeEnabled) {
        _applyHttpOverrides();
        AppLogger.instance.warn(
          '网络调试模式已启用',
          source: 'NetworkDebug',
          detail: '不安全证书: $_allowInsecureCerts, '
              '代理: ${hasProxy ? proxyAddress : "无"}',
        );
      } else {
        _removeHttpOverrides();
      }
    } catch (e) {
      debugPrint('NetworkDebugConfig load error: $e');
    }
  }

  /// Save a single setting and reload.
  Future<void> setDebugMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('net_debug_mode', value);
    _debugModeEnabled = value;
    await load();
  }

  Future<void> setAllowInsecureCerts(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('net_allow_insecure', value);
    _allowInsecureCerts = value;
    await load();
  }

  Future<void> setProxyHost(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('net_proxy_host', value.trim());
    _proxyHost = value.trim();
    await load();
  }

  Future<void> setProxyPort(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('net_proxy_port', value);
    _proxyPort = value;
    await load();
  }

  /// Apply HttpOverrides for debug mode (proxy + insecure certs).
  void _applyHttpOverrides() {
    HttpOverrides.global = _DebugHttpOverrides(
      allowInsecure: _allowInsecureCerts,
      proxyHost: hasProxy ? _proxyHost : null,
      proxyPort: hasProxy ? _proxyPort : null,
    );
  }

  /// Remove custom HttpOverrides, restore defaults.
  void _removeHttpOverrides() {
    HttpOverrides.global = null;
  }

  /// Create an HttpClient configured for current debug settings.
  /// Used by WebSocket and other custom network code.
  HttpClient createHttpClient() {
    final client = HttpClient();
    if (allowInsecureCerts) {
      client.badCertificateCallback = (cert, host, port) => true;
    }
    if (hasProxy) {
      client.findProxy = (uri) => 'PROXY $proxyAddress';
    }
    return client;
  }
}

class _DebugHttpOverrides extends HttpOverrides {
  final bool allowInsecure;
  final String? proxyHost;
  final int? proxyPort;

  _DebugHttpOverrides({
    required this.allowInsecure,
    this.proxyHost,
    this.proxyPort,
  });

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    if (allowInsecure) {
      client.badCertificateCallback = (cert, host, port) => true;
    }
    if (proxyHost != null && proxyPort != null && proxyPort! > 0) {
      client.findProxy = (uri) => 'PROXY $proxyHost:$proxyPort';
    }
    return client;
  }
}
