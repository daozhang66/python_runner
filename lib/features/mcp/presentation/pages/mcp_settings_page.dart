import '../../../../widgets/app_dialogs.dart';
import '../../../../ui/app_materials.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../ui/app_settings_section.dart';
import '../../../ssh/application/log/log_record.dart';
import '../../../ssh/presentation/pages/terminal_logs_page.dart';
import '../../../ssh/presentation/ssh_text.dart';
import '../../application/mcp_policy_service.dart';
import '../../application/mcp_server_controller.dart';
import '../../domain/mcp_permission.dart';
import '../../infrastructure/mcp_session_store.dart';
import '../../infrastructure/mcp_token_store.dart';

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
  bool _savingToken = false;
  List<String> _lanUrls = const [];
  bool _lanRequested = false;

  @override
  void initState() {
    super.initState();
    for (final service in [
      ref.read(mcpAuditLogProvider),
      ref.read(mcpSessionStoreProvider),
      ref.read(mcpConfirmationServiceProvider),
    ]) {
      service.addListener(_onServiceChanged);
      _watchedServices.add(service);
    }
    unawaited(_loadToken());
  }

  Future<void> _loadToken() async {
    try {
      await ref.read(mcpTokenStoreProvider).initialize();
    } catch (_) {
      // The observable store exposes a retryable, non-sensitive error state.
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
    } catch (_) {
      // Loopback remains available if the platform cannot enumerate interfaces.
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mcpServerControllerProvider);
    final tokens = ref.watch(mcpTokenStoreProvider);
    final sessions = ref.watch(mcpSessionStoreProvider);
    if (!_portInitialized) {
      _portController.text = state.port.toString();
      _portInitialized = true;
    }
    if (state.status != McpServerStatus.running) {
      // Look the addresses up again the next time the service runs.
      _lanUrls = const [];
      _lanRequested = false;
    } else if (!_lanRequested) {
      _lanRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_refreshLanUrls());
      });
    }
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
          flexibleSpace: appGlassBarBackground(context),
          title: Text(l10n.mcpPageTitle)),
      body: LayoutBuilder(builder: (context, constraints) {
        final inset =
            ((constraints.maxWidth - 760) / 2).clamp(0.0, double.infinity);
        return ListView(
          padding: EdgeInsets.symmetric(horizontal: inset, vertical: 8),
          children: [
            _buildServiceSection(state),
            _buildTokenSection(tokens),
            _buildPermissionSection(),
            _buildSessionsSection(sessions),
            _buildAuditSection(),
            const SizedBox(height: 24),
          ],
        );
      }),
    );
  }

  Widget _section(IconData icon, String title, List<Widget> children) =>
      AppSettingsSection(
        framed: true,
        icon: icon,
        title: title,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: children,
      );

  Widget _buildServiceSection(McpServerState state) {
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final t = SshText.of(context);
    final controller = ref.read(mcpServerControllerProvider.notifier);
    final running = state.status == McpServerStatus.running;
    final busy = _toggling || state.status == McpServerStatus.starting;
    final localOnly = controller.localOnly;
    final restartNeeded = running && controller.boundLocalOnly != localOnly;
    final statusLabel = switch (state.status) {
      McpServerStatus.stopped => l10n.mcpStatusStopped,
      McpServerStatus.starting => l10n.mcpStatusStarting,
      McpServerStatus.running => l10n.mcpStatusRunning,
      McpServerStatus.error => l10n.mcpStatusError,
    };
    final notice = _noticeText(l10n, state);
    return _section(Icons.smart_toy_outlined, l10n.mcpService, [
      SwitchListTile(
        key: const ValueKey('mcp-service-switch'),
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.mcpService),
        subtitle: Text(statusLabel),
        value: running,
        onChanged: busy ? null : (_) => _toggleService(),
      ),
      if (busy) const LinearProgressIndicator(minHeight: 2),
      if (notice != null)
        Text(notice, style: TextStyle(color: colors.error, fontSize: 12)),
      if (running) ...[
        const SizedBox(height: 8),
        _buildCopyRow('MCP URL', 'http://127.0.0.1:${state.port}/mcp'),
        for (final url in _lanUrls) _buildCopyRow(l10n.mcpLanUrl, url),
        Wrap(spacing: 4, runSpacing: 4, children: [
          TextButton.icon(
            icon: const Icon(Icons.picture_in_picture_alt),
            label: Text(l10n.mcpShowKeepAliveOverlay),
            onPressed: () => ref
                .read(mcpServerControllerProvider.notifier)
                .refreshKeepAlive(requestPermission: true, showOverlay: true),
          ),
          TextButton.icon(
            icon: const Icon(Icons.visibility_off_outlined),
            label: Text(l10n.mcpHideOverlay),
            onPressed: () =>
                ref.read(mcpServerControllerProvider.notifier).hideOverlay(),
          ),
        ]),
        Text(
          state.requireToken
              ? l10n.mcpConnectionTokenHint
              : l10n.mcpConnectionNoTokenHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
            child: TextField(
          controller: _portController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          enabled: !running && !busy,
          decoration:
              InputDecoration(labelText: l10n.mcpPortRange, isDense: true),
        )),
        const SizedBox(width: 8),
        IconButton(
          onPressed: running || busy ? null : _savePort,
          tooltip: l10n.save,
          icon: const Icon(Icons.save_outlined),
        ),
      ]),
      const SizedBox(height: 8),
      SwitchListTile(
        key: const ValueKey('mcp-auth-switch'),
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.mcpRequirePairingToken),
        subtitle: Text(l10n.mcpTokenDisabledWarning),
        value: state.requireToken,
        onChanged: busy ? null : _setRequireToken,
      ),
      SwitchListTile(
        key: const ValueKey('mcp-local-only-switch'),
        contentPadding: EdgeInsets.zero,
        title: Text(t('仅本机访问', 'This device only')),
        subtitle: Text(restartNeeded
            ? t('已保存，重启 MCP 服务后生效', 'Saved. Restart the MCP service to apply it')
            : t(
                '开启后只监听本机地址，局域网里的其他设备连不上；关闭则允许局域网设备连接（现状）',
                'On: only this device can connect. Off: devices on the local network can connect too (current behaviour)',
              )),
        value: localOnly,
        onChanged: busy ? null : _setLocalOnly,
      ),
    ]);
  }

  Widget _buildCopyRow(String label, String value) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            SelectableText(value, style: const TextStyle(fontSize: 13)),
          ],
        )),
        IconButton(
          icon: const Icon(Icons.copy, size: 20),
          tooltip: l10n.copy,
          onPressed: () => _copyToClipboard(value),
        ),
      ]),
    );
  }

  Widget _buildTokenSection(McpTokenStore tokens) {
    final l10n = AppLocalizations.of(context)!;
    final ready = tokens.isInitialized && !_savingToken;
    return _section(Icons.key_outlined, l10n.mcpPairingToken, [
      if (tokens.token != null)
        SelectableText(
          tokens.token!,
          key: const ValueKey('mcp-token-value'),
          style: const TextStyle(fontSize: 14, height: 1.5),
        )
      else
        Text(tokens.loadFailed
            ? l10n.mcpTokenStorageError
            : !tokens.isInitialized
                ? l10n.loading
                : tokens.isLegacyToken
                    ? l10n.mcpLegacyTokenHint
                    : l10n.mcpNoTokenYet),
      if (tokens.loadFailed)
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _loadToken,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.retry),
            )),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 4, children: [
        FilledButton.tonalIcon(
          key: const ValueKey('mcp-regenerate-token'),
          onPressed: ready ? _regenerateToken : null,
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(tokens.hasToken ? l10n.mcpRegenerate : l10n.mcpGenerate),
        ),
        OutlinedButton.icon(
          key: const ValueKey('mcp-custom-token'),
          onPressed: ready ? _editToken : null,
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: Text(l10n.mcpCustomToken),
        ),
        IconButton(
          key: const ValueKey('mcp-copy-token'),
          onPressed: tokens.token == null
              ? null
              : () => _copyToClipboard(tokens.token!),
          tooltip: l10n.mcpCopyToken,
          icon: const Icon(Icons.copy_outlined),
        ),
      ]),
      if (_savingToken) const LinearProgressIndicator(minHeight: 2),
      const SizedBox(height: 8),
      Text(l10n.mcpRegenerateTokenHint,
          style: Theme.of(context).textTheme.bodySmall),
    ]);
  }

  Widget _buildPermissionSection() {
    final l10n = AppLocalizations.of(context)!;
    final t = SshText.of(context);
    final policy = ref.watch(mcpPolicyProvider);
    return _section(
        Icons.admin_panel_settings_outlined, l10n.mcpToolPermissions, [
      Text(l10n.mcpToolPermissionsHint,
          style: Theme.of(context).textTheme.bodySmall),
      for (final permission in McpPermission.values)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(_permissionTitle(l10n, t, permission)),
          subtitle: Text(permission == McpPermission.terminal
              ? '${permission.id} · ${t('每条命令都会弹窗让你确认', 'every command asks you first')}'
              : permission.id),
          value: policy.isPermissionEnabled(permission),
          onChanged: (value) => _togglePermission(policy, permission, value),
        ),
    ]);
  }

  Widget _buildSessionsSection(McpSessionStore sessions) {
    final l10n = AppLocalizations.of(context)!;
    return _section(Icons.devices_outlined, l10n.mcpCurrentConnections, [
      Text(l10n.mcpSessionsCount(sessions.activeCount)),
      if (sessions.sessions.isEmpty)
        Text(l10n.mcpNoConnections,
            style: Theme.of(context).textTheme.bodySmall)
      else
        for (final session in sessions.sessions)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.laptop, size: 20),
            title: Text(session.clientLabel),
            subtitle: Text(l10n.mcpSessionSummary(
                session.id.substring(
                    0, session.id.length < 8 ? session.id.length : 8),
                session.protocolVersion)),
            trailing: IconButton(
              icon: const Icon(Icons.link_off, size: 20),
              tooltip: l10n.mcpDisconnect,
              onPressed: () => sessions.terminate(session.id),
            ),
          ),
    ]);
  }

  /// The short in-memory list that used to be here is replaced by the
  /// persistent AI operations log (compressed, detail levels, export, delete).
  Widget _buildAuditSection() {
    final l10n = AppLocalizations.of(context)!;
    final t = SshText.of(context);
    return _section(Icons.receipt_long_outlined, l10n.mcpAuditLog, [
      Text(
        t(
          '每一次 MCP 调用（连接、断开、工具名、参数摘要、结果、耗时）以及 AI 在终端里的操作都保存在「日志」页的「AI 操作」里：可切换详略、导出、删除，重启后仍在。',
          'Every MCP call (connect, disconnect, tool, argument summary, result, duration) and everything the AI does in terminals is kept in the AI operations log: switch the detail level, export or delete it; it survives restarts.',
        ),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('mcp-open-operations-log'),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: Text(t('打开 AI 操作日志', 'Open the AI operations log')),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const TerminalLogsPage(
                initialChannel: LogChannel.operations,
              ),
            ),
          ),
        ),
      ),
    ]);
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

  String _permissionTitle(
          AppLocalizations l10n, SshText t, McpPermission permission) =>
      switch (permission) {
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
        McpPermission.terminal => t(
            '终端：AI 发命令、读输出、给你留言',
            'Terminals: AI sends commands, reads output, leaves you messages',
          ),
        McpPermission.readFilesystem => l10n.mcpPermissionReadFilesystem,
      };

  Future<void> _toggleService() async {
    setState(() => _toggling = true);
    try {
      final controller = ref.read(mcpServerControllerProvider.notifier);
      await controller.setEnabled(!controller.isRunning);
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<void> _setRequireToken(bool value) async {
    setState(() => _toggling = true);
    try {
      await ref
          .read(mcpServerControllerProvider.notifier)
          .setRequireToken(value);
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<void> _setLocalOnly(bool value) async {
    final controller = ref.read(mcpServerControllerProvider.notifier);
    await controller.setLocalOnly(value);
    if (!mounted || !controller.isRunning) return;
    final t = SshText.of(context);
    _showMessage(t('已保存，重启 MCP 服务后生效',
        'Saved. Restart the MCP service to apply it'));
  }

  Future<void> _savePort() async {
    final ok = await ref
        .read(mcpServerControllerProvider.notifier)
        .setPort(int.tryParse(_portController.text.trim()) ?? 0);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    _showMessage(ok ? l10n.mcpPortSavedNextStart : l10n.mcpInvalidPort);
  }

  Future<void> _togglePermission(
      McpPolicyService policy, McpPermission permission, bool value) async {
    await policy.setPermissionEnabled(permission, value);
    if (mounted) setState(() {});
  }

  Future<void> _regenerateToken() async {
    final l10n = AppLocalizations.of(context)!;
    if (ref.read(mcpTokenStoreProvider).hasToken) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AppAlertDialog(
          scrollable: true,
          title: Text(l10n.mcpRegenerateTokenTitle),
          content: Text(l10n.mcpRegenerateTokenConfirm),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.mcpGenerate)),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await _saveToken(
        () => ref.read(mcpServerControllerProvider.notifier).regenerateToken());
  }

  Future<void> _editToken() async {
    final tokens = ref.read(mcpTokenStoreProvider);
    final value = await showDialog<String>(
      context: context,
      builder: (_) =>
          _CustomTokenDialog(token: tokens.token, replacing: tokens.hasToken),
    );
    if (value == null || !mounted) return;
    await _saveToken(() =>
        ref.read(mcpServerControllerProvider.notifier).setCustomToken(value));
  }

  Future<void> _saveToken(Future<String> Function() save) async {
    setState(() => _savingToken = true);
    try {
      await save();
      if (mounted) _showMessage(AppLocalizations.of(context)!.mcpTokenSaved);
    } catch (_) {
      if (mounted) {
        _showMessage(AppLocalizations.of(context)!.mcpTokenSaveFailed);
      }
    } finally {
      if (mounted) setState(() => _savingToken = false);
    }
  }

  void _showMessage(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(message), duration: const Duration(seconds: 2)));

  Future<void> _copyToClipboard(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      _showMessage(AppLocalizations.of(context)!.mcpCopiedToClipboard);
    }
  }
}

