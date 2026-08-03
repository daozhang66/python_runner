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
  late List<_LogLineRange> _allLines;
  List<_LogLineRange> _filteredLines = const [];
  Timer? _searchDebounce;

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

  @override
  void initState() {
    super.initState();
    _allLines = _indexLogLines(widget.logContent);
    _refreshFilteredLines();
  }

  @override
  void didUpdateWidget(covariant _SystemLogViewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.logContent != oldWidget.logContent) {
      _searchDebounce?.cancel();
      _allLines = _indexLogLines(widget.logContent);
      _refreshFilteredLines();
    }
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(_refreshFilteredLines);
    });
  }

  void _refreshFiltersImmediately(void Function() update) {
    _searchDebounce?.cancel();
    setState(() {
      update();
      _refreshFilteredLines();
    });
  }

  void _refreshFilteredLines() {
    final query = _query.trim().toLowerCase();
    final section = _selectedSectionRange(widget.logContent);
    _filteredLines = List<_LogLineRange>.unmodifiable(_allLines.where((line) {
      if (line.start < section.start || line.start >= section.end) {
        return false;
      }
      final text = line.text(widget.logContent);
      final lower = text.toLowerCase();
      final matchesQuery = query.isEmpty || lower.contains(query);
      final matchesLevel =
          _levelFilter == 'ALL' || lower.contains(_levelFilter.toLowerCase());
      return matchesQuery && matchesLevel;
    }));
  }

  _LogTextRange _selectedSectionRange(String input) {
    if (_sectionFilter == '全部') {
      return _LogTextRange(0, input.length);
    }
    final header = '====== $_sectionFilter ======';
    final start = input.indexOf(header);
    if (start < 0) return const _LogTextRange(0, 0);
    final next = input.indexOf('====== ', start + header.length);
    return _LogTextRange(start, next < 0 ? input.length : next);
  }

  List<_LogLineRange> _indexLogLines(String input) {
    if (input.isEmpty) return const [];
    final lines = <_LogLineRange>[];
    var start = 0;
    while (start <= input.length) {
      final next = input.indexOf('\n', start);
      final end = next < 0 ? input.length : next;
      lines.add(_LogLineRange(start, end));
      if (next < 0) break;
      start = next + 1;
    }
    return List<_LogLineRange>.unmodifiable(lines);
  }

  String _joinedFilteredContent() {
    final buffer = StringBuffer();
    for (var index = 0; index < _filteredLines.length; index++) {
      if (index > 0) buffer.write('\n');
      buffer.write(_filteredLines[index].text(widget.logContent));
    }
    return buffer.toString();
  }

  void _copyFilteredContent() {
    _searchDebounce?.cancel();
    setState(_refreshFilteredLines);
    Clipboard.setData(ClipboardData(text: _joinedFilteredContent()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.logsCopiedCurrent),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = widget.logContent.isEmpty ||
        _filteredLines.isEmpty ||
        widget.logContent.startsWith('(暂无');
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.systemLogs),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: _copyFilteredContent,
            tooltip: AppLocalizations.of(context)!.copy,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: AppLocalizations.of(context)!.searchLogsLabel,
                hintText: AppLocalizations.of(context)!.searchLogsHint,
              ),
              onChanged: _onQueryChanged,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _levelFilter,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.level,
                    ),
                    items: const ['ALL', 'INFO', 'WARN', 'ERROR']
                        .map((level) =>
                            DropdownMenuItem(value: level, child: Text(level)))
                        .toList(),
                    onChanged: (value) => _refreshFiltersImmediately(
                      () => _levelFilter = value ?? 'ALL',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _sectionFilter,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.section,
                    ),
                    items: _sectionFilters
                        .map((section) => DropdownMenuItem(
                            value: section, child: Text(section)))
                        .toList(),
                    onChanged: (value) => _refreshFiltersImmediately(
                      () => _sectionFilter = value ?? '全部',
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: isEmpty
                ? Center(
                    child: Text(
                    AppLocalizations.of(context)!.noMatchingSystemLogs,
                    style: const TextStyle(color: Colors.grey),
                  ))
                : SelectionArea(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      scrollCacheExtent: const ScrollCacheExtent.pixels(200),
                      addAutomaticKeepAlives: false,
                      addRepaintBoundaries: true,
                      itemCount: _filteredLines.length,
                      itemBuilder: (context, index) {
                        final text =
                            _filteredLines[index].text(widget.logContent);
                        return Text(
                          text.isEmpty ? '\u200B' : text,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }
}

class _LogTextRange {
  final int start;
  final int end;

  const _LogTextRange(this.start, this.end);
}

class _LogLineRange {
  final int start;
  final int end;

  const _LogLineRange(this.start, this.end);

  String text(String source) => source.substring(start, end);
}

class _AboutPage extends StatefulWidget {
  const _AboutPage();
  @override
  State<_AboutPage> createState() => _AboutPageState();
}

class _RuntimeInstallDialog extends StatefulWidget {
  const _RuntimeInstallDialog();

  @override
  State<_RuntimeInstallDialog> createState() => _RuntimeInstallDialogState();
}

class _RuntimeInstallDialogState extends State<_RuntimeInstallDialog> {
  final _bridge = NativeBridge();
  StreamSubscription? _progressSubscription;
  bool _checking = true;
  bool _installed = false;
  bool _installing = false;
  String _stage = '';
  int _percent = 0;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _refreshAvailability();
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }

  Future<void> _refreshAvailability() async {
    try {
      final info = await _bridge.getLinuxLikeRuntimeInfo();
      if (!mounted) return;
      setState(() {
        _installed = info['available'] == 'true';
        _checking = false;
      });
    } catch (_) {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _installOrRepair() async {
    if (_installing) return;
    setState(() {
      _installing = true;
      _stage = '';
      _percent = 0;
      _message = '';
    });
    await _progressSubscription?.cancel();
    _progressSubscription = _bridge.installProgressStream.listen((event) {
      if (!mounted) return;
      setState(() {
        _stage = event['stage']?.toString() ?? '';
        _percent = (event['percent'] as num?)?.toInt() ?? 0;
        _message = event['message']?.toString() ?? '';
      });
    });
    try {
      await _bridge.prepareLinuxLikeRuntime();
      await _bridge.installLinuxLikeRuntime();
      if (!mounted) return;
      setState(() {
        _installed = true;
        _installing = false;
      });
      Navigator.pop(context, true);
    } catch (error, stackTrace) {
      AppLogger.instance.error(
        '安装 Linux-like 运行环境失败: $error',
        source: 'Settings',
        detail: stackTrace.toString(),
      );
      if (!mounted) return;
      setState(() => _installing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)!.installFailed(error))),
      );
    } finally {
      await _progressSubscription?.cancel();
      _progressSubscription = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_installing,
      child: AlertDialog(
        title: Text(l10n.linuxLikeExperimental),
        content: _checking
            ? const SizedBox(
                height: 48,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _installed
                            ? Icons.check_circle_outline
                            : Icons.info_outline,
                        color: _installed ? Colors.green : colors.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_installed
                            ? l10n.runtimeInstalled
                            : l10n.runtimeNotInstalled),
                      ),
                    ],
                  ),
                  if (!_installed && !_installing) ...[
                    const SizedBox(height: 12),
                    Text(l10n.runtimeDownloadRequirement,
                        style: TextStyle(
                            fontSize: 12, color: colors.onSurfaceVariant)),
                  ],
                  if (_installing) ...[
                    const SizedBox(height: 16),
                    Text(_stage.isEmpty ? l10n.preparing : _stage,
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: _percent > 0 ? _percent / 100 : null,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    const SizedBox(height: 6),
                    Text(_message.isEmpty ? l10n.processing : _message,
                        style: TextStyle(
                            fontSize: 12, color: colors.onSurfaceVariant)),
                  ],
                ],
              ),
        actions: [
          TextButton(
            onPressed: _installing ? null : () => Navigator.pop(context),
            child: Text(l10n.close),
          ),
          if (!_checking)
            FilledButton.icon(
              onPressed: _installing ? null : _installOrRepair,
              icon: Icon(
                  _installed ? Icons.build_outlined : Icons.download_outlined),
              label:
                  Text(_installed ? l10n.repairRuntime : l10n.installRuntime),
            ),
        ],
      ),
    );
  }
}

