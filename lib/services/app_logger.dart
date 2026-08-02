import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

enum AppLogLevel { info, warn, error }

class AppLogEntry {
  final AppLogLevel level;
  final String message;
  final DateTime timestamp;
  final String? source;
  final String? detail;

  AppLogEntry({
    required this.level,
    required this.message,
    required this.timestamp,
    this.source,
    this.detail,
  });

  String get formatted {
    final ts = DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(timestamp);
    final lvl = level.name.toUpperCase().padRight(5);
    final src = source != null ? '[$source] ' : '';
    final det = detail != null ? '\n  Detail: $detail' : '';
    return '[$ts] $lvl $src$message$det';
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'level': level.name,
        'message': message,
        'timestamp': timestamp.toIso8601String(),
        'source': source,
        'detail': detail,
      };

  static AppLogEntry? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final levelName = value['level'];
    final message = value['message'];
    final timestamp = value['timestamp'];
    if (levelName is! String || message is! String || timestamp is! String) {
      return null;
    }
    final parsedTimestamp = DateTime.tryParse(timestamp);
    final level = AppLogLevel.values.where((item) => item.name == levelName);
    if (parsedTimestamp == null || level.isEmpty) return null;
    final source = value['source'];
    final detail = value['detail'];
    if (source != null && source is! String) return null;
    if (detail != null && detail is! String) return null;
    return AppLogEntry(
      level: level.first,
      message: message,
      timestamp: parsedTimestamp,
      source: source as String?,
      detail: detail as String?,
    );
  }
}

/// Unified app-level logger with in-memory buffer and file persistence.
/// Uses synchronous file writes for crash/error logs to ensure they survive crashes.
class AppLogger {
  AppLogger._({Directory? testingLogDirectory})
      : _testingLogDirectory = testingLogDirectory;
  static final AppLogger instance = AppLogger._();

  @visibleForTesting
  AppLogger.forTesting(Directory logDirectory)
      : _testingLogDirectory = logDirectory;

  static const int _maxMemoryLogs = 500;
  static const String _systemLogFile = 'system.log';
  static const String _systemLogOldFile = 'system.log.old';
  static const String _historyLogFile = 'app_history.jsonl';
  static const String _historyTempFile = 'app_history.jsonl.tmp';
  static const String _crashLogFile = 'crash.log';
  static const String _scriptErrorLogFile = 'script_errors.log';

  final List<AppLogEntry> _memoryLogs = [];
  final Directory? _testingLogDirectory;
  Directory? _logDir;
  bool _initialized = false;
  IOSink? _systemLogSink;
  Future<void> _fileWriteQueue = Future<void>.value();
  int _systemLogSize = 0;
  static const int _maxSystemLogSize = 2 * 1024 * 1024; // 2MB

  List<AppLogEntry> get recentLogs => List.unmodifiable(_memoryLogs);

  String _dateStamp([DateTime? value]) =>
      DateFormat('yyyy-MM-dd').format(value ?? DateTime.now());

  String _appLogFileName([DateTime? value]) => 'app-${_dateStamp(value)}.log';
  String _scriptLogFileName([DateTime? value]) =>
      'script-${_dateStamp(value)}.log';
  String _crashLogFileName([DateTime? value]) =>
      'crash-${_dateStamp(value)}.log';

  /// Initialize the logger, creating the log directory.
  Future<void> init() async {
    if (_initialized) return;
    try {
      final appDir = _testingLogDirectory ??
          Directory('${(await getApplicationDocumentsDirectory()).path}/app_logs');
      _logDir = appDir;
      if (!await _logDir!.exists()) {
        await _logDir!.create(recursive: true);
      }

      // Check current system log size for rotation
      final sysFile = File('${_logDir!.path}/$_systemLogFile');
      if (await sysFile.exists()) {
        _systemLogSize = await sysFile.length();
        if (_systemLogSize > _maxSystemLogSize) {
          // Rotate: rename old log, start fresh
          try {
            await sysFile.rename('${_logDir!.path}/$_systemLogFile.old');
          } catch (_) {
            await sysFile.delete();
          }
          _systemLogSize = 0;
        }
      }

      await _restoreRecentHistory();

      _initialized = true;
      info('AppLogger initialized', source: 'AppLogger');
    } catch (e) {
      debugPrint('AppLogger init failed: $e');
    }
  }

