import '../../../widgets/app_dialogs.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/mcp_confirmation_service.dart';
import '../application/mcp_server_controller.dart';
import '../../../l10n/app_localizations.dart';

/// 全局 MCP 确认入口：包裹主页面，写操作工具调用时弹出确认框（计划 §8.3）。
///
/// 确认框展示工具名、参数摘要、发起客户端与超时提示；
/// 不展示完整密钥、Cookie 或超长代码正文（摘要由工具层生成时保证）。
class McpConfirmationGate extends ConsumerStatefulWidget {
  const McpConfirmationGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<McpConfirmationGate> createState() =>
      _McpConfirmationGateState();
}

class _McpConfirmationGateState extends ConsumerState<McpConfirmationGate> {
  bool _dialogShowing = false;
  McpConfirmationService? _watchedService;

  @override
  void initState() {
    super.initState();
    final service = ref.read(mcpConfirmationServiceProvider);
    _watchedService = service;
    service.addListener(_onPendingChanged);
  }

  @override
  void dispose() {
    _watchedService?.removeListener(_onPendingChanged);
    super.dispose();
  }

  void _onPendingChanged() {
    final service = ref.read(mcpConfirmationServiceProvider);
    if (service.pending.isEmpty || _dialogShowing) return;
    if (!mounted) return;
    _dialogShowing = true;
    _showNext(service);
  }

  Future<void> _showNext(McpConfirmationService service) async {
    while (mounted && service.pending.isNotEmpty) {
      final item = service.pending.first;
      final decision = await showDialog<McpConfirmationDecision>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => _McpConfirmationDialog(item: item),
      );
      // 对话框可能因超时被服务侧关闭（future 已完成）；此处只需兜底。
      if (!item.isResolved && decision != null) {
        service.resolve(item.id, decision);
      }
    }
    _dialogShowing = false;
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
        OutlinedButton(
          onPressed: () =>
              Navigator.of(context).pop(McpConfirmationDecision.allowSession),
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
