import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/mcp_policy_service.dart';
import '../../application/mcp_server_controller.dart';
import '../../domain/mcp_permission.dart';
import '../../infrastructure/mcp_audit_log.dart';
import '../../infrastructure/mcp_session_store.dart';
import '../../../../l10n/app_localizations.dart';

/// AI / MCP 服务设置页（计划 §11）。
///
/// 服务开关、状态、端口、连接方式、可选配对令牌、权限、连接数、
/// 最近工具调用与审计日志。
class McpSettingsPage extends ConsumerStatefulWidget {
  const McpSettingsPage({super.key});

  @override
  ConsumerState<McpSettingsPage> createState() => _McpSettingsPageState();
}

class _McpSettingsPageState extends ConsumerState<McpSettingsPage> {
  final _portController = TextEditingController();
  final List<Listenable> _watchedServices = [];
  bool _portInitialized = false;
  bool _toggling = false;
  List<String> _lanUrls = const [];
  bool _lanRefreshScheduled = false;

  @override
  void initState() {
    super.initState();
    final services = [
      ref.read(mcpAuditLogProvider),
      ref.read(mcpSessionStoreProvider),
      ref.read(mcpConfirmationServiceProvider),
    ];
    for (final service in services) {
      service.addListener(_onServiceChanged);
      _watchedServices.add(service);
    }
  }

