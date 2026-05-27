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
/// Uses synchronous file writes for crash/error logs to ensure they survive crashes.
class AppLogger {
  AppLogger._();
  static final AppLogger instance = AppLogger._();

  static const int _maxMemoryLogs = 500;
  static const String _systemLogFile = 'system.log';
  static const String _crashLogFile = 'crash.log';
  static const String _scriptErrorLogFile = 'script_errors.log';

  final List<AppLogEntry> _memoryLogs = [];
  Directory? _logDir;
  bool _initialized = false;
  IOSink? _systemLogSink;
  int _systemLogSize = 0;
  static const int _maxSystemLogSize = 2 * 1024 * 1024; // 2MB

  List<AppLogEntry> get recentLogs => List.unmodifiable(_memoryLogs);

  String _dateStamp([DateTime? value]) =>
      DateFormat('yyyy-MM-dd').format(value ?? DateTime.now());

  String _appLogFileName([DateTime? value]) => 'app-${_dateStamp(value)}.log';
  String _scriptLogFileName([DateTime? value]) => 'script-${_dateStamp(value)}.log';
  String _crashLogFileName([DateTime? value]) => 'crash-${_dateStamp(value)}.log';

  /// Initialize the logger, creating the log directory.
  Future<void> init() async {
    if (_initialized) return;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _logDir = Directory('${appDir.path}/app_logs');
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

      // Open system log in append mode with immediate flush
      _systemLogSink = sysFile.openWrite(mode: FileMode.append);

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
  void scriptError(String scriptName, String errorMessage, {String? stackTrace}) {
    final detail = StringBuffer();
    detail.writeln('Script: $scriptName');
    detail.writeln('Error: $errorMessage');
    if (stackTrace != null) detail.writeln('StackTrace:\n$stackTrace');
    _log(AppLogLevel.error, '脚本执行错误: $scriptName', source: 'Script', detail: detail.toString());
    final content = '=== ${DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(DateTime.now())} ===\n'
        'Script: $scriptName\nError: $errorMessage\n${stackTrace != null ? "StackTrace:\n$stackTrace\n" : ""}\n';
    _writeSyncToLog(_scriptErrorLogFile, content);
    _writeSyncToLog(_scriptLogFileName(), content);
  }

  /// Log an error from an exception/stack trace (crash-level).
  void crash(String message, {Object? exception, StackTrace? stackTrace, String? source}) {
    final detail = StringBuffer();
    if (exception != null) detail.writeln('Exception: $exception');
    if (stackTrace != null) detail.writeln('StackTrace:\n$stackTrace');
    _log(AppLogLevel.error, message, source: source ?? 'CRASH', detail: detail.toString());
    // Synchronous write to ensure crash log survives app termination
    _writeSyncCrashLog(message, exception, stackTrace);
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

    // File persistence (buffered stream for normal logs)
    _writeToSystemLog(entry);
  }

  void _writeToSystemLog(AppLogEntry entry) {
    if (_logDir == null) return;
    try {
      final line = '${entry.formatted}\n';
      _systemLogSink?.write(line);
      _writeSyncToLog(_appLogFileName(entry.timestamp), line);
      _systemLogSize += line.length;
      // Flush warning/error entries so important breadcrumbs survive process death.
      if (entry.level == AppLogLevel.warn || entry.level == AppLogLevel.error) {
        _systemLogSink?.flush();
      }
    } catch (_) {
      // Silently fail to avoid recursion
    }
  }

  Future<void> flush() async {
    try {
      await _systemLogSink?.flush();
    } catch (_) {}
  }

  Future<List<FileSystemEntity>> _listLogFiles({
    required String prefix,
    required String suffix,
    int limit = 20,
  }) async {
    if (_logDir == null || !await _logDir!.exists()) return [];
    final files = await _logDir!
        .list()
        .where((entity) {
          final name = entity.path.split(Platform.pathSeparator).last;
          return name.startsWith(prefix) && name.endsWith(suffix);
        })
        .toList();
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
  void _writeSyncCrashLog(String message, Object? exception, StackTrace? stackTrace) {
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
      file.writeAsStringSync(buf.toString(), mode: FileMode.append, flush: true);
      final datedFile = File('${_logDir!.path}/${_crashLogFileName()}');
      datedFile.writeAsStringSync(buf.toString(), mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  /// Synchronous write to a named log file.
  void _writeSyncToLog(String fileName, String content) {
    if (_logDir == null) return;
    try {
      final file = File('${_logDir!.path}/$fileName');
      file.writeAsStringSync(content, mode: FileMode.append, flush: true);
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
    return _memoryLogs
        .sublist(start)
        .map((e) => e.formatted)
        .join('\n');
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
      final systemFile = File('${_logDir!.path}/$_systemLogFile');
      if (await systemFile.exists()) await systemFile.delete();
      final crashFile = File('${_logDir!.path}/$_crashLogFile');
      if (await crashFile.exists()) await crashFile.delete();
      final scriptErrFile = File('${_logDir!.path}/$_scriptErrorLogFile');
      if (await scriptErrFile.exists()) await scriptErrFile.delete();
      await for (final entity in _logDir!.list()) {
        final name = entity.path.split(Platform.pathSeparator).last;
        final isManagedLog =
            (name.startsWith('app-') ||
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
    buf.writeln('Generated at: ${DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(DateTime.now())}');
    buf.writeln('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
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
      final files = await nativeDir.list()
          .where((f) => f.path.endsWith('.txt'))
          .toList();
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