class _AboutPageState extends State<_AboutPage> {
  final _bridge = NativeBridge();
  String _runtimeBackend = RuntimeManager.chaquopyBackendId;
  String _appVersion = '';
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
      _pyVersion = pyInfo['pythonVersion'] ?? '';
      _sitePackages = pyInfo['sitePackages'] ?? '';
      _pythonPath = pyInfo['pythonPath'] ?? '';
      _chaquopyPipDir = pyInfo['chaquopyPipDir'] ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final installDirectory = _runtimeBackend == RuntimeManager.chaquopyBackendId
        ? (_chaquopyPipDir.isNotEmpty ? _chaquopyPipDir : _sitePackages)
        : _sitePackages;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.about)),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // ── 标题区 ──
          Center(
            child: Column(
              children: [
                Text(
                  l10n.appTitle,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: c.onSurface),
                ),
                if (_appVersion.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'v$_appVersion',
                    style: TextStyle(fontSize: 13, color: c.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 6),
                Text(l10n.appSubtitle,
                    style: TextStyle(fontSize: 13, color: c.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _AboutCard(
            icon: Icons.code_rounded,
            title: l10n.pythonEnvironment,
            children: [
              _AboutItem(
                label: l10n.engine,
                value: _runtimeBackend == RuntimeManager.linuxLikeBackendId
                    ? 'Linux-like'
                    : 'Chaquopy',
              ),
              if (_pyVersion.isNotEmpty)
                _AboutItem(label: l10n.version, value: _pyVersion),
              if (installDirectory.isNotEmpty)
                _AboutItem(
                    label: l10n.installDirectory,
                    value: installDirectory,
                    mono: true),
              if (_pythonPath.isNotEmpty)
                _AboutItem(
                    label: l10n.pythonPath, value: _pythonPath, mono: true),
            ],
          ),
          const SizedBox(height: 12),
          _AboutCard(
            icon: Icons.info_outline_rounded,
            title: l10n.about,
            children: [
              _AboutItem(
                label: l10n.projectHomepage,
                value: 'github.com/daozhang66/python_runner',
                onTap: () => _bridge
                    .openUrl('https://github.com/daozhang66/python_runner'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _AboutCard(
            icon: Icons.architecture_rounded,
            title: l10n.technicalArchitecture,
            children: [
              _AboutItem(
                  label: l10n.framework,
                  value: l10n.architectureFrameworkValue),
              _AboutItem(
                  label: l10n.runtimeEngine,
                  value: l10n.architectureEngineValue),
              _AboutItem(
                  label: l10n.nativeLayer, value: l10n.architectureNativeValue),
              _AboutItem(
                  label: l10n.storage, value: l10n.architectureStorageValue),
              _AboutItem(
                  label: l10n.runtimeRequirements,
                  value: l10n.architectureRequirementsValue),
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