  @override
  void dispose() {
    for (final service in _watchedServices) {
      service.removeListener(_onServiceChanged);
    }
    _portController.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshLanUrls() async {
    try {
      final urls = await ref.read(mcpServerControllerProvider.notifier).lanUrls;
      if (mounted) setState(() => _lanUrls = urls);
    } finally {
      _lanRefreshScheduled = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mcpServerControllerProvider);
    final sessions = ref.watch(mcpSessionStoreProvider);
    if (!_portInitialized) {
      _portController.text = state.port.toString();
      _portInitialized = true;
    }
    if (state.status == McpServerStatus.running &&
        _lanUrls.isEmpty &&
        !_lanRefreshScheduled) {
      _lanRefreshScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshLanUrls());
    }

    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.mcpPageTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _buildServiceCard(context, state),
          _buildTokenCard(context),
          _buildPermissionCard(context),
          _buildSessionsCard(context, sessions),
          _buildAuditCard(context),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── 服务状态 ──

  Widget _buildServiceCard(BuildContext context, McpServerState state) {
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final running = state.status == McpServerStatus.running;
    final statusLabel = switch (state.status) {
      McpServerStatus.stopped => l10n.mcpStatusStopped,
      McpServerStatus.starting => l10n.mcpStatusStarting,
      McpServerStatus.running => l10n.mcpStatusRunning,
      McpServerStatus.error => l10n.mcpStatusError,
    };
    final statusColor = switch (state.status) {
      McpServerStatus.running => Colors.green,
      McpServerStatus.starting => Colors.orange,
      McpServerStatus.error => colors.error,
      _ => colors.outline,
    };
    final noticeText = _noticeText(l10n, state);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.smart_toy_outlined, size: 20, color: colors.primary),
                const SizedBox(width: 10),
                Text(l10n.mcpService,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.primary)),
                const Spacer(),
                if (_toggling)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Switch(
                    value: running,
                    onChanged: (_) => _toggleService(),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.circle, size: 10, color: statusColor),
                const SizedBox(width: 6),
                Text(statusLabel),
                if (noticeText != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      noticeText,
                      style: TextStyle(fontSize: 12, color: colors.error),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
            if (running) ...[
              const Divider(height: 24),
              _buildCopyRow(
                  context, 'MCP URL', 'http://127.0.0.1:${state.port}/mcp'),
              for (final url in _lanUrls)
                _buildCopyRow(context, l10n.mcpLanUrl, url),
              Wrap(children: [
                TextButton.icon(
                  icon: const Icon(Icons.picture_in_picture_alt),
                  label: Text(l10n.mcpShowKeepAliveOverlay),
                  onPressed: () => ref
                      .read(mcpServerControllerProvider.notifier)
                      .refreshKeepAlive(
                          requestPermission: true, showOverlay: true),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.visibility_off_outlined),
                  label: Text(l10n.mcpHideOverlay),
                  onPressed: () => ref
                      .read(mcpServerControllerProvider.notifier)
                      .hideOverlay(),
                )
              ]),
              const SizedBox(height: 4),
              Text(
                state.requireToken
                    ? l10n.mcpConnectionTokenHint
                    : l10n.mcpConnectionNoTokenHint,
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
            ],
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _portController,
                    keyboardType: TextInputType.number,
                    enabled: !running,
                    decoration: InputDecoration(
                      labelText: l10n.mcpPortRange,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: running ? null : () => _savePort(),
                  child: Text(l10n.save),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.mcpRequirePairingToken,
                  style: const TextStyle(fontSize: 13)),
              subtitle: Text(l10n.mcpTokenDisabledWarning,
                  style: TextStyle(fontSize: 11)),
              value: state.requireToken,
              onChanged: (value) => ref
                  .read(mcpServerControllerProvider.notifier)
                  .setRequireToken(value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCopyRow(BuildContext context, String label, String value) {
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(label,
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            tooltip: l10n.copy,
            onPressed: () => _copyToClipboard(value),
          ),
        ],
      ),
    );
  }

  // ── 配对令牌 ──

  Widget _buildTokenCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final tokens = ref.watch(mcpTokenStoreProvider);
    final controller = ref.read(mcpServerControllerProvider.notifier);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.key_outlined, size: 20, color: colors.primary),
                const SizedBox(width: 10),
                Text(l10n.mcpPairingToken,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.primary)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              tokens.hasToken
                  ? l10n.mcpCurrentToken(
                      tokens.tokenHint ?? l10n.mcpTokenGenerated)
                  : l10n.mcpNoTokenYet,
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => _regenerateToken(controller),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(l10n.mcpRegenerate),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.mcpRegenerateTokenHint,
                    style:
                        TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── 权限 ──

  Widget _buildPermissionCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final policy = ref.watch(mcpPolicyProvider);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.admin_panel_settings_outlined,
                    size: 20, color: colors.primary),
                const SizedBox(width: 10),
                Text(l10n.mcpToolPermissions,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.primary)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.mcpToolPermissionsHint,
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
            for (final permission in McpPermission.values)
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(_permissionTitle(l10n, permission),
                    style: const TextStyle(fontSize: 13)),
                subtitle: Text(permission.id,
                    style: TextStyle(
                        fontSize: 11, color: colors.onSurfaceVariant)),
                value: policy.isPermissionEnabled(permission),
                onChanged: (value) =>
                    _togglePermission(policy, permission, value),
              ),
          ],
        ),
      ),
    );
  }

  // ── 连接信息 ──

  Widget _buildSessionsCard(BuildContext context, McpSessionStore sessions) {
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final list = sessions.sessions;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.devices_outlined, size: 20, color: colors.primary),
                const SizedBox(width: 10),
                Text(l10n.mcpCurrentConnections,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.primary)),
                const Spacer(),
                Text(l10n.mcpSessionsCount(sessions.activeCount)),
              ],
            ),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.mcpNoConnections,
                  style:
                      TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                ),
              )
            else
              for (final session in list)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.laptop, size: 18),
                  title: Text(session.clientLabel,
                      style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                    l10n.mcpSessionSummary(
                        session.id.substring(0, 8), session.protocolVersion),
                    style:
                        TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.link_off, size: 18),
                    tooltip: l10n.mcpDisconnect,
                    onPressed: () => sessions.terminate(session.id),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  // ── 审计日志 ──

  Widget _buildAuditCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final audit = ref.watch(mcpAuditLogProvider);
    final entries = audit.entries.reversed.take(30).toList();
    final toolCalls =
        entries.where((entry) => entry.kind == McpAuditKind.toolCall).length;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long_outlined,
                    size: 20, color: colors.primary),
                const SizedBox(width: 10),
                Text(l10n.mcpAuditLog,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.primary)),
                const Spacer(),
                Text(
                  l10n.mcpRecentToolCalls(toolCalls),
                  style:
                      TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  tooltip: l10n.mcpClearAuditLog,
                  onPressed: entries.isEmpty ? null : () => audit.clear(),
                ),
              ],
            ),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.mcpNoAuditRecords,
                  style:
                      TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                ),
              )
            else
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatTime(entry.timestamp),
                        style: TextStyle(
                            fontSize: 10,
                            color: colors.onSurfaceVariant,
                            fontFamily: 'monospace'),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        _auditIcon(entry),
                        size: 13,
                        color: entry.status == 'ok'
                            ? colors.primary
                            : colors.error,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _auditText(l10n, entry),
                          style: const TextStyle(fontSize: 11),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  IconData _auditIcon(McpAuditEntry entry) {
    return switch (entry.kind) {
      McpAuditKind.toolCall => Icons.build_outlined,
      McpAuditKind.connect => Icons.login,
      McpAuditKind.disconnect => Icons.logout,
      McpAuditKind.server => Icons.dns_outlined,
    };
  }

  String? _noticeText(AppLocalizations l10n, McpServerState state) {
    final detail = state.noticeDetail?.toString() ?? '';
    return switch (state.notice) {
      null => null,
      McpServerNotice.startFailed => l10n.mcpStartFailed(detail),
      McpServerNotice.overlayPermissionRequired =>
        l10n.mcpOverlayPermissionRequired,
      McpServerNotice.keepAliveUnavailable =>
        l10n.mcpKeepAliveUnavailable(detail),
      McpServerNotice.hideOverlayFailed => l10n.mcpHideOverlayFailed(detail),
    };
  }

  String _permissionTitle(AppLocalizations l10n, McpPermission permission) {
    return switch (permission) {
      McpPermission.readScripts => l10n.mcpPermissionReadScripts,
      McpPermission.writeScripts => l10n.mcpPermissionWriteScripts,
      McpPermission.readProjects => l10n.mcpPermissionReadProjects,
      McpPermission.writeProjects => l10n.mcpPermissionWriteProjects,
      McpPermission.readNetwork => l10n.mcpPermissionReadNetwork,
      McpPermission.readPackages => l10n.mcpPermissionReadPackages,
      McpPermission.installPackages => l10n.mcpPermissionInstallPackages,
      McpPermission.runScripts => l10n.mcpPermissionRunScripts,
      McpPermission.writeFilesystem => l10n.mcpPermissionWriteFilesystem,
      McpPermission.deleteFilesystem => l10n.mcpPermissionDeleteFilesystem,
      McpPermission.readFilesystem => l10n.mcpPermissionReadFilesystem,
    };
  }

  String _auditText(AppLocalizations l10n, McpAuditEntry entry) {
    final client = entry.clientLabel ?? '';
    switch (entry.kind) {
      case McpAuditKind.toolCall:
        if (entry.status == 'ok') {
          return l10n.mcpAuditToolCall(
              client, entry.tool ?? 'unknown', entry.durationMs ?? 0);
        }
        return l10n.mcpAuditToolCallFailed(
            client, entry.tool ?? 'unknown', entry.errorCode ?? 'UNKNOWN');
      case McpAuditKind.connect:
        return l10n.mcpAuditConnect(client);
      case McpAuditKind.disconnect:
        return l10n.mcpAuditDisconnect(client);
      case McpAuditKind.server:
        return l10n.mcpAuditServer(entry.status, entry.argsSummary ?? '');
    }
  }

  String _formatTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }

  // ── 交互 ──

  Future<void> _toggleService() async {
    setState(() => _toggling = true);
    try {
      final controller = ref.read(mcpServerControllerProvider.notifier);
      final running = ref.read(mcpServerControllerProvider).status ==
          McpServerStatus.running;
      await controller.setEnabled(!running);
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<void> _savePort() async {
    final controller = ref.read(mcpServerControllerProvider.notifier);
    final port = int.tryParse(_portController.text.trim());
    final ok = await controller.setPort(port ?? 0);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? l10n.mcpPortSavedNextStart : l10n.mcpInvalidPort),
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _togglePermission(
    McpPolicyService policy,
    McpPermission permission,
    bool value,
  ) async {
    await policy.setPermissionEnabled(permission, value);
    if (mounted) setState(() {});
  }

  Future<void> _regenerateToken(McpServerController controller) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.mcpRegenerateTokenTitle),
        content: Text(l10n.mcpRegenerateTokenConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.mcpGenerate),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final token = await controller.regenerateToken();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.mcpNewTokenTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              token,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _copyToClipboard(token),
              icon: const Icon(Icons.copy, size: 16),
              label: Text(l10n.mcpCopyToken),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(String value) {
    Clipboard.setData(ClipboardData(text: value));
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(l10n.mcpCopiedToClipboard),
      duration: Duration(seconds: 1),
    ));
  }
}
