import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/script_provider.dart';
import '../providers/execution_provider.dart';
import '../services/native_bridge.dart';
import '../widgets/confirm_dialog.dart';
import 'script_editor_page.dart';
import 'run_console_page.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

class ScriptListPage extends StatefulWidget {
  final VoidCallback? onSettingsTap;
  const ScriptListPage({super.key, this.onSettingsTap});

  @override
  State<ScriptListPage> createState() => _ScriptListPageState();
}

class _ScriptListPageState extends State<ScriptListPage> {
  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');
  bool _isGridView = false;
  final _bridge = NativeBridge();
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _searchMode = false;
  bool _multiSelectMode = false;
  final Set<String> _selectedScripts = {};

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      context.read<ScriptProvider>().loadScripts();
      _loadViewMode();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isGridView = prefs.getBool('script_grid_view') ?? false;
    });
  }

  Future<void> _setViewMode(bool isGridView) async {
    if (_isGridView == isGridView) return;
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isGridView = isGridView;
    });
    await prefs.setBool('script_grid_view', _isGridView);
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  void _exitSearch() {
    _searchController.clear();
    setState(() {
      _searchMode = false;
      _searchQuery = '';
    });
  }

  void _enterMultiSelect() {
    setState(() {
      _multiSelectMode = true;
      _selectedScripts.clear();
    });
  }

  void _handleMoreAction(String action) {
    switch (action) {
      case 'add':
        _showAddScriptOptions();
        break;
      case 'search':
        setState(() => _searchMode = true);
        break;
      case 'toggle_view':
        _setViewMode(!_isGridView);
        break;
      case 'select':
        _enterMultiSelect();
        break;
    }
  }

  String _formatRunLabel(int runCount) =>
      runCount > 0 ? '运行 $runCount 次' : '未运行';

  void _showAddScriptOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: const Text('新建脚本'),
              subtitle: const Text('创建一个空白 Python 脚本'),
              onTap: () {
                Navigator.pop(ctx);
                _createScript();
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_open_outlined),
              title: const Text('导入脚本'),
              subtitle: const Text('从设备选择 .py 文件'),
              onTap: () {
                Navigator.pop(ctx);
                _importScript();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _createScript() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建脚本'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '脚本名称 (不含 .py)',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              var name = controller.text.trim();
              if (name.isEmpty) return;
              if (!name.endsWith('.py')) name += '.py';
              Navigator.pop(ctx);
              final success = await context.read<ScriptProvider>().createScript(
                    name,
                    content:
                        '# ${name.replaceAll(".py", "")}\n\nprint("Hello, Python!")\n',
                  );
              if (success && mounted) _openEditor(name);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  void _importScript() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['py'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (!file.name.toLowerCase().endsWith('.py')) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('只支持导入 .py 文件'), duration: Duration(seconds: 2)));
      return;
    }
    final name = file.name;
    final bytes = file.bytes;
    if (bytes == null || !mounted) return;
    final content = utf8.decode(bytes, allowMalformed: true);

    // Check if script with same name already exists
    final provider = context.read<ScriptProvider>();
    final exists = provider.scripts.any((s) => s.name == name);
    if (exists) {
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('脚本已存在'),
          content: Text('已存在同名脚本「$name」，是否覆盖？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('覆盖',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            ),
          ],
        ),
      );
      if (overwrite != true) return;
      // Overwrite existing script content
      await provider.saveScript(name, content);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('已覆盖: $name'), duration: const Duration(seconds: 2)));
    } else {
      await provider.createScript(name, content: content);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('已导入: $name'), duration: const Duration(seconds: 2)));
    }
  }

  void _openEditor(String name) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => ScriptEditorPage(scriptName: name)));
  }

  Future<void> _exportScript(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final destDir = prefs.getString('export_dir') ?? '';
    try {
      final path = await _bridge.exportScript(name, destDir);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('已导出到: $path'),
              duration: const Duration(seconds: 3)),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
    }
  }

  Future<void> _exportSelected() async {
    final prefs = await SharedPreferences.getInstance();
    final destDir = prefs.getString('export_dir') ?? '';
    int ok = 0;
    String? lastPath;
    for (final name in _selectedScripts) {
      try {
        lastPath = await _bridge.exportScript(name, destDir);
        ok++;
      } catch (_) {}
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '已导出 $ok 个脚本到: ${lastPath?.replaceAll(RegExp(r"/[^/]+$"), "") ?? destDir}'),
            duration: const Duration(seconds: 3)),
      );
      setState(() {
        _multiSelectMode = false;
        _selectedScripts.clear();
      });
    }
  }

  Future<void> _deleteSelected() async {
    final count = _selectedScripts.length;
    final confirmed = await ConfirmDialog.show(context,
        title: '批量删除',
        content: '确定要删除选中的 $count 个脚本吗？此操作不可撤销。',
        confirmText: '删除 $count 个',
        confirmColor: Theme.of(context).colorScheme.error);
    if (!confirmed || !mounted) return;
    final provider = context.read<ScriptProvider>();
    for (final name in _selectedScripts.toList()) {
      await provider.deleteScript(name);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('已删除 $count 个脚本'),
            duration: const Duration(seconds: 2)),
      );
      setState(() {
        _multiSelectMode = false;
        _selectedScripts.clear();
      });
    }
  }

  Future<void> _runScript(String name) async {
    try {
      final scriptProvider = context.read<ScriptProvider>();
      final execProvider = context.read<ExecutionProvider>();
      await scriptProvider.incrementRunCount(name);
      execProvider.clearLogs();
      await execProvider.executeScript(name);
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => RunConsolePage(scriptName: name)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('运行失败: $e'), duration: const Duration(seconds: 3)),
        );
      }
    }
  }

  Future<void> _togglePinned(String name) async {
    await context.read<ScriptProvider>().togglePinned(name);
  }

  void _showContextMenu(String name, bool isPinned) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
                leading:
                    Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined),
                title: Text(isPinned ? '取消置顶' : '置顶'),
                onTap: () {
                  Navigator.pop(ctx);
                  _togglePinned(name);
                }),
            ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('重命名'),
                onTap: () {
                  Navigator.pop(ctx);
                  _renameScript(name);
                }),
            ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('复制'),
                onTap: () {
                  Navigator.pop(ctx);
                  _duplicateScript(name);
                }),
            ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: const Text('导出到设备'),
                onTap: () {
                  Navigator.pop(ctx);
                  _exportScript(name);
                }),
            ListTile(
                leading: Icon(Icons.delete,
                    color: Theme.of(context).colorScheme.error),
                title: Text('删除',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteScript(name);
                }),
          ],
        ),
      ),
    );
  }

  void _renameScript(String oldName) {
    final controller =
        TextEditingController(text: oldName.replaceAll('.py', ''));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              var newName = controller.text.trim();
              if (newName.isEmpty) return;
              if (!newName.endsWith('.py')) newName += '.py';
              if (newName == oldName) return;
              Navigator.pop(ctx);
              context.read<ScriptProvider>().renameScript(oldName, newName);
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  void _duplicateScript(String name) async {
    final provider = context.read<ScriptProvider>();
    final content = await provider.readScript(name);
    final copyName = name.replaceAll('.py', '_copy.py');
    await provider.createScript(copyName, content: content);
  }

  void _deleteScript(String name) async {
    final confirmed = await ConfirmDialog.show(context,
        title: '删除脚本',
        content: '确定要删除 "${name.replaceAll(".py", "")}" 吗？此操作不可撤销。',
        confirmText: '删除',
        confirmColor: Theme.of(context).colorScheme.error);
    if (confirmed && mounted) context.read<ScriptProvider>().deleteScript(name);
  }

  Widget _buildScriptTitleBadge(int count) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Python',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: colors.primaryContainer.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            count.toString(),
            style: TextStyle(
              fontSize: 12,
              height: 1.1,
              fontWeight: FontWeight.w700,
              color: colors.onPrimaryContainer,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScriptMenu() {
    return PopupMenuButton<String>(
      onSelected: _handleMoreAction,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'add',
          child: ListTile(
            leading: Icon(Icons.add_circle_outline),
            title: Text('添加脚本'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'search',
          child: ListTile(
            leading: Icon(Icons.search),
            title: Text('搜索脚本'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'toggle_view',
          child: ListTile(
            leading: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
            title: Text(_isGridView ? '列表视图' : '宫格视图'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'select',
          child: ListTile(
            leading: Icon(Icons.checklist),
            title: Text('多选管理'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScriptProvider>();
    final allScripts = provider.scripts;
    final scripts = _searchQuery.isEmpty
        ? allScripts
        : allScripts
            .where((s) =>
                s.name.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();
    final allSelected = scripts.isNotEmpty &&
        scripts.every((s) => _selectedScripts.contains(s.name));

    return Scaffold(
      appBar: _multiSelectMode
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _multiSelectMode = false;
                  _selectedScripts.clear();
                }),
              ),
              title: Text('已选 ${_selectedScripts.length} 个'),
              actions: [
                TextButton(
                  onPressed: () => setState(() {
                    if (allSelected)
                      _selectedScripts.clear();
                    else
                      _selectedScripts.addAll(scripts.map((s) => s.name));
                  }),
                  child: Text(allSelected ? '取消全选' : '全选'),
                ),
                if (_selectedScripts.isNotEmpty) ...[
                  IconButton(
                    icon: const Icon(Icons.file_download_outlined),
                    tooltip: '批量导出',
                    onPressed: _exportSelected,
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error),
                    tooltip: '批量删除',
                    onPressed: _deleteSelected,
                  ),
                ],
              ],
            )
          : _searchMode
              ? AppBar(
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: _exitSearch,
                  ),
                  title: TextField(
                    controller: _searchController,
                    autofocus: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      hintText: '搜索脚本...',
                      border: InputBorder.none,
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                  actions: [
                    if (_searchQuery.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _clearSearch,
                        tooltip: '清空搜索',
                      ),
                  ],
                )
              : AppBar(
                  title: _buildScriptTitleBadge(allScripts.length),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: widget.onSettingsTap,
                    ),
                    _buildScriptMenu(),
                  ],
                ),
      body: Column(
        children: [
          if (!_multiSelectMode && _searchQuery.isNotEmpty)
            _buildSearchResultBar(allScripts.length, scripts.length),
          Expanded(
            child: provider.loading && allScripts.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : scripts.isEmpty
                    ? Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.code_off,
                            size: 64,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(height: 16),
                        Text(_searchQuery.isNotEmpty ? '无匹配结果' : '还没有脚本'),
                        if (_searchQuery.isEmpty) const SizedBox(height: 8),
                        if (_searchQuery.isEmpty)
                          const Text('点击上方 + 按钮创建',
                              style: TextStyle(fontSize: 12)),
                      ]))
                    : RefreshIndicator(
                        onRefresh: () => provider.loadScripts(),
                        child: _isGridView
                            ? _buildGridView(scripts)
                            : _buildListView(scripts),
                      ),
          ),
        ],
      ),
      floatingActionButton: null,
    );
  }

  Widget _buildSearchResultBar(int totalCount, int visibleCount) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '匹配 $visibleCount / 共 $totalCount 个',
        style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
      ),
    );
  }

  Widget _buildListView(List<dynamic> scripts) {
    final colors = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: scripts.length,
      itemBuilder: (context, index) {
        final script = scripts[index];
        final displayName = script.name.replaceAll('.py', '');
        final selected = _selectedScripts.contains(script.name);
        return TweenAnimationBuilder<double>(
          key: ValueKey('script_${script.name}'),
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 200 + index * 30),
          curve: Curves.easeOutCubic,
          builder: (context, v, child) => Opacity(
            opacity: v,
            child: Transform.translate(
                offset: Offset(0, 16 * (1 - v)), child: child),
          ),
          child: _ScriptCardSurface(
            colors: colors,
            selected: _multiSelectMode && selected,
            pinned: script.isPinned,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _multiSelectMode
                  ? setState(() {
                      if (selected)
                        _selectedScripts.remove(script.name);
                      else
                        _selectedScripts.add(script.name);
                    })
                  : _openEditor(script.name),
              onLongPress: () => _multiSelectMode
                  ? null
                  : _showContextMenu(script.name, script.isPinned),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                child: Row(
                  children: [
                    if (_multiSelectMode)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Checkbox(
                          value: selected,
                          onChanged: (_) => setState(() {
                            if (selected)
                              _selectedScripts.remove(script.name);
                            else
                              _selectedScripts.add(script.name);
                          }),
                        ),
                      )
                    else
                      _ScriptIcon(colors: colors, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(displayName,
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: colors.onSurface),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              if (script.isPinned) ...[
                                const SizedBox(width: 6),
                                _PinnedBadge(colors: colors),
                              ],
                            ],
                          ),
                          const SizedBox(height: 7),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              _ScriptMetaChip(
                                colors: colors,
                                icon: Icons.schedule_rounded,
                                label: _dateFormat.format(script.modifiedAt),
                              ),
                              _ScriptMetaChip(
                                colors: colors,
                                icon: Icons.play_circle_outline_rounded,
                                label: _formatRunLabel(script.runCount),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (!_multiSelectMode) ...[
                      const SizedBox(width: 8),
                      _QuickRunButton(onPressed: () => _runScript(script.name)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGridView(List<dynamic> scripts) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 1.44,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10),
      itemCount: scripts.length,
      itemBuilder: (context, index) {
        final script = scripts[index];
        final selected = _selectedScripts.contains(script.name);
        return _ScriptGridCard(
          key: ValueKey('script_grid_${script.name}'), // Preserve identity
          name: script.name,
          modifiedAt: script.modifiedAt,
          runCount: script.runCount,
          dateFormat: _dateFormat,
          pinned: script.isPinned,
          selected: _multiSelectMode ? selected : null,
          onTap: () => _multiSelectMode
              ? setState(() {
                  if (selected)
                    _selectedScripts.remove(script.name);
                  else
                    _selectedScripts.add(script.name);
                })
              : _openEditor(script.name),
          onLongPress: () => _multiSelectMode
              ? null
              : _showContextMenu(script.name, script.isPinned),
          onRun: _multiSelectMode ? null : () => _runScript(script.name),
        );
      },
    );
  }
}

class _ScriptGridCard extends StatelessWidget {
  final String name;
  final DateTime modifiedAt;
  final int runCount;
  final DateFormat dateFormat;
  final bool pinned;
  final bool? selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onRun;

  const _ScriptGridCard({
    super.key,
    required this.name,
    required this.modifiedAt,
    required this.runCount,
    required this.dateFormat,
    required this.pinned,
    this.selected,
    required this.onTap,
    required this.onLongPress,
    this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final displayName = name.replaceAll('.py', '');
    final runLabel = runCount > 0 ? '运行 $runCount 次' : '未运行';

    return _ScriptCardSurface(
      colors: colors,
      selected: selected == true,
      pinned: pinned,
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _ScriptIcon(colors: colors, size: 36, fontSize: 13),
                  const Spacer(),
                  if (pinned && selected == null) _PinnedBadge(colors: colors),
                  if (pinned && selected == null) const SizedBox(width: 6),
                  if (selected != null)
                    Icon(
                        selected!
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked,
                        size: 22,
                        color: selected! ? colors.primary : colors.outline)
                  else if (onRun != null)
                    _QuickRunButton(onPressed: onRun!),
                ],
              ),
              const SizedBox(height: 12),
              Text(displayName,
                  style: TextStyle(
                      fontSize: 14,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const Spacer(),
              Row(
                children: [
                  Flexible(
                    child: _ScriptMetaChip(
                      colors: colors,
                      icon: Icons.history_rounded,
                      label: dateFormat.format(modifiedAt),
                      compact: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(runLabel,
                  style: TextStyle(fontSize: 11, color: colors.primary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScriptCardSurface extends StatelessWidget {
  final ColorScheme colors;
  final bool selected;
  final bool pinned;
  final EdgeInsetsGeometry margin;
  final Widget child;

  const _ScriptCardSurface({
    required this.colors,
    required this.selected,
    required this.pinned,
    required this.margin,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: selected
            ? colors.primaryContainer.withValues(alpha: 0.82)
            : pinned
                ? colors.primaryContainer.withValues(alpha: 0.72)
                : colors.surfaceContainer,
        borderRadius: radius,
        border: Border.all(
          color: pinned
              ? colors.primary.withValues(alpha: 0.42)
              : colors.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: child,
      ),
    );
  }
}

class _ScriptIcon extends StatelessWidget {
  final ColorScheme colors;
  final double size;
  final double fontSize;

  const _ScriptIcon({
    required this.colors,
    required this.size,
    this.fontSize = 15,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      alignment: Alignment.center,
      child: Text(
        'Py',
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: colors.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _ScriptMetaChip extends StatelessWidget {
  final ColorScheme colors;
  final IconData icon;
  final String label;
  final bool compact;

  const _ScriptMetaChip({
    required this.colors,
    required this.icon,
    required this.label,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: compact ? 11 : 12, color: colors.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: compact ? 10.5 : 11,
            color: colors.onSurfaceVariant,
            height: 1,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _PinnedBadge extends StatelessWidget {
  final ColorScheme colors;

  const _PinnedBadge({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.push_pin, size: 10, color: colors.primary),
          const SizedBox(width: 2),
          Text(
            '置顶',
            style: TextStyle(
              fontSize: 10,
              height: 1,
              fontWeight: FontWeight.w700,
              color: colors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickRunButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _QuickRunButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: '运行',
      child: SizedBox.square(
        dimension: 34,
        child: Material(
          color: colors.primaryContainer,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Icon(
              Icons.play_arrow_rounded,
              size: 20,
              color: colors.onPrimaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}
