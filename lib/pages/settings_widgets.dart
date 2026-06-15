part of 'settings_page.dart';

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _SectionCard(
      {required this.icon, required this.title, required this.children});

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
                  Text(title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.primary,
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
      final matchesLevel =
          _levelFilter == 'ALL' || lower.contains(_levelFilter.toLowerCase());
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
    final isEmpty = widget.logContent.isEmpty ||
        filtered.trim().isEmpty ||
        widget.logContent.startsWith('(暂无');
    return Scaffold(
      appBar: AppBar(
        title: const Text('系统日志'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: filtered));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('已复制当前日志内容'), duration: Duration(seconds: 1)),
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
                    initialValue: _levelFilter,
                    decoration: const InputDecoration(labelText: '级别'),
                    items: const ['ALL', 'INFO', 'WARN', 'ERROR']
                        .map((level) =>
                            DropdownMenuItem(value: level, child: Text(level)))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _levelFilter = value ?? 'ALL'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _sectionFilter,
                    decoration: const InputDecoration(labelText: '区块'),
                    items: _sectionFilters
                        .map((section) => DropdownMenuItem(
                            value: section, child: Text(section)))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _sectionFilter = value ?? '全部'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: isEmpty
                ? const Center(
                    child: Text('暂无匹配日志', style: TextStyle(color: Colors.grey)))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      filtered,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 11),
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
    return Scaffold(
      appBar: AppBar(title: const Text('使用手册')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: const [
          _ManualSection(
            icon: Icons.code,
            title: '脚本列表',
            items: [
              _ManualItem(Icons.add, '新建脚本', '右上角菜单进入添加脚本，可创建空白 Python 脚本'),
              _ManualItem(
                  Icons.file_open, '导入脚本', '右上角菜单进入添加脚本，可从设备选择 .py 文件导入'),
              _ManualItem(Icons.account_tree_outlined, '新建项目',
                  '切换并安装 Linux-like 运行引擎后，右上角菜单可创建项目型脚本组'),
              _ManualItem(Icons.archive_outlined, '导入项目 ZIP',
                  'Linux-like 下可导入项目 ZIP，导入后选择或确认项目主程序'),
              _ManualItem(Icons.create_new_folder_outlined, '添加分组',
                  '右上角菜单创建应用内逻辑分组，不移动真实 .py 文件'),
              _ManualItem(Icons.folder_outlined, '分组管理',
                  '点击文件夹或项目卡片进入；长按可重命名、删除或进入批量管理'),
              _ManualItem(Icons.flag_outlined, '项目主程序',
                  '项目页可设置主程序、运行项目、导入/导出 ZIP；根目录存在 requirements.txt 时可安装依赖'),
              _ManualItem(Icons.drive_file_move_outline, '移动到分组',
                  '多选脚本或长按单个脚本可移动到分组；分组较多时列表可滚动并可拖拽展开'),
              _ManualItem(
                  Icons.home_outlined, '移出到首页', '分组内脚本可移回首页，未分组普通脚本会直接显示在首页'),
              _ManualItem(Icons.play_arrow, '快捷运行', '列表/宫格中直接点击 ▶ 按钮运行脚本'),
              _ManualItem(Icons.search, '搜索', '按名称快速过滤脚本'),
              _ManualItem(
                  Icons.checklist, '多选管理', '右上角菜单进入脚本多选；分组批量删除从文件夹长按菜单进入'),
              _ManualItem(Icons.push_pin, '置顶脚本', '长按脚本可置顶/取消置顶，置顶脚本始终显示在首页前方'),
              _ManualItem(Icons.drag_indicator, '拖拽排序',
                  '首页和分组内的未置顶脚本可拖拽排序；置顶脚本、普通分组和项目卡片不可拖动'),
              _ManualItem(Icons.grid_view, '视图切换', '列表/宫格视图切换'),
              _ManualItem(Icons.visibility_outlined, '隐藏脚本名',
                  '首页眼睛按钮可隐藏真实脚本名，适合演示或录屏时保护隐私'),
              _ManualItem(Icons.more_vert, '长按脚本', '重命名、复制、导出、删除'),
            ],
          ),
          SizedBox(height: 12),
          _ManualSection(
            icon: Icons.edit_note,
            title: '代码编辑器',
            items: [
              _ManualItem(Icons.lock, '只读/编辑', '锁图标切换，默认只读防误触'),
              _ManualItem(Icons.search, '代码搜索', '搜索关键字，上下跳转匹配'),
              _ManualItem(Icons.pinch, '字体大小', '双指捏合缩放编辑器字号'),
              _ManualItem(Icons.save, '保存', '修改后出现，点击保存'),
              _ManualItem(Icons.play_arrow, '运行脚本', '点击 ▶ 按钮保存并运行，自动跳转全屏终端'),
              _ManualItem(Icons.fullscreen, '全屏终端', '点击全屏图标直接打开终端页面'),
              _ManualItem(Icons.undo, '编辑工具栏', '编辑模式下底部工具栏提供缩进、撤回、重做'),
            ],
          ),
          SizedBox(height: 12),
          _ManualSection(
            icon: Icons.terminal,
            title: '全屏终端',
            items: [
              _ManualItem(Icons.play_arrow, '运行/停止', '运行中显示停止按钮和计时，结束后显示重运行按钮'),
              _ManualItem(Icons.search, '搜索日志', '点击搜索按钮，实时过滤日志内容'),
              _ManualItem(
                  Icons.error_outline, '只看错误', '搜索栏内点击错误图标，快速过滤 stderr/error'),
              _ManualItem(
                  Icons.palette_outlined, '终端主题', '右上角菜单可切换深色、浅色、跟随系统和单色终端主题'),
              _ManualItem(Icons.copy, '复制日志', '工具栏一键复制全部日志'),
              _ManualItem(Icons.pinch, '字体大小', '双指捏合缩放终端字号'),
              _ManualItem(Icons.delete_outline, '清空', '清除终端输出'),
              _ManualItem(Icons.chevron_right, '交互输入', 'input() 时底部出现输入框，自动聚焦'),
              _ManualItem(Icons.notifications, '运行通知', '前台通知显示脚本名称和运行时长'),
            ],
          ),
          SizedBox(height: 12),
          _ManualSection(
            icon: Icons.touch_app_outlined,
            title: '底部导航',
            items: [
              _ManualItem(Icons.touch_app, '点击切换', '点击底部按钮可切换脚本、网络和库管理页面'),
            ],
          ),
          SizedBox(height: 12),
          _ManualSection(
            icon: Icons.bubble_chart,
            title: '悬浮球',
            items: [
              _ManualItem(Icons.play_arrow, '状态指示',
                  '灰色=空闲，旋转=运行中，红色=报错，橙色=等待输入；不同状态显示对应图标'),
              _ManualItem(Icons.touch_app, '点击操作', '折叠时点击展开悬浮球；展开时点击显示/隐藏信息面板'),
              _ManualItem(Icons.open_in_full, '长按展开',
                  '长按显示信息面板：运行中查看脚本名、实时计时和停止按钮；空闲时查看最近运行的脚本列表'),
              _ManualItem(Icons.history, '快捷运行', '空闲面板显示最近 5 个脚本，点击即可快速重新运行'),
              _ManualItem(
                  Icons.swap_vert, '贴边收起', '松手自动贴向最近屏幕边缘并保留可见把手；点击或长按可重新展开'),
              _ManualItem(Icons.swipe, '拖拽移动', '拖动悬浮球到屏幕任意位置，松手自动贴边'),
              _ManualItem(Icons.delete_outline, '拖拽停止', '运行中拖到底部停止区域松手可快速停止脚本'),
              _ManualItem(Icons.settings, '开关控制',
                  '在设置页开启或关闭；开启后完整显示约 5 秒，随后自动贴边收起，关闭后消失'),
              _ManualItem(
                  Icons.security, '权限', '首次开启需授予「显示在其他应用上层」权限；显示失败时会提示原因并关闭开关'),
            ],
          ),
          SizedBox(height: 12),
          _ManualSection(
            icon: Icons.http,
            title: '网络请求调试',
            items: [
              _ManualItem(Icons.visibility_outlined, '请求查看器',
                  '底部「网络」Tab 查看 Python 网络请求记录'),
              _ManualItem(Icons.search, '搜索 URL', '顶部搜索栏实时搜索 URL / 域名关键字'),
              _ManualItem(Icons.bar_chart, '统计摘要', '显示总数、成功数、错误数、平均耗时'),
              _ManualItem(Icons.filter_list, '高级筛选', '按域名、请求方法和状态码范围筛选'),
              _ManualItem(Icons.list_alt, '请求详情', '点击单条请求查看完整请求头/响应头/响应体'),
              _ManualItem(
                  Icons.account_tree, 'JSON 树查看', '响应体支持 JSON 树状结构查看和搜索'),
              _ManualItem(Icons.tune, '请求覆盖', '设置页开启后可全局覆盖 UA/Headers/Cookie'),
              _ManualItem(Icons.code, '支持的库',
                  'requests、httpx、urllib3、urllib.request、aiohttp 会记录 HTTP；socket 记录 DNS/connect；subprocess 记录常见网络命令信息'),
              _ManualItem(Icons.bug_report_outlined, '代理调试',
                  '配合 Charles/Fiddler 外部抓包工具使用'),
            ],
          ),
          SizedBox(height: 12),
          _ManualSection(
            icon: Icons.inventory_2_outlined,
            title: '库管理',
            items: [
              _ManualItem(Icons.search, '搜索', '按名称过滤已安装的包'),
              _ManualItem(Icons.tab, '分类查看', '用户安装/内置库两个 Tab 分开显示'),
              _ManualItem(Icons.add, '安装包', '输入包名安装，可指定版本和 PyPI 源；留空使用官方源'),
              _ManualItem(Icons.playlist_add_check, 'requirements.txt',
                  '库管理页可选择 requirements.txt 批量安装，当前仅 Linux-like 运行引擎支持'),
              _ManualItem(
                  Icons.delete_outline, '卸载包', '用户安装的包点击删除按钮卸载；支持清理其孤儿依赖'),
              _ManualItem(Icons.view_list_outlined, '用户安装列表',
                  '随当前运行引擎显示包列表；用户安装页仅显示顶层安装包，不显示 certifi、urllib3 等自动依赖'),
            ],
          ),
          SizedBox(height: 12),
          _ManualSection(
            icon: Icons.settings,
            title: '设置',
            items: [
              _ManualItem(
                  Icons.palette_outlined, '主题模式', '点击后选择浅色 / 跟随系统 / 深色'),
              _ManualItem(Icons.colorize_outlined, '配色方案',
                  '关闭 Material You 后可选预设主题，也可在更多颜色卡片中选择颜色或把自定义颜色添加到末尾'),
              _ManualItem(Icons.color_lens_outlined, 'Material You',
                  'Android 12+ 可跟随系统壁纸动态取色'),
              _ManualItem(Icons.tune_outlined, '高级外观', '可调整色彩算法、对话框毛玻璃效果和应用字体'),
              _ManualItem(
                  Icons.bubble_chart, '悬浮球', '开启后显示悬浮球，支持贴边收起、快捷运行最近脚本、拖拽停止等'),
              _ManualItem(Icons.memory, '运行引擎',
                  '支持 Chaquopy 和 Linux-like 两种运行引擎；Linux-like 可在管理引擎页安装或修复'),
              _ManualItem(Icons.inventory_2_outlined, 'PyPI 源',
                  'pip 安装索引地址；留空使用官方源，也可一键恢复官方源'),
              _ManualItem(Icons.timer_outlined, '执行超时', '脚本最长运行时间（可设为无限制）'),
              _ManualItem(Icons.work_outline, '工作目录', '脚本中 open() 等相对路径的基准目录'),
              _ManualItem(Icons.folder_outlined, '导出目录', '脚本导出目标文件夹'),
              _ManualItem(Icons.update_outlined, '自动更新', '每次启动检查更新，可在设置中开关'),
              _ManualItem(
                  Icons.history_outlined, '更新日志', '查看 GitHub Releases 历史版本'),
              _ManualItem(
                  Icons.bug_report_outlined, '网络调试模式', '代理/SSL 配置，用于外部抓包工具'),
              _ManualItem(
                  Icons.visibility_outlined, '记录网络请求', '捕获 Python 脚本的网络活动'),
              _ManualItem(Icons.tune, '请求覆盖', '全局覆盖 UA/Headers/Cookie/超时/重定向'),
              _ManualItem(Icons.article_outlined, '应用日志',
                  '应用日志页可搜索、筛选、导出到剪贴板并清空；设置页另可导出完整诊断日志'),
            ],
          ),
          SizedBox(height: 12),
          _ManualSection(
            icon: Icons.extension_outlined,
            title: '自定义 Python 库',
            items: [
              _ManualItem(Icons.folder_outlined, '添加存储',
                  'MT管理器侧拉栏点击 ⋮ → 添加本地存储 → 点击 ≡ 找到 Python运行器 → 使用此文件夹'),
              _ManualItem(Icons.code, 'Chaquopy 库目录',
                  '添加后进入 files → chaquopy → pip，pip 安装的包和自定义库都在这里'),
              _ManualItem(Icons.code, 'Linux-like 库目录',
                  '添加后进入 files → linux_like → user_site_packages，Linux-like 用户安装库和自定义库都在这里'),
              _ManualItem(Icons.create_new_folder, '创建库文件',
                  '在库目录中新建 .py 文件（如 mylib.py），编写代码保存即可'),
              _ManualItem(Icons.play_arrow, '脚本中引用',
                  '放入当前引擎对应库目录后可直接 import mylib，也可创建包目录 mylib/__init__.py'),
              _ManualItem(Icons.cleaning_services_outlined, '缓存目录',
                  'Linux-like 运行时会把 Python 字节码缓存放到执行临时目录，并清理脚本/项目根目录的 __pycache__ 残留'),
              _ManualItem(Icons.warning_amber, '注意事项',
                  '两个引擎的库目录互相独立，切换引擎后需进入对应目录操作；修改后无需重启 APP'),
            ],
          ),
          SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _ManualSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<_ManualItem> items;

  const _ManualSection(
      {required this.icon, required this.title, required this.items});

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
            Text(title,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.primary)),
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
                          TextSpan(
                              text: '${item.label}  ',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
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
    try {
      appInfo = await _bridge.getAppInfo();
    } catch (_) {}
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
      try {
        pyInfo = await _bridge.getPythonInfo();
      } catch (_) {}
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
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: c.onSurface),
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
              if (_pyVersion.isNotEmpty)
                _AboutItem(label: '版本', value: _pyVersion),
              if (_runtimeBackend == RuntimeManager.chaquopyBackendId &&
                  _chaquopyPipDir.isNotEmpty)
                _AboutItem(label: '安装目录', value: _chaquopyPipDir, mono: true),
              if (_runtimeBackend == RuntimeManager.chaquopyBackendId &&
                  _chaquopyPipDir.isEmpty &&
                  _sitePackages.isNotEmpty)
                _AboutItem(label: '安装目录', value: _sitePackages, mono: true),
              if (_runtimeBackend != RuntimeManager.chaquopyBackendId &&
                  _sitePackages.isNotEmpty)
                _AboutItem(label: '安装目录', value: _sitePackages, mono: true),
              if (_pythonPath.isNotEmpty)
                _AboutItem(label: '路径', value: _pythonPath, mono: true),
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
                onTap: () => _bridge
                    .openUrl('https://github.com/daozhang66/python_runner'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── 技术架构 ──
          const _AboutCard(
            icon: Icons.architecture_rounded,
            title: '技术架构',
            children: [
              _AboutItem(
                  label: '框架', value: 'Flutter + Dart · Material 3 · Provider'),
              _AboutItem(
                  label: '运行引擎',
                  value:
                      'Chaquopy (Python 3.11) / Linux-like (Debian proot) 可切换'),
              _AboutItem(
                  label: '原生层',
                  value: 'Kotlin · MethodChannel + EventChannel 双向通信'),
              _AboutItem(
                  label: '存储', value: 'SharedPreferences + SQLite + 文件系统'),
              _AboutItem(label: '运行要求', value: 'Android 8.0+ · arm64-v8a'),
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
  const _AboutCard(
      {required this.icon, required this.title, required this.children});
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
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.onSurface)),
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
  const _AboutItem(
      {required this.label,
      required this.value,
      this.mono = false,
      this.onTap});
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
              child: Text(label,
                  style: TextStyle(fontSize: 12.5, color: c.onSurfaceVariant)),
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
            if (onTap != null)
              Icon(Icons.chevron_right, size: 16, color: c.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
