import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart';
import '../../../../models/log_entry.dart';
import '../../../../models/script_group.dart';
import '../../../../providers/execution_provider.dart';
import '../../../../providers/console_display_preferences_provider.dart';
import '../../../../models/execution_state.dart';
import 'package:python_runner/features/scripts/application/script_workspace_controller.dart';
import '../../../../services/native_bridge.dart';
import '../../../../ui/app_badges.dart';
import '../../../../ui/app_design_tokens.dart';
import '../widgets/terminal_view.dart';
import '../../../../l10n/app_localizations.dart';

class RunConsolePage extends ConsumerStatefulWidget {
  final String scriptName;
  final ScriptGroup? projectGroup;

  const RunConsolePage({
    super.key,
    required this.scriptName,
    this.projectGroup,
  });

  @override
  ConsumerState<RunConsolePage> createState() => _RunConsolePageState();
}

class _RunConsolePageState extends ConsumerState<RunConsolePage>
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
    final activeRecord =
        exec.historyRecordForScriptExecution(widget.scriptName) ??
            exec.latestHistoryRecordForScript(widget.scriptName);
    _runStartTime = activeRecord?.startTime;
  }

  @override
  void didChangeMetrics() {
    // Keyboard open/close: scroll to bottom
    _terminalKey.currentState?.forceAutoScroll();
  }

  Future<void> _rerun() async {
    try {
      final exec = context.read<ExecutionProvider>();
      final scriptWorkspace =
          ref.read(scriptWorkspaceControllerProvider.notifier);
      exec.clearLogs();
      final projectGroup = widget.projectGroup;
      if (projectGroup != null && projectGroup.isProject) {
        await exec.executeScriptProject(projectGroup);
        if (exec.isRunning) {
          await scriptWorkspace.markProjectGroupUsed(projectGroup);
        }
      } else {
        await scriptWorkspace.incrementRunCount(widget.scriptName);
        await exec.executeScript(widget.scriptName);
      }
      if (!mounted) return;
      setState(() {
        _captureStartTime();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context)!.error}: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _exportLogs(String content) async {
    if (content.isEmpty) return;
    try {
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final path = await NativeBridge().exportLog(
        content,
        fileName: '${_displayName}_$timestamp.log',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            path.isEmpty
                ? AppLocalizations.of(context)!.logsExported
                : AppLocalizations.of(context)!.logsExportedTo(path),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${AppLocalizations.of(context)!.error}: $error')),
      );
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppThemeColors.terminalCanvas(isDark),
      appBar: _RunConsoleAppBar(
        scriptName: widget.scriptName,
        displayName: _displayName,
        runStartTime: _runStartTime,
        onRerun: _rerun,
      ),
      body: _RunConsoleTerminalPane(
        terminalKey: _terminalKey,
        scriptName: widget.scriptName,
        onExport: _exportLogs,
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
    final l10n = AppLocalizations.of(context)!;
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
    final providerStatus = context.select<ExecutionProvider, ExecutionStatus>(
      (p) => p.state.status,
    );
    final executionProvider = context.read<ExecutionProvider>();
    final selectedRecord = executionProvider.historyRecordForScriptExecution(
          scriptName,
        ) ??
        executionProvider.latestHistoryRecordForScript(scriptName);
    final isRunning = providerIsRunning && currentScriptName == scriptName;
    final status = isRunning
        ? providerStatus
        : (selectedRecord?.status ?? ExecutionStatus.idle);
    final selectedWaiting = isRunning ? waiting : false;

    final statusText = isRunning
        ? (selectedWaiting ? l10n.waitingForInputStatus : l10n.running)
        : (status == ExecutionStatus.error
            ? l10n.error
            : status == ExecutionStatus.timeout
                ? l10n.timeout
                : status == ExecutionStatus.stopped
                    ? l10n.stopped
                    : status == ExecutionStatus.completed
                        ? l10n.finished
                        : l10n.noRun);
    final appBarBg =
        isDark ? AppThemeColors.terminalDarkSurface : colors.surface;
    final statusColor =
        _statusColor(context, isRunning, selectedWaiting, status);

    return AppBar(
      backgroundColor: appBarBg,
      foregroundColor: AppThemeColors.terminalText(colors, isDark),
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
                fontSize: AppTextSize.toolbarTitle,
                fontWeight: FontWeight.w500,
                color: AppThemeColors.terminalText(colors, isDark),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _buildRunStatusBadge(
            context,
            isRunning: isRunning,
            waiting: selectedWaiting,
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
            tooltip: l10n.stop,
          )
        else
          IconButton(
            icon: Icon(Icons.replay_rounded, color: colors.tertiary, size: 22),
            onPressed: onRerun,
            tooltip: l10n.runAgain,
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
    if (isRunning) {
      return colors.tertiary;
    }
    return switch (status) {
      ExecutionStatus.error => colors.error,
      ExecutionStatus.timeout => colors.tertiary,
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
            ExecutionStatus.stopped => AppBadgeTone.neutral,
            _ => AppBadgeTone.neutral,
          };

    return AppStatusBadge(
      label: statusText,
      tone: tone,
      icon: isRunning
          ? (waiting ? Icons.keyboard_outlined : Icons.play_circle_outline)
          : Icons.circle_outlined,
      fontSize: AppTextSize.label,
    );
  }
}

class _RunConsoleTerminalPane extends ConsumerWidget {
  final GlobalKey<TerminalViewState> terminalKey;
  final String scriptName;
  final Future<void> Function(String content) onExport;

  const _RunConsoleTerminalPane({
    required this.terminalKey,
    required this.scriptName,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayPreferences = ref.watch(consoleDisplayPreferencesProvider);
    return Selector<ExecutionProvider, _TerminalSnapshot>(
      selector: (context, execution) {
        final isRunning =
            execution.isRunning && execution.currentScriptName == scriptName;
        final selectedRecord = isRunning
            ? execution.historyRecordForScriptExecution(scriptName) ??
                execution.latestHistoryRecordForScript(scriptName)
            : execution.latestHistoryRecordForScript(scriptName);
        return _TerminalSnapshot(
          logs: isRunning
              ? execution.logs
              : (selectedRecord?.logs ?? const <LogEntry>[]),
          isRunning: isRunning,
          waitingForInput: isRunning && execution.waitingForInput,
          logVersion: isRunning
              ? execution.logVersion
              : (selectedRecord?.logs.length ?? 0),
        );
      },
      builder: (context, snapshot, _) {
        return RepaintBoundary(
          child: TerminalView(
            key: terminalKey,
            logs: snapshot.logs,
            isRunning: snapshot.isRunning,
            waitingForInput: snapshot.waitingForInput,
            onStdin: (input) =>
                context.read<ExecutionProvider>().sendStdin(input),
            onClear: snapshot.isRunning
                ? () => context.read<ExecutionProvider>().clearLogs()
                : null,
            onExport: onExport,
            autoFollowInitiallyEnabled: displayPreferences.autoFollowOutput,
            onAutoFollowPreferenceChanged: ref
                .read(consoleDisplayPreferencesProvider.notifier)
                .setAutoFollowOutput,
            emptyMessage: snapshot.isRunning
                ? AppLocalizations.of(context)!.waitingForOutput
                : AppLocalizations.of(context)!.noOutput,
            showLineNumberToggle: false,
            logVersion: snapshot.logVersion,
          ),
        );
      },
    );
  }
}

class _TerminalSnapshot {
  const _TerminalSnapshot({
    required this.logs,
    required this.isRunning,
    required this.waitingForInput,
    required this.logVersion,
  });

  final List<LogEntry> logs;
  final bool isRunning;
  final bool waitingForInput;
  final int logVersion;

  @override
  bool operator ==(Object other) {
    return other is _TerminalSnapshot &&
        identical(other.logs, logs) &&
        other.isRunning == isRunning &&
        other.waitingForInput == waitingForInput &&
        other.logVersion == logVersion;
  }

  @override
  int get hashCode => Object.hash(logs, isRunning, waitingForInput, logVersion);
}
