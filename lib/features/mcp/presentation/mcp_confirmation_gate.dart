import '../../../widgets/app_dialogs.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../ssh/presentation/ssh_text.dart';
import '../application/mcp_confirmation_service.dart';
import '../application/mcp_server_controller.dart';
import '../application/mcp_terminal_service.dart';

/// 全局 MCP 确认入口：包裹主页面，写操作工具调用时弹出确认框（计划 §8.3）。
///
/// 确认框展示工具名、参数摘要、发起客户端与超时提示；
/// 不展示完整密钥、Cookie 或超长代码正文（摘要由工具层生成时保证）。
///
/// The same gate also shows the notes an AI leaves for the person (with a
/// field to answer them).
class McpConfirmationGate extends ConsumerStatefulWidget {
  const McpConfirmationGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<McpConfirmationGate> createState() =>
      _McpConfirmationGateState();
}

class _McpConfirmationGateState extends ConsumerState<McpConfirmationGate> {
  bool _busy = false;
  McpConfirmationService? _confirmations;
  McpTerminalService? _terminal;

  @override
  void initState() {
    super.initState();
    _confirmations = ref.read(mcpConfirmationServiceProvider)
      ..addListener(_onChanged);
    _terminal = ref.read(mcpTerminalServiceProvider)..addListener(_onChanged);
  }

  @override
  void dispose() {
    _confirmations?.removeListener(_onChanged);
    _terminal?.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (_busy || !mounted) return;
    unawaited(_drain());
  }

  /// Shows what is waiting, one dialog at a time; approvals come first.
  Future<void> _drain() async {
    _busy = true;
    try {
      while (mounted) {
        final confirmations = ref.read(mcpConfirmationServiceProvider);
        final terminal = ref.read(mcpTerminalServiceProvider);
        if (confirmations.pending.isNotEmpty) {
          await _showConfirmation(confirmations);
        } else if (terminal.openMessages.isNotEmpty) {
          await _showMessage(terminal, terminal.openMessages.first);
        } else {
          break;
        }
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _showConfirmation(McpConfirmationService service) async {
    final item = service.pending.first;
    final decision = await showDialog<McpConfirmationDecision>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _McpConfirmationDialog(item: item),
    );
    // 对话框可能因超时被服务侧关闭（future 已完成）；此处只需兑底。
    if (!item.isResolved && decision != null) {
      service.resolve(item.id, decision);
    }
  }

  Future<void> _showMessage(
    McpTerminalService service,
    McpUserMessage message,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) =>
          _McpMessageDialog(service: service, message: message),
    );
    // Closed some other way: count it as dismissed so it is not shown again.
    if (message.isOpen) service.dismiss(message.id);
  }

  @override
  Widget build(BuildContext context) => widget.child;
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

/// A note from the AI with a field to answer it. Closes itself when the note
/// is answered or dismissed elsewhere (for example when the service stops).
class _McpMessageDialog extends StatefulWidget {
  const _McpMessageDialog({required this.service, required this.message});

  final McpTerminalService service;
  final McpUserMessage message;

  @override
  State<_McpMessageDialog> createState() => _McpMessageDialogState();
}

class _McpMessageDialogState extends State<_McpMessageDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_check);
  }

  @override
  void dispose() {
    widget.service.removeListener(_check);
    _controller.dispose();
    super.dispose();
  }

  void _check() {
    if (!widget.message.isOpen) _close();
  }

  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  void _reply() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.service.reply(widget.message.id, text);
    _close();
  }

  void _dismiss() {
    widget.service.dismiss(widget.message.id);
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final t = SshText.of(context);
    return AppAlertDialog(
      scrollable: true,
      title: Text(t('AI 的留言', 'Message from the AI')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(widget.message.text),
          const SizedBox(height: 8),
          Text(
            widget.message.clientLabel,
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            minLines: 1,
            maxLines: 5,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              labelText: t('回复', 'Reply'),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _dismiss,
          child: Text(t('忽略', 'Dismiss')),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) => FilledButton(
            onPressed: value.text.trim().isEmpty ? null : _reply,
            child: Text(t('回复', 'Reply')),
          ),
        ),
      ],
    );
  }
}
