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
}

/// Unified app-level logger with in-memory buffer and file persistence.
class AppLogger {
  AppLogger._();
  static final AppLogger instance = AppLogger._();

  static const int _maxMemoryLogs = 500;
  static const String _systemLogFile = 'system.log';
  static const String _crashLogFile = 'crash.log';

  final List<AppLogEntry> _memoryLogs = [];
  Directory? _logDir;
  bool _initialized = false;

  List<AppLogEntry> get recentLogs => List.unmodifiable(_memoryLogs);

  /// Initialize the logger, creating the log directory.
  Future<void> init() async {
    if (_initialized) return;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _logDir = Directory('${appDir.path}/app_logs');
      if (!await _logDir!.exists()) {
        await _logDir!.create(recursive: true);
      }
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

  /// Log an error from an exception/stack trace (crash-level).
  void crash(String message, {Object? exception, StackTrace? stackTrace, String? source}) {
    final detail = StringBuffer();
    if (exception != null) detail.writeln('Exception: $exception');
    if (stackTrace != null) detail.writeln('StackTrace:\n$stackTrace');
    _log(AppLogLevel.error, message, source: source ?? 'CRASH', detail: detail.toString());
    _writeToCrashLog(message, exception, stackTrace);
  }

  void _log(AppLogLevel level, String message, {String? source, String? detail}) {
    final entry = AppLogEntry(
      level: level,
      message: message,
      timestamp: DateTime.now(),
      source: source,
      detail: detail,
    );

    // Memory buffer
    _memoryLogs.add(entry);
    if (_memoryLogs.length > _maxMemoryLogs) {
      _memoryLogs.removeRange(0, _memoryLogs.length - _maxMemoryLogs);
    }

    // Console output (keep debugPrint)
    debugPrint(entry.formatted);

    // File persistence
    _writeToSystemLog(entry);
  }

  Future<void> _writeToSystemLog(AppLogEntry entry) async {
    if (_logDir == null) return;
    try {
      final file = File('${_logDir!.path}/$_systemLogFile');
      await file.writeAsString('${entry.formatted}\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // Silently fail to avoid recursion
    }
  }

  Future<void> _writeToCrashLog(String message, Object? exception, StackTrace? stackTrace) async {
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
      await file.writeAsString(buf.toString(), mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  /// Read full system log content.
  Future<String> readSystemLog() async {
    if (_logDir == null) return '(日志系统未初始化)';
    try {
      final file = File('${_logDir!.path}/$_systemLogFile');
      if (await file.exists()) {
        return await file.readAsString();
      }
      return '(暂无系统日志)';
    } catch (e) {
      return '(读取日志失败: $e)';
    }
  }

  /// Read recent N lines from memory buffer as text.
  String readRecentLogs({int count = 50}) {
    final start = _memoryLogs.length > count ? _memoryLogs.length - count : 0;
    return _memoryLogs
        .sublist(start)
        .map((e) => e.formatted)
        .join('\n');
  }

  /// Read crash log content.
  Future<String> readCrashLog() async {
    if (_logDir == null) return '(日志系统未初始化)';
    try {
      final file = File('${_logDir!.path}/$_crashLogFile');
      if (await file.exists()) {
        return await file.readAsString();
      }
      return '(暂无崩溃日志)';
    } catch (e) {
      return '(读取崩溃日志失败: $e)';
    }
  }

  /// Clear all log files and memory buffer.
  Future<void> clearAll() async {
    _memoryLogs.clear();
    if (_logDir == null) return;
    try {
      final systemFile = File('${_logDir!.path}/$_systemLogFile');
      if (await systemFile.exists()) await systemFile.delete();
      final crashFile = File('${_logDir!.path}/$_crashLogFile');
      if (await crashFile.exists()) await crashFile.delete();
    } catch (_) {}
  }

  /// Export all logs as a combined string (for sharing/saving).
  Future<String> exportAll() async {
    final buf = StringBuffer();
    buf.writeln('====== 系统日志 ======');
    buf.writeln(await readSystemLog());
    buf.writeln();
    buf.writeln('====== Dart 崩溃日志 ======');
    buf.writeln(await readCrashLog());
    buf.writeln();
    buf.writeln('====== 原生崩溃日志 ======');
    buf.writeln(await readNativeCrashLogs());
    return buf.toString();
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
      final files = await nativeDir.list()
          .where((f) => f.path.endsWith('.txt'))
          .toList();
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
}
