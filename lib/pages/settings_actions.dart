// ignore_for_file: invalid_use_of_protected_member

part of 'settings_page.dart';

// Flutter 3.44.2 deprecated RadioListTile.groupValue/onChanged; keep until migrate.
// ignore_for_file: deprecated_member_use

extension _SettingsActions on _SettingsPageState {
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final overrideCfg = RequestOverrideConfig.instance;
    await overrideCfg.load();
    final autoCheckUpdates = await _appUpdateManager.isAutoCheckEnabled();
    if (!mounted) return;
    setState(() {
      _mirrorController.text = prefs.getString('pypi_index_url') ?? '';
      _timeout = prefs.getInt('execution_timeout') ?? 60;
      _exportDir = prefs.getString('export_dir');
      _workingDir = prefs.getString('working_dir');
      _netDebugMode = prefs.getBool('net_debug_mode') ?? false;
      _netAllowInsecure = prefs.getBool('net_allow_insecure') ?? false;
      _proxyHostController.text = prefs.getString('net_proxy_host') ?? '';
      _proxyPortController.text = (prefs.getInt('net_proxy_port') ?? 0) > 0
          ? prefs.getInt('net_proxy_port').toString()
          : '';
      _overrideEnabled = overrideCfg.overrideEnabled;
      _recordRequests = overrideCfg.recordRequests;
      _recordResponseBody = overrideCfg.recordResponseBody;
      _autoCheckUpdates = autoCheckUpdates;
      _runtimeBackend = RuntimeManager.normalizePreferredBackendId(
        prefs.getString(RuntimeManager.prefsKey),
      );
      _githubMirrorController.text =
          prefs.getString('github_mirror_prefix') ?? '';
    });
    await _refreshLinuxLikeAvailability();
  }

  /// Reads the native runtime state instead of relying on a stale settings
  /// snapshot after an in-place installation or repair completes.
  Future<bool> _refreshLinuxLikeAvailability() async {
    try {
      final info = await _bridge.getLinuxLikeRuntimeInfo();
      final available = info['available'] == 'true';
      if (mounted && _linuxLikeAvailable != available) {
        setState(() => _linuxLikeAvailable = available);
      }
      return available;
    } catch (error, stackTrace) {
      AppLogger.instance.warn(
        '读取 Linux-like 运行环境状态失败: $error',
        source: 'Settings',
        detail: stackTrace.toString(),
      );
      return false;
    }
  }

  Future<void> _saveRuntimeBackend(String backendId) async {
    final normalizedBackendId =
        RuntimeManager.normalizePreferredBackendId(backendId);

    // Re-check immediately because an installation may have just completed.
    if (normalizedBackendId == RuntimeManager.linuxLikeBackendId &&
        !await _refreshLinuxLikeAvailability()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppLocalizations.of(context)!.linuxLikeNotInstalledAction),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    await RuntimeManager.savePreferredBackendId(normalizedBackendId);
    if (!mounted) return;

    invalidateRuntimeBackendFromWidget(ref);
    try {
      await legacy_provider.Provider.of<ExecutionProvider>(
        context,
        listen: false,
      ).onBackendChanged(normalizedBackendId);
    } catch (e, stackTrace) {
      AppLogger.instance.warn(
        '同步执行引擎失败: $e',
        source: 'Settings',
        detail: stackTrace.toString(),
      );
    }
    if (!mounted) return;
    setState(() => _runtimeBackend = normalizedBackendId);

    final message = normalizedBackendId == RuntimeManager.linuxLikeBackendId
        ? AppLocalizations.of(context)!.runtimeSwitchLinuxLike
        : AppLocalizations.of(context)!.runtimeSwitchChaquopy;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _showRuntimeBackendPicker() async {
    final selected = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) => Consumer(
        builder: (context, ref, _) {
          final enableBlur =
              ref.watch(themeProvider.select((s) => s.enableBlurEffect));
          final dialog = AlertDialog(
            backgroundColor: appDialogBackgroundColor(ctx, enableBlur),
            surfaceTintColor: Colors.transparent,
            title: Text(AppLocalizations.of(ctx)!.selectRuntimeEngine),
            contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<String>(
                  value: RuntimeManager.chaquopyBackendId,
                  groupValue: _runtimeBackend,
                  title: Text(AppLocalizations.of(ctx)!.chaquopyDefault),
                  subtitle: Text(AppLocalizations.of(ctx)!.chaquopyDescription),
                  onChanged: (value) => Navigator.pop(ctx, value),
                ),
                RadioListTile<String>(
                  value: RuntimeManager.linuxLikeBackendId,
                  groupValue: _runtimeBackend,
                  title: Text(AppLocalizations.of(ctx)!.linuxLikeExperimental),
                  subtitle:
                      Text(AppLocalizations.of(ctx)!.linuxLikeDescription),
                  onChanged: (value) => Navigator.pop(ctx, value),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(AppLocalizations.of(ctx)!.cancel),
              ),
            ],
          );

          return appDialogFrame(enableBlur: enableBlur, child: dialog);
        },
      ),
    );

    if (selected != null && selected != _runtimeBackend) {
      await _saveRuntimeBackend(selected);
    }
  }

  Future<void> _showRuntimeInstallDialog() async {
    final installed = await showDialog<bool>(
      context: context,
      builder: (_) => const _RuntimeInstallDialog(),
    );
    if (!mounted || installed != true) return;
    await _refreshLinuxLikeAvailability();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(AppLocalizations.of(context)!.runtimeInstalledSuccess)),
    );
  }

  String get _runtimeBackendSubtitle {
    final label = _runtimeBackend == RuntimeManager.linuxLikeBackendId
        ? (_linuxLikeAvailable
            ? AppLocalizations.of(context)!.available
            : AppLocalizations.of(context)!.notInstalled)
        : AppLocalizations.of(context)!.available;
    return '$label：${RuntimeManager.backendStatusMessage(_runtimeBackend)}';
  }

  Future<void> _saveMirror() async {
    final prefs = await SharedPreferences.getInstance();
    final url = _mirrorController.text.trim();
    if (url.isEmpty) {
      await prefs.remove('pypi_index_url');
    } else {
      await prefs.setString('pypi_index_url', url);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.pypiSourceSaved),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _restoreOfficialMirror() async {
    final prefs = await SharedPreferences.getInstance();
    _mirrorController.clear();
    await prefs.remove('pypi_index_url');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.officialSourceRestored),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _saveGithubMirror() async {
    final prefs = await SharedPreferences.getInstance();
    var prefix = _githubMirrorController.text.trim();
    if (prefix.isNotEmpty && !prefix.endsWith('/')) prefix = '$prefix/';
    _githubMirrorController.text = prefix;
    if (prefix.isEmpty) {
      await prefs.remove('github_mirror_prefix');
    } else {
      await prefs.setString('github_mirror_prefix', prefix);
    }
    setState(() {});
  }

  void _showGithubMirrorDialog() {
    final dialogCtrl =
        TextEditingController(text: _githubMirrorController.text);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Theme.of(ctx).colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        title: Text(AppLocalizations.of(ctx)!.downloadMirrorTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(ctx)!.downloadMirrorDescription,
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: dialogCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'https://ghfast.top/',
                isDense: true,
                border: OutlineInputBorder(gapPadding: 0),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(ctx)!.downloadMirrorEmptyHint,
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(ctx)!.cancel),
          ),
          FilledButton(
            onPressed: () {
              _githubMirrorController.text = dialogCtrl.text;
              _saveGithubMirror();
              Navigator.pop(ctx);
            },
            child: Text(AppLocalizations.of(ctx)!.save),
          ),
        ],
      ),
    ).whenComplete(() => dialogCtrl.dispose());
  }

  Future<void> _saveTimeout(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('execution_timeout', value);
    setState(() => _timeout = value);
  }

  Future<void> _pickExportDir() async {
    final result = await AppFilePickerPage.pickFolder(
      context,
      title: AppLocalizations.of(context)!.selectScriptExportDirectory,
    );

    if (result != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('export_dir', result.path);

      setState(() {
        _exportDir = result.path;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.exportDirectorySet),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _pickWorkingDir() async {
    final result = await AppFilePickerPage.pickFolder(
      context,
      title: AppLocalizations.of(context)!.selectWorkingDirectory,
    );

    if (result != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('working_dir', result.path);

      setState(() {
        _workingDir = result.path;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.workingDirectorySet),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // ── Network Debug Config ──

  Future<void> _toggleNetDebugMode(bool value) async {
    await NetworkDebugConfig.instance.setDebugMode(value);
    setState(() => _netDebugMode = value);
    if (!value) {
      // When disabling debug mode, also disable insecure certs
      await NetworkDebugConfig.instance.setAllowInsecureCerts(false);
      setState(() => _netAllowInsecure = false);
    }
  }

  Future<void> _toggleAllowInsecure(bool value) async {
    if (value && mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Theme.of(ctx).colorScheme.surfaceContainerHigh,
          surfaceTintColor: Colors.transparent,
          title: Text(AppLocalizations.of(ctx)!.securityWarning),
          content: Text(AppLocalizations.of(ctx)!.insecureCertificateWarning),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(AppLocalizations.of(ctx)!.cancel)),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(AppLocalizations.of(ctx)!.confirmEnable,
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await NetworkDebugConfig.instance.setAllowInsecureCerts(value);
    setState(() => _netAllowInsecure = value);
  }

  Future<void> _saveProxyConfig() async {
    final host = _proxyHostController.text;
    final rawPort = _proxyPortController.text.trim();
    final port = rawPort.isEmpty ? 0 : int.tryParse(rawPort);
    if (port == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(AppLocalizations.of(context)!.proxyPortMustBeInteger)),
        );
      }
      return;
    }
    try {
      await NetworkDebugConfig.instance.setProxy(host, port);
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.proxyConfigurationSaved),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  // ── System Log Management ──

  Future<void> _viewSystemLogs() async {
    final logContent = await AppLogger.instance.exportAll();
    if (!mounted) return;
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => _SystemLogViewPage(logContent: logContent)));
  }

  Future<void> _exportSystemLogs() async {
    try {
      final content = await AppLogger.instance.exportAll();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final prefs = await SharedPreferences.getInstance();
      final workingDir = (prefs.getString('working_dir') ?? '').trim();
      final logExportDir = workingDir.isEmpty ? null : workingDir;
      final path = await _bridge.exportLog(
        content,
        fileName: 'python_runner_logs_$timestamp.txt',
        destDir: logExportDir,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(AppLocalizations.of(context)!.fullLogsExportedTo(path)),
              duration: const Duration(seconds: 3)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.exportFailed),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _openAboutPage() {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const _AboutPage()));
  }

  Future<void> _checkForUpdates() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    try {
      await _appUpdateManager.checkForUpdates(context, manual: true);
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _setAutoCheckUpdates(bool enabled) async {
    await _appUpdateManager.setAutoCheckEnabled(enabled);
    if (!mounted) return;
    setState(() => _autoCheckUpdates = enabled);
  }

  void _openUpdateLogPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => UpdateLogPage()),
    );
  }
}
