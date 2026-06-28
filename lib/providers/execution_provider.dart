import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/script_group.dart';
import '../models/log_entry.dart';
import '../models/execution_state.dart';
import '../services/native_bridge.dart';
import '../services/app_logger.dart';
import '../services/http_inspector_store.dart';
import '../services/request_override_config.dart';
import '../services/network_debug_config.dart';
import '../services/project_path_validator.dart';
import '../services/script_name_validator.dart';
import '../runtime/runtime_manager.dart';
import '../runtime/runtime_request.dart';
import 'package:intl/intl.dart';

/// Stores logs for a single script execution run
class ScriptLogRecord {
  final String executionId;
  final String scriptName;
  final DateTime startTime;
  final List<LogEntry> logs;
  ExecutionStatus status;
  int? exitCode;

  ScriptLogRecord({
    required this.executionId,
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

class _ExecutionPreferences {
  final bool floatingBallEnabled;
  final String? workingDir;
  final int? timeoutSeconds;
  final String preferredRuntimeBackendId;

  const _ExecutionPreferences({
    required this.floatingBallEnabled,
    required this.workingDir,
    required this.timeoutSeconds,
    required this.preferredRuntimeBackendId,
  });
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
  final Map<String, ScriptLogRecord> _historyByExecutionId = {};
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

  /// Returns the newest recorded run for [scriptName], or null if the script
  /// has never been executed.
  ScriptLogRecord? latestHistoryRecordForScript(String scriptName) {
    for (var i = _logHistory.length - 1; i >= 0; i--) {
      final record = _logHistory[i];
      if (record.scriptName == scriptName) {
        return record;
      }
    }
    return null;
  }

  ScriptLogRecord? _historyRecordForExecutionId(String? executionId) {
    if (executionId == null || executionId.isEmpty) return null;
    return _historyByExecutionId[executionId];
  }

  ScriptLogRecord? _activeHistoryRecord() {
    final executionId = _state.executionId;
    if (executionId == null) return null;
    if (_state.status != ExecutionStatus.running &&
        _state.status != ExecutionStatus.stopping) {
      return null;
    }
    return _historyRecordForExecutionId(executionId);
  }

  ScriptLogRecord? historyRecordForScriptExecution(String scriptName) {
    final activeExecutionId = _state.executionId;
    final activeRecord = _historyRecordForExecutionId(activeExecutionId);
    if (activeRecord != null && activeRecord.scriptName == scriptName) {
      return activeRecord;
    }
    for (var i = _logHistory.length - 1; i >= 0; i--) {
      final record = _logHistory[i];
      if (record.scriptName == scriptName) {
        return record;
      }
    }
    return null;
  }

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
    } catch (e, stackTrace) {
      _logger.warn(
        '读取悬浮球设置失败: $e',
        source: 'Execution',
        detail: stackTrace.toString(),
      );
    }
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

        final routedRecord =
            _historyRecordForExecutionId(entry.executionId) ??
                _activeHistoryRecord();
        _appendLiveLog(entry, routedRecord: routedRecord);
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
        if (!_isCurrentExecutionState(state)) {
          return;
        }
        _state = state;
        final isTerminal = _state.status != ExecutionStatus.running &&
            _state.status != ExecutionStatus.stopping;
        if (isTerminal) {
          final record = _historyRecordForExecutionId(_state.executionId) ??
              (_logHistory.isNotEmpty ? _logHistory.last : null);
          if (record != null) {
            record.status = _state.status;
            record.exitCode = _state.exitCode;
          }
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

  bool _isCurrentExecutionState(ExecutionState state) {
    final nextExecutionId = state.executionId;
    final activeExecutionId = _state.executionId;
    if (nextExecutionId != null &&
        activeExecutionId != null &&
        nextExecutionId != activeExecutionId) {
      return false;
    }
    if (nextExecutionId == null &&
        activeExecutionId != null &&
        (_state.status == ExecutionStatus.running ||
            _state.status == ExecutionStatus.stopping)) {
      return false;
    }
    return true;
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

  void _appendLiveLog(LogEntry entry, {ScriptLogRecord? routedRecord}) {
    final record = routedRecord ?? _activeHistoryRecord();
    final activeExecutionId = _state.executionId;
    final shouldAppendLive = record != null &&
        activeExecutionId != null &&
        record.executionId == activeExecutionId &&
        (_state.status == ExecutionStatus.running ||
            _state.status == ExecutionStatus.stopping);
    final shouldAppendAnonymousLive =
        record == null &&
            (_state.status != ExecutionStatus.running &&
                _state.status != ExecutionStatus.stopping);
    if (shouldAppendLive || shouldAppendAnonymousLive) {
      _logs.add(entry);
      _trimListToMax(_logs, maxCurrentLogs);
    }
    _appendHistoryLog(entry, routedRecord: record);
    _bumpLogVersion();
  }

  void _appendHistoryLog(LogEntry entry, {ScriptLogRecord? routedRecord}) {
    final record = routedRecord ?? _activeHistoryRecord();
    if (record == null) return;
    record.logs.add(entry);
    _trimListToMax(record.logs, maxLogsPerHistoryRecord);
  }

  void _replaceLastLiveLog(LogEntry entry) {
    if (_logs.isEmpty) {
      _appendLiveLog(entry);
      return;
    }
    _logs[_logs.length - 1] = entry;
    final record = _activeHistoryRecord();
    if (record != null && record.logs.isNotEmpty) {
      record.logs[record.logs.length - 1] = entry;
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

  void _trimHistoryRecords() {
    while (_logHistory.length > maxHistoryRecords) {
      final removed = _logHistory.removeAt(0);
      _historyByExecutionId.remove(removed.executionId);
    }
  }

  Future<_ExecutionPreferences> _loadExecutionPreferences({
    bool includeWorkingDir = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return _ExecutionPreferences(
      floatingBallEnabled: prefs.getBool('floating_ball_enabled') ?? false,
      workingDir: includeWorkingDir ? prefs.getString('working_dir') : null,
      timeoutSeconds: prefs.getInt('execution_timeout'),
      preferredRuntimeBackendId: RuntimeManager.normalizePreferredBackendId(
        prefs.getString(RuntimeManager.prefsKey),
      ),
    );
  }

  Map<String, String> _buildTimezoneEnvironment() {
    final offset = DateTime.now().timeZoneOffset;
    final totalMinutes = offset.inMinutes;
    final absMinutes = totalMinutes.abs();
    final h = absMinutes ~/ 60;
    final m = absMinutes % 60;
    final tzSign = totalMinutes >= 0 ? '-' : '+';
    final tzValue =
        m > 0 ? 'UTC$tzSign$h:${m.toString().padLeft(2, '0')}' : 'UTC$tzSign$h';
    return {'TZ': tzValue};
  }

  Map<String, String> _buildNetworkHookEnvironment() {
    final overrideConfig = RequestOverrideConfig.instance;
    final netDebugConfig = NetworkDebugConfig.instance;
    if (!overrideConfig.recordRequests && !overrideConfig.overrideEnabled) {
      return const {};
    }
    return {
      'PYRUNNER_HTTP_HOOK_CONFIG': overrideConfig.toJsonString(),
      'PYRUNNER_PROXY_HOST': netDebugConfig.proxyHost,
      'PYRUNNER_PROXY_PORT': netDebugConfig.proxyPort > 0
          ? netDebugConfig.proxyPort.toString()
          : '',
      'PYRUNNER_SSL_VERIFY': netDebugConfig.allowInsecureCerts ? '0' : '1',
    };
  }

  Map<String, String> _buildRuntimeEnvironment({
    required String runtimeBackendId,
    required String preferredRuntimeBackendId,
  }) {
    return {
      'PYRUNNER_RUNTIME_BACKEND': runtimeBackendId,
      'PYRUNNER_PREFERRED_RUNTIME_BACKEND': preferredRuntimeBackendId,
      'TERM': 'xterm-256color',
      ..._buildTimezoneEnvironment(),
      ..._buildNetworkHookEnvironment(),
    };
  }

  Duration? _timeoutFromSeconds(int? timeoutSeconds) {
    return timeoutSeconds != null && timeoutSeconds > 0
        ? Duration(seconds: timeoutSeconds)
        : null;
  }

  Future<String> _resolveExecutableBackendId(
    String preferredBackendId, {
    bool isProject = false,
  }) async {
    final resolvedBackendId =
        RuntimeManager.resolveBackendId(preferredBackendId);
    if (_runtimeManagerLocked ||
        resolvedBackendId != RuntimeManager.linuxLikeBackendId) {
      return resolvedBackendId;
    }
    try {
      final health = await RuntimeManager.linuxLike(_bridge).checkHealth();
      if (health.ok) {
        return resolvedBackendId;
      }

      if (isProject) {
        throw StateError('Linux-like 运行时未就绪: ${health.message}\n\n'
            '项目脚本需要 Linux-like 环境。请先安装运行时或在设置中切换到 Chaquopy。');
      }

      _logger.warn(
        '运行引擎 $preferredBackendId 未就绪: ${health.message}，回退到 Chaquopy',
        source: 'Execution',
      );
    } catch (e) {
      if (e is StateError) rethrow;

      if (isProject) {
        throw StateError('Linux-like 运行时健康检查失败: $e\n\n'
            '项目脚本需要 Linux-like 环境。请先安装运行时或在设置中切换到 Chaquopy。');
      }

      _logger.warn(
        '运行引擎 $preferredBackendId 健康检查失败: $e，回退到 Chaquopy',
        source: 'Execution',
      );
    }
    return RuntimeManager.fallbackBackendId;
  }

  Future<void> executeScript(String name) async {
    final safeName = ScriptNameValidator.normalize(name);
    // If a previous execution is still marked as running, clean it up
    if (_state.status == ExecutionStatus.running) {
      final previousRecord = _activeHistoryRecord();
      try {
        await _runtimeManager.stopExecution();
      } catch (e, stackTrace) {
        _logger.warn(
          '停止上一轮执行失败: $e',
          source: 'Execution',
          detail: stackTrace.toString(),
        );
      }
      if (previousRecord != null) {
        previousRecord.status = ExecutionStatus.stopped;
        previousRecord.exitCode = 0;
      }
    }

    final executionId = _nextExecutionId();
    _currentScriptName = safeName;
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
      final prefs = await _loadExecutionPreferences();
      _floatingBallEnabled = prefs.floatingBallEnabled;
      workingDir = prefs.workingDir;
      timeoutSeconds = prefs.timeoutSeconds;
      preferredRuntimeBackendId = prefs.preferredRuntimeBackendId;
      runtimeBackendId =
          await _resolveExecutableBackendId(preferredRuntimeBackendId);
    } catch (e, stackTrace) {
      _logger.warn(
        '读取执行偏好失败，使用默认配置: $e',
        source: 'Execution',
        detail: stackTrace.toString(),
      );
    }
    _selectRuntimeManager(runtimeBackendId);

    // Create a new log history record
    final record = ScriptLogRecord(
      executionId: executionId,
      scriptName: safeName,
      startTime: DateTime.now(),
    );
    _logHistory.add(record);
    _historyByExecutionId[executionId] = record;
    _trimHistoryRecords();

    notifyListeners();

    try {
      final environment = _buildRuntimeEnvironment(
        runtimeBackendId: runtimeBackendId,
        preferredRuntimeBackendId: preferredRuntimeBackendId,
      );
      if (preferredRuntimeBackendId != runtimeBackendId) {
        final fallbackMsg =
            '⚠️ 运行引擎 $preferredRuntimeBackendId 尚未就绪，回退到 $runtimeBackendId';
        _logger.warn(
          fallbackMsg,
          source: 'Execution',
        );
        // Add visible warning to execution output
        _appendLiveLog(LogEntry(
          type: LogType.info,
          content: '\x1b[33m$fallbackMsg\x1b[0m\n',
          timestamp: DateTime.now(),
          executionId: executionId,
        ));
      }

      await _runtimeManager.startScript(RuntimeRequest(
        scriptName: safeName,
        executionId: executionId,
        workingDirectory: workingDir,
        environment: environment,
        timeout: _timeoutFromSeconds(timeoutSeconds),
      ));
      _logger.info(
        '脚本开始执行: $safeName (id: $executionId, runtime: $runtimeBackendId)',
        source: 'Execution',
      );

      // Show floating ball if enabled and permitted
      _showFloatingBallIfNeeded(safeName);
    } catch (e) {
      _logger.error('脚本启动失败: $safeName, error: $e', source: 'Execution');
      _appendLiveLog(LogEntry(
        type: LogType.error,
        content: 'Failed to start: $e',
        timestamp: DateTime.now(),
        executionId: executionId,
      ));
      _state = ExecutionState(
        executionId: executionId,
        status: ExecutionStatus.error,
        exitCode: -1,
      );
      final record = _historyRecordForExecutionId(executionId);
      if (record != null) {
        record.status = ExecutionStatus.error;
        record.exitCode = -1;
      }
      notifyListeners();
    }
  }

  Future<void> executeScriptProject(ScriptGroup group) async {
    if (!group.isProject) {
      throw StateError('普通分组不能作为项目运行');
    }

    final projectKey =
        ProjectPathValidator.normalizeProjectKey(group.projectKey ?? '');
    final mainFilePath =
        ProjectPathValidator.validateMainFilePath(group.mainFilePath ?? '');
    final displayName = group.name.trim().isEmpty ? projectKey : group.name;

    if (_state.status == ExecutionStatus.running) {
      final previousRecord = _activeHistoryRecord();
      try {
        await _runtimeManager.stopExecution();
      } catch (e, stackTrace) {
        _logger.warn(
          '停止上一轮项目执行失败: $e',
          source: 'Execution',
          detail: stackTrace.toString(),
        );
      }
      if (previousRecord != null) {
        previousRecord.status = ExecutionStatus.stopped;
        previousRecord.exitCode = 0;
      }
    }

    final executionId = _nextExecutionId();
    _currentScriptName = displayName;
    _clearCurrentLogs();
    _waitingForInput = false;
    _currentInputPrompt = '';
    _state = ExecutionState(
      executionId: executionId,
      status: ExecutionStatus.running,
    );

    int? timeoutSeconds;
    String preferredRuntimeBackendId = RuntimeManager.chaquopyBackendId;
    try {
      final prefs = await _loadExecutionPreferences(includeWorkingDir: false);
      _floatingBallEnabled = prefs.floatingBallEnabled;
      timeoutSeconds = prefs.timeoutSeconds;
      preferredRuntimeBackendId = prefs.preferredRuntimeBackendId;
    } catch (e, stackTrace) {
      _logger.warn(
        '读取项目执行偏好失败，使用默认配置: $e',
        source: 'Execution',
        detail: stackTrace.toString(),
      );
    }

    final record = ScriptLogRecord(
      executionId: executionId,
      scriptName: displayName,
      startTime: DateTime.now(),
    );
    _logHistory.add(record);
    _historyByExecutionId[executionId] = record;
    _trimHistoryRecords();
    notifyListeners();

    try {
      if (preferredRuntimeBackendId != RuntimeManager.linuxLikeBackendId) {
        throw StateError('项目只能在 Linux-like 引擎下运行，请先切换运行引擎');
      }
      if (_runtimeManagerLocked &&
          _runtimeManager.activeBackendId !=
              RuntimeManager.linuxLikeBackendId) {
        throw StateError('当前执行引擎不支持项目运行');
      }

      final health = await RuntimeManager.linuxLike(_bridge).checkHealth();
      if (!health.ok) {
        throw StateError(health.message);
      }
      _selectRuntimeManager(RuntimeManager.linuxLikeBackendId);

      final environment = _buildRuntimeEnvironment(
        runtimeBackendId: RuntimeManager.linuxLikeBackendId,
        preferredRuntimeBackendId: preferredRuntimeBackendId,
      );

      await _runtimeManager.startScript(RuntimeRequest(
        scriptName: displayName,
        executionId: executionId,
        environment: environment,
        timeout: _timeoutFromSeconds(timeoutSeconds),
        projectKey: projectKey,
        projectMainFilePath: mainFilePath,
      ));
      _logger.info(
        '项目开始执行: $displayName (id: $executionId, runtime: linux_like)',
        source: 'Execution',
      );
      _showFloatingBallIfNeeded(displayName);
    } catch (e) {
      _logger.error('项目启动失败: $displayName, error: $e', source: 'Execution');
      _appendLiveLog(LogEntry(
        type: LogType.error,
        content: 'Failed to start project: $e',
        timestamp: DateTime.now(),
        executionId: executionId,
      ));
      _state = ExecutionState(
        executionId: executionId,
        status: ExecutionStatus.error,
        exitCode: -1,
      );
      final record = _historyRecordForExecutionId(executionId);
      if (record != null) {
        record.status = ExecutionStatus.error;
        record.exitCode = -1;
      }
      notifyListeners();
    }
  }

  Future<void> sendStdin(String input) async {
    try {
      await _runtimeManager.sendStdin(input);
      final prompt = _currentInputPrompt;
      final echoedInput = prompt.isNotEmpty ? '$prompt$input' : '> $input';
      final mergedPromptLine =
          prompt.isNotEmpty && _logs.isNotEmpty && _logs.last.content == prompt;
      final entry = LogEntry(
        type: mergedPromptLine ? LogType.stdout : LogType.info,
        content: echoedInput,
        timestamp: DateTime.now(),
        executionId: _state.executionId,
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
        final record = _historyRecordForExecutionId(_state.executionId);
        if (record != null) {
          record.status = ExecutionStatus.stopping;
        }
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
    _historyByExecutionId.clear();
    notifyListeners();
  }

  void removeHistoryRecord(int index) {
    if (index >= 0 && index < _logHistory.length) {
      final removed = _logHistory.removeAt(index);
      _historyByExecutionId.remove(removed.executionId);
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
    } catch (e, stackTrace) {
      _logger.error(
        '悬浮球显示失败: $e',
        source: 'FloatingBall',
        detail: stackTrace.toString(),
      );
    }
  }

  Future<void> syncFloatingBallVisibility({bool throwOnError = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _floatingBallEnabled = prefs.getBool('floating_ball_enabled') ?? false;
    } catch (e, stackTrace) {
      _logger.error(
        '读取悬浮球设置失败: $e',
        source: 'FloatingBall',
        detail: stackTrace.toString(),
      );
      if (throwOnError) rethrow;
    }
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
    } catch (e, stackTrace) {
      _logger.error(
        '同步悬浮球显示状态失败: $e',
        source: 'FloatingBall',
        detail: stackTrace.toString(),
      );
      if (throwOnError) rethrow;
    }
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
        final safeName =
            name == null ? null : ScriptNameValidator.tryNormalize(name);
        if (safeName != null && safeName.isNotEmpty) {
          executeScript(safeName);
          if (onNavigateToConsole != null) {
            onNavigateToConsole!.call(safeName);
          } else {
            _pendingNavigateScriptName = safeName;
          }
        }
      } catch (e, stackTrace) {
        _logger.warn(
          '轮询悬浮球待运行脚本失败: $e',
          source: 'FloatingBall',
          detail: stackTrace.toString(),
        );
      } finally {
        _pollingPending = false;
      }
    });
  }

  Future<void> _hideFloatingBall() async {
    try {
      await _bridge.hideFloatingBall();
    } catch (e, stackTrace) {
      _logger.warn(
        '隐藏悬浮球失败: $e',
        source: 'FloatingBall',
        detail: stackTrace.toString(),
      );
    }
  }

  Future<void> _updateFloatingBallStatus(String status) async {
    if (!_floatingBallEnabled) return;
    try {
      await _bridge.updateFloatingBallStatus(status);
    } catch (e, stackTrace) {
      _logger.warn(
        '更新悬浮球状态失败: $e',
        source: 'FloatingBall',
        detail: stackTrace.toString(),
      );
    }
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
