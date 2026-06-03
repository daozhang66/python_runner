import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../services/native_bridge.dart';
import '../services/app_logger.dart';
import '../services/app_update_manager.dart';
import '../services/network_debug_config.dart';
import '../services/request_override_config.dart';
import '../runtime/runtime_manager.dart';

class SettingsPage extends StatefulWidget {
  final ValueChanged<ThemeMode> onThemeChanged;
  final ThemeMode currentThemeMode;
  final ValueChanged<bool> onMaterialYouChanged;
  final bool currentMaterialYouEnabled;

  const SettingsPage({
    super.key,
    required this.onThemeChanged,
    required this.currentThemeMode,
    required this.onMaterialYouChanged,
    required this.currentMaterialYouEnabled,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _mirrorController = TextEditingController();
  final _exportDirController = TextEditingController();
  final _workingDirController = TextEditingController();
  final _proxyHostController = TextEditingController();
  final _proxyPortController = TextEditingController();
  final _globalUaController = TextEditingController();
  final _globalHeadersController = TextEditingController();
  final _globalCookieController = TextEditingController();
  final _githubMirrorController = TextEditingController();
  int _timeout = 60;
  bool _netDebugMode = false;
  bool _netAllowInsecure = false;
  bool _overrideEnabled = false;
  bool _recordRequests = true;
  bool _recordResponseBody = false;
  int _defaultHttpTimeout = 30;
  bool _followRedirects = true;
  bool _forceProxy = false;
  bool _autoCheckUpdates = true;
  bool _floatingBallEnabled = false;
  String _runtimeBackend = RuntimeManager.chaquopyBackendId;
  final _bridge = NativeBridge();
  final _appUpdateManager = AppUpdateManager();
  bool _checkingUpdate = false;
  bool _installingLinuxLike = false;
  bool _linuxLikeAvailable = false;
  int _engineDropdownKey = 0;
  String _installStage = '';
  int _installPercent = 0;
  String _installMessage = '';
  StreamSubscription? _installProgressSub;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

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
      _autoCheckUpdates = autoCheckUpdates;
      _floatingBallEnabled = prefs.getBool('floating_ball_enabled') ?? false;
      _runtimeBackend = RuntimeManager.normalizePreferredBackendId(
        prefs.getString(RuntimeManager.prefsKey),
      );
      _githubMirrorController.text = prefs.getString('github_mirror_prefix') ?? '';
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
    if (normalizedBackendId == RuntimeManager.linuxLikeBackendId && !_linuxLikeAvailable) {
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
        const SnackBar(content: Text('PyPI 源已保存'), duration: Duration(seconds: 1)),
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
    final dialogCtrl = TextEditingController(text: _githubMirrorController.text);
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
            const Text('填写 GitHub 代理前缀，加速 APK 下载', style: TextStyle(fontSize: 13)),
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
              style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
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
    final dir = await FilePicker.platform.getDirectoryPath();
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
        const SnackBar(content: Text('导出目录已保存'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _pickWorkingDir() async {
    final dir = await FilePicker.platform.getDirectoryPath();
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
        const SnackBar(content: Text('工作目录已保存'), duration: Duration(seconds: 1)),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Theme.of(ctx).colorScheme.surfaceContainerHigh,
          surfaceTintColor: Colors.transparent,
          title: const Text('安全警告'),
          content: const Text(
            '允许不安全证书将使网络连接不验证SSL证书，'
            '这会降低安全性。仅在使用抓包工具调试时启用。\n\n'
            '确定要启用吗？',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('确认启用', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
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
        const SnackBar(content: Text('代理配置已保存'), duration: Duration(seconds: 1)),
      );
    }
  }

  // ── System Log Management ──

  Future<void> _viewSystemLogs() async {
    final logContent = await AppLogger.instance.exportAll();
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => _SystemLogViewPage(logContent: logContent)));
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
          SnackBar(content: Text('完整日志已导出到: $path'), duration: const Duration(seconds: 3)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e'), duration: const Duration(seconds: 2)),
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('清空', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AppLogger.instance.clearAll();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('系统日志已清空'), duration: Duration(seconds: 1)),
      );
    }
  }

  void _openAboutPage() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const _AboutPage()));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ── General ──
          _SectionCard(
            icon: Icons.tune,
            title: '通用',
            children: [
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('主题'),
                trailing: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode, size: 18)),
                    ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.auto_mode, size: 18)),
                    ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode, size: 18)),
                  ],
                  selected: {widget.currentThemeMode},
                  onSelectionChanged: (s) => widget.onThemeChanged(s.first),
                  showSelectedIcon: false,
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.color_lens_outlined),
                title: const Text('Material You'),
                subtitle: const Text('Android 12+ 跟随系统壁纸动态取色，不支持时使用默认蓝色', style: TextStyle(fontSize: 12)),
                value: widget.currentMaterialYouEnabled,
                onChanged: widget.onMaterialYouChanged,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.bubble_chart),
                title: const Text('悬浮球'),
                subtitle: const Text('脚本运行时显示悬浮球，点击返回应用，长按查看详情', style: TextStyle(fontSize: 12)),
                value: _floatingBallEnabled,
                onChanged: (v) async {
                  if (v) {
                    try {
                      final hasPermission = await _bridge.checkOverlayPermission();
                      if (!hasPermission) {
                        if (!mounted) return;
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            backgroundColor: Theme.of(ctx).colorScheme.surfaceContainerHigh,
                            surfaceTintColor: Colors.transparent,
                            title: const Text('需要悬浮窗权限'),
                            content: const Text(
                              '悬浮球需要「显示在其他应用上层」权限。\n\n'
                              '点击确认后，请在系统设置中开启此权限。',
                            ),
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
                        if (confirmed == true) {
                          await _bridge.requestOverlayPermission();
                        } else {
                          return;
                        }
                      }
                    } catch (_) {}
                  }
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('floating_ball_enabled', v);
                  setState(() => _floatingBallEnabled = v);
                  if (v) {
                    // Show idle ball immediately
                    try { await _bridge.showFloatingBall(''); } catch (_) {}
                  } else {
                    try { await _bridge.hideFloatingBall(); } catch (_) {}
                  }
                },
              ),
            ],
          ),

          // ── Runtime Engine ──
          _SectionCard(
            icon: Icons.memory,
            title: '运行引擎',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: DropdownButtonFormField<String>(
                  key: ValueKey('$_runtimeBackend-$_engineDropdownKey'),
                  value: _runtimeBackend,
                  borderRadius: BorderRadius.circular(16),
                  dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                  iconEnabledColor: Theme.of(context).colorScheme.primary,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    labelText: '运行引擎',
                    prefixIcon: Icon(Icons.memory),
                    border: OutlineInputBorder(gapPadding: 0),
                    isDense: true,
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: RuntimeManager.chaquopyBackendId,
                      child: Text('Chaquopy（默认）'),
                    ),
                    DropdownMenuItem(
                      value: RuntimeManager.linuxLikeBackendId,
                      child: Text('Linux-like（实验）'),
                    ),
                  ],
                  selectedItemBuilder: (context) => [
                    Text('Chaquopy',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        )),
                    Text('Linux-like',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        )),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      _saveRuntimeBackend(value);
                    }
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  _runtimeBackendSubtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _installingLinuxLike
                    ? _InstallProgressCard(
                        stage: _installStage,
                        percent: _installPercent,
                        message: _installMessage,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _installLinuxLikeRuntime,
                            icon: const Icon(Icons.download_for_offline_outlined),
                            label: const Text('安装/修复 Linux-like 开发版'),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '会下载约 104MB 的 Debian + Python + pip + build-essential 环境包。',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('PyPI 源', style: Theme.of(context).textTheme.titleSmall),
                        const Spacer(),
                        Text('留空使用官方源', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _mirrorController,
                            enableSuggestions: false,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              hintText: 'https://pypi.org/simple',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(onPressed: _saveMirror, icon: const Icon(Icons.save)),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _restoreOfficialMirror,
                        child: const Text('恢复官方源'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Script ──
          _SectionCard(
            icon: Icons.code,
            title: '脚本',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('执行超时时间', style: Theme.of(context).textTheme.titleSmall),
                        const Spacer(),
                        Text(_timeout == 0 ? '无限制' : _timeout >= 3600
                            ? '${(_timeout / 3600).toStringAsFixed(1)} 小时'
                            : _timeout >= 60
                            ? '${(_timeout / 60).toStringAsFixed(0)} 分钟'
                            : '$_timeout 秒',
                            style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                    Slider(
                      value: _timeout == 0 ? 0 : _timeout <= 60
                          ? _timeout.toDouble()
                          : _timeout <= 600
                          ? 60 + (_timeout - 60) * 40 / 540
                          : _timeout <= 3600
                          ? 100 + (_timeout - 600) * 40 / 3000
                          : 140 + (_timeout - 3600) * 10 / 32400,
                      min: 0,
                      max: 150,
                      divisions: 150,
                      label: _timeout == 0 ? '无限制'
                          : _timeout >= 3600 ? '${(_timeout / 3600).toStringAsFixed(1)}h'
                          : _timeout >= 60 ? '${(_timeout / 60).toStringAsFixed(0)}m'
                          : '${_timeout}s',
                      onChanged: (v) {
                        int val;
                        if (v == 0) {
                          val = 0;
                        } else if (v <= 60) {
                          val = v.round();
                        } else if (v <= 100) {
                          val = 60 + ((v - 60) * 540 / 40).round();
                          val = (val / 60).round() * 60;
                        } else if (v <= 140) {
                          val = 600 + ((v - 100) * 3000 / 40).round();
                          val = (val / 300).round() * 300;
                        } else {
                          val = 3600 + ((v - 140) * 32400 / 10).round();
                          val = (val / 1800).round() * 1800;
                        }
                        setState(() => _timeout = val);
                      },
                      onChangeEnd: (v) => _saveTimeout(_timeout),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('工作目录', style: Theme.of(context).textTheme.titleSmall),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('脚本运行时的文件读写目录，留空使用默认',
                        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _workingDirController,
                            decoration: const InputDecoration(
                              hintText: '/sdcard/Download/PythonRunner',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(onPressed: _pickWorkingDir, icon: const Icon(Icons.folder_open)),
                        IconButton(onPressed: _saveWorkingDir, icon: const Icon(Icons.save)),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('脚本导出目录', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text('留空使用默认下载目录',
                        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _exportDirController,
                            decoration: const InputDecoration(
                              hintText: '/sdcard/Download/PythonRunner',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(onPressed: _pickExportDir, icon: const Icon(Icons.folder_open)),
                        IconButton(onPressed: _saveExportDir, icon: const Icon(Icons.save)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Network ──
          _SectionCard(
            icon: Icons.http,
            title: '网络',
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.developer_mode),
                title: const Text('网络调试模式'),
                subtitle: const Text('开启后可配置代理和证书选项', style: TextStyle(fontSize: 12)),
                value: _netDebugMode,
                onChanged: _toggleNetDebugMode,
              ),
              if (_netDebugMode) ...[
                SwitchListTile(
                  secondary: Icon(Icons.lock_open, color: _netAllowInsecure ? Theme.of(context).colorScheme.error : null),
                  title: const Text('允许不安全证书'),
                  subtitle: Text(
                    _netAllowInsecure
                        ? '已开启 — 将信任自签名/抓包证书（降低安全性）'
                        : '关闭 — 严格校验SSL证书',
                    style: TextStyle(fontSize: 12, color: _netAllowInsecure ? Theme.of(context).colorScheme.error : null),
                  ),
                  value: _netAllowInsecure,
                  onChanged: _toggleAllowInsecure,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('代理配置（可选）', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      const Text('填写后网络请求将通过指定代理', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _proxyHostController,
                              enableSuggestions: false,
                              autocorrect: false,
                              decoration: const InputDecoration(
                                hintText: '192.168.1.100',
                                labelText: '代理地址',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 1,
                            child: TextField(
                              controller: _proxyPortController,
                              enableSuggestions: false,
                              autocorrect: false,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: const InputDecoration(
                                hintText: '8888',
                                labelText: '端口',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(onPressed: _saveProxyConfig, icon: const Icon(Icons.save)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const Divider(height: 1, indent: 16, endIndent: 16),
              SwitchListTile(
                secondary: const Icon(Icons.visibility_outlined),
                title: const Text('记录网络请求'),
                subtitle: const Text('捕获 requests/httpx/urllib3 的真实请求', style: TextStyle(fontSize: 12)),
                value: _recordRequests,
                onChanged: (v) async {
                  await RequestOverrideConfig.instance.setRecordRequests(v);
                  setState(() => _recordRequests = v);
                },
              ),
              if (_recordRequests)
                SwitchListTile(
                  secondary: const Icon(Icons.description_outlined),
                  title: const Text('记录响应体预览'),
                  subtitle: const Text('记录响应内容前 2 MB（增加内存占用）', style: TextStyle(fontSize: 12)),
                  value: _recordResponseBody,
                  onChanged: (v) async {
                    await RequestOverrideConfig.instance.setRecordResponseBody(v);
                    setState(() => _recordResponseBody = v);
                  },
                ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              SwitchListTile(
                secondary: Icon(Icons.tune, color: _overrideEnabled ? Theme.of(context).colorScheme.primary : null),
                title: const Text('启用请求覆盖'),
                subtitle: Text(
                  _overrideEnabled
                      ? '已开启 — 全局覆盖将应用到所有 Python HTTP 请求'
                      : '关闭 — 不修改脚本的默认请求行为',
                  style: TextStyle(fontSize: 12, color: _overrideEnabled ? Theme.of(context).colorScheme.primary : null),
                ),
                value: _overrideEnabled,
                onChanged: (v) async {
                  if (v && mounted) {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        backgroundColor: Theme.of(ctx).colorScheme.surfaceContainerHigh,
                        surfaceTintColor: Colors.transparent,
                        title: const Text('启用请求覆盖'),
                        content: const Text(
                          '开启后将全局覆盖 Python 脚本中 HTTP 请求的 '
                          'User-Agent、Headers、Cookie、超时等设置。\n\n'
                          '这会修改脚本的实际网络行为，仅建议在调试时使用。',
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认启用')),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                  }
                  await RequestOverrideConfig.instance.setOverrideEnabled(v);
                  setState(() => _overrideEnabled = v);
                },
              ),
              if (_overrideEnabled) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('全局 User-Agent', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      const Text('覆盖 requests 等库的默认 UA（如 python-requests/2.x.x）',
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _globalUaController,
                              enableSuggestions: false,
                              autocorrect: false,
                              decoration: const InputDecoration(
                                hintText: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) ...',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () async {
                              await RequestOverrideConfig.instance
                                  .setGlobalUserAgent(_globalUaController.text);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('User-Agent 已保存'), duration: Duration(seconds: 1)),
                                );
                              }
                            },
                            icon: const Icon(Icons.save),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('全局额外请求头', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      const Text('JSON 格式，如 {"Accept-Language":"zh-CN"}',
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _globalHeadersController,
                              enableSuggestions: false,
                              autocorrect: false,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                hintText: '{"Accept-Language":"zh-CN","X-Custom":"value"}',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () async {
                              final text = _globalHeadersController.text.trim();
                              if (text.isNotEmpty) {
                                try {
                                  final _ = Map<String, dynamic>.from(
                                      const JsonDecoder().convert(text) as Map);
                                } catch (_) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('JSON 格式错误'), duration: Duration(seconds: 2)),
                                    );
                                  }
                                  return;
                                }
                              }
                              await RequestOverrideConfig.instance.setGlobalHeaders(text);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('全局请求头已保存'), duration: Duration(seconds: 1)),
                                );
                              }
                            },
                            icon: const Icon(Icons.save),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('全局 Cookie', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      const Text('注入到所有请求的 Cookie 头',
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _globalCookieController,
                              enableSuggestions: false,
                              autocorrect: false,
                              decoration: const InputDecoration(
                                hintText: 'session_id=abc123; token=xyz',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () async {
                              await RequestOverrideConfig.instance
                                  .setGlobalCookie(_globalCookieController.text);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Cookie 已保存'), duration: Duration(seconds: 1)),
                                );
                              }
                            },
                            icon: const Icon(Icons.save),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Text('默认 HTTP 超时', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          const Spacer(),
                          Text('$_defaultHttpTimeout 秒',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w500)),
                        ],
                      ),
                      Slider(
                        value: _defaultHttpTimeout.toDouble(),
                        min: 5,
                        max: 120,
                        divisions: 23,
                        label: '$_defaultHttpTimeout 秒',
                        onChanged: (v) => setState(() => _defaultHttpTimeout = v.round()),
                        onChangeEnd: (v) async {
                          await RequestOverrideConfig.instance.setDefaultTimeout(v.round());
                        },
                      ),
                    ],
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.redo),
                  title: const Text('跟随重定向'),
                  subtitle: const Text('是否自动跟随 HTTP 重定向', style: TextStyle(fontSize: 12)),
                  value: _followRedirects,
                  onChanged: (v) async {
                    await RequestOverrideConfig.instance.setFollowRedirects(v);
                    setState(() => _followRedirects = v);
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.vpn_lock),
                  title: const Text('强制使用代理'),
                  subtitle: const Text('将代理配置强制应用到 Python HTTP 请求', style: TextStyle(fontSize: 12)),
                  value: _forceProxy,
                  onChanged: (v) async {
                    await RequestOverrideConfig.instance.setForceProxy(v);
                    setState(() => _forceProxy = v);
                  },
                ),
              ],
            ],
          ),

          // ── System Tools ──
          _SectionCard(
            icon: Icons.build_outlined,
            title: '系统工具',
            children: [
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: const Text('查看完整日志'),
                subtitle: const Text('查看完整诊断日志、崩溃日志和脚本错误', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _viewSystemLogs,
              ),
              ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: const Text('导出完整日志'),
                subtitle: const Text('导出完整诊断日志到工作目录，未设置则使用默认目录', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _exportSystemLogs,
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                title: const Text('清空系统日志'),
                subtitle: const Text('删除所有系统日志文件', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _clearSystemLogs,
              ),
            ],
          ),

          // ── About ──
          _SectionCard(
            icon: Icons.info_outline,
            title: '关于',
            children: [
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('使用手册'),
                subtitle: const Text('功能说明与操作指南', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const _UserManualPage())),
              ),
              ListTile(
                leading: _checkingUpdate
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.system_update_alt),
                title: const Text('检查更新'),
                subtitle: const Text(
                  '从 GitHub Releases 获取最新 APK',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _checkingUpdate ? null : _checkForUpdates,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.update_outlined),
                title: const Text('启动时自动检查更新'),
                subtitle: const Text(
                  '每次启动应用时自动检查更新',
                  style: TextStyle(fontSize: 12),
                ),
                value: _autoCheckUpdates,
                onChanged: _setAutoCheckUpdates,
              ),
              ListTile(
                leading: const Icon(Icons.speed_outlined),
                title: const Text('下载加速镜像'),
                subtitle: Text(
                  _githubMirrorController.text.isEmpty
                      ? '未设置（点击配置）'
                      : _githubMirrorController.text,
                  style: const TextStyle(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showGithubMirrorDialog,
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('关于应用'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openAboutPage,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _installProgressSub?.cancel();
    _mirrorController.dispose();
    _exportDirController.dispose();
    _workingDirController.dispose();
    _proxyHostController.dispose();
    _proxyPortController.dispose();
    _globalUaController.dispose();
    _globalHeadersController.dispose();
    _globalCookieController.dispose();
    _githubMirrorController.dispose();
    super.dispose();
  }
}

class _InstallProgressCard extends StatelessWidget {
  final String stage;
  final int percent;
  final String message;

  const _InstallProgressCard({
    required this.stage,
    required this.percent,
    required this.message,
  });

  IconData _stageIcon(String s) {
    switch (s) {
      case 'manifest': return Icons.cloud_download_outlined;
      case 'downloading': return Icons.download_outlined;
      case 'verifying': return Icons.verified_outlined;
      case 'extracting': return Icons.folder_open_outlined;
      case 'finalizing': return Icons.check_circle_outline;
      default: return Icons.hourglass_empty;
    }
  }

  String _stageLabel(String s) {
    switch (s) {
      case 'manifest': return '获取版本信息';
      case 'downloading': return '下载运行环境';
      case 'verifying': return '校验文件完整性';
      case 'extracting': return '解压运行环境';
      case 'finalizing': return '配置完成中';
      default: return '准备中';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_stageIcon(stage), size: 18, color: c.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '正在安装 Linux-like',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.onSurface),
                ),
              ),
              Text(
                '$percent%',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.primary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent / 100.0,
              minHeight: 6,
              backgroundColor: c.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(c.primary),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: c.primary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message.isNotEmpty ? message : _stageLabel(stage),
                  style: TextStyle(fontSize: 11.5, color: c.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _SectionCard({required this.icon, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: colors.primary),
                  const SizedBox(width: 10),
                  Text(title, style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: colors.primary,
                  )),
                ],
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SystemLogViewPage extends StatefulWidget {
  final String logContent;
  const _SystemLogViewPage({required this.logContent});

  @override
  State<_SystemLogViewPage> createState() => _SystemLogViewPageState();
}

class _SystemLogViewPageState extends State<_SystemLogViewPage> {
  String _query = '';
  String _levelFilter = 'ALL';
  String _sectionFilter = '全部';

  static const List<String> _sectionFilters = [
    '全部',
    '诊断信息',
    '系统日志',
    'Dart 崩溃日志',
    '脚本错误日志',
    '原生脚本错误日志',
    '原生崩溃日志',
    'Diagnostic Archive',
    'Current Diagnostics',
    'Local Log Files',
    'Archived Diagnostics',
  ];

  String get _filteredLogContent {
    final query = _query.trim().toLowerCase();
    final sectionContent = _sectionLogContent(widget.logContent);
    final lines = sectionContent.split('\n').where((line) {
      final lower = line.toLowerCase();
      final matchesQuery = query.isEmpty || lower.contains(query);
      final matchesLevel = _levelFilter == 'ALL' || lower.contains(_levelFilter.toLowerCase());
      return matchesQuery && matchesLevel;
    });
    return lines.join('\n');
  }

  String _sectionLogContent(String input) {
    if (_sectionFilter == '全部') return input;
    final header = '====== $_sectionFilter ======';
    final start = input.indexOf(header);
    if (start < 0) return '';
    final next = input.indexOf('====== ', start + header.length);
    return next < 0 ? input.substring(start) : input.substring(start, next);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredLogContent;
    final isEmpty = widget.logContent.isEmpty || filtered.trim().isEmpty || widget.logContent.startsWith('(暂无');
    return Scaffold(
      appBar: AppBar(
        title: const Text('系统日志'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: filtered));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制当前日志内容'), duration: Duration(seconds: 1)),
              );
            },
            tooltip: '复制',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: '搜索日志',
                hintText: '输入关键字过滤日志内容',
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _levelFilter,
                    decoration: const InputDecoration(labelText: '级别'),
                    items: const ['ALL', 'INFO', 'WARN', 'ERROR']
                        .map((level) => DropdownMenuItem(value: level, child: Text(level)))
                        .toList(),
                    onChanged: (value) => setState(() => _levelFilter = value ?? 'ALL'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _sectionFilter,
                    decoration: const InputDecoration(labelText: '区块'),
                    items: _sectionFilters
                        .map((section) => DropdownMenuItem(value: section, child: Text(section)))
                        .toList(),
                    onChanged: (value) => setState(() => _sectionFilter = value ?? '全部'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: isEmpty
                ? const Center(child: Text('暂无匹配日志', style: TextStyle(color: Colors.grey)))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      filtered,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _UserManualPage extends StatelessWidget {
  const _UserManualPage();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('使用手册')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _ManualSection(
            icon: Icons.code,
            title: '脚本列表',
            items: const [
              _ManualItem(Icons.add, '新建脚本', '顶部 + 按钮创建新脚本'),
              _ManualItem(Icons.file_open, '导入脚本', '顶部文件夹按钮选择 .py 文件导入'),
              _ManualItem(Icons.play_arrow, '快捷运行', '列表/宫格中直接点击 ▶ 按钮运行脚本'),
              _ManualItem(Icons.search, '搜索', '按名称快速过滤脚本'),
              _ManualItem(Icons.checklist, '多选模式', '进入多选后可批量导出或删除'),
              _ManualItem(Icons.grid_view, '视图切换', '列表/宫格视图切换'),
              _ManualItem(Icons.more_vert, '长按脚本', '重命名、复制、导出、删除'),
            ],
          ),
          const SizedBox(height: 12),
          _ManualSection(
            icon: Icons.edit_note,
            title: '代码编辑器',
            items: const [
              _ManualItem(Icons.lock, '只读/编辑', '锁图标切换，默认只读防误触'),
              _ManualItem(Icons.search, '代码搜索', '搜索关键字，上下跳转匹配'),
              _ManualItem(Icons.format_size, '字体大小', '点击 Aa 按钮滑动调节编辑器字号'),
              _ManualItem(Icons.save, '保存', '修改后出现，点击保存'),
              _ManualItem(Icons.play_arrow, '运行脚本', '点击 ▶ 按钮保存并运行，自动跳转全屏终端'),
              _ManualItem(Icons.fullscreen, '全屏终端', '点击全屏图标直接打开终端页面'),
              _ManualItem(Icons.undo, '编辑工具栏', '编辑模式下底部工具栏提供缩进、撤回、重做'),
            ],
          ),
          const SizedBox(height: 12),
          _ManualSection(
            icon: Icons.terminal,
            title: '全屏终端',
            items: const [
              _ManualItem(Icons.play_arrow, '运行/停止', '运行中显示停止按钮和计时，结束后显示重运行按钮'),
              _ManualItem(Icons.search, '搜索日志', '点击搜索按钮，实时过滤日志内容'),
              _ManualItem(Icons.error_outline, '只看错误', '搜索栏内点击错误图标，快速过滤 stderr/error'),
              _ManualItem(Icons.copy, '复制日志', '工具栏一键复制全部日志'),
              _ManualItem(Icons.format_size, '字体大小', '点击 Aa 按钮滑动调节终端字号'),
              _ManualItem(Icons.delete_outline, '清空', '清除终端输出'),
              _ManualItem(Icons.chevron_right, '交互输入', 'input() 时底部出现输入框，自动聚焦'),
              _ManualItem(Icons.notifications, '运行通知', '前台通知显示脚本名称和运行时长'),
            ],
          ),
          const SizedBox(height: 12),
          _ManualSection(
            icon: Icons.bubble_chart,
            title: '悬浮球',
            items: const [
              _ManualItem(Icons.play_arrow, '状态指示', '灰色=空闲，绿色脉冲=运行中，红色=报错，橙色=等待输入；不同状态显示不同图标（Py/▶/×/?）'),
              _ManualItem(Icons.touch_app, '点击操作', '折叠时点击展开悬浮球；展开时点击显示/隐藏信息面板'),
              _ManualItem(Icons.open_in_full, '长按展开', '长按显示信息面板：运行中查看脚本名、实时计时和停止按钮；空闲时查看最近运行的脚本列表'),
              _ManualItem(Icons.history, '快捷运行', '空闲面板显示最近 5 个脚本，点击即可快速重新运行'),
              _ManualItem(Icons.swap_vert, '贴边收起', '松手自动贴向最近屏幕边缘，仅露出 16px；3 秒后自动收起，点击或长按重新展开'),
              _ManualItem(Icons.swipe, '拖拽移动', '拖动悬浮球到屏幕任意位置，松手自动贴边'),
              _ManualItem(Icons.delete_outline, '拖拽停止', '运行中拖到底部红色区域松手可快速停止脚本'),
              _ManualItem(Icons.settings, '开关控制', '在设置页开启或关闭，开启后悬浮球常驻屏幕，关闭后消失'),
              _ManualItem(Icons.security, '权限', '首次开启需授予「显示在其他应用上层」权限'),
            ],
          ),
          const SizedBox(height: 12),
          _ManualSection(
            icon: Icons.http,
            title: '网络请求调试',
            items: const [
              _ManualItem(Icons.visibility_outlined, '请求查看器', '底部「网络」Tab 查看所有 Python HTTP 请求'),
              _ManualItem(Icons.search, '搜索 URL', '顶部搜索栏实时搜索 URL / 域名关键字'),
              _ManualItem(Icons.bar_chart, '统计摘要', '显示总数、成功数、错误数、平均耗时'),
              _ManualItem(Icons.filter_list, '高级筛选', '按域名、请求方法和状态码范围筛选'),
              _ManualItem(Icons.list_alt, '请求详情', '点击单条请求查看完整请求头/响应头/响应体'),
              _ManualItem(Icons.account_tree, 'JSON 树查看', '响应体支持 JSON 树状结构查看和搜索'),
              _ManualItem(Icons.tune, '请求覆盖', '设置页开启后可全局覆盖 UA/Headers/Cookie'),
              _ManualItem(Icons.code, '支持的库', 'requests、httpx、urllib 自动 Hook'),
              _ManualItem(Icons.bug_report_outlined, '代理调试', '配合 Charles/Fiddler 外部抓包工具使用'),
            ],
          ),
          const SizedBox(height: 12),
          _ManualSection(
            icon: Icons.inventory_2_outlined,
            title: '库管理',
            items: const [
              _ManualItem(Icons.search, '搜索', '按名称过滤已安装的包'),
              _ManualItem(Icons.tab, '分类查看', '用户安装/内置库两个 Tab 分开显示'),
              _ManualItem(Icons.add, '安装包', '输入包名安装，可指定版本和 PyPI 源；留空使用官方源'),
              _ManualItem(Icons.delete_outline, '卸载包', '用户安装的包点击删除按钮卸载；支持清理其孤儿依赖'),
              _ManualItem(Icons.view_list_outlined, '用户安装列表', '仅显示顶层安装包，不显示 certifi、urllib3 等自动依赖'),
            ],
          ),
          const SizedBox(height: 12),
          _ManualSection(
            icon: Icons.settings,
            title: '设置',
            items: const [
              _ManualItem(Icons.palette_outlined, '主题', '浅色/跟随系统/深色'),
              _ManualItem(Icons.color_lens_outlined, 'Material You', 'Android 12+ 可跟随系统壁纸动态取色'),
              _ManualItem(Icons.bubble_chart, '悬浮球', '开启后悬浮球常驻屏幕，支持贴边收起、快捷运行最近脚本、拖拽停止等'),
              _ManualItem(Icons.memory, '运行引擎',
                  '支持两种运行引擎：Chaquopy（轻量稳定，Python 3.11）和 Linux-like（Debian 环境，支持更多系统依赖），可在设置中切换'),
              _ManualItem(Icons.inventory_2_outlined, 'PyPI 源', 'pip 安装索引地址；留空使用官方源，也可一键恢复官方源'),
              _ManualItem(Icons.timer_outlined, '执行超时', '脚本最长运行时间（可设为无限制）'),
              _ManualItem(Icons.work_outline, '工作目录', '脚本中 open() 等相对路径的基准目录'),
              _ManualItem(Icons.folder_outlined, '导出目录', '脚本导出目标文件夹'),
              _ManualItem(Icons.update_outlined, '自动更新', '每次启动检查更新，可在设置中开关'),
              _ManualItem(Icons.bug_report_outlined, '网络调试模式', '代理/SSL 配置，用于外部抓包工具'),
              _ManualItem(Icons.visibility_outlined, '记录网络请求', '捕获 Python HTTP 库的真实请求'),
              _ManualItem(Icons.tune, '请求覆盖', '全局覆盖 UA/Headers/Cookie/超时/重定向'),
              _ManualItem(Icons.article_outlined, '系统日志', '查看、导出或清空运行日志和崩溃日志'),
            ],
          ),
          const SizedBox(height: 12),
          _ManualSection(
            icon: Icons.extension_outlined,
            title: '自定义 Python 库',
            items: [
              const _ManualItem(Icons.folder_outlined, '添加存储',
                  'MT管理器侧拉栏点击 ⋮ → 添加本地存储 → 点击 ≡ 找到 Python运行器 → 使用此文件夹'),
              const _ManualItem(Icons.code, 'Chaquopy 库目录',
                  '添加后进入 files → chaquopy → pip，pip 安装的包和自定义库都在这里'),
              const _ManualItem(Icons.code, 'Linux-like 库目录',
                  '添加后进入 files → linux_like → user_site_packages，Linux-like 用户安装库和自定义库都在这里'),
              const _ManualItem(Icons.create_new_folder, '创建库文件',
                  '在库目录中新建 .py 文件（如 mylib.py），编写代码保存即可'),
              const _ManualItem(Icons.play_arrow, '脚本中引用',
                  '直接 import mylib 即可使用，无需额外配置，也可创建包目录 mylib/__init__.py'),
              const _ManualItem(Icons.warning_amber, '注意事项',
                  '两个引擎的库目录互相独立，切换引擎后需进入对应目录操作；修改后无需重启 APP'),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _ManualSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<_ManualItem> items;

  const _ManualSection({required this.icon, required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colors.primaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Icon(icon, size: 20, color: colors.primary),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colors.primary)),
          ]),
        ),
        const SizedBox(height: 8),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(item.icon, size: 18, color: colors.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(fontSize: 13, color: colors.onSurface),
                    children: [
                      TextSpan(text: '${item.label}  ', style: const TextStyle(fontWeight: FontWeight.w600)),
                      TextSpan(text: item.description),
                    ],
                  ),
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }
}

class _ManualItem {
  final IconData icon;
  final String label;
  final String description;
  const _ManualItem(this.icon, this.label, this.description);
}

// ═══════════════════════════════════════════════════════════════
// About Page
// ═══════════════════════════════════════════════════════════════

class _AboutPage extends StatefulWidget {
  const _AboutPage();
  @override
  State<_AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<_AboutPage> {
  final _bridge = NativeBridge();
  String _runtimeBackend = RuntimeManager.chaquopyBackendId;
  String _appVersion = '';
  String _buildNumber = '';
  String _pyVersion = '';
  String _sitePackages = '';
  String _pythonPath = '';
  String _chaquopyPipDir = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final runtimeBackend = RuntimeManager.normalizePreferredBackendId(
      prefs.getString(RuntimeManager.prefsKey),
    );
    Map<String, String> appInfo = {};
    Map<String, String> pyInfo = {};
    try { appInfo = await _bridge.getAppInfo(); } catch (_) {}
    if (runtimeBackend == RuntimeManager.linuxLikeBackendId) {
      try {
        final linuxInfo = await _bridge.getLinuxLikeRuntimeInfo();
        pyInfo = {
          'pythonVersion': linuxInfo['runtimeFlavor'] ?? 'Linux-like',
          'sitePackages': linuxInfo['userSitePackagesDir'] ?? '',
          'pythonPath': linuxInfo['pythonPath'] ?? '',
        };
      } catch (_) {}
    } else {
      try { pyInfo = await _bridge.getPythonInfo(); } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _runtimeBackend = runtimeBackend;
      _appVersion = appInfo['version'] ?? '';
      _buildNumber = appInfo['buildNumber'] ?? '';
      _pyVersion = pyInfo['pythonVersion'] ?? '';
      _sitePackages = pyInfo['sitePackages'] ?? '';
      _pythonPath = pyInfo['pythonPath'] ?? '';
      _chaquopyPipDir = pyInfo['chaquopyPipDir'] ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // ── 标题区 ──
          Center(
            child: Column(
              children: [
                Text(
                  'Python 运行器',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.onSurface),
                ),
                if (_appVersion.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'v$_appVersion · build $_buildNumber',
                    style: TextStyle(fontSize: 13, color: c.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  '本地 Python 脚本运行环境',
                  style: TextStyle(fontSize: 13, color: c.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // ── Python 环境 ──
          _AboutCard(
            icon: Icons.code_rounded,
            title: 'Python 环境',
            children: [
              _AboutItem(
                label: '引擎',
                value: _runtimeBackend == RuntimeManager.linuxLikeBackendId
                    ? 'Linux-like'
                    : 'Chaquopy',
              ),
              if (_pyVersion.isNotEmpty) _AboutItem(label: '版本', value: _pyVersion),
              if (_runtimeBackend == RuntimeManager.chaquopyBackendId && _chaquopyPipDir.isNotEmpty)
                _AboutItem(label: '安装目录', value: _chaquopyPipDir, mono: true),
              if (_runtimeBackend == RuntimeManager.chaquopyBackendId && _chaquopyPipDir.isEmpty && _sitePackages.isNotEmpty)
                _AboutItem(label: '安装目录', value: _sitePackages, mono: true),
              if (_runtimeBackend != RuntimeManager.chaquopyBackendId && _sitePackages.isNotEmpty)
                _AboutItem(label: '安装目录', value: _sitePackages, mono: true),
              if (_pythonPath.isNotEmpty) _AboutItem(label: '路径', value: _pythonPath, mono: true),
            ],
          ),
          const SizedBox(height: 12),
          // ── 关于 ──
          _AboutCard(
            icon: Icons.info_outline_rounded,
            title: '关于',
            children: [
              const _AboutItem(label: '开发者', value: '道长'),
              _AboutItem(
                label: 'GitHub',
                value: 'github.com/daozhang66/python_runner',
                onTap: () => _bridge.openUrl('https://github.com/daozhang66/python_runner'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── 技术架构 ──
          _AboutCard(
            icon: Icons.architecture_rounded,
            title: '技术架构',
            children: [
              const _AboutItem(label: '框架', value: 'Flutter + Dart · Material 3 · Provider'),
              const _AboutItem(label: '运行引擎',
                  value: 'Chaquopy (Python 3.11) / Linux-like (Debian proot) 可切换'),
              const _AboutItem(label: '原生层', value: 'Kotlin · MethodChannel + EventChannel 双向通信'),
              const _AboutItem(label: '存储', value: 'SharedPreferences + SQLite + 文件系统'),
              const _AboutItem(label: '运行要求', value: 'Android 8.0+ · arm64-v8a'),
            ],
          ),
        ],
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;
  const _AboutCard({required this.icon, required this.title, required this.children});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: c.primary),
                const SizedBox(width: 8),
                Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.onSurface)),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _AboutItem extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  final VoidCallback? onTap;
  const _AboutItem({required this.label, required this.value, this.mono = false, this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 70,
              child: Text(label, style: TextStyle(fontSize: 12.5, color: c.onSurfaceVariant)),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 12.5,
                  color: c.onSurface,
                  fontFamily: mono ? 'monospace' : null,
                ),
              ),
            ),
            if (onTap != null) Icon(Icons.chevron_right, size: 16, color: c.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

