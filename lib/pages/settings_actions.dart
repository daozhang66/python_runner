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
      _exportDirController.text = prefs.getString('export_dir') ?? '';
      _workingDirController.text = prefs.getString('working_dir') ?? '';
      _netDebugMode = prefs.getBool('net_debug_mode') ?? false;
      _netAllowInsecure = prefs.getBool('net_allow_insecure') ?? false;
      _proxyHostController.text = prefs.getString('net_proxy_host') ?? '';
      _proxyPortController.text = (prefs.getInt('net_proxy_port') ?? 0) > 0
          ? prefs.getInt('net_proxy_port').toString()
          : '';
      _overrideEnabled = overrideCfg.overrideEnabled;
      _recordRequests = overrideCfg.recordRequests;
      _recordResponseBody = overrideCfg.recordResponseBody;
      _globalUaController.text = overrideCfg.globalUserAgent;
      _globalHeadersController.text = overrideCfg.globalHeaders;
      _globalCookieController.text = overrideCfg.globalCookie;
      _defaultHttpTimeout = overrideCfg.defaultTimeout;
      _followRedirects = overrideCfg.followRedirects;
      _forceProxy = overrideCfg.forceProxy;
      _requestConfigError = overrideCfg.configError;
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

  Future<void> _saveRuntimeBackend(String backendId) async {
    final normalizedBackendId =
        RuntimeManager.normalizePreferredBackendId(backendId);

    // Prevent switching to Linux-like if not installed
    if (normalizedBackendId == RuntimeManager.linuxLikeBackendId &&
        !_linuxLikeAvailable) {
      if (!mounted) return;
      setState(() => _engineDropdownKey++); // Force dropdown widget to recreate
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

  Future<void> _installLinuxLikeRuntime() async {
    if (_installingLinuxLike) return;
    setState(() {
      _installingLinuxLike = true;
      _installStage = 'manifest';
      _installPercent = 0;
      _installMessage = '获取版本信息...';
    });

    // Listen to real-time progress from Kotlin
    _installProgressSub?.cancel();
    _installProgressSub = _bridge.installProgressStream.listen((event) {
      if (!mounted) return;
      final status = event['status']?.toString() ?? '';
      final message = event['message']?.toString() ?? '';
      int percent = _installPercent;
      final pctMatch = RegExp(r'(\d+)%').firstMatch(message);
      if (pctMatch != null) {
        percent = int.parse(pctMatch.group(1)!);
      }
      setState(() {
        _installStage = status;
        _installPercent = percent;
        _installMessage = message;
      });
    });

    try {
      final info = await _bridge.installLinuxLikeRuntime();
      await RuntimeManager.savePreferredBackendId(
        RuntimeManager.linuxLikeBackendId,
      );
      if (!mounted) return;
      setState(() {
        _installingLinuxLike = false;
        _runtimeBackend = RuntimeManager.linuxLikeBackendId;
        _linuxLikeAvailable = info['available'] == 'true';
        _installStage = '';
        _installPercent = 100;
        _installMessage = '';
      });

      final message = info['available'] == 'true'
          ? 'Linux-like 开发版已安装'
          : (info['message'] ?? 'Linux-like 安装完成，但暂不可用');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _installingLinuxLike = false;
        _installStage = '';
        _installPercent = 0;
        _installMessage = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Linux-like 安装失败: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      _installProgressSub?.cancel();
      _installProgressSub = null;
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
    final dir = await FilePicker.getDirectoryPath();
    if (dir == null) return;
    _exportDirController.text = dir;
    await _saveExportDir();
  }

  Future<void> _saveExportDir() async {
    final prefs = await SharedPreferences.getInstance();
    final dir = _exportDirController.text.trim();
    if (dir.isEmpty) {
      await prefs.remove('export_dir');
    } else {
      await prefs.setString('export_dir', dir);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('导出目录已保存'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _pickWorkingDir() async {
    final dir = await FilePicker.getDirectoryPath();
    if (dir == null) return;
    _workingDirController.text = dir;
    await _saveWorkingDir();
  }

  Future<void> _saveWorkingDir() async {
    final prefs = await SharedPreferences.getInstance();
    final dir = _workingDirController.text.trim();
    if (dir.isEmpty) {
      await prefs.remove('working_dir');
    } else {
      await prefs.setString('working_dir', dir);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('工作目录已保存'), duration: Duration(seconds: 1)),
      );
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

  Future<void> _clearSystemLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Theme.of(ctx).colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        title: const Text('清空系统日志'),
        content: const Text('确定要清空所有系统日志和崩溃日志吗？此操作不可撤销。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('清空',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AppLogger.instance.clearAll();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('系统日志已清空'), duration: Duration(seconds: 1)),
      );
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

  Future<void> _showThemeModePicker() async {
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Theme.of(ctx).colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        title: const Text('选择主题模式'),
        content: RadioGroup<ThemeMode>(
          groupValue: widget.currentThemeMode,
          onChanged: (value) => Navigator.pop(ctx, value),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<ThemeMode>(
                value: ThemeMode.light,
                title: Text('浅色'),
                secondary: Icon(Icons.light_mode),
              ),
              RadioListTile<ThemeMode>(
                value: ThemeMode.system,
                title: Text('跟随系统'),
                secondary: Icon(Icons.auto_mode),
              ),
              RadioListTile<ThemeMode>(
                value: ThemeMode.dark,
                title: Text('深色'),
                secondary: Icon(Icons.dark_mode),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      widget.onThemeChanged(selected);
    }
  }

  Future<void> _showThemePalettePicker() async {
    if (widget.currentMaterialYouEnabled) return;
    final selected = await showDialog<AppThemePalette>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Theme.of(ctx).colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        title: const Text('选择配色方案'),
        content: SizedBox(
          width: double.maxFinite,
          child: RadioGroup<AppThemePalette>(
            groupValue: widget.currentThemePalette,
            onChanged: (value) => Navigator.pop(ctx, value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: AppThemePalette.values.map((palette) {
                final subtitle = palette.darkOnly
                    ? '${palette.description}（仅深色）'
                    : palette.description;
                return RadioListTile<AppThemePalette>(
                  value: palette,
                  title: Text(palette.label),
                  subtitle: Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12),
                  ),
                  secondary: CircleAvatar(
                    radius: 10,
                    backgroundColor: palette.previewColor,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
    if (selected != null) {
      widget.onThemePaletteChanged(selected);
    }
  }
}
