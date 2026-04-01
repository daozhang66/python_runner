import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// A single captured HTTP request/response record.
class HttpRecord {
  final String id;
  final DateTime timestamp;
  final String method;
  final String url;
  final Map<String, String> requestHeaders;
  final String? requestBody;
  final bool usedProxy;
  final bool sslVerify;
  final String library; // requests / httpx / urllib3

  // Response
  int? statusCode;
  Map<String, String>? responseHeaders;
  String? responseBodyPreview;
  String? errorType;
  String? errorMessage;
  int? durationMs;

  HttpRecord({
    required this.id,
    required this.timestamp,
    required this.method,
    required this.url,
    required this.requestHeaders,
    this.requestBody,
    this.usedProxy = false,
    this.sslVerify = true,
    this.library = 'unknown',
    this.statusCode,
    this.responseHeaders,
    this.responseBodyPreview,
    this.errorType,
    this.errorMessage,
    this.durationMs,
  });

  bool get isError => statusCode == null || statusCode! >= 400 || errorType != null;
  bool get isSuccess => statusCode != null && statusCode! >= 200 && statusCode! < 400;

  String get statusText {
    if (errorType != null) return errorType!;
    if (statusCode == null) return 'pending';
    return statusCode.toString();
  }

  String get durationText {
    if (durationMs == null) return '-';
    if (durationMs! < 1000) return '${durationMs}ms';
    return '${(durationMs! / 1000).toStringAsFixed(1)}s';
  }