  /// Log an info-level message.
  void info(String message, {String? source, String? detail}) {
    _log(AppLogLevel.info, message, source: source, detail: detail);
  }

  /// Log a warning-level message.
  void warn(String message, {String? source, String? detail}) {
    _log(AppLogLevel.warn, message, source: source, detail: detail);
  }

  /// Log an error-level message.
  void error(String message, {String? source, String? detail}) {
    _log(AppLogLevel.error, message, source: source, detail: detail);
  }

  /// Log a script execution error (persisted to separate file, survives restart).
  void scriptError(String scriptName, String errorMessage,
      {String? stackTrace}) {
    final detail = StringBuffer();
    detail.writeln('Script: $scriptName');
    detail.writeln('Error: $errorMessage');
    if (stackTrace != null) detail.writeln('StackTrace:\n$stackTrace');
    _log(AppLogLevel.error, '脚本执行错误: $scriptName',
        source: 'Script', detail: detail.toString());
    final content =
        '=== ${DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(DateTime.now())} ===\n'
        'Script: $scriptName\nError: $errorMessage\n${stackTrace != null ? "StackTrace:\n$stackTrace\n" : ""}\n';
    _enqueueNamedLog(_scriptErrorLogFile, content, flush: true);
    _enqueueNamedLog(_scriptLogFileName(), content, flush: true);
  }

  /// Log an error from an exception/stack trace (crash-level).
  void crash(String message,
      {Object? exception, StackTrace? stackTrace, String? source}) {
    final detail = StringBuffer();
    if (exception != null) detail.writeln('Exception: $exception');
    if (stackTrace != null) detail.writeln('StackTrace:\n$stackTrace');
    _log(AppLogLevel.error, message,
        source: source ?? 'CRASH', detail: detail.toString());
    // Synchronous write to ensure crash log survives app termination
    _writeSyncCrashLog(message, exception, stackTrace);
  }

  void _log(AppLogLevel level, String message,
      {String? source, String? detail}) {
    final entry = AppLogEntry(
      level: level,
      message: message,
      timestamp: DateTime.now(),
      source: source,
      detail: detail,
    );

    // Memory buffer
    _memoryLogs.add(entry);
    var historyNeedsCompaction = false;
    if (_memoryLogs.length > _maxMemoryLogs) {
      _memoryLogs.removeRange(0, _memoryLogs.length - _maxMemoryLogs);
      historyNeedsCompaction = true;
    }

    // Console output (keep debugPrint)
    debugPrint(entry.formatted);

    // File persistence (buffered stream for normal logs)
    _writeToSystemLog(entry);
    _enqueueHistoryLog(entry, compact: historyNeedsCompaction);
  }

  void _writeToSystemLog(AppLogEntry entry) {
    if (_logDir == null) return;
    final line = '${entry.formatted}\n';
    _enqueueSystemLog(
      line,
      timestamp: entry.timestamp,
      flush: entry.level != AppLogLevel.info,
    );
  }

  Future<void> flush() async {
    try {
      await _fileWriteQueue;
      await _systemLogSink?.flush();
    } catch (_) {}
  }

  void _enqueueSystemLog(
    String line, {
    required DateTime timestamp,
    required bool flush,
  }) {
    final directory = _logDir;
    if (directory == null) return;
    _fileWriteQueue = _fileWriteQueue.catchError((_) {}).then((_) async {
      final systemFile = File('${directory.path}/$_systemLogFile');
      final lineBytes = line.length;
      if (_systemLogSize + lineBytes > _maxSystemLogSize) {
        await _rotateSystemLog(systemFile);
      }
      await systemFile.writeAsString(
        line,
        mode: FileMode.append,
        flush: flush,
      );
      await File('${directory.path}/${_appLogFileName(timestamp)}')
          .writeAsString(
        line,
        mode: FileMode.append,
        flush: flush,
      );
      _systemLogSize += lineBytes;
    });
  }

  void _enqueueNamedLog(String fileName, String content, {bool flush = false}) {
    final directory = _logDir;
    if (directory == null) return;
    _fileWriteQueue = _fileWriteQueue.catchError((_) {}).then<void>((_) async {
      await File('${directory.path}/$fileName').writeAsString(
        content,
        mode: FileMode.append,
        flush: flush,
      );
    });
  }

