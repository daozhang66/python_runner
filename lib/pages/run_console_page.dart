import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/log_entry.dart';
import '../providers/execution_provider.dart';
import '../models/execution_state.dart';
import '../providers/script_provider.dart';
import '../ui/app_badges.dart';
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
      if (!mounted) return;
      setState(() {
        _captureStartTime();
      });
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
    final isRunning = providerIsRunning && currentScriptName == scriptName;

    final statusText = isRunning
        ? (waiting ? '等待输入' : '运行中')
        : (status == ExecutionStatus.error
            ? '错误'
            : status == ExecutionStatus.timeout
                ? '超时'
                : '已结束');
    final appBarBg = isDark ? const Color(0xFF161B22) : colors.surface;
    final statusColor = _statusColor(context, isRunning, waiting, status);

    return AppBar(
      backgroundColor: appBarBg,
      foregroundColor: isDark ? Colors.white : colors.onSurface,
      elevation: 0,
      titleSpacing: 0,
      title: Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Container(
              key: ValueKey('$statusText-$isRunning'),
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
          _buildRunStatusBadge(
            context,
            isRunning: isRunning,
            waiting: waiting,
            status: status,
            statusText: statusText,
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

  Color _statusColor(
    BuildContext context,
    bool isRunning,
    bool waiting,
    ExecutionStatus status,
  ) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isRunning) {
      return waiting
          ? Colors.amber.shade700
          : (isDark ? Colors.greenAccent : Colors.green);
    }
    return switch (status) {
      ExecutionStatus.error => colors.error,
      ExecutionStatus.timeout => Colors.orange,
      _ => colors.onSurfaceVariant,
    };
  }

  Widget _buildRunStatusBadge(
    BuildContext context, {
    required bool isRunning,
    required bool waiting,
    required ExecutionStatus status,
    required String statusText,
  }) {
    final tone = isRunning
        ? (waiting ? AppBadgeTone.warning : AppBadgeTone.success)
        : switch (status) {
            ExecutionStatus.error => AppBadgeTone.error,
            ExecutionStatus.timeout => AppBadgeTone.warning,
            _ => AppBadgeTone.neutral,
          };

    return AppStatusBadge(
      label: statusText,
      tone: tone,
      icon: isRunning
          ? (waiting ? Icons.keyboard_outlined : Icons.play_circle_outline)
          : Icons.circle_outlined,
      fontSize: 11,
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
    final logVersion = context.select<ExecutionProvider, int>(
      (p) => p.logVersion,
    );
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
    final isRunning = providerIsRunning && currentScriptName == scriptName;

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
      logVersion: logVersion,
    );
  }
}