  /// Parse from JSON map sent by Python hook.
  factory HttpRecord.fromJson(Map<String, dynamic> json) {
    Map<String, String> parseHeaders(dynamic h) {
      if (h == null) return {};
      if (h is Map) return h.map((k, v) => MapEntry(k.toString(), v.toString()));
      if (h is String && h.isNotEmpty) {
        try {
          final decoded = jsonDecode(h);
          if (decoded is Map) return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        } catch (_) {}
      }
      return {};
    }

    return HttpRecord(
      id: json['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
      timestamp: json['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch((json['timestamp'] as num).toInt())
          : DateTime.now(),
      method: (json['method'] as String?)?.toUpperCase() ?? 'GET',
      url: json['url'] as String? ?? '',
      requestHeaders: parseHeaders(json['request_headers']),
      requestBody: json['request_body'] as String?,
      usedProxy: json['used_proxy'] == true,
      sslVerify: json['ssl_verify'] != false,
      library: json['library'] as String? ?? 'unknown',
      statusCode: json['status_code'] as int?,
      responseHeaders: parseHeaders(json['response_headers']),
      responseBodyPreview: json['response_body_preview'] as String?,
      errorType: json['error_type'] as String?,
      errorMessage: json['error_message'] as String?,
      durationMs: json['duration_ms'] as int?,
    );
  }

  /// Export as formatted text for logging/export.
  String toExportText() {
    final buf = StringBuffer();
    final ts = DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(timestamp);
    buf.writeln('[$ts] $method $url');
    buf.writeln('Library: $library | Proxy: $usedProxy | SSL Verify: $sslVerify | Duration: $durationText');
    buf.writeln('--- Request Headers ---');
    requestHeaders.forEach((k, v) => buf.writeln('  $k: $v'));
    if (requestBody != null && requestBody!.isNotEmpty) {
      buf.writeln('--- Request Body ---');
      buf.writeln('  $requestBody');
    }
    buf.writeln('--- Response ---');
    buf.writeln('  Status: $statusText');
    if (responseHeaders != null && responseHeaders!.isNotEmpty) {
      buf.writeln('--- Response Headers ---');
      responseHeaders!.forEach((k, v) => buf.writeln('  $k: $v'));
    }
    if (responseBodyPreview != null && responseBodyPreview!.isNotEmpty) {
      buf.writeln('--- Response Body Preview ---');
      buf.writeln('  $responseBodyPreview');
    }
    if (errorMessage != null) {
      buf.writeln('--- Error ---');
      buf.writeln('  $errorType: $errorMessage');
    }
    return buf.toString();
  }
}

/// In-memory store for captured HTTP records.
class HttpInspectorStore extends ChangeNotifier {
  HttpInspectorStore._();
  static final HttpInspectorStore instance = HttpInspectorStore._();

  static const int maxRecords = 500;

  final List<HttpRecord> _records = [];
  String _filterDomain = '';
  String _filterMethod = '';
  int? _filterStatus; // null = all, 0 = errors, 200 = 2xx, etc.

  List<HttpRecord> get records => List.unmodifiable(_records);
  int get count => _records.length;

  String get filterDomain => _filterDomain;
  String get filterMethod => _filterMethod;
  int? get filterStatus => _filterStatus;

  /// Get filtered records (newest first).
  List<HttpRecord> get filteredRecords {
    var list = _records.reversed.toList();
    if (_filterDomain.isNotEmpty) {
      final d = _filterDomain.toLowerCase();
      list = list.where((r) => r.url.toLowerCase().contains(d)).toList();
    }
    if (_filterMethod.isNotEmpty) {
      list = list.where((r) => r.method == _filterMethod.toUpperCase()).toList();
    }
    if (_filterStatus != null) {
      if (_filterStatus == 0) {
        list = list.where((r) => r.isError).toList();
      } else {
        final base = _filterStatus!;
        list = list.where((r) =>
            r.statusCode != null &&
            r.statusCode! >= base &&
            r.statusCode! < base + 100).toList();
      }
    }
    return list;
  }

  void setFilterDomain(String v) {
    _filterDomain = v;
    notifyListeners();
  }

  void setFilterMethod(String v) {
    _filterMethod = v;
    notifyListeners();
  }

  void setFilterStatus(int? v) {
    _filterStatus = v;
    notifyListeners();
  }

  void clearFilters() {
    _filterDomain = '';
    _filterMethod = '';
    _filterStatus = null;
    notifyListeners();
  }

  /// Add a new record from Python hook JSON.
  void addFromJson(Map<String, dynamic> json) {
    try {
      final record = HttpRecord.fromJson(json);
      _records.add(record);
      if (_records.length > maxRecords) {
        _records.removeRange(0, _records.length - maxRecords);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('HttpInspectorStore.addFromJson error: $e');
    }
  }

  /// Clear all records.
  void clear() {
    _records.clear();
    notifyListeners();
  }

  /// Export all records as text.
  String exportAll() {
    if (_records.isEmpty) return '(无网络请求记录)';
    final buf = StringBuffer();
    buf.writeln('====== 网络请求记录 (${_records.length} 条) ======');
    buf.writeln();
    for (final r in _records) {
      buf.writeln(r.toExportText());
      buf.writeln('${'─' * 50}');
    }
    return buf.toString();
  }

  /// Export filtered records as text.
  String exportFiltered() {
    final list = filteredRecords;
    if (list.isEmpty) return '(无匹配的网络请求记录)';
    final buf = StringBuffer();
    buf.writeln('====== 网络请求记录 (${list.length} 条) ======');
    buf.writeln();
    for (final r in list) {
      buf.writeln(r.toExportText());
      buf.writeln('${'─' * 50}');
    }
    return buf.toString();
  }

  /// Export records as HAR 1.2 JSON format.
  String exportHar({bool filteredOnly = false}) {
    final list = filteredOnly ? filteredRecords : _records;
    final entries = list.map((r) => _recordToHarEntry(r)).toList();
    final har = {
      'log': {
        'version': '1.2',
        'creator': {
          'name': 'PythonRunner',
          'version': '1.3.0',
        },
        'entries': entries,
      },
    };
    return jsonEncode(har);
  }

  Map<String, dynamic> _recordToHarEntry(HttpRecord r) {
    final startedDateTime = r.timestamp.toUtc().toIso8601String();
    final timeMs = r.durationMs ?? 0;

    // Request headers
    final reqHeaders = r.requestHeaders.entries
        .map((e) => {'name': e.key, 'value': e.value})
        .toList();

    // Response headers
    final resHeaders = (r.responseHeaders ?? {})
        .entries
        .map((e) => {'name': e.key, 'value': e.value})
        .toList();

    // Request body
    Map<String, dynamic>? postData;
    if (r.requestBody != null && r.requestBody!.isNotEmpty) {
      postData = {
        'mimeType': 'application/octet-stream',
        'text': r.requestBody,
      };
    }

    // Response body
    Map<String, dynamic> responseContent = {
      'size': r.responseBodyPreview?.length ?? 0,
      'mimeType': _extractMimeType(r.responseHeaders),
    };
    if (r.responseBodyPreview != null && r.responseBodyPreview!.isNotEmpty) {
      responseContent['text'] = r.responseBodyPreview;
    }

    final entry = <String, dynamic>{
      'startedDateTime': startedDateTime,
      'time': timeMs,
      'request': {
        'method': r.method,
        'url': r.url,
        'httpVersion': 'HTTP/1.1',
        'cookies': <dynamic>[],
        'headers': reqHeaders,
        'queryString': _parseQueryString(r.url),
        'headersSize': -1,
        'bodySize': r.requestBody?.length ?? 0,
        if (postData != null) 'postData': postData,
      },
      'response': {
        'status': r.statusCode ?? 0,
        'statusText': r.errorType ?? (r.statusCode != null ? '' : 'Error'),
        'httpVersion': 'HTTP/1.1',
        'cookies': <dynamic>[],
        'headers': resHeaders,
        'content': responseContent,
        'redirectURL': '',
        'headersSize': -1,
        'bodySize': r.responseBodyPreview?.length ?? -1,
      },
      'cache': <String, dynamic>{},
      'timings': {
        'send': 0,
        'wait': timeMs,
        'receive': 0,
      },
      'comment': 'library: ${r.library}',
    };

    if (r.errorMessage != null) {
      entry['_error'] = '${r.errorType}: ${r.errorMessage}';
    }

    return entry;
  }

  String _extractMimeType(Map<String, String>? headers) {
    if (headers == null) return 'text/plain';
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == 'content-type') {
        return e.value.split(';').first.trim();
      }
    }
    return 'text/plain';
  }

  List<Map<String, String>> _parseQueryString(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.queryParameters.entries
          .map((e) => {'name': e.key, 'value': e.value})
          .toList();
    } catch (_) {
      return [];
    }
  }
}