  void _enqueueHistoryLog(AppLogEntry entry, {required bool compact}) {
    final directory = _logDir;
    if (directory == null) return;
    final snapshot = compact ? List<AppLogEntry>.of(_memoryLogs) : null;
    _fileWriteQueue = _fileWriteQueue.catchError((_) {}).then<void>((_) async {
      final historyFile = File('${directory.path}/$_historyLogFile');
      if (snapshot == null) {
        await historyFile.writeAsString(
          '${jsonEncode(entry.toJson())}\n',
          mode: FileMode.append,
          flush: entry.level != AppLogLevel.info,
        );
        return;
      }
      await _writeHistorySnapshot(directory, snapshot);
    });
  }

  Future<void> _writeHistorySnapshot(
    Directory directory,
    List<AppLogEntry> entries,
  ) async {
    final tempFile = File('${directory.path}/$_historyTempFile');
    final historyFile = File('${directory.path}/$_historyLogFile');
    final content = entries.map((entry) => jsonEncode(entry.toJson())).join('\n');
    await tempFile.writeAsString(
      content.isEmpty ? '' : '$content\n',
      flush: true,
    );
    await tempFile.rename(historyFile.path);
  }

  Future<void> _restoreRecentHistory() async {
    final directory = _logDir;
    if (directory == null) return;
    final historyFile = File('${directory.path}/$_historyLogFile');
    final tempFile = File('${directory.path}/$_historyTempFile');
    try {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      if (await historyFile.exists()) {
        await _readJsonlHistory(historyFile);
        return;
      }
      await _migrateLegacySystemHistory(directory);
      if (_memoryLogs.isNotEmpty) {
        await _writeHistorySnapshot(directory, List<AppLogEntry>.of(_memoryLogs));
      }
    } catch (error) {
      debugPrint('AppLogger history restore failed: $error');
      _memoryLogs.clear();
    }
  }

  Future<void> _readJsonlHistory(File file) async {
    await for (final line in file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      try {
        final entry = AppLogEntry.tryFromJson(jsonDecode(line));
        if (entry != null) _appendRestoredEntry(entry);
      } catch (_) {
        // An interrupted final line or an old malformed record must not block startup.
      }
    }
  }

  Future<void> _migrateLegacySystemHistory(Directory directory) async {
    final oldFile = File('${directory.path}/$_systemLogOldFile');
    final currentFile = File('${directory.path}/$_systemLogFile');
    for (final file in [oldFile, currentFile]) {
      if (!await file.exists()) continue;
      await _readLegacySystemFile(file);
    }
  }

  Future<void> _readLegacySystemFile(File file) async {
    final startPattern = RegExp(
      r'^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3})\]\s+(INFO|WARN|ERROR)\s+(?:\[([^\]]+)\]\s+)?(.*)$',
    );
    AppLogEntry? current;
    StringBuffer? detail;

    void commitCurrent() {
      final entry = current;
      if (entry == null) return;
      _appendRestoredEntry(AppLogEntry(
        level: entry.level,
        message: entry.message,
        timestamp: entry.timestamp,
        source: entry.source,
        detail: detail?.toString(),
      ));
      current = null;
      detail = null;
    }

    await for (final line in file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      final match = startPattern.firstMatch(line);
      if (match == null) {
        if (current == null) continue;
        const detailPrefix = '  Detail: ';
        if (line.startsWith(detailPrefix)) {
          detail = StringBuffer(line.substring(detailPrefix.length));
        } else if (detail != null) {
          detail!.writeln(line);
        }
        continue;
      }
      commitCurrent();
      final timestamp = DateTime.tryParse(match.group(1)!.replaceFirst(' ', 'T'));
      final level = AppLogLevel.values
          .where((item) => item.name.toUpperCase() == match.group(2));
      if (timestamp == null || level.isEmpty) continue;
      current = AppLogEntry(
        level: level.first,
        message: match.group(4) ?? '',
        timestamp: timestamp,
        source: match.group(3),
      );
    }
    commitCurrent();
  }

  void _appendRestoredEntry(AppLogEntry entry) {
    _memoryLogs.add(entry);
    if (_memoryLogs.length > _maxMemoryLogs) {
      _memoryLogs.removeRange(0, _memoryLogs.length - _maxMemoryLogs);
    }
  }

  Future<void> _rotateSystemLog(File systemFile) async {
    if (await systemFile.exists()) {
      final oldFile = File('${systemFile.path}.old');
      if (await oldFile.exists()) {
        await oldFile.delete();
      }
      await systemFile.rename(oldFile.path);
    }
    _systemLogSize = 0;
  }

