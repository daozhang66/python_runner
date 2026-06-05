import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/log_entry.dart';
import '../models/execution_state.dart';
import '../services/native_bridge.dart';
import '../services/app_logger.dart';
import '../services/http_inspector_store.dart';
import '../services/request_override_config.dart';
import '../services/network_debug_config.dart';
import '../runtime/runtime_manager.dart';
import '../runtime/runtime_request.dart';
import 'package:intl/intl.dart';

/// Stores logs for a single script execution run
class ScriptLogRecord {
  final String scriptName;
  final DateTime startTime;
  final List<LogEntry> logs;
  ExecutionStatus status;
  int? exitCode;

  ScriptLogRecord({
    required this.scriptName,
    required this.startTime,
    List<LogEntry>? logs,
    this.status = ExecutionStatus.running,
    this.exitCode,
  }) : logs = logs ?? [];

  String get logsAsText {
    return logs.map((e) => e.content).join('\n');
  }
}

class ExecutionProvider extends ChangeNotifier {
  static const int maxCurrentLogs = 5000;
  static const int maxLogsPerHistoryRecord = 5000;
  static const int maxHistoryRecords = 20;

  final NativeBridge _bridge;
  RuntimeManager _runtimeManager;
  final bool _runtimeManagerLocked;
  int _executionSequence = 0;

  ExecutionState _state = const ExecutionState();
  final List<LogEntry> _logs = [];
  late final UnmodifiableListView<LogEntry> _logsView =
      UnmodifiableListView(_logs);
  StreamSubscription? _logSub;
  StreamSubscription? _statusSub;
  StreamSubscription? _stdinSub;
  String? _currentScriptName;
  bool _waitingForInput = false;
  String _currentInputPrompt = '';
  int _logVersion = 0;

  /// History of all script execution logs
  final List<ScriptLogRecord> _logHistory = [];
  late final UnmodifiableListView<ScriptLogRecord> _logHistoryView =
      UnmodifiableListView(_logHistory);

  bool _floatingBallEnabled = false;

  /// Callback for navigating to the console page when script is triggered from floating ball.
  static void Function(String scriptName)? onNavigateToConsole;
  static String? _pendingNavigateScriptName;

  static void setNavigateToConsoleHandler(
      void Function(String scriptName)? handler) {
    onNavigateToConsole = handler;
    if (handler != null && _pendingNavigateScriptName != null) {
      final pending = _pendingNavigateScriptName!;
      _pendingNavigateScriptName = null;
      handler(pending);
    }
  }

  /// Throttled notification timer — batches rapid updates into a single
  /// notifyListeners() call after a short delay (100ms).
  Timer? _notifyTimer;
  Timer? _pendingRunPollTimer;
  bool _disposed = false;
  static const _notifyDelay = Duration(milliseconds: 100);

  ExecutionState get state => _state;
  List<LogEntry> get logs => _logsView;
  int get logVersion => _logVersion;
  String? get currentScriptName => _currentScriptName;
  bool get isRunning =>
      _state.status == ExecutionStatus.running ||
      _state.status == ExecutionStatus.stopping;
  bool get waitingForInput => _waitingForInput;
  String get currentInputPrompt => _currentInputPrompt;
  List<ScriptLogRecord> get logHistory => _logHistoryView;

  ExecutionProvider(this._bridge, {RuntimeManager? runtimeManager})
      : _runtimeManager = runtimeManager ??
            RuntimeManager.fromPreferredBackend(
              _bridge,
              RuntimeManager.chaquopyBackendId,
            ),
        _runtimeManagerLocked = runtimeManager != null {
    _loadFloatingBallSetting();
    _listenStreams();
    syncFloatingBallVisibility();
    _pollPendingRunScript();
  }

  final _logger = AppLogger.instance;

