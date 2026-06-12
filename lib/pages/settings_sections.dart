// ignore_for_file: invalid_use_of_protected_member

part of 'settings_page.dart';

extension _SettingsSections on _SettingsPageState {
  Widget _buildRuntimeSection() {
    return Column(
      children: [
        // ── Runtime Engine ──
        _SectionCard(
          icon: Icons.memory,
          title: '运行引擎',
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: DropdownButtonFormField<String>(
                key: ValueKey('$_runtimeBackend-$_engineDropdownKey'),
                initialValue: _runtimeBackend,
                borderRadius: BorderRadius.circular(16),
                dropdownColor:
                    Theme.of(context).colorScheme.surfaceContainerHigh,
                iconEnabledColor: Theme.of(context).colorScheme.primary,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  labelText: '运行引擎',
                  prefixIcon: const Icon(Icons.memory),
                  border: const OutlineInputBorder(gapPadding: 0),
                  isDense: true,
                  filled: true,
                  fillColor: AppThemeColors.softSurface(
                    Theme.of(context).colorScheme,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
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
                      Text('PyPI 源',
                          style: Theme.of(context).textTheme.titleSmall),
                      const Spacer(),
                      Text('留空使用官方源',
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
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
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                          onPressed: _saveMirror, icon: const Icon(Icons.save)),
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
                      Text('执行超时时间',
                          style: Theme.of(context).textTheme.titleSmall),
                      const Spacer(),
                      Text(
                          _timeout == 0
                              ? '无限制'
                              : _timeout >= 3600
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
                    value: _timeout == 0
                        ? 0
                        : _timeout <= 60
                            ? _timeout.toDouble()
                            : _timeout <= 600
                                ? 60 + (_timeout - 60) * 40 / 540
                                : _timeout <= 3600
                                    ? 100 + (_timeout - 600) * 40 / 3000
                                    : 140 + (_timeout - 3600) * 10 / 32400,
                    min: 0,
                    max: 150,
                    divisions: 150,
                    label: _timeout == 0
                        ? '无限制'
                        : _timeout >= 3600
                            ? '${(_timeout / 3600).toStringAsFixed(1)}h'
                            : _timeout >= 60
                                ? '${(_timeout / 60).toStringAsFixed(0)}m'
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
                      Text('工作目录',
                          style: Theme.of(context).textTheme.titleSmall),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('脚本运行时的文件读写目录，留空使用默认',
                      style: TextStyle(
                          fontSize: 11,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _workingDirController,
                          decoration: const InputDecoration(
                            hintText:
                                '/storage/emulated/0/Download/PythonRunner',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                          onPressed: _pickWorkingDir,
                          icon: const Icon(Icons.folder_open)),
                      IconButton(
                          onPressed: _saveWorkingDir,
                          icon: const Icon(Icons.save)),
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
                      style: TextStyle(
                          fontSize: 11,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _exportDirController,
                          decoration: const InputDecoration(
                            hintText:
                                '/storage/emulated/0/Download/PythonRunner',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                          onPressed: _pickExportDir,
                          icon: const Icon(Icons.folder_open)),
                      IconButton(
                          onPressed: _saveExportDir,
                          icon: const Icon(Icons.save)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNetworkDebugSection() {
    return Column(
      children: [
        // ── Network ──
        _SectionCard(
          icon: Icons.http,
          title: '网络',
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.developer_mode),
              title: const Text('网络调试模式'),
              subtitle:
                  const Text('开启后可配置代理和证书选项', style: TextStyle(fontSize: 12)),
              value: _netDebugMode,
              onChanged: _toggleNetDebugMode,
            ),
            if (_netDebugMode) ...[
              SwitchListTile(
                secondary: Icon(Icons.lock_open,
                    color: _netAllowInsecure
                        ? Theme.of(context).colorScheme.error
                        : null),
                title: const Text('允许不安全证书'),
                subtitle: Text(
                  _netAllowInsecure
                      ? '已开启 — 将信任自签名/抓包证书（降低安全性）'
                      : '关闭 — 严格校验SSL证书',
                  style: TextStyle(
                      fontSize: 12,
                      color: _netAllowInsecure
                          ? Theme.of(context).colorScheme.error
                          : null),
                ),
                value: _netAllowInsecure,
                onChanged: _toggleAllowInsecure,
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('代理配置（可选）',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    const Text('填写后网络请求将通过指定代理',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
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
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
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
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            decoration: const InputDecoration(
                              hintText: '8888',
                              labelText: '端口',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                            onPressed: _saveProxyConfig,
                            icon: const Icon(Icons.save)),
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
              subtitle: const Text('捕获 HTTP、DNS、socket 与常见网络命令',
                  style: TextStyle(fontSize: 12)),
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
                subtitle: const Text('文本前 10 MB，图片最大 30 MB（增加内存占用）',
                    style: TextStyle(fontSize: 12)),
                value: _recordResponseBody,
                onChanged: (v) async {
                  await RequestOverrideConfig.instance.setRecordResponseBody(v);
                  setState(() => _recordResponseBody = v);
                },
              ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            SwitchListTile(
              secondary: Icon(Icons.tune,
                  color: _overrideEnabled
                      ? Theme.of(context).colorScheme.primary
                      : null),
              title: const Text('启用请求覆盖'),
              subtitle: Text(
                _overrideEnabled
                    ? '已开启 — 全局覆盖将应用到所有 Python HTTP 请求'
                    : '关闭 — 不修改脚本的默认请求行为',
                style: TextStyle(
                    fontSize: 12,
                    color: _overrideEnabled
                        ? Theme.of(context).colorScheme.primary
                        : null),
              ),
              value: _overrideEnabled,
              onChanged: (v) async {
                if (v && mounted) {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      backgroundColor:
                          Theme.of(ctx).colorScheme.surfaceContainerHigh,
                      surfaceTintColor: Colors.transparent,
                      title: const Text('启用请求覆盖'),
                      content: const Text(
                        '开启后将全局覆盖 Python 脚本中 HTTP 请求的 '
                        'User-Agent、Headers、Cookie、超时等设置。\n\n'
                        '这会修改脚本的实际网络行为，仅建议在调试时使用。',
                      ),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('取消')),
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('确认启用')),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                }
                await RequestOverrideConfig.instance.setOverrideEnabled(v);
                setState(() => _overrideEnabled = v);
              },
            ),
            if (_requestConfigError != null)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 18,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _requestConfigError!,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_overrideEnabled) ...[
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('全局 User-Agent',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
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
                              hintText:
                                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) ...',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () async {
                            await RequestOverrideConfig.instance
                                .setGlobalUserAgent(_globalUaController.text);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('User-Agent 已保存'),
                                  duration: Duration(seconds: 1)),
                            );
                          },
                          icon: const Icon(Icons.save),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('全局额外请求头',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
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
                              hintText:
                                  '{"Accept-Language":"zh-CN","X-Custom":"value"}',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () async {
                            final text = _globalHeadersController.text.trim();
                            try {
                              await RequestOverrideConfig.instance
                                  .setGlobalHeaders(text);
                            } on FormatException catch (e) {
                              if (!mounted) return;
                              setState(() {
                                _requestConfigError =
                                    RequestOverrideConfig.instance.configError;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(e.message),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                              return;
                            }
                            if (!mounted) return;
                            setState(() {
                              _requestConfigError =
                                  RequestOverrideConfig.instance.configError;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('全局请求头已保存'),
                                  duration: Duration(seconds: 1)),
                            );
                          },
                          icon: const Icon(Icons.save),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('全局 Cookie',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
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
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () async {
                            await RequestOverrideConfig.instance
                                .setGlobalCookie(_globalCookieController.text);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Cookie 已保存'),
                                  duration: Duration(seconds: 1)),
                            );
                          },
                          icon: const Icon(Icons.save),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('默认 HTTP 超时',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500)),
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
                      onChanged: (v) =>
                          setState(() => _defaultHttpTimeout = v.round()),
                      onChangeEnd: (v) async {
                        await RequestOverrideConfig.instance
                            .setDefaultTimeout(v.round());
                      },
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.redo),
                title: const Text('跟随重定向'),
                subtitle: const Text('是否自动跟随 HTTP 重定向',
                    style: TextStyle(fontSize: 12)),
                value: _followRedirects,
                onChanged: (v) async {
                  await RequestOverrideConfig.instance.setFollowRedirects(v);
                  setState(() => _followRedirects = v);
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.vpn_lock),
                title: const Text('强制使用代理'),
                subtitle: const Text('将代理配置强制应用到 Python HTTP 请求',
                    style: TextStyle(fontSize: 12)),
                value: _forceProxy,
                onChanged: (v) async {
                  await RequestOverrideConfig.instance.setForceProxy(v);
                  setState(() => _forceProxy = v);
                },
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildDiagnosticsSection() {
    return Column(
      children: [
        // ── System Tools ──
        _SectionCard(
          icon: Icons.build_outlined,
          title: '系统工具',
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('查看完整日志'),
              subtitle: const Text('查看完整诊断日志、崩溃日志和脚本错误',
                  style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _viewSystemLogs,
            ),
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('导出完整日志'),
              subtitle: const Text('导出完整诊断日志到工作目录，未设置则使用默认目录',
                  style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _exportSystemLogs,
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: const Text('清空系统日志'),
              subtitle:
                  const Text('删除所有系统日志文件', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _clearSystemLogs,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAboutSection() {
    return Column(
      children: [
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
            ListTile(
              leading: const Icon(Icons.history_outlined),
              title: const Text('更新日志'),
              subtitle: const Text(
                '查看 GitHub Releases 历史版本',
                style: TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openUpdateLogPage,
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
    );
  }

  Widget _buildAppearanceSection() {
    return _SectionCard(
      icon: Icons.tune,
      title: '通用',
      children: [
        ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: const Text('主题模式'),
          subtitle: Text(
            switch (widget.currentThemeMode) {
              ThemeMode.light => '当前：浅色',
              ThemeMode.dark => '当前：深色',
              ThemeMode.system => '当前：跟随系统',
            },
            style: const TextStyle(fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _showThemeModePicker,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.color_lens_outlined),
          title: const Text('Material You'),
          subtitle: const Text('Android 12+ 跟随系统壁纸动态取色；关闭后可使用下方自定义配色',
              style: TextStyle(fontSize: 12)),
          value: widget.currentMaterialYouEnabled,
          onChanged: widget.onMaterialYouChanged,
        ),
        ListTile(
          leading: const Icon(Icons.colorize_outlined),
          title: const Text('配色方案'),
          subtitle: Text(
            widget.currentMaterialYouEnabled
                ? '当前由 Material You 接管；关闭后可切换海蓝、青玉、Claude、Codex'
                : '当前：${widget.currentThemePalette.label} · ${widget.currentThemePalette.description}',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: Icon(
            widget.currentMaterialYouEnabled
                ? Icons.block_outlined
                : Icons.chevron_right,
          ),
          onTap:
              widget.currentMaterialYouEnabled ? null : _showThemePalettePicker,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.bubble_chart),
          title: const Text('悬浮球'),
          subtitle: const Text('脚本运行时显示悬浮球，点击返回应用，长按查看详情',
              style: TextStyle(fontSize: 12)),
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
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      title: const Text('需要悬浮窗权限'),
                      content: const Text('悬浮球需要「显示在其他应用上层」权限。\n\n'
                          '点击确认后，请在系统设置中开启此权限。'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('取消')),
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('去设置')),
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
            if (!mounted) return;
            setState(() => _floatingBallEnabled = v);
            if (v) {
              try {
                await _bridge.showFloatingBall('');
              } catch (_) {}
            } else {
              try {
                await _bridge.hideFloatingBall();
              } catch (_) {}
            }
          },
        ),
      ],
    );
  }
}
