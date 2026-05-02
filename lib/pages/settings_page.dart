import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import '../services/native_bridge.dart';
import '../services/app_logger.dart';
import '../services/network_debug_config.dart';
import '../services/request_override_config.dart';

class SettingsPage extends StatefulWidget {
  final ValueChanged<ThemeMode> onThemeChanged;
  final ThemeMode currentThemeMode;

  const SettingsPage({
    super.key,
    required this.onThemeChanged,
    required this.currentThemeMode,
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
  int _timeout = 60;
  bool _graphicsEnabled = false;
  bool _netDebugMode = false;
  bool _netAllowInsecure = false;
  bool _overrideEnabled = false;
  bool _recordRequests = true;
  bool _recordResponseBody = false;
  int _defaultHttpTimeout = 30;
  bool _followRedirects = true;
  bool _forceProxy = false;
  final _bridge = NativeBridge();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final overrideCfg = RequestOverrideConfig.instance;
    await overrideCfg.load();
    setState(() {
      _mirrorController.text = prefs.getString('pypi_index_url') ?? '';
      _timeout = prefs.getInt('execution_timeout') ?? 60;
      _graphicsEnabled = prefs.getBool('graphics_engine_enabled') ?? true;
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
    });
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
        const SnackBar(content: Text('镜像源已保存'), duration: Duration(seconds: 1)),
      );
    }
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
              child: Text('确认启用', style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
    final logContent = AppLogger.instance.readRecentLogs(count: 100);
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => _SystemLogViewPage(logContent: logContent)));
  }

  Future<void> _exportSystemLogs() async {
    try {
      final content = await AppLogger.instance.exportAll();
      final path = await _bridge.exportLog(content);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('系统日志已导出到: $path'), duration: const Duration(seconds: 3)),
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

  Future<void> _showAboutDialog() async {
    Map<String, String> pythonInfo = {};
    try {
      pythonInfo = await _bridge.getPythonInfo();
    } catch (_) {}
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('关于'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Python 运行器', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              const Text('版本 1.3.1', style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 10),
              const Text('安卓端 Python 脚本运行环境，主要功能：'),
              const SizedBox(height: 4),
              const Text('• 代码编辑器（语法高亮、搜索、缩进）'),
              const Text('• 本地运行'),
              const Text('• 交互式输入（input）支持'),
              const Text('• 图形引擎（scene 模块，游戏/动画）'),
              const Text('• pip 包管理（安装/卸载）'),
              const Text('• 50+ 内置 Python 库'),
              const Text('• 运行日志历史与导出'),
              const Text('• 脚本导入/导出/批量管理'),
              const Text('• 网络请求查看器（requests/httpx/urllib3）'),
              const Text('• 全局请求覆盖（UA/Headers/Cookie/超时）'),
              const Text('• 代理 & SSL 调试（Charles/Fiddler/抓包）'),
              const Divider(height: 20),
              const Text('Python 环境', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              _infoRow('Python 版本', pythonInfo['pythonVersion'] ?? '获取失败'),
              _infoRow('库安装目录', pythonInfo['sitePackages'] ?? '获取失败'),
              _infoRow('Python 路径', pythonInfo['pythonPath'] ?? '获取失败'),
              const Divider(height: 20),
              const Text('技术栈', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('• Flutter + Material 3'),
              const Text('• Chaquopy（Python 运行时）'),
              const Text('• CustomPaint（图形渲染）'),
              const Divider(height: 20),
              const Text('开发者', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              const Text('道长'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('确定')),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Future<void> _showSimpleAboutDialog() async {
    Map<String, String> appInfo = {};
    Map<String, String> pythonInfo = {};
    try {
      appInfo = await _bridge.getAppInfo();
    } catch (_) {}
    try {
      pythonInfo = await _bridge.getPythonInfo();
    } catch (_) {}
    if (!mounted) return;

    final appName = appInfo['appName']?.trim().isNotEmpty == true
        ? appInfo['appName']!
        : 'Python 运行器';
    final version = appInfo['version']?.trim().isNotEmpty == true
        ? appInfo['version']!
        : '1.3.3';
    final buildNumber = appInfo['buildNumber']?.trim().isNotEmpty == true
        ? appInfo['buildNumber']!
        : '7';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('关于'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                appName,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                '版本 $version ($buildNumber)',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              const Text(
                '面向 Android 的本地 Python 脚本运行环境，支持编辑、运行、终端交互和网络调试。',
                style: TextStyle(fontSize: 13),
              ),
              const Divider(height: 20),
              const Text('Python 环境', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              _infoRow('Python 版本', pythonInfo['pythonVersion'] ?? '获取失败'),
              _infoRow('库目录', pythonInfo['sitePackages'] ?? '获取失败'),
              _infoRow('Python 路径', pythonInfo['pythonPath'] ?? '获取失败'),
              const Divider(height: 20),
              const Text('开发者', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              const Text('道长'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
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
                secondary: const Icon(Icons.videogame_asset_outlined),
                title: const Text('图形引擎'),
                subtitle: const Text('启用 scene 模块（游戏/动画支持）', style: TextStyle(fontSize: 12)),
                value: _graphicsEnabled,
                onChanged: (v) async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('graphics_engine_enabled', v);
                  setState(() => _graphicsEnabled = v);
                },
              ),
            ],
          ),

          // ── Script ──
          _SectionCard(
            icon: Icons.code,
            title: '脚本',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('PyPI 镜像源', style: Theme.of(context).textTheme.titleSmall),
                        const Spacer(),
                        Text('留空使用默认源', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                              hintText: 'https://pypi.tuna.tsinghua.edu.cn/simple',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(onPressed: _saveMirror, icon: const Icon(Icons.save)),
                      ],
                    ),
                  ],
                ),
              ),
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
                          // 60s -> 600s (1m -> 10m), step 60s
                          val = 60 + ((v - 60) * 540 / 40).round();
                          val = (val / 60).round() * 60;
                        } else if (v <= 140) {
                          // 600s -> 3600s (10m -> 1h), step 300s
                          val = 600 + ((v - 100) * 3000 / 40).round();
                          val = (val / 300).round() * 300;
                        } else {
                          // 3600s -> 36000s (1h -> 10h), step 1800s
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
                  subtitle: const Text('记录响应内容前 2KB（增加内存占用）', style: TextStyle(fontSize: 12)),
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

          // ── Logs & Info ──
          _SectionCard(
            icon: Icons.article_outlined,
            title: '日志与信息',
            children: [
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: const Text('查看最近日志'),
                subtitle: const Text('查看内存中最近的系统日志', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _viewSystemLogs,
              ),
              ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: const Text('导出系统日志'),
                subtitle: const Text('导出完整系统日志和崩溃日志', style: TextStyle(fontSize: 12)),
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
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('使用手册'),
                subtitle: const Text('功能说明与操作指南', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const _UserManualPage())),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('关于'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showSimpleAboutDialog,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _mirrorController.dispose();
    _exportDirController.dispose();
    _workingDirController.dispose();
    _proxyHostController.dispose();
    _proxyPortController.dispose();
    _globalUaController.dispose();
    _globalHeadersController.dispose();
    _globalCookieController.dispose();
    super.dispose();
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

class _SystemLogViewPage extends StatelessWidget {
  final String logContent;
  const _SystemLogViewPage({required this.logContent});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('系统日志'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: logContent));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制系统日志'), duration: Duration(seconds: 1)),
              );
            },
            tooltip: '复制',
          ),
        ],
      ),
      body: logContent.isEmpty || logContent.startsWith('(暂无')
          ? const Center(child: Text('暂无系统日志', style: TextStyle(color: Colors.grey)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                logContent,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
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
              _ManualItem(Icons.add, '新建脚本', '点击 + 按钮创建新脚本'),
              _ManualItem(Icons.file_open, '导入脚本', '从设备选择 .py 文件导入'),
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
              _ManualItem(Icons.format_size, '字体大小', '调整编辑器字号（10-28px）'),
              _ManualItem(Icons.save, '保存', '修改后出现，点击保存'),
              _ManualItem(Icons.play_arrow, '运行脚本', '点击 ▶ 按钮保存并运行，自动跳转全屏终端'),
              _ManualItem(Icons.fullscreen, '全屏终端', '点击全屏图标直接打开终端页面'),
            ],
          ),
          const SizedBox(height: 12),
          _ManualSection(
            icon: Icons.terminal,
            title: '全屏终端',
            items: const [
              _ManualItem(Icons.play_arrow, '运行/停止', '运行中显示停止按钮，结束后显示重运行按钮'),
              _ManualItem(Icons.search, '搜索日志', '点击搜索按钮，实时过滤日志内容'),
              _ManualItem(Icons.error_outline, '只看错误', '搜索栏内点击错误图标，快速过滤 stderr/error'),
              _ManualItem(Icons.copy, '复制日志', '长按某行复制该行，或一键复制全部'),
              _ManualItem(Icons.select_all, '多行选择', '手指拖选可自由选择多行文本'),
              _ManualItem(Icons.format_size, '字体大小', '工具栏调节终端字号'),
              _ManualItem(Icons.delete_outline, '清空', '清除终端输出'),
              _ManualItem(Icons.chevron_right, '交互输入', 'input() 时底部出现输入框'),
              _ManualItem(Icons.notifications, '运行通知', '前台通知显示脚本名称和运行时长，每 10 秒更新'),
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
              _ManualItem(Icons.filter_list, '高级筛选', '按请求方法（GET/POST 等）和状态码范围筛选'),
              _ManualItem(Icons.list_alt, '请求详情', '点击单条请求查看完整请求头/响应头/响应体'),
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
              _ManualItem(Icons.add, '安装包', '输入包名安装，可指定版本和镜像源'),
              _ManualItem(Icons.delete_outline, '卸载包', '用户安装的包点击删除按钮卸载'),
            ],
          ),
          const SizedBox(height: 12),
          _ManualSection(
            icon: Icons.settings,
            title: '设置',
            items: const [
              _ManualItem(Icons.palette_outlined, '主题', '浅色/跟随系统/深色'),
              _ManualItem(Icons.videogame_asset_outlined, '图形引擎', '开启后支持 scene 模块游戏/动画'),
              _ManualItem(Icons.inventory_2_outlined, 'PyPI 镜像源', 'pip 安装镜像地址，留空用官方源'),
              _ManualItem(Icons.timer_outlined, '执行超时', '脚本最长运行时间（可设为无限制）'),
              _ManualItem(Icons.work_outline, '工作目录', '脚本中 open() 等相对路径的基准目录'),
              _ManualItem(Icons.folder_outlined, '导出目录', '脚本导出目标文件夹'),
              _ManualItem(Icons.bug_report_outlined, '网络调试模式', '代理/SSL 配置，用于外部抓包工具'),
              _ManualItem(Icons.visibility_outlined, '记录网络请求', '捕获 Python HTTP 库的真实请求'),
              _ManualItem(Icons.tune, '请求覆盖', '全局覆盖 UA/Headers/Cookie/超时/重定向'),
              _ManualItem(Icons.article_outlined, '系统日志', '查看、导出或清空运行日志和崩溃日志'),
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
