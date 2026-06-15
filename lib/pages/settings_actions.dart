// ignore_for_file: invalid_use_of_protected_member

part of 'settings_page.dart';

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
      _floatingBallEnabled = prefs.getBool('floating_ball_enabled') ?? false;
      _runtimeBackend = RuntimeManager.normalizePreferredBackendId(
        prefs.getString(RuntimeManager.prefsKey),
      );
      _githubMirrorController.text =
          prefs.getString('github_mirror_prefix') ?? '';
    });
    // Check Linux-like availability
    try {
      final info = await _bridge.getLinuxLikeRuntimeInfo();
      if (mounted) {
        setState(() => _linuxLikeAvailable = info['available'] == 'true');
      }
    } catch (_) {}
  }

  Future<void> _setFloatingBallEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();

    if (!enabled) {
      await prefs.setBool('floating_ball_enabled', false);
      if (!mounted) return;
      setState(() {
        _floatingBallEnabled = false;
        _waitingForFloatingBallPermission = false;
      });
      await legacy_provider.Provider.of<ExecutionProvider>(
        context,
        listen: false,
      ).syncFloatingBallVisibility();
      return;
    }

    var hasPermission = false;
    try {
      hasPermission = await _bridge.checkOverlayPermission();
    } catch (_) {}

    if (!hasPermission) {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('需要悬浮窗权限'),
          content: const Text('悬浮球需要「显示在其他应用上层」权限。\n\n'
              '点击确认后，请在系统设置中开启此权限，返回应用后会自动显示悬浮球。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('去设置'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      await prefs.setBool('floating_ball_enabled', true);
      if (!mounted) return;
      setState(() {
        _floatingBallEnabled = true;
        _waitingForFloatingBallPermission = true;
      });
      await _bridge.requestOverlayPermission();
      return;
    }

    await prefs.setBool('floating_ball_enabled', true);
    if (!mounted) return;
    setState(() {
      _floatingBallEnabled = true;
      _waitingForFloatingBallPermission = false;
    });
    await _syncFloatingBallNow();
  }

  Future<void> _syncFloatingBallAfterPermissionReturn() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('floating_ball_enabled') ?? false;
    if (!enabled && !_waitingForFloatingBallPermission) return;

    var hasPermission = false;
    try {
      hasPermission = await _bridge.checkOverlayPermission();
    } catch (_) {}

    if (!mounted) return;
    if (!hasPermission) {
      final executionProvider = legacy_provider.Provider.of<ExecutionProvider>(
        context,
        listen: false,
      );
      final messenger = ScaffoldMessenger.of(context);
      await prefs.setBool('floating_ball_enabled', false);
      setState(() {
        _floatingBallEnabled = false;
        _waitingForFloatingBallPermission = false;
      });
      await executionProvider.syncFloatingBallVisibility();
      messenger.showSnackBar(
        const SnackBar(content: Text('未授予悬浮窗权限，悬浮球已关闭')),
      );
      return;
    }

    setState(() {
      _floatingBallEnabled = true;
      _waitingForFloatingBallPermission = false;
    });
    await _syncFloatingBallNow();
  }

  Future<void> _syncFloatingBallNow() async {
    final executionProvider = legacy_provider.Provider.of<ExecutionProvider>(
      context,
      listen: false,
    );
    try {
      await executionProvider.syncFloatingBallVisibility(throwOnError: true);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted || !_floatingBallEnabled) return;
      await executionProvider.syncFloatingBallVisibility(throwOnError: true);
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('floating_ball_enabled', false);
      await executionProvider.syncFloatingBallVisibility();
      if (!mounted) return;
      setState(() {
        _floatingBallEnabled = false;
        _waitingForFloatingBallPermission = false;
      });
      final message = e is NativeBridgeException ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('悬浮球显示失败：$message')),
      );
    }
  }

  Future<void> _saveRuntimeBackend(String backendId) async {
    final normalizedBackendId =
        RuntimeManager.normalizePreferredBackendId(backendId);

    // Prevent switching to Linux-like if not installed
    if (normalizedBackendId == RuntimeManager.linuxLikeBackendId &&
        !_linuxLikeAvailable) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Linux-like 未安装，请先点击下方「安装/修复」按钮'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    await RuntimeManager.savePreferredBackendId(normalizedBackendId);
    if (!mounted) return;

    setState(() => _runtimeBackend = normalizedBackendId);

    final message = normalizedBackendId == RuntimeManager.linuxLikeBackendId
        ? 'Linux-like 已保存；执行和包管理将使用 Linux-like'
        : '运行引擎已切换为 Chaquopy';
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
            title: const Text('选择运行引擎'),
            contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<String>(
                  value: RuntimeManager.chaquopyBackendId,
                  groupValue: _runtimeBackend,
                  title: const Text('Chaquopy（默认）'),
                  subtitle: const Text('基于 Python 官方实现，稳定可靠'),
                  onChanged: (value) => Navigator.pop(ctx, value),
                ),
                RadioListTile<String>(
                  value: RuntimeManager.linuxLikeBackendId,
                  groupValue: _runtimeBackend,
                  title: const Text('Linux-like（实验）'),
                  subtitle: const Text('Debian 环境，支持更多包'),
                  onChanged: (value) => Navigator.pop(ctx, value),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
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

  String get _runtimeBackendSubtitle {
    final label = _runtimeBackend == RuntimeManager.linuxLikeBackendId
        ? (_linuxLikeAvailable ? '可用' : '未安装')
        : '可用';
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
        const SnackBar(
            content: Text('PyPI 源已保存'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _restoreOfficialMirror() async {
    final prefs = await SharedPreferences.getInstance();
    _mirrorController.clear();
    await prefs.remove('pypi_index_url');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已恢复官方源（https://pypi.org/simple）'),
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
        title: const Text('下载加速镜像'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('填写 GitHub 代理前缀，加速 APK 下载',
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
              '留空则直接使用 GitHub 原始地址',
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              _githubMirrorController.text = dialogCtrl.text;
              _saveGithubMirror();
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
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
      title: '选择脚本导出目录',
    );

    if (result != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('export_dir', result.path);

      setState(() {
        _exportDir = result.path;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('导出目录已设置'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _pickWorkingDir() async {
    final result = await AppFilePickerPage.pickFolder(
      context,
      title: '选择工作目录',
    );

    if (result != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('working_dir', result.path);

      setState(() {
        _workingDir = result.path;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('工作目录已设置'),
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
          title: const Text('安全警告'),
          content: const Text(
            '允许不安全证书将使网络连接不验证SSL证书，'
            '这会降低安全性。仅在使用抓包工具调试时启用。\n\n'
            '确定要启用吗？',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('确认启用',
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
    final host = _proxyHostController.text.trim();
    final port = int.tryParse(_proxyPortController.text.trim()) ?? 0;
    await NetworkDebugConfig.instance.setProxyHost(host);
    await NetworkDebugConfig.instance.setProxyPort(port);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('代理配置已保存'), duration: Duration(seconds: 1)),
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
              content: Text('完整日志已导出到: $path'),
              duration: const Duration(seconds: 3)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('导出失败: $e'), duration: const Duration(seconds: 2)),
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
