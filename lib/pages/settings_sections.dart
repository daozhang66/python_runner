// ignore_for_file: invalid_use_of_protected_member

part of 'settings_page.dart';

extension _SettingsSections on _SettingsPageState {
  Widget _buildRuntimeSection() {
    return Column(
      children: [
        _SectionCard(
          icon: Icons.memory,
          title: '运行引擎',
          children: [
            ListTile(
              leading: const Icon(Icons.memory),
              title: const Text('运行引擎'),
              subtitle: Text(
                _runtimeBackend == RuntimeManager.chaquopyBackendId
                    ? 'Chaquopy（默认）'
                    : 'Linux-like（实验）',
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _showRuntimeBackendPicker,
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
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('管理引擎'),
              subtitle: Text(
                _linuxLikeAvailable
                    ? 'Linux-like 运行引擎已安装'
                    : '安装 Linux-like 运行引擎',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RuntimeManagerPage(),
                  ),
                );
              },
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
                      Text(
                        '留空使用官方源',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
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
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _saveMirror,
                        icon: const Icon(Icons.save),
                      ),
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
                          fontWeight: FontWeight.w500,
                        ),
                      ),
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
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('工作目录'),
              subtitle: Text(
                _workingDir ?? '默认：/storage/emulated/0/Download/PythonRunner',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: _pickWorkingDir,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '脚本运行时的文件读写目录',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.drive_folder_upload_outlined),
              title: const Text('脚本导出目录'),
              subtitle: Text(
                _exportDir ?? '默认：下载目录',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: _pickExportDir,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNetworkDebugSection() {
    return Column(
      children: [
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
                secondary: Icon(
                  Icons.lock_open,
                  color: _netAllowInsecure
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
                title: const Text('允许不安全证书'),
                subtitle: Text(
                  _netAllowInsecure
                      ? '已开启 — 将信任自签名/抓包证书（降低安全性）'
                      : '关闭 — 严格校验SSL证书',
                  style: TextStyle(
                    fontSize: 12,
                    color: _netAllowInsecure
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
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
                                horizontal: 12,
                                vertical: 10,
                              ),
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
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              hintText: '8888',
                              labelText: '端口',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _saveProxyConfig,
                          icon: const Icon(Icons.save),
                        ),
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
              secondary: Icon(
                Icons.tune,
                color: _overrideEnabled
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              title: const Text('启用请求覆盖'),
              subtitle: Text(
                _overrideEnabled
                    ? '已开启 — 全局覆盖将应用到所有 Python HTTP 请求'
                    : '关闭 — 不修改脚本的默认请求行为',
                style: TextStyle(
                  fontSize: 12,
                  color: _overrideEnabled
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
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
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('确认启用'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                }
                await RequestOverrideConfig.instance.setOverrideEnabled(v);
                setState(() => _overrideEnabled = v);
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDiagnosticsSection() {
    return Column(
      children: [
        _SectionCard(
          icon: Icons.build_outlined,
          title: '系统工具',
          children: [
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: const Text('应用日志'),
              subtitle: const Text('查看和筛选系统日志、崩溃日志、脚本错误',
                  style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AppLogsPage(),
                ),
              ),
              onLongPress: _viewSystemLogs,
            ),
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('导出完整日志'),
              subtitle: const Text('导出完整诊断日志到工作目录，未设置则使用默认目录',
                  style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _exportSystemLogs,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAboutSection() {
    return Column(
      children: [
        _SectionCard(
          icon: Icons.info_outline,
          title: '关于',
          children: [
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('使用手册'),
              subtitle: const Text('功能说明与操作指南', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const _UserManualPage()),
              ),
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
              subtitle: const Text('从 GitHub Releases 获取最新 APK',
                  style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _checkingUpdate ? null : _checkForUpdates,
            ),
            ListTile(
              leading: const Icon(Icons.history_outlined),
              title: const Text('更新日志'),
              subtitle: const Text('查看 GitHub Releases 历史版本',
                  style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openUpdateLogPage,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.update_outlined),
              title: const Text('启动时自动检查更新'),
              subtitle:
                  const Text('每次启动应用时自动检查更新', style: TextStyle(fontSize: 12)),
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
          title: const Text('主题与配色'),
          subtitle: const Text('主题模式、Material You、配色方案、自定义颜色、字体',
              style: TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ThemeSettingsPage(),
            ),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.bubble_chart),
          title: const Text('悬浮球'),
          subtitle: const Text('常驻显示运行状态，点击展开面板，长按查看详情',
              style: TextStyle(fontSize: 12)),
          value: _floatingBallEnabled,
          onChanged: _setFloatingBallEnabled,
        ),
      ],
    );
  }
}