  Future<void> _loadFloatingBallSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _floatingBallEnabled = prefs.getBool('floating_ball_enabled') ?? false;
    } catch (_) {}
  }

  void _listenStreams() {
    _logSub?.cancel();
    _statusSub?.cancel();
    _stdinSub?.cancel();

    try {
      _logSub = _runtimeManager.outputStream.listen((output) {
        // Normal log entry
        final entry = output.toLogEntry();

        // Intercept HTTP record messages from Python hook
        if (entry.content.startsWith('__HTTP_RECORD__')) {
          try {
            final jsonStr = entry.content.substring('__HTTP_RECORD__'.length);
            final jsonMap = jsonDecode(jsonStr) as Map<String, dynamic>;
            HttpInspectorStore.instance.addFromJson(jsonMap);
          } catch (e) {
            _logger.warn('HTTP record parse error: $e', source: 'Execution');
          }
          // Don't show this in the normal log output
          return;
        }

        // Filter out hook diagnostic messages
        if (entry.content.startsWith('__HOOK_DIAG__')) {
          return;
        }

        _appendLiveLog(entry);
        // High-frequency log streams — throttle notifications
        _scheduleNotify();
      }, onError: (e) {
        _logger.error('logStream error: $e', source: 'Execution');
      });
    } catch (e) {
      _logger.error('Failed to listen logStream: $e', source: 'Execution');
    }

    try {
      _statusSub = _runtimeManager.stateStream.listen((state) {
        _state = state;
        final isTerminal = _state.status != ExecutionStatus.running &&
            _state.status != ExecutionStatus.stopping;
        if (_logHistory.isNotEmpty && isTerminal) {
          _logHistory.last.status = _state.status;
          _logHistory.last.exitCode = _state.exitCode;
        }
        if (isTerminal) {
          _waitingForInput = false;
          _currentInputPrompt = '';
          unawaited(HttpInspectorStore.instance.flush());
          // Update floating ball status and hide after delay
          _updateFloatingBallOnTerminal(_state.status);
        }
        _scheduleNotify();
      }, onError: (e) {
        _logger.error('statusStream error: $e', source: 'Execution');
      });
    } catch (e) {
      _logger.error('Failed to listen executionStatusStream: $e',
          source: 'Execution');
    }

    try {
      _stdinSub = _runtimeManager.stdinRequestStream.listen((request) {
        final activeExecutionId = _state.executionId;
        if (_state.status != ExecutionStatus.running &&
            _state.status != ExecutionStatus.stopping) {
          return;
        }
        if (request.executionId != null &&
            activeExecutionId != null &&
            request.executionId != activeExecutionId) {
          return;
        }
        _currentInputPrompt = request.prompt;
        if (_currentInputPrompt.isNotEmpty) {
          final entry = LogEntry(
            type: LogType.stdout,
            content: _currentInputPrompt,
            timestamp: DateTime.now(),
          );
          _appendLiveLog(entry);
        }
        _waitingForInput = true;
        // Update floating ball to show waiting state
        _updateFloatingBallStatus('waiting_input');
        _scheduleNotify();
      }, onError: (e) {
        _logger.error('stdinRequestStream error: $e', source: 'Execution');
      });
    } catch (e) {
      _logger.error('Failed to listen stdinRequestStream: $e',
          source: 'Execution');
    }
  }

  void _selectRuntimeManager(String backendId) {
    if (_runtimeManagerLocked) return;
    final nextManager = RuntimeManager.fromPreferredBackend(_bridge, backendId);
    if (nextManager.activeBackendId == _runtimeManager.activeBackendId) {
      return;
    }
    _runtimeManager = nextManager;
    _listenStreams();
  }

  /// Schedule a throttled notifyListeners() call.
  /// Multiple rapid updates within [notifyDelay] are coalesced into one.
  void _scheduleNotify() {
    if (_disposed) return;
    _notifyTimer?.cancel();
    _notifyTimer = Timer(_notifyDelay, () {
      if (!_disposed) {
        notifyListeners();
      }
    });
  }

  void _bumpLogVersion() {
    _logVersion++;
  }

  static void _trimListToMax<T>(List<T> items, int maxItems) {
    if (items.length <= maxItems) return;
    items.removeRange(0, items.length - maxItems);
  }

  void _appendLiveLog(LogEntry entry) {
    _logs.add(entry);
    _trimListToMax(_logs, maxCurrentLogs);
    if (_logHistory.isNotEmpty) {
      final historyLogs = _logHistory.last.logs;
      historyLogs.add(entry);
      _trimListToMax(historyLogs, maxLogsPerHistoryRecord);
    }
    _bumpLogVersion();
  }

  void _replaceLastLiveLog(LogEntry entry) {
    if (_logs.isEmpty) {
      _appendLiveLog(entry);
      return;
    }
    _logs[_logs.length - 1] = entry;
    if (_logHistory.isNotEmpty && _logHistory.last.logs.isNotEmpty) {
      _logHistory.last.logs[_logHistory.last.logs.length - 1] = entry;
    }
    _bumpLogVersion();
  }

  void _clearCurrentLogs() {
    if (_logs.isEmpty) return;
    _logs.clear();
    _bumpLogVersion();
  }

  String _nextExecutionId() {
    _executionSequence = (_executionSequence + 1) & 0xFFFF;
    final micros = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final seq = _executionSequence.toRadixString(16).padLeft(4, '0');
    return '$micros-$seq';
  }

  Future<void> executeScript(String name) async {
    // If a previous execution is still marked as running, clean it up
    if (_state.status == ExecutionStatus.running) {
      try {
        await _runtimeManager.stopExecution();
      } catch (_) {}
      if (_logHistory.isNotEmpty) {
        _logHistory.last.status = ExecutionStatus.error;
        _logHistory.last.exitCode = 1;
      }
    }

    final executionId = _nextExecutionId();
    _currentScriptName = name;
    _clearCurrentLogs();
    _waitingForInput = false;
    _currentInputPrompt = '';
    _state = ExecutionState(
      executionId: executionId,
      status: ExecutionStatus.running,
    );

    // Load working directory, timeout, and floating ball setting
    String? workingDir;
    int? timeoutSeconds;
    String preferredRuntimeBackendId = RuntimeManager.chaquopyBackendId;
    String runtimeBackendId = RuntimeManager.chaquopyBackendId;
    try {
      final prefs = await SharedPreferences.getInstance();
      _floatingBallEnabled = prefs.getBool('floating_ball_enabled') ?? false;
      workingDir = prefs.getString('working_dir');
      timeoutSeconds = prefs.getInt('execution_timeout');
      preferredRuntimeBackendId = RuntimeManager.normalizePreferredBackendId(
        prefs.getString(RuntimeManager.prefsKey),
      );
      runtimeBackendId =
          RuntimeManager.resolveBackendId(preferredRuntimeBackendId);
    } catch (_) {}
    _selectRuntimeManager(runtimeBackendId);

    // Create a new log history record
    _logHistory.add(ScriptLogRecord(
      scriptName: name,
      startTime: DateTime.now(),
    ));
    _trimListToMax(_logHistory, maxHistoryRecords);

    notifyListeners();

    try {
      final offset = DateTime.now().timeZoneOffset;
      final totalMinutes = offset.inMinutes;
      final absMinutes = totalMinutes.abs();
      final h = absMinutes ~/ 60;
      final m = absMinutes % 60;
      // POSIX TZ: negative sign = east of UTC (e.g. UTC-8 means UTC+8)
      final tzSign = totalMinutes >= 0 ? '-' : '+';
      final tzValue = m > 0
          ? 'UTC$tzSign$h:${m.toString().padLeft(2, '0')}'
          : 'UTC$tzSign$h';

      final environment = <String, String>{
        'PYRUNNER_RUNTIME_BACKEND': runtimeBackendId,
        'PYRUNNER_PREFERRED_RUNTIME_BACKEND': preferredRuntimeBackendId,
        'TERM': 'xterm-256color',
        // Pass device timezone to Linux-like so Python sees the correct local time
        'TZ': tzValue,
      };
      if (preferredRuntimeBackendId != runtimeBackendId) {
        _logger.warn(
          '运行引擎 $preferredRuntimeBackendId 尚未就绪，回退到 $runtimeBackendId',
          source: 'Execution',
        );
      }

      // Build HTTP hook environment config
      final overrideConfig = RequestOverrideConfig.instance;
      final netDebugConfig = NetworkDebugConfig.instance;
      if (overrideConfig.recordRequests || overrideConfig.overrideEnabled) {
        environment.addAll({
          'PYRUNNER_HTTP_HOOK_CONFIG': overrideConfig.toJsonString(),
          'PYRUNNER_PROXY_HOST': netDebugConfig.proxyHost,
          'PYRUNNER_PROXY_PORT': netDebugConfig.proxyPort > 0
              ? netDebugConfig.proxyPort.toString()
              : '',
          'PYRUNNER_SSL_VERIFY': netDebugConfig.allowInsecureCerts ? '0' : '1',
        });
      }

      await _runtimeManager.startScript(RuntimeRequest(
        scriptName: name,
        executionId: executionId,
        workingDirectory: workingDir,
        environment: environment,
        timeout: timeoutSeconds != null && timeoutSeconds > 0
            ? Duration(seconds: timeoutSeconds)
            : null,
      ));
      _logger.info(
        '脚本开始执行: $name (id: $executionId, runtime: $runtimeBackendId)',
        source: 'Execution',
      );

      // Show floating ball if enabled and permitted
      _showFloatingBallIfNeeded(name);
    } catch (e) {
      _logger.error('脚本启动失败: $name, error: $e', source: 'Execution');
      _appendLiveLog(LogEntry(
        type: LogType.error,
        content: 'Failed to start: $e',
        timestamp: DateTime.now(),
      ));
      _state = ExecutionState(
        executionId: executionId,
        status: ExecutionStatus.error,
        exitCode: -1,
      );
      if (_logHistory.isNotEmpty) {
        _logHistory.last.status = ExecutionStatus.error;
        _logHistory.last.exitCode = -1;
      }
      notifyListeners();
    }
  }

  Future<void> sendStdin(String input) async {
    try {
      await _runtimeManager.sendStdin(input);
      final prompt = _currentInputPrompt;
      final echoedInput = prompt.isNotEmpty ? '$prompt$input' : '> $input';
      final mergedPromptLine = prompt.isNotEmpty &&
          _logs.isNotEmpty &&
          _logs.last.content == prompt;
      final entry = LogEntry(
        type: mergedPromptLine ? LogType.stdout : LogType.info,
        content: echoedInput,
        timestamp: DateTime.now(),
      );
      if (mergedPromptLine) {
        _replaceLastLiveLog(entry);
      } else {
        _appendLiveLog(entry);
      }
      _currentInputPrompt = '';
      _waitingForInput = false;
      _scheduleNotify();
    } catch (e) {
      _logger.error('sendStdin error: $e', source: 'Execution');
    }
  }

  Future<void> stopExecution() async {
    try {
      if (_state.status == ExecutionStatus.running) {
        _state = _state.copyWith(status: ExecutionStatus.stopping);
        notifyListeners();
      }
      await _runtimeManager.stopExecution();
      _logger.info('脚本执行已停止', source: 'Execution');
    } catch (e) {
      _logger.error('stopExecution error: $e', source: 'Execution');
    }
  }

  void clearLogs() {
    _clearCurrentLogs();
    notifyListeners();
  }

  void clearHistory() {
    _logHistory.clear();
    notifyListeners();
  }

  void removeHistoryRecord(int index) {
    if (index >= 0 && index < _logHistory.length) {
      _logHistory.removeAt(index);
      notifyListeners();
    }
  }

  String getLogsAsText() {
    return _logs.map((e) => e.content).join('\n');
  }

  String getAllHistoryAsText() {
    final buf = StringBuffer();
    final dateFmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    for (final record in _logHistory) {
      buf.writeln(
          '=== ${record.scriptName} [${dateFmt.format(record.startTime)}] ===');
      buf.writeln(record.logsAsText);
      buf.writeln();
    }
    return buf.toString();
  }

  @override
  void dispose() {
    _disposed = true;
    _notifyTimer?.cancel();
    _pendingRunPollTimer?.cancel();
    _logSub?.cancel();
    _statusSub?.cancel();
    _stdinSub?.cancel();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  // Floating Ball Helpers
  // ═══════════════════════════════════════════════════════════

  Future<void> _showFloatingBallIfNeeded(String scriptName) async {
    if (!_floatingBallEnabled) return;
    try {
      final hasPermission = await _bridge.checkOverlayPermission();
      if (hasPermission) {
        await _bridge.showFloatingBall(scriptName);
      }
    } catch (_) {}
  }

  Future<void> syncFloatingBallVisibility() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _floatingBallEnabled = prefs.getBool('floating_ball_enabled') ?? false;
    } catch (_) {}
    if (!_floatingBallEnabled) {
      await _hideFloatingBall();
      return;
    }
    try {
      final hasPermission = await _bridge.checkOverlayPermission();
      if (hasPermission) {
        // Show with empty name → idle state
        await _bridge
            .showFloatingBall(isRunning ? (_currentScriptName ?? '') : '');
      }
    } catch (_) {}
  }

  bool _pollingPending = false;

  void _pollPendingRunScript() {
    // Poll every 500ms to check if floating ball triggered a script run
    _pendingRunPollTimer =
        Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      if (_disposed) {
        timer.cancel();
        return;
      }
      if (isRunning || _pollingPending) return;
      _pollingPending = true;
      try {
        final name = await _bridge.consumePendingRunScript();
        if (name != null && name.isNotEmpty) {
          executeScript(name);
          if (onNavigateToConsole != null) {
            onNavigateToConsole!.call(name);
          } else {
            _pendingNavigateScriptName = name;
          }
        }
      } catch (_) {} finally {
        _pollingPending = false;
      }
    });
  }

  Future<void> _hideFloatingBall() async {
    try {
      await _bridge.hideFloatingBall();
    } catch (_) {}
  }

  Future<void> _updateFloatingBallStatus(String status) async {
    if (!_floatingBallEnabled) return;
    try {
      await _bridge.updateFloatingBallStatus(status);
    } catch (_) {}
  }

  Future<void> _updateFloatingBallOnTerminal(ExecutionStatus status) async {
    if (!_floatingBallEnabled) return;
    if (status == ExecutionStatus.error) {
      await _updateFloatingBallStatus('error');
      // Show error for 3 seconds, then go idle
      await Future.delayed(const Duration(seconds: 3));
      if (_disposed) return;
    }
    await _updateFloatingBallStatus('idle');
  }
}