  Future<List<FileSystemEntity>> _listLogFiles({
    required String prefix,
    required String suffix,
    int limit = 20,
  }) async {
    if (_logDir == null || !await _logDir!.exists()) return [];
    final files = await _logDir!.list().where((entity) {
      final name = entity.path.split(Platform.pathSeparator).last;
      return name.startsWith(prefix) && name.endsWith(suffix);
    }).toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files.take(limit).toList();
  }

  Future<String> _readLogFiles(List<FileSystemEntity> files) async {
    final buf = StringBuffer();
    for (final entity in files) {
      try {
        final name = entity.path.split(Platform.pathSeparator).last;
        buf.writeln('--- $name ---');
        buf.writeln(await File(entity.path).readAsString());
        buf.writeln();
      } catch (_) {}
    }
    return buf.toString();
  }

  /// Synchronous crash log write — guaranteed to survive app termination.
  void _writeSyncCrashLog(
      String message, Object? exception, StackTrace? stackTrace) {
    if (_logDir == null) return;
    try {
      final ts = DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(DateTime.now());
      final buf = StringBuffer();
      buf.writeln('=== CRASH [$ts] ===');
      buf.writeln('Message: $message');
      if (exception != null) buf.writeln('Exception: $exception');
      if (stackTrace != null) buf.writeln('StackTrace:\n$stackTrace');
      buf.writeln();

      final file = File('${_logDir!.path}/$_crashLogFile');
      file.writeAsStringSync(buf.toString(),
          mode: FileMode.append, flush: true);
      final datedFile = File('${_logDir!.path}/${_crashLogFileName()}');
      datedFile.writeAsStringSync(buf.toString(),
          mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  /// Read full system log content.
  Future<String> readSystemLog() async {
    if (_logDir == null) return '(日志系统未初始化)';
    try {
      await flush();
      final oldFile = File('${_logDir!.path}/$_systemLogFile.old');
      final file = File('${_logDir!.path}/$_systemLogFile');
      final buf = StringBuffer();
      if (await oldFile.exists()) {
        buf.writeln('--- $_systemLogFile.old ---');
        buf.writeln(await oldFile.readAsString());
      }
      if (await file.exists()) {
        if (buf.isNotEmpty) buf.writeln();
        buf.writeln('--- $_systemLogFile ---');
        buf.writeln(await file.readAsString());
      }
      final appLogs = await _listLogFiles(prefix: 'app-', suffix: '.log');
      if (appLogs.isNotEmpty) {
        if (buf.isNotEmpty) buf.writeln();
        buf.writeln('--- dated app logs ---');
        buf.writeln(await _readLogFiles(appLogs));
      }
      if (buf.isNotEmpty) {
        return buf.toString();
      }
      return '(暂无系统日志)';
    } catch (e) {
      return '(读取日志失败: $e)';
    }
  }

  /// Read recent N lines from memory buffer as text.
  String readRecentLogs({int count = 50}) {
    final start = _memoryLogs.length > count ? _memoryLogs.length - count : 0;
    return _memoryLogs.sublist(start).map((e) => e.formatted).join('\n');
  }

  /// Read crash log content.
  Future<String> readCrashLog() async {
    if (_logDir == null) return '(日志系统未初始化)';
    try {
      final buf = StringBuffer();
      final file = File('${_logDir!.path}/$_crashLogFile');
      if (await file.exists()) {
        buf.writeln('--- $_crashLogFile ---');
        buf.writeln(await file.readAsString());
      }
      final dated = await _listLogFiles(prefix: 'crash-', suffix: '.log');
      if (dated.isNotEmpty) {
        if (buf.isNotEmpty) buf.writeln();
        buf.writeln(await _readLogFiles(dated));
      }
      return buf.isEmpty ? '(暂无崩溃日志)' : buf.toString();
    } catch (e) {
      return '(读取崩溃日志失败: $e)';
    }
  }

  /// Read script error log content.
  Future<String> readScriptErrorLog() async {
    if (_logDir == null) return '(日志系统未初始化)';
    try {
      final buf = StringBuffer();
      final file = File('${_logDir!.path}/$_scriptErrorLogFile');
      if (await file.exists()) {
        buf.writeln('--- $_scriptErrorLogFile ---');
        buf.writeln(await file.readAsString());
      }
      final dated = await _listLogFiles(prefix: 'script-', suffix: '.log');
      if (dated.isNotEmpty) {
        if (buf.isNotEmpty) buf.writeln();
        buf.writeln(await _readLogFiles(dated));
      }
      return buf.isEmpty ? '(暂无脚本错误日志)' : buf.toString();
    } catch (e) {
      return '(读取脚本错误日志失败: $e)';
    }
  }

  /// Clear all log files and memory buffer.
  Future<void> clearAll() async {
    _memoryLogs.clear();
    if (_logDir == null) return;
    try {
      await flush();
      await _systemLogSink?.close();
      _systemLogSink = null;
      _systemLogSize = 0;
      final systemFile = File('${_logDir!.path}/$_systemLogFile');
      if (await systemFile.exists()) await systemFile.delete();
      final oldSystemFile = File('${_logDir!.path}/$_systemLogOldFile');
      if (await oldSystemFile.exists()) await oldSystemFile.delete();
      final historyFile = File('${_logDir!.path}/$_historyLogFile');
      if (await historyFile.exists()) await historyFile.delete();
      final historyTempFile = File('${_logDir!.path}/$_historyTempFile');
      if (await historyTempFile.exists()) await historyTempFile.delete();
      final crashFile = File('${_logDir!.path}/$_crashLogFile');
      if (await crashFile.exists()) await crashFile.delete();
      final scriptErrFile = File('${_logDir!.path}/$_scriptErrorLogFile');
      if (await scriptErrFile.exists()) await scriptErrFile.delete();
      await for (final entity in _logDir!.list()) {
        final name = entity.path.split(Platform.pathSeparator).last;
        final isManagedLog = (name.startsWith('app-') ||
                name.startsWith('script-') ||
                name.startsWith('crash-')) &&
            name.endsWith('.log');
        if (isManagedLog) {
          await File(entity.path).delete();
        }
      }
    } catch (_) {}
  }

  /// Export all logs as a combined string (for sharing/saving).
  Future<String> exportAll() async {
    await flush();
    final buf = StringBuffer();
    buf.writeln('====== 诊断信息 ======');
    buf.writeln(
        'Generated at: ${DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(DateTime.now())}');
    buf.writeln(
        'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    buf.writeln('Log directory: ${logDirPath ?? "(日志系统未初始化)"}');
    buf.writeln('Recent memory entries: ${_memoryLogs.length}');
    buf.writeln();
    buf.writeln('====== 系统日志 ======');
    buf.writeln(await readSystemLog());
    buf.writeln();
    buf.writeln('====== Dart 崩溃日志 ======');
    buf.writeln(await readCrashLog());
    buf.writeln();
    buf.writeln('====== 脚本错误日志 ======');
    buf.writeln(await readScriptErrorLog());
    buf.writeln();
    buf.writeln('====== 原生脚本错误日志 ======');
    buf.writeln(await readNativeScriptErrorLogs());
    buf.writeln();
    buf.writeln('====== 原生崩溃日志 ======');
    buf.writeln(await readNativeCrashLogs());
    return buf.toString();
  }

  /// Read native (Kotlin) script error logs.
  Future<String> readNativeScriptErrorLogs() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final nativeDir = Directory('${appDir.parent.path}/script_error_logs');
      if (!await nativeDir.exists()) return '(暂无脚本错误日志)';
      final files =
          await nativeDir.list().where((f) => f.path.endsWith('.txt')).toList();
      if (files.isEmpty) return '(暂无脚本错误日志)';
      files.sort((a, b) => b.path.compareTo(a.path)); // newest first
      final recent = files.take(10);
      final buf = StringBuffer();
      for (final f in recent) {
        try {
          final content = await File(f.path).readAsString();
          buf.writeln('--- ${f.path.split('/').last} ---');
          buf.writeln(content);
          buf.writeln();
        } catch (_) {}
      }
      return buf.toString();
    } catch (e) {
      return '(读取脚本错误日志失败: $e)';
    }
  }

  /// Read native (Kotlin/Java) crash logs written by App.kt.
  Future<String> readNativeCrashLogs() async {
    try {
      // Native crash logs are stored in app's internal filesDir/crash_logs/
      // Flutter can access via getApplicationDocumentsDirectory's parent
      final appDir = await getApplicationDocumentsDirectory();
      // filesDir is the parent of the documents directory on Android
      final nativeDir = Directory('${appDir.parent.path}/crash_logs');
      if (!await nativeDir.exists()) return '(暂无原生崩溃日志)';
      final files =
          await nativeDir.list().where((f) => f.path.endsWith('.txt')).toList();
      if (files.isEmpty) return '(暂无原生崩溃日志)';
      files.sort((a, b) => b.path.compareTo(a.path)); // newest first
      // Read up to 5 most recent crash files
      final recent = files.take(5);
      final buf = StringBuffer();
      for (final f in recent) {
        try {
          final content = await File(f.path).readAsString();
          buf.writeln('--- ${f.path.split('/').last} ---');
          buf.writeln(content);
          buf.writeln();
        } catch (_) {}
      }
      return buf.toString();
    } catch (e) {
      return '(读取原生崩溃日志失败: $e)';
    }
  }

  /// Get the log directory path.
  String? get logDirPath => _logDir?.path;

  // ═══════════════════════════════════════════════════════════════
  // 新增：日志筛选和导出功能
  // ═══════════════════════════════════════════════════════════════

  /// 获取所有日志来源列表
  Set<String> getAllSources() {
    return _memoryLogs
        .where((log) => log.source != null)
        .map((log) => log.source!)
        .toSet();
  }

  /// 按条件筛选日志
  List<AppLogEntry> filterLogs({
    Set<AppLogLevel>? levels,
    String? source,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
  }) {
    return _memoryLogs.where((log) {
      // 级别筛选
      if (levels != null && levels.isNotEmpty && !levels.contains(log.level)) {
        return false;
      }

      // 来源筛选
      if (source != null && source.isNotEmpty && log.source != source) {
        return false;
      }

      // 时间范围筛选
      if (startDate != null && log.timestamp.isBefore(startDate)) {
        return false;
      }
      if (endDate != null && log.timestamp.isAfter(endDate)) {
        return false;
      }

      // 搜索关键字
      if (searchQuery != null && searchQuery.isNotEmpty) {
        final query = searchQuery.toLowerCase();
        return log.message.toLowerCase().contains(query) ||
            (log.detail?.toLowerCase().contains(query) ?? false) ||
            (log.source?.toLowerCase().contains(query) ?? false);
      }

      return true;
    }).toList();
  }

  /// 按日期分组日志
  Map<String, List<AppLogEntry>> groupByDate() {
    final Map<String, List<AppLogEntry>> grouped = {};
    for (final log in _memoryLogs) {
      final dateKey = DateFormat('yyyy-MM-dd').format(log.timestamp);
      grouped.putIfAbsent(dateKey, () => []);
      grouped[dateKey]!.add(log);
    }
    return grouped;
  }

  /// 导出筛选后的日志为文本
  String exportFilteredLogs({
    Set<AppLogLevel>? levels,
    String? source,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final filtered = filterLogs(
      levels: levels,
      source: source,
      startDate: startDate,
      endDate: endDate,
    );

    final buf = StringBuffer();
    buf.writeln('====== 筛选日志导出 ======');
    buf.writeln(
        'Generated at: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}');
    buf.writeln('Total entries: ${filtered.length}');
    if (levels != null && levels.isNotEmpty) {
      buf.writeln('Levels: ${levels.map((l) => l.name).join(', ')}');
    }
    if (source != null) {
      buf.writeln('Source: $source');
    }
    if (startDate != null || endDate != null) {
      buf.writeln(
          'Date range: ${startDate != null ? DateFormat('yyyy-MM-dd').format(startDate) : 'any'} ~ ${endDate != null ? DateFormat('yyyy-MM-dd').format(endDate) : 'any'}');
    }
    buf.writeln('=' * 40);
    buf.writeln();

    for (final log in filtered) {
      buf.writeln(log.formatted);
    }

    return buf.toString();
  }

  /// 获取日志统计信息
  Map<String, dynamic> getStatistics() {
    final stats = <String, dynamic>{};
    stats['total'] = _memoryLogs.length;
    stats['info'] =
        _memoryLogs.where((log) => log.level == AppLogLevel.info).length;
    stats['warn'] =
        _memoryLogs.where((log) => log.level == AppLogLevel.warn).length;
    stats['error'] =
        _memoryLogs.where((log) => log.level == AppLogLevel.error).length;
    stats['sources'] = getAllSources().length;

    // 最近的错误
    final recentErrors = _memoryLogs
        .where((log) => log.level == AppLogLevel.error)
        .toList()
        .reversed
        .take(5)
        .toList();
    stats['recentErrors'] = recentErrors;

    return stats;
  }
}
