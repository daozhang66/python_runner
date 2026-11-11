import '../../../widgets/app_dialogs.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../providers/execution_provider.dart';
import '../../ssh/application/terminal/terminal_locale.dart';
import '../application/mcp_confirmation_service.dart';
import '../application/mcp_server_controller.dart';
import 'ai_chat_sheet.dart';

/// Global MCP surface, wrapped around the whole app (above the navigator):
///
/// * approval dialogs for operations that ask the person first;
/// * a small round button, shown while the MCP service runs, that opens the
///   AI chat (what the AI said, what waits for the person, the pause switch).
///   A badge counts unread messages, or shows "!" when a terminal or script
///   waits for the person;
/// * when the person comes back to the app while something waits for them
///   (a password prompt, a script's input), the app opens that terminal or
///   console right away.
///
/// Dialogs and pages are shown through [navigatorKey], because this widget
/// sits above the navigator and has no navigator of its own context.
class McpConfirmationGate extends ConsumerStatefulWidget {
  const McpConfirmationGate({
    super.key,
    required this.child,
    this.navigatorKey,
  });

  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  ConsumerState<McpConfirmationGate> createState() =>
      _McpConfirmationGateState();
}

class _McpConfirmationGateState extends ConsumerState<McpConfirmationGate>
    with WidgetsBindingObserver {
  bool _busy = false;
  McpConfirmationService? _confirmations;
  ExecutionProvider? _execution;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final service = ref.read(mcpConfirmationServiceProvider);
    service.addListener(_onChanged);
    _confirmations = service;
    try {
      final execution = ref.read(mcpExecutionOwnerProvider);
      execution.addListener(_onExecution);
      _execution = execution;
    } catch (_) {
      // No app execution attached (widget tests): nothing to watch.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _execution?.removeListener(_onExecution);
    _confirmations?.removeListener(_onChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _openPending();
  }

  /// A script started waiting for input (or stopped waiting).
  void _onExecution() {
    final execution = _execution;
    if (execution == null || !mounted) return;
    final terminal = ref.read(mcpTerminalServiceProvider);
    final name = execution.currentScriptName;
    final serviceRunning =
        ref.read(mcpServerControllerProvider).status == McpServerStatus.running;
    if (serviceRunning &&
        execution.isRunning &&
        execution.waitingForInput &&
        name != null) {
      terminal.raiseAttention(
        'script',
        name,
        tr(
          '脚本「$name」在等你输入，点开控制台输入',
          'Script "$name" is waiting for your input; open its console',
        ),
      );
    } else {
      terminal.clearAttentionKind('script');
    }
  }

  /// Takes the person to the first thing that waits for them, once.
  void _openPending() {
    final navigator = widget.navigatorKey?.currentState;
    if (navigator == null) return;
    final terminal = ref.read(mcpTerminalServiceProvider);
    for (final item in terminal.attention) {
      if (item.opened) continue;
      item.opened = true;
      navigator.push(routeForAttention(item));
      return;
    }
  }

  void _onChanged() {
    if (_busy || !mounted) return;
    unawaited(_drain());
  }

  /// Shows the waiting approvals one dialog at a time.
  Future<void> _drain() async {
    _busy = true;
    try {
      while (mounted) {
        final service = ref.read(mcpConfirmationServiceProvider);
        if (service.pending.isEmpty) break;
        await _showConfirmation(service);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _showConfirmation(McpConfirmationService service) async {
    final item = service.pending.first;
    final dialogContext = widget.navigatorKey?.currentContext;
    if (dialogContext == null) {
      // No navigator to show it in: refuse rather than wait for the timeout.
      service.resolve(item.id, McpConfirmationDecision.deny);
      return;
    }
    McpConfirmationDecision? decision;
    try {
      decision = await showDialog<McpConfirmationDecision>(
        context: dialogContext,
        barrierDismissible: false,
        builder: (_) => _McpConfirmationDialog(item: item),
      );
    } catch (_) {
      decision = McpConfirmationDecision.deny;
    }
    // 对话框可能因超时被服务侧关闭（future 已完成）；此处只需兑底。
    if (!item.isResolved && decision != null) {
      service.resolve(item.id, decision);
    }
  }

  void _openChat() {
    final target = widget.navigatorKey?.currentContext;
    if (target == null) return;
    unawaited(showAiChatSheet(target));
  }

  @override
  Widget build(BuildContext context) {
    final running = ref.watch(mcpServerControllerProvider
        .select((state) => state.status == McpServerStatus.running));
    final unread = ref
        .watch(mcpTerminalServiceProvider.select((s) => s.unreadCount));
    final waiting = ref
        .watch(mcpTerminalServiceProvider.select((s) => s.attention.length));
    final paused =
        ref.watch(mcpTerminalServiceProvider.select((s) => s.paused));
    final scheme = Theme.of(context).colorScheme;
    final color = waiting > 0
        ? scheme.tertiaryContainer
        : paused
            ? scheme.errorContainer
            : scheme.primaryContainer;
    final onColor = waiting > 0
        ? scheme.onTertiaryContainer
        : paused
            ? scheme.onErrorContainer
            : scheme.onPrimaryContainer;
    // The child stays at the same place in the tree whether or not the button
    // is shown, so the app's navigation is never rebuilt by it.
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (running)
          Positioned(
            right: 10,
            bottom: MediaQuery.of(context).padding.bottom + 110,
            child: Material(
              color: color,
              elevation: 3,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _openChat,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: Badge(
                      isLabelVisible: waiting > 0 || unread > 0,
                      label: Text(waiting > 0 ? '!' : '$unread'),
                      child: Icon(
                        paused ? Icons.pause : Icons.smart_toy_outlined,
                        color: onColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _McpConfirmationDialog extends StatefulWidget {
  const _McpConfirmationDialog({required this.item});

  final McpPendingConfirmation item;

  @override
  State<_McpConfirmationDialog> createState() => _McpConfirmationDialogState();
}

class _McpConfirmationDialogState extends State<_McpConfirmationDialog> {
  int _remainingSeconds = 0;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.item.timeoutAt
        .difference(DateTime.now())
        .inSeconds
        .clamp(0, 9999);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remainingSeconds = widget.item.timeoutAt
            .difference(DateTime.now())
            .inSeconds
            .clamp(0, 9999);
      });
    });
    // 服务侧超时自动拒绝时关闭对话框。
    widget.item.future.then((_) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return AppAlertDialog(
      title: Text(l10n.mcpConfirmationTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.smart_toy, size: 18, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.item.toolName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              widget.item.summary,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.mcpConfirmationClient(widget.item.clientLabel),
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            _remainingSeconds > 0
                ? l10n.mcpConfirmationAutoDeny(_remainingSeconds)
                : l10n.mcpConfirmationAutoDenySoon,
            style: TextStyle(fontSize: 12, color: colors.error),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(McpConfirmationDecision.deny),
          child: Text(l10n.mcpDeny),
        ),
        if (!widget.item.singleUse)
          OutlinedButton(
            onPressed: () => Navigator.of(context)
                .pop(McpConfirmationDecision.allowSession),
            child: Text(l10n.mcpAllowSession),
          ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(McpConfirmationDecision.allow),
          child: Text(l10n.mcpAllow),
        ),
      ],
    );
  }
}
