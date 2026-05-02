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
  const ScriptListPage({super.key});

  @override
  State<ScriptListPage> createState() => _ScriptListPageState();
}

class _ScriptListPageState extends State<ScriptListPage> {
  final _dateFormat = DateFormat('MM-dd HH:mm');
  bool _isGridView = false;
  final _bridge = NativeBridge();
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _searchVisible = false;
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

  Future<void> _toggleViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() { _isGridView = !_isGridView; });
    await prefs.setBool('script_grid_view', _isGridView);
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              var name = controller.text.trim();
              if (name.isEmpty) return;
              if (!name.endsWith('.py')) name += '.py';
              Navigator.pop(ctx);
              final success = await context.read<ScriptProvider>().createScript(
                name, content: '# ${name.replaceAll(".py", "")}\n\nprint("Hello, Python!")\n',
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('只支持导入 .py 文件'), duration: Duration(seconds: 2)));
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
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('覆盖', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            ),
          ],
        ),
      );
      if (overwrite != true) return;
      // Overwrite existing script content
      await provider.saveScript(name, content);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已覆盖: $name'), duration: const Duration(seconds: 2)));
    } else {
      await provider.createScript(name, content: content);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入: $name'), duration: const Duration(seconds: 2)));
    }
  }

  void _openEditor(String name) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ScriptEditorPage(scriptName: name)));
  }

  Future<void> _exportScript(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final destDir = prefs.getString('export_dir') ?? '';
    try {
      final path = await _bridge.exportScript(name, destDir);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导出到: $path'), duration: const Duration(seconds: 3)),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
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
        SnackBar(content: Text('已导出 $ok 个脚本到: ${lastPath?.replaceAll(RegExp(r"/[^/]+$"), "") ?? destDir}'),
            duration: const Duration(seconds: 3)),
      );
      setState(() { _multiSelectMode = false; _selectedScripts.clear(); });
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
        SnackBar(content: Text('已删除 $count 个脚本'), duration: const Duration(seconds: 2)),
      );
      setState(() { _multiSelectMode = false; _selectedScripts.clear(); });
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
          SnackBar(content: Text('运行失败: $e'), duration: const Duration(seconds: 3)),
        );
      }
    }
  }

  void _showContextMenu(String name) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.edit), title: const Text('重命名'),
              onTap: () { Navigator.pop(ctx); _renameScript(name); }),
            ListTile(leading: const Icon(Icons.copy), title: const Text('复制'),
              onTap: () { Navigator.pop(ctx); _duplicateScript(name); }),
            ListTile(leading: const Icon(Icons.file_download_outlined), title: const Text('导出到设备'),
              onTap: () { Navigator.pop(ctx); _exportScript(name); }),
            ListTile(
              leading: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
              title: Text('删除', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () { Navigator.pop(ctx); _deleteScript(name); }),
          ],
        ),
      ),
    );
  }

  void _renameScript(String oldName) {
    final controller = TextEditingController(text: oldName.replaceAll('.py', ''));
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
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
      title: '删除脚本', content: '确定要删除 "${name.replaceAll(".py", "")}" 吗？此操作不可撤销。',
      confirmText: '删除', confirmColor: Theme.of(context).colorScheme.error);
    if (confirmed && mounted) context.read<ScriptProvider>().deleteScript(name);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScriptProvider>();
    final allScripts = provider.scripts;
    final scripts = _searchQuery.isEmpty ? allScripts : allScripts.where(
      (s) => s.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    final allSelected = scripts.isNotEmpty && scripts.every((s) => _selectedScripts.contains(s.name));

    return Scaffold(
      appBar: _multiSelectMode
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() { _multiSelectMode = false; _selectedScripts.clear(); }),
              ),
              title: Text('已选 ${_selectedScripts.length} 个'),
              actions: [
                TextButton(
                  onPressed: () => setState(() {
                    if (allSelected) _selectedScripts.clear();
                    else _selectedScripts.addAll(scripts.map((s) => s.name));
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
                    icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                    tooltip: '批量删除',
                    onPressed: _deleteSelected,
                  ),
                ],
              ],
            )
          : _searchVisible
              ? AppBar(
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () { _searchController.clear(); setState(() { _searchVisible = false; _searchQuery = ''; }); },
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
                )
              : AppBar(
                  title: Text('脚本 (${allScripts.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () => setState(() => _searchVisible = true),
                      tooltip: '搜索',
                    ),
                    IconButton(
                      icon: const Icon(Icons.checklist),
                      onPressed: () => setState(() { _multiSelectMode = true; _selectedScripts.clear(); }),
                      tooltip: '多选',
                    ),
                    IconButton(
                      icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view, size: 20),
                      onPressed: _toggleViewMode,
                      tooltip: _isGridView ? '列表视图' : '宫格视图',
                    ),
                  ],
                ),
      body: Column(
        children: [
          Expanded(
            child: provider.loading && allScripts.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : scripts.isEmpty
                    ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.code_off, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(height: 16),
                        Text(_searchQuery.isNotEmpty ? '无匹配结果' : '还没有脚本'),
                        if (_searchQuery.isEmpty) const SizedBox(height: 8),
                        if (_searchQuery.isEmpty) const Text('点击右下角按钮创建', style: TextStyle(fontSize: 12)),
                      ]))
                    : RefreshIndicator(
                        onRefresh: () => provider.loadScripts(),
                        child: _isGridView ? _buildGridView(scripts) : _buildListView(scripts),
                      ),
          ),
        ],
      ),
      floatingActionButton: _multiSelectMode ? null : Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'import', onPressed: _importScript, child: const Icon(Icons.file_open)),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'create', onPressed: _createScript, child: const Icon(Icons.add)),
        ],
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
            child: Transform.translate(offset: Offset(0, 16 * (1 - v)), child: child),
          ),
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _multiSelectMode
                  ? setState(() {
                      if (selected) _selectedScripts.remove(script.name);
                      else _selectedScripts.add(script.name);
                    })
                  : _openEditor(script.name),
              onLongPress: () => _multiSelectMode ? null : _showContextMenu(script.name),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    if (_multiSelectMode)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Checkbox(
                          value: selected,
                          onChanged: (_) => setState(() {
                            if (selected) _selectedScripts.remove(script.name);
                            else _selectedScripts.add(script.name);
                          }),
                        ),
                      )
                    else
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text('Py', style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600,
                            color: colors.onPrimaryContainer,
                          )),
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(displayName,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 3),
                          Text(
                            '${_dateFormat.format(script.modifiedAt)}  ${script.runCount > 0 ? "运行 ${script.runCount} 次" : "未运行"}',
                            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (!_multiSelectMode)
                      IconButton(
                        icon: const Icon(Icons.play_arrow_rounded, size: 22),
                        color: colors.primary,
                        onPressed: () => _runScript(script.name),
                        tooltip: '运行',
                      ),
                    Icon(Icons.chevron_right, size: 18, color: colors.onSurfaceVariant),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, childAspectRatio: 1.6, crossAxisSpacing: 6, mainAxisSpacing: 6),
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
          selected: _multiSelectMode ? selected : null,
          onTap: () => _multiSelectMode
              ? setState(() {
                  if (selected) _selectedScripts.remove(script.name);
                  else _selectedScripts.add(script.name);
                })
              : _openEditor(script.name),
          onLongPress: () => _multiSelectMode ? null : _showContextMenu(script.name),
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
  final bool? selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onRun;

  const _ScriptGridCard({
    super.key,
    required this.name, required this.modifiedAt, required this.runCount,
    required this.dateFormat, this.selected,
    required this.onTap, required this.onLongPress, this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayName = name.replaceAll('.py', '');
    return Card(
      margin: EdgeInsets.zero,
      elevation: 1,
      color: selected == true ? colorScheme.primaryContainer : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(child: Text('Py', style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600,
                    color: colorScheme.onPrimaryContainer))),
                ),
                const Spacer(),
                if (selected != null)
                  Icon(selected! ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 18, color: selected! ? colorScheme.primary : colorScheme.outline)
                else if (onRun != null)
                  SizedBox(
                    width: 28, height: 28,
                    child: IconButton(
                      icon: Icon(Icons.play_arrow_rounded, size: 18),
                      color: Colors.green,
                      padding: EdgeInsets.zero,
                      onPressed: onRun,
                      tooltip: '运行',
                    ),
                  ),
              ]),
              const Spacer(),
              Text(displayName,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text('${dateFormat.format(modifiedAt)}  ${runCount > 0 ? "运行$runCount次" : "未运行"}',
                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}
