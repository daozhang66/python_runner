import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

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
  final int? responseBodyBytes;
  final bool responseBodyTruncated;
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
    this.responseBodyBytes,
    this.responseBodyTruncated = false,
    this.errorType,
    this.errorMessage,
    this.durationMs,
  });

  bool get isError => statusCode == null || statusCode! >= 400 || errorType != null;
  bool get isSuccess => statusCode != null && statusCode! >= 200 && statusCode! < 400;

  /// Whether the response body is a base64-encoded image (data URI).
  bool get isImageBody {
    final body = responseBodyPreview;
    if (body == null || !body.startsWith('data:image/')) return false;
    return true;
  }

  /// Whether the response body is an audio/video metadata record.
  bool get isMediaBody {
    final body = responseBodyPreview;
    return body != null && body.startsWith('media:');
  }

  /// Parse media metadata (type + size). Returns null if not media.
  Map<String, dynamic>? get mediaMeta {
    final body = responseBodyPreview;
    if (body == null || !body.startsWith('media:')) return null;
    try {
      return jsonDecode(body.substring(6)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Extract the image MIME type from the data URI, or null.
  String? get imageMimeType {
    final body = responseBodyPreview;
    if (body == null || !body.startsWith('data:image/')) return null;
    final end = body.indexOf(';');
    if (end < 0) return null;
    return body.substring(5, end); // skip "data:"
  }

  /// Extract domain from URL.
  String get domain {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return url;
    }
  }

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

  int get capturedResponseBodyBytes {
    final body = responseBodyPreview;
    if (body == null || body.isEmpty) return 0;
    try {
      return utf8.encode(body).length;
    } catch (_) {
      return body.length;
    }
  }

  int get storedBodyBytes =>
      (requestBody?.length ?? 0) + capturedResponseBodyBytes;

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
      responseBodyBytes: (json['response_body_size'] as num?)?.toInt(),
      responseBodyTruncated: json['response_body_truncated'] == true ||
          ((json['response_body_preview'] as String?)?.endsWith('... (truncated)') ?? false),
      errorType: json['error_type'] as String?,
      errorMessage: json['error_message'] as String?,
      durationMs: json['duration_ms'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'method': method,
      'url': url,
      'request_headers': requestHeaders,
      'request_body': requestBody,
      'used_proxy': usedProxy,
      'ssl_verify': sslVerify,
      'library': library,
      'status_code': statusCode,
      'response_headers': responseHeaders,
      'response_body_preview': responseBodyPreview,
      'response_body_size': responseBodyBytes ?? capturedResponseBodyBytes,
      'response_body_truncated': responseBodyTruncated,
      'error_type': errorType,
      'error_message': errorMessage,
      'duration_ms': durationMs,
    };
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
      final label = responseBodyTruncated ? '--- Response Body Preview ---' : '--- Response Body ---';
      buf.writeln(label);
      if (responseBodyTruncated && responseBodyBytes != null) {
        buf.writeln('  [captured $capturedResponseBodyBytes / $responseBodyBytes bytes]');
      }
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
  HttpInspectorStore._({
    Future<Directory> Function()? supportDirectoryProvider,
    Duration persistDebounce = _defaultPersistDebounce,
  })  : _supportDirectoryProvider =
            supportDirectoryProvider ?? getApplicationSupportDirectory,
        _persistDebounce = persistDebounce;

  static final HttpInspectorStore instance = HttpInspectorStore._();

  static const int maxRecords = 5000;
  static const int maxCapturedBodyBytes = 24 * 1024 * 1024;
  static const Duration _defaultPersistDebounce = Duration(milliseconds: 250);
  static const String _storageFileName = 'http_inspector_records.json';

  @visibleForTesting
  factory HttpInspectorStore.test({
    required Future<Directory> Function() supportDirectoryProvider,
    Duration persistDebounce = _defaultPersistDebounce,
  }) {
    return HttpInspectorStore._(
      supportDirectoryProvider: supportDirectoryProvider,
      persistDebounce: persistDebounce,
    );
  }

  final List<HttpRecord> _records = [];
  final Future<Directory> Function() _supportDirectoryProvider;
  final Duration _persistDebounce;
  String _filterDomain = '';
  String _filterMethod = '';
  int? _filterStatus; // null = all, 0 = errors, 200 = 2xx, etc.
  Timer? _persistTimer;
  Future<void>? _loadFuture;
  Future<void> _persistChain = Future<void>.value();
  bool _loaded = false;

  List<HttpRecord> get records => List.unmodifiable(_records);
  int get count => _records.length;

  String get filterDomain => _filterDomain;
  String get filterMethod => _filterMethod;
  int? get filterStatus => _filterStatus;
  bool get isLoaded => _loaded;

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

  /// Get domain statistics: list of (domain, count) sorted by count desc.
  List<MapEntry<String, int>> get domainStats {
    final counts = <String, int>{};
    for (final r in _records) {
      final d = r.domain;
      if (d.isNotEmpty) {
        counts[d] = (counts[d] ?? 0) + 1;
      }
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  /// Add a new record from Python hook JSON.
  void addFromJson(Map<String, dynamic> json) {
    try {
      if (json['note'] != null) return;
      final record = HttpRecord.fromJson(json);
      if (record.url.isEmpty) return;
      _records.add(record);
      _applyLimits();
      notifyListeners();
      _schedulePersist();
    } catch (e) {
      debugPrint('HttpInspectorStore.addFromJson error: $e');
    }
  }

  /// Clear all records.
  void clear() {
    _records.clear();
    notifyListeners();
    _schedulePersist();
  }

  Future<void> ensureLoaded() {
    return _loadFuture ??= _loadFromDisk();
  }

  Future<void> flush() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    await _persistNow();
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
      'size': r.responseBodyBytes ?? r.responseBodyPreview?.length ?? 0,
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
        'bodySize': r.responseBodyBytes ?? r.responseBodyPreview?.length ?? -1,
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

  static List<HttpRecord> trimRecords(
    List<HttpRecord> records, {
    int maxRecords = HttpInspectorStore.maxRecords,
    int maxCapturedBodyBytes = HttpInspectorStore.maxCapturedBodyBytes,
  }) {
    final trimmed = List<HttpRecord>.from(records);

    if (trimmed.length > maxRecords) {
      trimmed.removeRange(0, trimmed.length - maxRecords);
    }

    var totalBytes = trimmed.fold<int>(0, (sum, record) => sum + record.storedBodyBytes);
    while (totalBytes > maxCapturedBodyBytes && trimmed.length > 1) {
      totalBytes -= trimmed.first.storedBodyBytes;
      trimmed.removeAt(0);
    }
    return trimmed;
  }

  void _applyLimits() {
    final trimmed = trimRecords(_records);
    if (trimmed.length == _records.length) return;
    _records
      ..clear()
      ..addAll(trimmed);
  }

  void _schedulePersist() {
    if (_persistTimer != null) return;
    _persistTimer = Timer(_persistDebounce, () {
      _persistTimer = null;
      unawaited(_persistNow());
    });
  }

  Future<void> _loadFromDisk() async {
    try {
      final file = await _storageFile();
      if (await file.exists()) {
        final text = await file.readAsString();
        final decoded = jsonDecode(text);
        if (decoded is List) {
          final loaded = decoded
              .whereType<Map>()
              .map((e) => HttpRecord.fromJson(Map<String, dynamic>.from(e)))
              .where((record) => record.url.isNotEmpty)
              .toList();
          _records
            ..clear()
            ..addAll(trimRecords(loaded));
        }
      }
    } catch (e) {
      debugPrint('HttpInspectorStore.load error: $e');
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> _persistNow() async {
    final snapshot = _records.map((record) => record.toJson()).toList(growable: false);
    _persistChain = _persistChain.then((_) async {
      try {
        final file = await _storageFile();
        await file.parent.create(recursive: true);
        final payload = jsonEncode(snapshot);
        await file.writeAsString(payload, flush: true);
      } catch (e) {
        debugPrint('HttpInspectorStore.persist error: $e');
      }
    }, onError: (_) async {
      try {
        final file = await _storageFile();
        await file.parent.create(recursive: true);
        final payload = jsonEncode(snapshot);
        await file.writeAsString(payload, flush: true);
      } catch (e) {
        debugPrint('HttpInspectorStore.persist error: $e');
      }
    });
    await _persistChain;
  }

  Future<File> _storageFile() async {
    final dir = await _supportDirectoryProvider();
    return File('${dir.path}${Platform.pathSeparator}$_storageFileName');
  }
}
