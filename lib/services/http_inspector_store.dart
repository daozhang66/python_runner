import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

@visibleForTesting
typedef HttpInspectorStorageWriter = Future<void> Function(
  File file,
  String payload,
);

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

  HttpRecord copyWith({
    String? requestBody,
    bool clearRequestBody = false,
    int? statusCode,
    Map<String, String>? responseHeaders,
    String? responseBodyPreview,
    bool clearResponseBodyPreview = false,
    int? responseBodyBytes,
    bool? responseBodyTruncated,
    String? errorType,
    String? errorMessage,
    int? durationMs,
  }) {
    return HttpRecord(
      id: id,
      timestamp: timestamp,
      method: method,
      url: url,
      requestHeaders: requestHeaders,
      requestBody: clearRequestBody ? null : (requestBody ?? this.requestBody),
      usedProxy: usedProxy,
      sslVerify: sslVerify,
      library: library,
      statusCode: statusCode ?? this.statusCode,
      responseHeaders: responseHeaders ?? this.responseHeaders,
      responseBodyPreview: clearResponseBodyPreview
          ? null
          : (responseBodyPreview ?? this.responseBodyPreview),
      responseBodyBytes: responseBodyBytes ?? this.responseBodyBytes,
      responseBodyTruncated:
          responseBodyTruncated ?? this.responseBodyTruncated,
      errorType: errorType ?? this.errorType,
      errorMessage: errorMessage ?? this.errorMessage,
      durationMs: durationMs ?? this.durationMs,
    );
  }

  bool get isError =>
      statusCode == null || statusCode! >= 400 || errorType != null;
  bool get isSuccess =>
      statusCode != null && statusCode! >= 200 && statusCode! < 400;

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

  /// Exact UTF-8 cost of this record in the V2 JSONL active log.
  ///
  /// Records are immutable once admitted to the store; caching avoids encoding
  /// the whole active window again whenever a new capture is appended.
  late final int storedJsonBytes = utf8.encode(jsonEncode(toJson())).length + 1;

  /// Parse from JSON map sent by Python hook.
  factory HttpRecord.fromJson(Map<String, dynamic> json) {
    Map<String, String> parseHeaders(dynamic h) {
      if (h == null) return {};
      if (h is Map) {
        return h.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
      if (h is String && h.isNotEmpty) {
        try {
          final decoded = jsonDecode(h);
          if (decoded is Map) {
            return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
          }
        } catch (_) {}
      }
      return {};
    }

    return HttpRecord(
      id: json['id']?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      timestamp: json['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['timestamp'] as num).toInt())
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
          ((json['response_body_preview'] as String?)
                  ?.endsWith('... (truncated)') ??
              false),
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
    buf.writeln(
        'Library: $library | Proxy: $usedProxy | SSL Verify: $sslVerify | Duration: $durationText');
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
      final label = responseBodyTruncated
          ? '--- Response Body Preview ---'
          : '--- Response Body ---';
      buf.writeln(label);
      if (responseBodyTruncated && responseBodyBytes != null) {
        buf.writeln(
            '  [captured $capturedResponseBodyBytes / $responseBodyBytes bytes]');
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
    Duration persistMaxDelay = _defaultPersistMaxDelay,
    bool throwOnStorageError = false,
    HttpInspectorStorageWriter? storageWriter,
  })  : _supportDirectoryProvider =
            supportDirectoryProvider ?? getApplicationSupportDirectory,
        _persistDebounce = persistDebounce,
        _persistMaxDelay = persistMaxDelay,
        _throwOnStorageError = throwOnStorageError,
        _storageWriter = storageWriter ?? _defaultStorageWriter,
        _usesStorageWriterOverride = storageWriter != null;

  static final HttpInspectorStore instance = HttpInspectorStore._();

  /// Maximum number of recent records available to the inspector UI.
  static const int maxRecords = 5000;

  /// Maximum total persisted size of the active JSONL window.
  static const int maxCapturedBodyBytes = 8 * 1024 * 1024;

  /// Hard limit for all newly captured data in one persisted record, including
  /// headers, URL and errors as well as request/response bodies.
  static const int maxBodyBytesPerNewRecord = 256 * 1024;

  static const int _maxHeadersPerNewRecord = 64;
  static const int _maxHeaderNameBytes = 256;
  static const int _maxHeaderValueBytes = 1024;
  static const int _maxUrlBytes = 8192;
  static const int _maxErrorBytes = 8192;
  static const int _maxLibraryBytes = 128;
  static const Duration _defaultPersistDebounce = Duration(milliseconds: 250);
  static const Duration _defaultPersistMaxDelay = Duration(seconds: 2);
  static const String _storageFileName = 'http_inspector_records.v2.jsonl';
  static const String _legacyStorageFileName = 'http_inspector_records.json';
  static const String _legacyArchiveFileName =
      'http_inspector_records.legacy.json';
  static const String _hideNoiseMethodsPrefsKey =
      'http_inspector_hide_noise_methods';
  static const Set<String> noiseMethods = {'DNS', 'CONNECT', 'PROCESS'};

  @visibleForTesting
  factory HttpInspectorStore.test({
    required Future<Directory> Function() supportDirectoryProvider,
    Duration persistDebounce = _defaultPersistDebounce,
    Duration persistMaxDelay = _defaultPersistMaxDelay,
    bool throwOnStorageError = true,
    HttpInspectorStorageWriter? storageWriter,
  }) {
    return HttpInspectorStore._(
      supportDirectoryProvider: supportDirectoryProvider,
      persistDebounce: persistDebounce,
      persistMaxDelay: persistMaxDelay,
      throwOnStorageError: throwOnStorageError,
      storageWriter: storageWriter,
    );
  }

  final List<HttpRecord> _records = [];
  final Future<Directory> Function() _supportDirectoryProvider;
  final Duration _persistDebounce;
  final Duration _persistMaxDelay;
  final bool _throwOnStorageError;
  final HttpInspectorStorageWriter _storageWriter;
  final bool _usesStorageWriterOverride;
  String _filterDomain = '';
  String _filterMethod = '';
  int? _filterStatus; // null = all, 0 = errors, 200 = 2xx, etc.
  bool _hideNoiseMethods = true;
  int _totalCount = 0;
  int _successCount = 0;
  int _errorCount = 0;
  int _totalDurationMs = 0;
  int _durationCount = 0;
  Timer? _persistDebounceTimer;
  Timer? _persistMaxDelayTimer;
  Future<void>? _loadFuture;
  Future<void>? _displayPreferencesLoadFuture;
  Future<void>? _persistFuture;
  int _dirtyRevision = 0;
  int _persistedRevision = 0;
  bool _persistInFlight = false;
  bool _needsFollowUpPersist = false;
  int? _failedPersistRevision;
  final List<_PendingAppend> _pendingAppends = [];
  int _compactionRequiredRevision = 0;
  bool _loaded = false;
  Object? _lastStorageError;
  List<HttpRecord>? _filteredRecordsCache;
  Map<String, dynamic>? _visibleStatsCache;
  List<MapEntry<String, int>>? _domainStatsCache;
  int? _hiddenNoiseCountCache;
  Map<String, dynamic>? _statsCache;

  List<HttpRecord> get records => List.unmodifiable(_records);
  int get count => _records.length;

  String get filterDomain => _filterDomain;
  String get filterMethod => _filterMethod;
  int? get filterStatus => _filterStatus;
  bool get hideNoiseMethods => _hideNoiseMethods;
  bool get isLoaded => _loaded;
  Object? get lastStorageError => _lastStorageError;
  Map<String, dynamic> get stats => _statsCache ??= Map.unmodifiable({
        'total': _totalCount,
        'success': _successCount,
        'error': _errorCount,
        'avgMs': _durationCount > 0
            ? (_totalDurationMs / _durationCount).round()
            : null,
      });
  Map<String, dynamic> get visibleStats =>
      _visibleStatsCache ??= Map.unmodifiable(_statsFor(filteredRecords));
  int get hiddenNoiseCount => _hiddenNoiseCountCache ??=
      _hideNoiseMethods ? _records.where(_isNoiseRecord).length : 0;

  /// Get filtered records (newest first).
  List<HttpRecord> get filteredRecords {
    final cached = _filteredRecordsCache;
    if (cached != null) return cached;
    var list = _recordsForCurrentNoisePreference(newestFirst: true);
    if (_filterDomain.isNotEmpty) {
      final d = _filterDomain.toLowerCase();
      list = list.where((r) => r.url.toLowerCase().contains(d)).toList();
    }
    if (_filterMethod.isNotEmpty) {
      list =
          list.where((r) => r.method == _filterMethod.toUpperCase()).toList();
    }
    if (_filterStatus != null) {
      if (_filterStatus == 0) {
        list = list.where((r) => r.isError).toList();
      } else {
        final base = _filterStatus!;
        list = list
            .where((r) =>
                r.statusCode != null &&
                r.statusCode! >= base &&
                r.statusCode! < base + 100)
            .toList();
      }
    }
    return _filteredRecordsCache = List.unmodifiable(list);
  }

  void _invalidateDerivedCaches({bool statsChanged = false}) {
    _filteredRecordsCache = null;
    _visibleStatsCache = null;
    _domainStatsCache = null;
    _hiddenNoiseCountCache = null;
    if (statsChanged) _statsCache = null;
  }

  void setFilterDomain(String v) {
    if (_filterDomain == v) return;
    _filterDomain = v;
    _invalidateDerivedCaches();
    notifyListeners();
  }

  void setFilterMethod(String v) {
    _filterMethod = v.trim().toUpperCase();
    if (_hideNoiseMethods && isNoiseMethod(_filterMethod)) {
      _hideNoiseMethods = false;
      unawaited(_saveHideNoiseMethodsPreference(false));
    }
    _invalidateDerivedCaches();
    notifyListeners();
  }

  void setHideNoiseMethods(bool value) {
    if (_hideNoiseMethods == value) return;
    _hideNoiseMethods = value;
    _invalidateDerivedCaches();
    notifyListeners();
    unawaited(_saveHideNoiseMethodsPreference(value));
  }

  void setFilterStatus(int? v) {
    if (_filterStatus == v) return;
    _filterStatus = v;
    _invalidateDerivedCaches();
    notifyListeners();
  }

  void clearFilters() {
    _filterDomain = '';
    _filterMethod = '';
    _filterStatus = null;
    _invalidateDerivedCaches();
    notifyListeners();
  }

  /// Get domain statistics: list of (domain, count) sorted by count desc.
  List<MapEntry<String, int>> get domainStats {
    final cached = _domainStatsCache;
    if (cached != null) return cached;
    final counts = <String, int>{};
    for (final r in _recordsForCurrentNoisePreference()) {
      final d = r.domain;
      if (d.isNotEmpty) {
        counts[d] = (counts[d] ?? 0) + 1;
      }
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return _domainStatsCache = List.unmodifiable(entries);
  }

  Future<void> loadDisplayPreferences() {
    return _displayPreferencesLoadFuture ??= _loadDisplayPreferences();
  }

  static bool isNoiseMethod(String method) {
    return noiseMethods.contains(method.trim().toUpperCase());
  }

  List<HttpRecord> _recordsForCurrentNoisePreference({
    bool newestFirst = false,
  }) {
    final source = newestFirst ? _records.reversed : _records;
    if (!_hideNoiseMethods) {
      return source.toList();
    }
    return source.where((record) => !_isNoiseRecord(record)).toList();
  }

  bool _isNoiseRecord(HttpRecord record) => isNoiseMethod(record.method);

  Map<String, dynamic> _statsFor(Iterable<HttpRecord> records) {
    var total = 0;
    var success = 0;
    var error = 0;
    var totalDurationMs = 0;
    var durationCount = 0;
    for (final record in records) {
      total++;
      if (record.isSuccess) success++;
      if (record.isError) error++;
      if (record.durationMs != null) {
        totalDurationMs += record.durationMs!;
        durationCount++;
      }
    }
    return {
      'total': total,
      'success': success,
      'error': error,
      'avgMs':
          durationCount > 0 ? (totalDurationMs / durationCount).round() : null,
    };
  }

  Future<void> _loadDisplayPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _hideNoiseMethods = prefs.getBool(_hideNoiseMethodsPrefsKey) ?? true;
      _invalidateDerivedCaches();
      notifyListeners();
    } catch (e) {
      debugPrint('HttpInspectorStore.loadDisplayPreferences error: $e');
    }
  }

  Future<void> _saveHideNoiseMethodsPreference(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_hideNoiseMethodsPrefsKey, value);
    } catch (e) {
      debugPrint('HttpInspectorStore.saveDisplayPreferences error: $e');
    }
  }

  /// Add a new record from Python hook JSON.
  void addFromJson(Map<String, dynamic> json) {
    try {
      if (json['note'] != null) return;
      final record = _normalizeNewRecord(HttpRecord.fromJson(json));
      if (record.url.isEmpty) return;
      _records.add(record);
      _addToStats(record);
      final compact = _applyLimits();
      _invalidateDerivedCaches(statsChanged: true);
      final revision = _markDirtyAndSchedulePersist();
      if (compact) {
        _compactionRequiredRevision = revision;
      } else {
        _pendingAppends.add(_PendingAppend(record, revision));
      }
      notifyListeners();
    } catch (e) {
      debugPrint('HttpInspectorStore.addFromJson error: $e');
    }
  }

  /// Clear all records.
  void clear() {
    _records.clear();
    _resetStats();
    _invalidateDerivedCaches(statsChanged: true);
    _pendingAppends.clear();
    final revision = _markDirtyAndSchedulePersist();
    _compactionRequiredRevision = revision;
    notifyListeners();
  }

  Future<void> ensureLoaded() {
    return _loadFuture ??= _loadFromDisk();
  }

  Future<void> flush() async {
    _cancelPersistTimers();
    // A caller explicitly flushing (lifecycle/export) is an intentional retry;
    // automatic timers still do not spin on the same failed revision.
    _failedPersistRevision = null;
    await _requestPersist();
  }

  /// Export all records as text.
  String exportAll() {
    if (_records.isEmpty) return '(无网络请求记录)';
    final buf = StringBuffer();
    buf.writeln('====== 网络请求记录 (${_records.length} 条) ======');
    buf.writeln();
    for (final r in _records) {
      buf.writeln(r.toExportText());
      buf.writeln('─' * 50);
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
      buf.writeln('─' * 50);
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

    var totalBytes =
        trimmed.fold<int>(0, (sum, record) => sum + record.storedJsonBytes);
    while (totalBytes > maxCapturedBodyBytes && trimmed.length > 1) {
      totalBytes -= trimmed.first.storedJsonBytes;
      trimmed.removeAt(0);
    }
    if (totalBytes > maxCapturedBodyBytes && trimmed.isNotEmpty) {
      final record = trimmed.last;
      trimmed[trimmed.length - 1] = _normalizeRecordToBudget(
        record,
        maxBytes: maxCapturedBodyBytes,
      );
    }
    return trimmed;
  }

  bool _applyLimits() {
    final trimmed = trimRecords(_records);
    var changed = trimmed.length != _records.length;
    if (!changed) {
      for (var i = 0; i < trimmed.length; i++) {
        if (!identical(trimmed[i], _records[i])) {
          changed = true;
          break;
        }
      }
    }
    if (!changed) return false;
    final removedCount = _records.length - trimmed.length;
    for (final removed in _records.take(removedCount)) {
      _removeFromStats(removed);
    }
    _records
      ..clear()
      ..addAll(trimmed);
    _invalidateDerivedCaches(statsChanged: true);
    return true;
  }

  void _resetStats() {
    _totalCount = 0;
    _successCount = 0;
    _errorCount = 0;
    _totalDurationMs = 0;
    _durationCount = 0;
    _statsCache = null;
  }

  void _addToStats(HttpRecord record) {
    _totalCount++;
    if (record.isSuccess) _successCount++;
    if (record.isError) _errorCount++;
    if (record.durationMs != null) {
      _totalDurationMs += record.durationMs!;
      _durationCount++;
    }
    _statsCache = null;
  }

  void _removeFromStats(HttpRecord record) {
    _totalCount--;
    if (record.isSuccess) _successCount--;
    if (record.isError) _errorCount--;
    if (record.durationMs != null) {
      _totalDurationMs -= record.durationMs!;
      _durationCount--;
    }
    _statsCache = null;
  }

  void _recomputeStats() {
    _resetStats();
    for (final record in _records) {
      _addToStats(record);
    }
    _invalidateDerivedCaches(statsChanged: true);
  }

  int _markDirtyAndSchedulePersist() {
    _dirtyRevision++;
    _failedPersistRevision = null;
    _schedulePersist();
    return _dirtyRevision;
  }

  void _schedulePersist() {
    _persistDebounceTimer?.cancel();
    _persistDebounceTimer = Timer(_persistDebounce, () {
      _persistDebounceTimer = null;
      _persistMaxDelayTimer?.cancel();
      _persistMaxDelayTimer = null;
      unawaited(_requestPersist());
    });
    _persistMaxDelayTimer ??= Timer(_persistMaxDelay, () {
      _persistMaxDelayTimer = null;
      _persistDebounceTimer?.cancel();
      _persistDebounceTimer = null;
      unawaited(_requestPersist());
    });
  }

  void _cancelPersistTimers() {
    _persistDebounceTimer?.cancel();
    _persistDebounceTimer = null;
    _persistMaxDelayTimer?.cancel();
    _persistMaxDelayTimer = null;
  }

  Future<void> _loadFromDisk() async {
    try {
      final file = await _storageFile();
      await _cleanTemporaryFiles(file);
      if (await file.exists()) {
        _replaceRecords(await _readJsonLines(file));
      } else {
        final legacy = await _legacyStorageFile();
        if (await legacy.exists()) {
          _replaceRecords(await _migrateLegacyFile(legacy, file));
        }
      }
      _lastStorageError = null;
    } catch (e) {
      _lastStorageError = e;
      debugPrint('HttpInspectorStore.load error: $e');
      if (_throwOnStorageError) rethrow;
    } finally {
      _recomputeStats();
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> _requestPersist() {
    if (_failedPersistRevision == _dirtyRevision) {
      return Future<void>.value();
    }
    if (_persistInFlight) {
      _needsFollowUpPersist = true;
    }
    return _persistFuture ??= _drainPersistQueue().whenComplete(() {
      _persistFuture = null;
    });
  }

  Future<void> _drainPersistQueue() async {
    do {
      _needsFollowUpPersist = false;
      if (_persistedRevision >= _dirtyRevision) {
        continue;
      }
      final persisted = await _persistChanges();
      if (!persisted) {
        break;
      }
      if (_dirtyRevision > _persistedRevision) {
        _needsFollowUpPersist = true;
      }
    } while (_needsFollowUpPersist);
  }

  Future<bool> _persistChanges() async {
    final snapshotRevision = _dirtyRevision;
    final shouldCompact = _compactionRequiredRevision > _persistedRevision;
    final snapshot = shouldCompact ? List<HttpRecord>.of(_records) : null;
    final appends = shouldCompact
        ? const <_PendingAppend>[]
        : _pendingAppends
            .where((pending) => pending.revision <= snapshotRevision)
            .toList(growable: false);
    _persistInFlight = true;
    try {
      final file = await _storageFile();
      await file.parent.create(recursive: true);
      if (shouldCompact) {
        await _compactStorage(file, snapshot!);
      } else if (appends.isNotEmpty) {
        await _writeLines(
          file,
          appends.map((pending) => _recordLine(pending.record)),
          append: true,
        );
      }
      _persistedRevision = snapshotRevision;
      _pendingAppends
          .removeWhere((pending) => pending.revision <= snapshotRevision);
      if (_compactionRequiredRevision <= snapshotRevision) {
        _compactionRequiredRevision = 0;
      }
      _lastStorageError = null;
      return true;
    } catch (e) {
      _lastStorageError = e;
      _failedPersistRevision = snapshotRevision;
      debugPrint('HttpInspectorStore.persist error: $e');
      if (_throwOnStorageError) rethrow;
      return false;
    } finally {
      _persistInFlight = false;
    }
  }

  Future<File> _storageFile() async {
    final dir = await _supportDirectoryProvider();
    return File('${dir.path}${Platform.pathSeparator}$_storageFileName');
  }

  Future<File> _legacyStorageFile() async {
    final dir = await _supportDirectoryProvider();
    return File('${dir.path}${Platform.pathSeparator}$_legacyStorageFileName');
  }

  Future<File> _legacyArchiveFile() async {
    final dir = await _supportDirectoryProvider();
    return File('${dir.path}${Platform.pathSeparator}$_legacyArchiveFileName');
  }

  Future<void> _cleanTemporaryFiles(File file) async {
    for (final temporary in [
      _temporaryStorageFile(file),
      _writerTemporaryFile(file),
    ]) {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  Future<List<HttpRecord>> _readJsonLines(File file) async {
    final loaded = <HttpRecord>[];
    await for (final line in file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map) continue;
        final record = _normalizeRecordToBudget(
          HttpRecord.fromJson(Map<String, dynamic>.from(decoded)),
        );
        if (record.url.isNotEmpty) loaded.add(record);
      } catch (e) {
        // A process interruption can only corrupt a trailing JSONL line; keep
        // all preceding records and make malformed external edits non-fatal.
        debugPrint('HttpInspectorStore.skip malformed JSONL record: $e');
      }
    }
    return trimRecords(loaded);
  }

  Future<List<HttpRecord>> _migrateLegacyFile(File legacy, File v2) async {
    final records = ListQueue<HttpRecord>();
    var totalBytes = 0;
    await for (final object in _readLegacyJsonObjects(legacy)) {
      try {
        final record = _normalizeRecordToBudget(HttpRecord.fromJson(object));
        if (record.url.isEmpty) continue;
        records.addLast(record);
        totalBytes += record.storedJsonBytes;
        while (records.length > maxRecords ||
            (totalBytes > maxCapturedBodyBytes && records.length > 1)) {
          totalBytes -= records.removeFirst().storedJsonBytes;
        }
      } catch (e) {
        debugPrint('HttpInspectorStore.skip malformed legacy record: $e');
      }
    }

    final migrated = List<HttpRecord>.of(records);
    await _compactStorage(v2, migrated);
    final archive = await _legacyArchiveFile();
    if (!await archive.exists()) {
      try {
        await legacy.rename(archive.path);
      } catch (e) {
        // V2 is already durable. Keep the untouched source if it cannot be
        // renamed, rather than risking a destructive replacement.
        debugPrint('HttpInspectorStore.archive legacy source error: $e');
      }
    }
    return migrated;
  }

  Stream<Map<String, dynamic>> _readLegacyJsonObjects(File file) async* {
    final buffer = StringBuffer();
    var collecting = false;
    var depth = 0;
    var inString = false;
    var escaped = false;

    await for (final chunk in file.openRead().transform(utf8.decoder)) {
      for (final codeUnit in chunk.codeUnits) {
        final char = String.fromCharCode(codeUnit);
        if (!collecting) {
          if (char == '{') {
            collecting = true;
            depth = 1;
            buffer.write(char);
          }
          continue;
        }

        buffer.write(char);
        if (inString) {
          if (escaped) {
            escaped = false;
          } else if (char == '\\') {
            escaped = true;
          } else if (char == '"') {
            inString = false;
          }
          continue;
        }
        if (char == '"') {
          inString = true;
        } else if (char == '{') {
          depth++;
        } else if (char == '}') {
          depth--;
          if (depth == 0) {
            final text = buffer.toString();
            buffer.clear();
            collecting = false;
            try {
              final decoded = jsonDecode(text);
              if (decoded is Map) {
                yield Map<String, dynamic>.from(decoded);
              }
            } catch (e) {
              debugPrint('HttpInspectorStore.skip malformed legacy JSON: $e');
            }
          }
        }
      }
    }
  }

  void _replaceRecords(List<HttpRecord> records) {
    _records
      ..clear()
      ..addAll(records);
    _pendingAppends.clear();
    _compactionRequiredRevision = 0;
  }

  Future<void> _compactStorage(File file, List<HttpRecord> records) async {
    final temporary = _temporaryStorageFile(file);
    await file.parent.create(recursive: true);
    if (await temporary.exists()) await temporary.delete();
    try {
      await _writeLines(
        temporary,
        records.map(_recordLine),
        append: false,
      );
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) {
        try {
          await temporary.delete();
        } catch (_) {
          // Startup cleanup handles an interrupted replacement.
        }
      }
    }
  }

  Future<void> _writeLines(
    File file,
    Iterable<String> lines, {
    required bool append,
  }) async {
    if (!_usesStorageWriterOverride) {
      final sink = file.openWrite(
        mode: append ? FileMode.append : FileMode.write,
      );
      try {
        for (final line in lines) {
          sink.write(line);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      return;
    }

    if (!append && await file.exists()) await file.delete();
    for (final line in lines) {
      final writerTemporary = _writerTemporaryFile(file);
      if (await writerTemporary.exists()) await writerTemporary.delete();
      try {
        await _storageWriter(writerTemporary, line);
        await file.writeAsString(
          await writerTemporary.readAsString(),
          mode: FileMode.append,
          flush: true,
        );
      } finally {
        if (await writerTemporary.exists()) await writerTemporary.delete();
      }
    }
    if (!append && !await file.exists()) {
      await file.writeAsString('', flush: true);
    }
  }

  String _recordLine(HttpRecord record) => '${jsonEncode(record.toJson())}\n';

  static File _temporaryStorageFile(File file) => File('${file.path}.tmp');

  static File _writerTemporaryFile(File file) => File('${file.path}.writer');

  static HttpRecord _normalizeNewRecord(HttpRecord record) =>
      _normalizeRecordToBudget(record);

  static HttpRecord _normalizeRecordToBudget(
    HttpRecord record, {
    int maxBytes = maxBodyBytesPerNewRecord,
  }) {
    final normalized = _normalizeMetadata(record);
    final originalResponse = normalized.responseBodyPreview;
    final originalResponseBytes =
        normalized.responseBodyBytes ?? normalized.capturedResponseBodyBytes;
    final base = normalized.copyWith(
      clearRequestBody: true,
      clearResponseBodyPreview: true,
      responseBodyBytes: originalResponseBytes,
      responseBodyTruncated: normalized.responseBodyTruncated ||
          (originalResponse?.isNotEmpty ?? false),
    );
    var remaining = maxBytes - base.storedJsonBytes;
    if (remaining <= 0) return base;

    var request = _truncateUtf8(normalized.requestBody, remaining);
    remaining -= request.bytes;
    var response = _truncateUtf8(originalResponse, remaining);
    var responseTruncated = normalized.responseBodyTruncated ||
        response.truncated ||
        (request.truncated && originalResponse != null);
    var result = base.copyWith(
      requestBody: request.value,
      responseBodyPreview: response.value,
      responseBodyBytes: originalResponseBytes,
      responseBodyTruncated: responseTruncated,
    );

    // JSON escaping can make the serialized value larger than its raw UTF-8
    // byte count. Tighten the body budget until the persisted line fits.
    for (var attempt = 0;
        result.storedJsonBytes > maxBytes && attempt < 8;
        attempt++) {
      final excess = result.storedJsonBytes - maxBytes;
      if (response.value != null && response.value!.isNotEmpty) {
        final target = (response.bytes - excess - 32).clamp(0, response.bytes);
        response = _truncateUtf8(response.value, target);
        responseTruncated = true;
      } else if (request.value != null && request.value!.isNotEmpty) {
        final target = (request.bytes - excess - 32).clamp(0, request.bytes);
        request = _truncateUtf8(request.value, target);
      } else {
        break;
      }
      result = base.copyWith(
        requestBody: request.value,
        responseBodyPreview: response.value,
        responseBodyBytes: originalResponseBytes,
        responseBodyTruncated: responseTruncated,
      );
    }
    return result;
  }

  static HttpRecord _normalizeMetadata(HttpRecord record) {
    return HttpRecord(
      id: _truncateUtf8(record.id, _maxUrlBytes).value ?? '',
      timestamp: record.timestamp,
      method: _truncateUtf8(record.method, _maxHeaderNameBytes).value ?? 'GET',
      url: _truncateUtf8(record.url, _maxUrlBytes).value ?? '',
      requestHeaders: _truncateHeaders(record.requestHeaders),
      requestBody: record.requestBody,
      usedProxy: record.usedProxy,
      sslVerify: record.sslVerify,
      library:
          _truncateUtf8(record.library, _maxLibraryBytes).value ?? 'unknown',
      statusCode: record.statusCode,
      responseHeaders: record.responseHeaders == null
          ? null
          : _truncateHeaders(record.responseHeaders!),
      responseBodyPreview: record.responseBodyPreview,
      responseBodyBytes: record.responseBodyBytes,
      responseBodyTruncated: record.responseBodyTruncated,
      errorType: _truncateUtf8(record.errorType, _maxErrorBytes).value,
      errorMessage: _truncateUtf8(record.errorMessage, _maxErrorBytes).value,
      durationMs: record.durationMs,
    );
  }

  static Map<String, String> _truncateHeaders(Map<String, String> headers) {
    final result = <String, String>{};
    for (final entry in headers.entries.take(_maxHeadersPerNewRecord)) {
      final key = _truncateUtf8(entry.key, _maxHeaderNameBytes).value ?? '';
      final value =
          _truncateUtf8(entry.value, _maxHeaderValueBytes).value ?? '';
      if (key.isNotEmpty) result[key] = value;
    }
    return result;
  }

  static _TruncatedText _truncateUtf8(String? value, int limit) {
    if (value == null || value.isEmpty || limit <= 0) {
      return _TruncatedText(
          limit <= 0 && (value?.isNotEmpty ?? false) ? '' : value,
          limit <= 0 && (value?.isNotEmpty ?? false),
          0);
    }
    final encoded = utf8.encode(value);
    if (encoded.length <= limit) {
      return _TruncatedText(value, false, encoded.length);
    }
    const suffix = '\n… (truncated)';
    final suffixBytes = utf8.encode(suffix).length;
    final prefixLength = (limit - suffixBytes).clamp(0, encoded.length);
    final prefix =
        utf8.decode(encoded.take(prefixLength).toList(), allowMalformed: true);
    final text = prefix + (limit >= suffixBytes ? suffix : '…');
    return _TruncatedText(text, true, utf8.encode(text).length);
  }

  static Future<void> _defaultStorageWriter(
    File file,
    String payload,
  ) async {
    await file.writeAsString(payload, flush: true);
  }
}

class _TruncatedText {
  const _TruncatedText(this.value, this.truncated, this.bytes);

  final String? value;
  final bool truncated;
  final int bytes;
}

class _PendingAppend {
  const _PendingAppend(this.record, this.revision);

  final HttpRecord record;
  final int revision;
}
