import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/log_entry.dart';
import '../providers/execution_provider.dart';
import '../models/execution_state.dart';
import '../providers/script_provider.dart';
import '../widgets/terminal_view.dart';

class RunConsolePage extends StatefulWidget {
  final String scriptName;
  const RunConsolePage({super.key, required this.scriptName});

  @override
  State<RunConsolePage> createState() => _RunConsolePageState();
}

class _RunConsolePageState extends State<RunConsolePage>
    with WidgetsBindingObserver {
  final _terminalKey = GlobalKey<TerminalViewState>();

  String get _displayName => widget.scriptName.replaceAll('.py', '');

  /// Record the time when execution started (from logHistory).
  DateTime? _runStartTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _captureStartTime();
  }

  void _captureStartTime() {
    final exec = context.read<ExecutionProvider>();
    if (exec.isRunning && exec.logHistory.isNotEmpty) {
      _runStartTime = exec.logHistory.last.startTime;
    }
  }

  @override
  void didChangeMetrics() {
    // Keyboard open/close: scroll to bottom
    _terminalKey.currentState?.forceAutoScroll();
  }

  Future<void> _rerun() async {
    try {
      final exec = context.read<ExecutionProvider>();
      final scriptProvider = context.read<ScriptProvider>();
      await scriptProvider.incrementRunCount(widget.scriptName);
      exec.clearLogs();
      await exec.executeScript(widget.scriptName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('运行失败: $e'), duration: const Duration(seconds: 3)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0D1117) : const Color(0xFFFAFAFA),
      appBar: _RunConsoleAppBar(
        scriptName: widget.scriptName,
        displayName: _displayName,
        runStartTime: _runStartTime,
        onRerun: _rerun,
      ),
      body: _RunConsoleTerminalPane(
        terminalKey: _terminalKey,
        scriptName: widget.scriptName,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class _RunConsoleAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String scriptName;
  final String displayName;
  final DateTime? runStartTime;
  final Future<void> Function() onRerun;

  const _RunConsoleAppBar({
    required this.scriptName,
    required this.displayName,
    required this.runStartTime,
    required this.onRerun,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentScriptName = context.select<ExecutionProvider, String?>(
      (p) => p.currentScriptName,
    );
    final providerIsRunning = context.select<ExecutionProvider, bool>(
      (p) => p.isRunning,
    );
    final waiting = context.select<ExecutionProvider, bool>(
      (p) => p.waitingForInput,
    );
    final status = context.select<ExecutionProvider, ExecutionStatus>(
      (p) => p.state.status,
    );
    final isRunning =
        providerIsRunning && currentScriptName == scriptName;

    final statusColor = isRunning
        ? (isDark ? Colors.greenAccent : Colors.green)
        : (status == ExecutionStatus.error
            ? colors.error
            : status == ExecutionStatus.timeout
                ? Colors.orange
                : colors.onSurfaceVariant);
    final statusText = isRunning
        ? (waiting ? '等待输入' : '运行中')
        : (status == ExecutionStatus.error
            ? '错误'
            : status == ExecutionStatus.timeout
                ? '超时'
                : '已结束');
    final appBarBg = isDark ? const Color(0xFF161B22) : colors.surface;

    return AppBar(
      backgroundColor: appBarBg,
      foregroundColor: isDark ? Colors.white : colors.onSurface,
      elevation: 0,
      titleSpacing: 0,
      title: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
              boxShadow: isRunning
                  ? [
                      BoxShadow(
                        color: statusColor.withValues(alpha: 0.5),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              displayName,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : colors.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: isRunning
                  ? _RunningTimer(
                      key: ValueKey(statusText),
                      startTime: runStartTime ?? DateTime.now(),
                      label: waiting ? '等待输入' : '运行中',
                      color: statusColor,
                    )
                  : Text(
                      statusText,
                      key: ValueKey(statusText),
                      style: TextStyle(
                        fontSize: 11,
                        color: statusColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      actions: [
        if (isRunning)
          IconButton(
            icon: Icon(Icons.stop_rounded, color: colors.error, size: 22),
            onPressed: () => context.read<ExecutionProvider>().stopExecution(),
            tooltip: '停止',
          )
        else
          IconButton(
            icon: Icon(Icons.replay_rounded,
                color: isDark ? Colors.greenAccent : Colors.green, size: 22),
            onPressed: onRerun,
            tooltip: '重新运行',
          ),
      ],
    );
  }
}

class _RunConsoleTerminalPane extends StatelessWidget {
  final GlobalKey<TerminalViewState> terminalKey;
  final String scriptName;

  const _RunConsoleTerminalPane({
    required this.terminalKey,
    required this.scriptName,
  });

  @override
  Widget build(BuildContext context) {
    context.select<ExecutionProvider, int>((p) => p.logVersion);
    final logs = context.select<ExecutionProvider, List<LogEntry>>(
      (p) => p.logs,
    );
    final currentScriptName = context.select<ExecutionProvider, String?>(
      (p) => p.currentScriptName,
    );
    final providerIsRunning = context.select<ExecutionProvider, bool>(
      (p) => p.isRunning,
    );
    final waiting = context.select<ExecutionProvider, bool>(
      (p) => p.waitingForInput,
    );
    final isRunning =
        providerIsRunning && currentScriptName == scriptName;

    return TerminalView(
      key: terminalKey,
      logs: logs,
      isRunning: isRunning,
      waitingForInput: waiting,
      onStdin: (input) => context.read<ExecutionProvider>().sendStdin(input),
      onClear: logs.isEmpty
          ? null
          : () => context.read<ExecutionProvider>().clearLogs(),
      emptyMessage: isRunning ? '等待输出...' : '暂无输出',
      showLineNumberToggle: false,
    );
  }
}

/// A real-time running timer widget that updates every second.
class _RunningTimer extends StatefulWidget {
  final DateTime startTime;
  final String label;
  final Color color;
  const _RunningTimer({
    super.key,
    required this.startTime,
    required this.label,
    required this.color,
  });

  @override
  State<_RunningTimer> createState() => _RunningTimerState();
}

class _RunningTimerState extends State<_RunningTimer> {
  late DateTime _startTime;
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTime = widget.startTime;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed = DateTime.now().difference(_startTime);
      });
    });
  }

  @override
  void didUpdateWidget(covariant _RunningTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startTime != widget.startTime) {
      _startTime = widget.startTime;
    }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h}h${m.toString().padLeft(2, '0')}m';
    }
    if (m > 0) {
      return '${m}m${s.toString().padLeft(2, '0')}s';
    }
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      '${widget.label} ${_formatDuration(_elapsed)}',
      style: TextStyle(
          fontSize: 11, color: widget.color, fontWeight: FontWeight.w500),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
