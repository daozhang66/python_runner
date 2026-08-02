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
  int _loadVersion = 0;

  bool get debugModeEnabled => _debugModeEnabled;
  bool get allowInsecureCerts => _debugModeEnabled && _allowInsecureCerts;
  String get proxyHost => _proxyHost;
  int get proxyPort => _proxyPort;
  bool get hasProxy =>
      _debugModeEnabled && _proxyHost.isNotEmpty && _proxyPort > 0;
  bool get affectsGlobalHttpClients => allowInsecureCerts || hasProxy;
  String get proxyAddress =>
      '${_proxyHost.contains(':') ? '[$_proxyHost]' : _proxyHost}:$_proxyPort';

  /// Load configuration from SharedPreferences.
  Future<void> load() async {
    final version = ++_loadVersion;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (version != _loadVersion) return; // superseded by a newer call
      _debugModeEnabled = prefs.getBool('net_debug_mode') ?? false;
      _allowInsecureCerts = prefs.getBool('net_allow_insecure') ?? false;
      final savedHost = prefs.getString('net_proxy_host') ?? '';
      final savedPort = prefs.getInt('net_proxy_port') ?? 0;
      try {
        _validateProxy(savedHost, savedPort);
        _proxyHost = _normalizeProxyHost(savedHost);
        _proxyPort = savedPort;
      } on FormatException catch (error) {
        _proxyHost = '';
        _proxyPort = 0;
        AppLogger.instance.warn(
          '已忽略无效的代理配置',
          source: 'NetworkDebug',
          detail: error.message,
        );
      }

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
    await setProxy(value, _proxyPort);
  }

  Future<void> setProxyPort(int value) async {
    await setProxy(_proxyHost, value);
  }

  /// Save host and port together so validation cannot persist a partial proxy.
  ///
  /// An empty host paired with port zero clears the proxy. Otherwise, a valid
  /// hostname/IP literal and a port in 1..65535 are required.
  Future<void> setProxy(String host, int port) async {
    _validateProxy(host, port);
    final normalizedHost = _normalizeProxyHost(host);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('net_proxy_host', normalizedHost);
    await prefs.setInt('net_proxy_port', port);
    _proxyHost = normalizedHost;
    _proxyPort = port;
    if (_debugModeEnabled) {
      _applyHttpOverrides();
    }
  }

  static void _validateProxy(String host, int port) {
    final normalizedHost = _normalizeProxyHost(host);
    if (normalizedHost.isEmpty && port == 0) return;
    if (normalizedHost.isEmpty) {
      throw const FormatException('代理端口需要同时填写代理主机');
    }
    if (port < 1 || port > 65535) {
      throw const FormatException('代理端口必须在 1 到 65535 之间');
    }
  }

  static String _normalizeProxyHost(String value) {
    if (value != value.trim()) {
      throw const FormatException('代理主机不能包含首尾空白');
    }
    final host = value.trim();
    if (host.isEmpty) return '';
    if (host.contains(RegExp(r'[\s/@?#\\]')) || host.contains('://')) {
      throw const FormatException('代理主机必须是主机名、IPv4 或 IPv6 地址');
    }
    final unbracketed = host.startsWith('[') && host.endsWith(']')
        ? host.substring(1, host.length - 1)
        : host;
    final address = InternetAddress.tryParse(unbracketed);
    if (address != null) return address.address;
    if (host.contains(':')) {
      throw const FormatException('代理主机不能包含端口');
    }
    final hostname = RegExp(
      r'^(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)$',
    );
    if (!hostname.hasMatch(host)) {
      throw const FormatException('代理主机必须是合法主机名或 IP 地址');
    }
    return host.toLowerCase();
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
