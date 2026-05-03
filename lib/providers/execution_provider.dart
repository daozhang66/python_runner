import 'dart:async';
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
import 'package:uuid/uuid.dart';
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
  final NativeBridge _bridge;
  final _uuid = const Uuid();

  ExecutionState _state = const ExecutionState();
  final List<LogEntry> _logs = [];
  StreamSubscription? _logSub;
  StreamSubscription? _statusSub;
  StreamSubscription? _stdinSub;
  String? _currentScriptName;
  bool _waitingForInput = false;

  /// History of all script execution logs
  final List<ScriptLogRecord> _logHistory = [];

  /// Scene/graphics state — updated at ~60fps during scene execution.
  /// These fields updated internally; UI reads via getters.
  bool _sceneActive = false;
  int _sceneOrientation = 0;
  List<dynamic>? _currentSceneFrame;
  int _frameCount = 0;
  bool _graphicsEnabled = false;

  /// Throttled notification timer — batches rapid updates into a single
  /// notifyListeners() call after a short delay (100ms).
  Timer? _notifyTimer;
  bool _disposed = false;
  static const _notifyDelay = Duration(milliseconds: 100);

  ExecutionState get state => _state;
  List<LogEntry> get logs => List.unmodifiable(_logs);
  String? get currentScriptName => _currentScriptName;
  bool get isRunning => _state.status == ExecutionStatus.running || _state.status == ExecutionStatus.stopping;
  bool get waitingForInput => _waitingForInput;
  List<ScriptLogRecord> get logHistory => List.unmodifiable(_logHistory);

  bool get sceneActive => _sceneActive;
  int get sceneOrientation => _sceneOrientation;
  List<dynamic>? get currentSceneFrame => _currentSceneFrame;
  int get frameCount => _frameCount;

  ExecutionProvider(this._bridge) {
    _loadGraphicsSetting();
    _listenStreams();
  }

  final _logger = AppLogger.instance;

  Future<void> _loadGraphicsSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _graphicsEnabled = prefs.getBool('graphics_engine_enabled') ?? false;
    } catch (_) {}
  }

  void _listenStreams() {
    try {
      _logSub = _bridge.logStream.listen((data) {
        final typeStr = data['type'] as String? ?? 'info';
        final content = data['content'] as String? ?? '';

        // Handle scene messages — always intercept, never show as text logs
        if (typeStr == '__scene_init__') {
          if (_graphicsEnabled) {
            try {
              final initData = jsonDecode(content) as Map<String, dynamic>;
              _sceneActive = true;
              _sceneOrientation = (initData['orientation'] as int?) ?? 0;
              _frameCount = 0;
              _currentSceneFrame = null;
            } catch (e) {
              _logger.warn('scene init parse error: $e', source: 'Execution');
            }
            _scheduleNotify();
          }
          return;
        }

        if (typeStr == '__scene_frame__') {
          if (_sceneActive) {
            try {
              _currentSceneFrame = jsonDecode(content) as List<dynamic>;
              _frameCount++;
            } catch (e) {
              _logger.warn('scene frame parse error: $e', source: 'Execution');
            }
            // Scene frames fire at ~60fps — throttle notifications to avoid UI rebuild storms
            _scheduleNotify();
          }
          return;
        }

        if (typeStr == '__scene_end__') {
          _sceneActive = false;
          _currentSceneFrame = null;
          _scheduleNotify();
          return;
        }

        // Normal log entry
        final entry = LogEntry.fromMap(data);

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

        _logs.add(entry);
        if (_logHistory.isNotEmpty) {
          _logHistory.last.logs.add(entry);
        }
        // High-frequency log streams — throttle notifications
        _scheduleNotify();
      }, onError: (e) {
        _logger.error('logStream error: $e', source: 'Execution');
      });
    } catch (e) {
      _logger.error('Failed to listen logStream: $e', source: 'Execution');
    }

    try {
      _statusSub = _bridge.executionStatusStream.listen((data) {
        _state = ExecutionState.fromMap(data);
        final isTerminal = _state.status != ExecutionStatus.running &&
            _state.status != ExecutionStatus.stopping;
        if (_logHistory.isNotEmpty && isTerminal) {
          _logHistory.last.status = _state.status;
          _logHistory.last.exitCode = _state.exitCode;
        }
        if (isTerminal) {
          _waitingForInput = false;
          _sceneActive = false;
          _currentSceneFrame = null;
          unawaited(HttpInspectorStore.instance.flush());
        }
        _scheduleNotify();
      }, onError: (e) {
        _logger.error('statusStream error: $e', source: 'Execution');
      });
    } catch (e) {
      _logger.error('Failed to listen executionStatusStream: $e', source: 'Execution');
    }

    try {
      _stdinSub = _bridge.stdinRequestStream.listen((data) {
        _waitingForInput = true;
        _scheduleNotify();
      }, onError: (e) {
        _logger.error('stdinRequestStream error: $e', source: 'Execution');
      });
    } catch (e) {
      _logger.error('Failed to listen stdinRequestStream: $e', source: 'Execution');
    }
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

  Future<void> executeScript(String name) async {
    // If a previous execution is still marked as running, clean it up
    if (_state.status == ExecutionStatus.running) {
      try {
        await _bridge.stopExecution();
      } catch (_) {}
      if (_logHistory.isNotEmpty) {
        _logHistory.last.status = ExecutionStatus.error;
        _logHistory.last.exitCode = 1;
      }
    }

    final executionId = _uuid.v4();
    _currentScriptName = name;
    _logs.clear();
    _waitingForInput = false;
    _sceneActive = false;
    _currentSceneFrame = null;
    _frameCount = 0;
    _state = ExecutionState(
      executionId: executionId,
      status: ExecutionStatus.running,
    );

    // Load graphics setting and working directory
    String? workingDir;
    int? timeoutSeconds;
    try {
      final prefs = await SharedPreferences.getInstance();
      _graphicsEnabled = prefs.getBool('graphics_engine_enabled') ?? false;
      workingDir = prefs.getString('working_dir');
      timeoutSeconds = prefs.getInt('execution_timeout');
    } catch (_) {
      _graphicsEnabled = false;
    }

    // Create a new log history record
    _logHistory.add(ScriptLogRecord(
      scriptName: name,
      startTime: DateTime.now(),
    ));

    notifyListeners();

    try {
      // Build HTTP hook environment config
      final overrideConfig = RequestOverrideConfig.instance;
      final netDebugConfig = NetworkDebugConfig.instance;
      Map<String, String>? hookEnv;
      if (overrideConfig.recordRequests || overrideConfig.overrideEnabled) {
        hookEnv = {
          'PYRUNNER_HTTP_HOOK_CONFIG': overrideConfig.toJsonString(),
          'PYRUNNER_PROXY_HOST': netDebugConfig.proxyHost,
          'PYRUNNER_PROXY_PORT': netDebugConfig.proxyPort > 0
              ? netDebugConfig.proxyPort.toString()
              : '',
          'PYRUNNER_SSL_VERIFY': netDebugConfig.allowInsecureCerts ? '0' : '1',
        };
      }

      await _bridge.executeScript(name, executionId,
          workingDir: workingDir, hookEnv: hookEnv, timeoutSeconds: timeoutSeconds);
      _logger.info('脚本开始执行: $name (id: $executionId)', source: 'Execution');
    } catch (e) {
      _logger.error('脚本启动失败: $name, error: $e', source: 'Execution');
      _logs.add(LogEntry(
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
      await _bridge.sendStdin(input);
      _logs.add(LogEntry(
        type: LogType.info,
        content: '> $input',
        timestamp: DateTime.now(),
      ));
      if (_logHistory.isNotEmpty) {
        _logHistory.last.logs.add(_logs.last);
      }
      _waitingForInput = false;
      _scheduleNotify();
    } catch (e) {
      _logger.error('sendStdin error: $e', source: 'Execution');
    }
  }

  Future<void> sendSceneTouch(String touchJson) async {
    try {
      await _bridge.sendSceneTouch(touchJson);
    } catch (e) {
      _logger.error('sendSceneTouch error: $e', source: 'Execution');
    }
  }

  Future<void> stopExecution() async {
    try {
      // Immediately show "stopping" in UI so user knows the request was sent
      if (_state.status == ExecutionStatus.running) {
        _state = _state.copyWith(status: ExecutionStatus.stopping);
        notifyListeners();
      }
      await _bridge.stopExecution();
      _logger.info('脚本执行已停止', source: 'Execution');
    } catch (e) {
      _logger.error('stopExecution error: $e', source: 'Execution');
    }
  }

  void clearLogs() {
    _logs.clear();
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
      buf.writeln('=== ${record.scriptName} [${dateFmt.format(record.startTime)}] ===');
      buf.writeln(record.logsAsText);
      buf.writeln();
    }
    return buf.toString();
  }

  @override
  void dispose() {
    _disposed = true;
    _notifyTimer?.cancel();
    _logSub?.cancel();
    _statusSub?.cancel();
    _stdinSub?.cancel();
    super.dispose();
  }
}