class _CustomTokenDialog extends StatefulWidget {
  const _CustomTokenDialog({required this.token, required this.replacing});
  final String? token;
  final bool replacing;
  @override
  State<_CustomTokenDialog> createState() => _CustomTokenDialogState();
}

class _CustomTokenDialogState extends State<_CustomTokenDialog> {
  late final _controller = TextEditingController(text: widget.token ?? '');
  bool _invalid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (!McpTokenStore.isValidCustomToken(_controller.text)) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppAlertDialog(
      scrollable: true,
      title: Text(l10n.mcpCustomToken),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          key: const ValueKey('mcp-custom-token-field'),
          controller: _controller,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          keyboardType: TextInputType.visiblePassword,
          textInputAction: TextInputAction.done,
          maxLines: 3,
          maxLength: McpTokenStore.maxCustomLength,
          maxLengthEnforcement: MaxLengthEnforcement.none,
          decoration: InputDecoration(
            labelText: l10n.mcpPairingToken,
            errorText: _invalid ? l10n.mcpCustomTokenValidation : null,
            errorMaxLines: 4,
          ),
          onChanged: (_) {
            if (_invalid) setState(() => _invalid = false);
          },
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 8),
        Text(widget.replacing
            ? l10n.mcpRegenerateTokenConfirm
            : l10n.mcpCustomTokenValidation),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(
            key: const ValueKey('mcp-save-custom-token'),
            onPressed: _save,
            child: Text(l10n.save)),
      ],
    );
  }
}
