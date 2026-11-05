import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'log_record.dart';
import 'segmented_log_store.dart';

/// The three on-disk logs (terminal, AI conversation, AI operations).
class TerminalLogs {
  TerminalLogs._();

  static final TerminalLogs instance = TerminalLogs._();

  static const String _recordTerminalKey = 'terminal_log_record_terminal';

  final Map<LogChannel, SegmentedLogStore> _stores =
      <LogChannel, SegmentedLogStore>{};
  Future<bool>? _init;
  bool _recordTerminal = true;

  /// Whether terminal input and output are written to the terminal log. The
  /// AI logs are always kept, because they are the audit trail.
  bool get recordTerminal => _recordTerminal;

  Future<bool> _ensureReady() => _init ??= _initialize();

  Future<bool> _initialize() async {
    try {
      final support = await getApplicationSupportDirectory();
      final root = Directory('${support.path}/terminal_logs');
      for (final channel in LogChannel.values) {
        _stores[channel] = SegmentedLogStore(
          directory: Directory('${root.path}/${channel.dirName}'),
        );
      }
      final prefs = await SharedPreferences.getInstance();
      _recordTerminal = prefs.getBool(_recordTerminalKey) ?? true;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> setRecordTerminal(bool value) async {
    _recordTerminal = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_recordTerminalKey, value);
  }

  /// Queues [record] for [channel]. Never throws.
  void add(LogChannel channel, LogRecord record) {
    if (channel == LogChannel.terminal && !_recordTerminal) return;
    unawaited(_add(channel, record));
  }

  Future<void> _add(LogChannel channel, LogRecord record) async {
    if (!await _ensureReady()) return;
    _stores[channel]?.append(record);
  }

  /// The store of [channel], or null when the logs cannot be opened.
  Future<SegmentedLogStore?> store(LogChannel channel) async {
    if (!await _ensureReady()) return null;
    return _stores[channel];
  }

  /// Writes everything that is still queued (call when the app pauses).
  Future<void> flushAll() async {
    if (!await _ensureReady()) return;
    for (final store in _stores.values) {
      await store.flush();
    }
  }
}
