import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import '../models/script_group.dart';
import '../providers/script_provider.dart';
import '../providers/execution_provider.dart';
import '../services/native_bridge.dart';
import '../utils/app_page_transitions.dart';
import '../widgets/confirm_dialog.dart';
import 'script_editor_page.dart';
import 'run_console_page.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

class ScriptListPageController {
  _ScriptListPageState? _state;

  void _attach(_ScriptListPageState state) {
    _state = state;
  }

  void _detach(_ScriptListPageState state) {
    if (identical(_state, state)) {
      _state = null;
    }
  }

  bool handleBack() => _state?._handleBackNavigation() ?? false;
}

class ScriptListPage extends StatefulWidget {
  final VoidCallback? onSettingsTap;
  final ScriptListPageController? controller;

  const ScriptListPage({
    super.key,
    this.onSettingsTap,
    this.controller,
  });

  @override
  State<ScriptListPage> createState() => _ScriptListPageState();
}

class _ScriptListPageState extends State<ScriptListPage> {
  static const double _scriptListItemExtent = 94;
  static const double _folderListItemExtent = 84;
  static const String _maskedScriptName = '●●●●●●';

  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');
  bool _isGridView = false;
  bool _maskScriptNames = false;
  final _bridge = NativeBridge();
  final _searchController = TextEditingController();
  final _gridScrollController = ScrollController();
  final _gridViewKey = GlobalKey();
  String? _gridDraggingScriptName;
  String? _gridDragPreviewTargetName;
  String _searchQuery = '';
  bool _searchMode = false;
  bool _multiSelectMode = false;
  int? _activeGroupId;
  String? _activeGroupName;
  final Set<String> _selectedScripts = {};

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    context.read<ScriptProvider>().loadScripts();
    _loadViewMode();
    _loadScriptNameMaskPreference();
  }

  @override
  void didUpdateWidget(covariant ScriptListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _searchController.dispose();
    _gridScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
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

  Future<void> _loadScriptNameMaskPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _maskScriptNames = prefs.getBool('script_name_mask_enabled') ?? false;
    });
  }

  Future<void> _toggleScriptNameMask() async {
    final nextValue = !_maskScriptNames;
    setState(() {
      _maskScriptNames = nextValue;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('script_name_mask_enabled', nextValue);
  }

  String _displayScriptName(String name, int _) {
    if (!_maskScriptNames) return name.replaceAll('.py', '');
    return _maskedScriptName;
  }

  String _displayGroupName(String name) {
    if (!_maskScriptNames) return name;
    return _maskedScriptName;
  }

  TextStyle? get _maskedNameStyle =>
      _maskScriptNames ? const TextStyle(color: Color(0xFF050505)) : null;

  bool _canAcceptListDrop(String draggedName, String targetName, int? groupId) {
    if (draggedName == targetName) return false;
    final groupScripts = context.read<ScriptProvider>().scriptsInGroup(groupId);
    final draggedIndex =
        groupScripts.indexWhere((script) => script.name == draggedName);
    final targetIndex =
        groupScripts.indexWhere((script) => script.name == targetName);
    if (draggedIndex < 0 || targetIndex < 0) return false;
    return !groupScripts[draggedIndex].isPinned &&
        !groupScripts[targetIndex].isPinned;
  }

  void _commitListDragTarget(
    String draggedName,
    String targetName,
    int? groupId,
  ) {
    if (!_canAcceptListDrop(draggedName, targetName, groupId)) return;
    context
        .read<ScriptProvider>()
        .swapScriptPositionsByName(draggedName, targetName);
  }

  Widget _buildListDragTarget({
    required String scriptName,
    required int? groupId,
    required Widget child,
  }) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          _canAcceptListDrop(details.data, scriptName, groupId),
      onAcceptWithDetails: (details) =>
          _commitListDragTarget(details.data, scriptName, groupId),
      builder: (context, candidateData, rejectedData) {
        return AnimatedScale(
          scale: candidateData.isEmpty ? 1 : 0.985,
          duration: const Duration(milliseconds: 100),
          child: child,
        );
      },
    );
  }

  Widget _buildListDragHandle(String scriptName, Color color) {
    return Draggable<String>(
      data: scriptName,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: Icon(Icons.drag_indicator, size: 24, color: color),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: Icon(Icons.drag_indicator, size: 22, color: color),
      ),
      child: Icon(Icons.drag_indicator, size: 22, color: color),
    );
  }

  bool _handleBackNavigation() {
    if (_multiSelectMode) {
      setState(() {
        _multiSelectMode = false;
        _selectedScripts.clear();
      });
      return true;
    }
    if (_searchMode) {
      _exitSearch();
      return true;
    }
    if (_activeGroupId != null) {
      _closeGroup();
      return true;
    }
    return false;
  }

  Widget _buildMaskedScriptNameText(
    String text, {
    required double fontSize,
    required FontWeight fontWeight,
    required int maxLines,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: _maskScriptNames ? const Color(0xFF050505) : colors.onSurface,
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
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

  void _openGroup(ScriptGroup group) {
    if (group.id == null) return;
    setState(() {
      _activeGroupId = group.id;
      _activeGroupName = group.name;
      _searchMode = false;
      _searchQuery = '';
      _selectedScripts.clear();
      _multiSelectMode = false;
    });
  }

  void _closeGroup() {
    setState(() {
      _activeGroupId = null;
      _activeGroupName = null;
      _searchMode = false;
      _searchQuery = '';
      _selectedScripts.clear();
      _multiSelectMode = false;
    });
  }

  void _handleMoreAction(String action) {
    switch (action) {
      case 'add':
        _showAddScriptOptions();
        break;
      case 'add_group':
        _showCreateGroupDialog();
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

  void _showCreateGroupDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加分组'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '分组名称',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          maxLength: 30,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              final success =
                  await context.read<ScriptProvider>().createGroup(name);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(success ? '已添加分组: $name' : '分组创建失败或已存在'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: const Text('创建'),
          ),
        ],
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
                    groupId: _activeGroupId,
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('只支持导入 .py 文件'), duration: Duration(seconds: 2)));
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('已覆盖: $name'), duration: const Duration(seconds: 2)));
      }
    } else {
      await provider.createScript(name,
          content: content, groupId: _activeGroupId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('已导入: $name'), duration: const Duration(seconds: 2)));
      }
    }
  }

  void _openEditor(String name) {
    Navigator.push(
      context,
      AppPageTransitions.sharedAxisLeftRight(
        ScriptEditorPage(scriptName: name),
      ),
    );
  }

  Future<void> _exportScript(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final destDir = prefs.getString('export_dir') ?? '';
    try {
      final path = await _bridge.exportScript(name, destDir);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('已导出到: $path'),
              duration: const Duration(seconds: 3)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
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

  Future<void> _moveScriptsToGroup(
      Set<String> names, int? groupId, String targetLabel) async {
    if (names.isEmpty) return;
    await context.read<ScriptProvider>().moveScriptsToGroup(names, groupId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(groupId == null
            ? '已将 ${names.length} 个脚本移出到首页'
            : '已将 ${names.length} 个脚本移动到「${_maskScriptNames ? _maskedScriptName : targetLabel}」'),
        duration: const Duration(seconds: 2),
      ),
    );
    setState(() {
      _multiSelectMode = false;
      _selectedScripts.clear();
    });
  }

  void _showMoveToGroupSheet({String? singleName}) {
    final provider = context.read<ScriptProvider>();
    final names = singleName == null ? _selectedScripts.toSet() : {singleName};
    if (names.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) => SafeArea(
          child: ListView(
            controller: scrollController,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
              const ListTile(
                leading: Icon(Icons.drive_file_move_outline),
                title: Text('移动到分组'),
              ),
              if (_activeGroupId != null)
                ListTile(
                  leading: const Icon(Icons.home_outlined),
                  title: const Text('移出到首页'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _moveScriptsToGroup(names, null, '首页');
                  },
                ),
              for (final group in provider.groups)
                if (group.id != null && group.id != _activeGroupId)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(
                      _displayGroupName(group.name),
                      style: _maskedNameStyle,
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _moveScriptsToGroup(names, group.id, group.name);
                    },
                  ),
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const Text('新建分组...'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showCreateGroupDialog();
                },
              ),
            ],
          ),
        ),
      ),
    );
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
          AppPageTransitions.fadeThrough(RunConsolePage(scriptName: name)),
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

  void _showContextMenu(String name, bool isPinned, {int? groupId}) {
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
                leading: const Icon(Icons.drive_file_move_outline),
                title: const Text('移动到分组'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showMoveToGroupSheet(singleName: name);
                }),
            if (groupId != null)
              ListTile(
                  leading: const Icon(Icons.home_outlined),
                  title: const Text('移出到首页'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _moveScriptsToGroup({name}, null, '首页');
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

  Future<void> _duplicateScript(String name) async {
    try {
      final provider = context.read<ScriptProvider>();
      final content = await provider.readScript(name);
      final copyName = name.replaceAll('.py', '_copy.py');
      await provider.createScript(copyName, content: content);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('复制失败: $e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  Future<void> _deleteScript(String name) async {
    final confirmed = await ConfirmDialog.show(context,
        title: '删除脚本',
        content: '确定要删除 "${name.replaceAll(".py", "")}" 吗？此操作不可撤销。',
        confirmText: '删除',
        confirmColor: Theme.of(context).colorScheme.error);
    if (confirmed && mounted) context.read<ScriptProvider>().deleteScript(name);
  }

  void _showGroupContextMenu(ScriptGroup group) {
    if (group.id == null) return;
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
              leading: const Icon(Icons.edit_outlined),
              title: const Text('重命名分组'),
              onTap: () {
                Navigator.pop(ctx);
                _renameGroup(group);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: Text('删除分组',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              subtitle: const Text('分组内脚本会回到首页'),
              onTap: () {
                Navigator.pop(ctx);
                _deleteGroup(group);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _renameGroup(ScriptGroup group) {
    if (group.id == null) return;
    final controller = TextEditingController(text: group.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名分组'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          autofocus: true,
          maxLength: 30,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              final success = await context
                  .read<ScriptProvider>()
                  .renameGroup(group.id!, name);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (success && mounted && _activeGroupId == group.id) {
                setState(() => _activeGroupName = name);
              }
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteGroup(ScriptGroup group) async {
    if (group.id == null) return;
    final confirmed = await ConfirmDialog.show(
      context,
      title: '删除分组',
      content: '确定要删除「${group.name}」吗？分组内脚本会回到首页。',
      confirmText: '删除',
      confirmColor: Theme.of(context).colorScheme.error,
    );
    if (!confirmed || !mounted) return;
    final success = await context.read<ScriptProvider>().deleteGroup(group.id!);
    if (success && mounted && _activeGroupId == group.id) {
      _closeGroup();
    }
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
          value: 'add_group',
          child: ListTile(
            leading: Icon(Icons.create_new_folder_outlined),
            title: Text('添加分组'),
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

  Widget _buildScriptNameVisibilityButton() {
    return IconButton(
      icon: Icon(_maskScriptNames
          ? Icons.visibility_off_outlined
          : Icons.visibility_outlined),
      tooltip: _maskScriptNames ? '显示脚本名' : '隐藏脚本名',
      onPressed: _toggleScriptNameMask,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScriptProvider>();
    final allScripts = provider.scripts;
    final homeScripts = provider.ungroupedScripts;
    final baseScripts = _activeGroupId == null
        ? homeScripts
        : provider.scriptsInGroup(_activeGroupId);
    final searchSource = _activeGroupId == null ? allScripts : baseScripts;
    final scripts = _searchQuery.isEmpty
        ? baseScripts
        : searchSource
            .where((s) =>
                s.name.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();
    final allSelected = scripts.isNotEmpty &&
        scripts.every((s) => _selectedScripts.contains(s.name));
    final showFolderHome = _activeGroupId == null && _searchQuery.isEmpty;
    final hasBodyContent = showFolderHome
        ? provider.groups.isNotEmpty || scripts.isNotEmpty
        : scripts.isNotEmpty;

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
                    if (allSelected) {
                      _selectedScripts.clear();
                    } else {
                      _selectedScripts.addAll(scripts.map((s) => s.name));
                    }
                  }),
                  child: Text(allSelected ? '取消全选' : '全选'),
                ),
                if (_selectedScripts.isNotEmpty) ...[
                  IconButton(
                    icon: const Icon(Icons.drive_file_move_outline),
                    tooltip: '移动到分组',
                    onPressed: _showMoveToGroupSheet,
                  ),
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
                  leading: _activeGroupId == null
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: _closeGroup,
                        ),
                  title: _activeGroupId == null
                      ? _buildScriptTitleBadge(allScripts.length)
                      : Text(
                          _displayGroupName(_activeGroupName ?? '分组'),
                          style: _maskedNameStyle,
                        ),
                  actions: _activeGroupId == null
                      ? [
                          _buildScriptNameVisibilityButton(),
                          IconButton(
                            icon: const Icon(Icons.settings_outlined),
                            onPressed: widget.onSettingsTap,
                          ),
                          _buildScriptMenu(),
                        ]
                      : null,
                ),
      body: Column(
        children: [
          if (!_multiSelectMode && _searchQuery.isNotEmpty)
            _buildSearchResultBar(searchSource.length, scripts.length),
          Expanded(
            child: provider.loading && allScripts.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : !hasBodyContent
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
                        child: showFolderHome
                            ? _buildFolderHome(provider, scripts)
                            : _isGridView
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

  Widget _buildFolderHome(ScriptProvider provider, List<dynamic> scripts) {
    final groups = provider.groups;
    final visibleScripts =
        scripts.where((script) => script.groupId == null).toList();
    final pinnedScripts =
        visibleScripts.where((script) => script.isPinned).toList();
    final regularScripts =
        visibleScripts.where((script) => !script.isPinned).toList();
    final firstFolderIndex = pinnedScripts.length;
    final firstRegularIndex = pinnedScripts.length + groups.length;
    final itemCount = firstRegularIndex + regularScripts.length;

    if (_isGridView) {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 1.44,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (index < firstFolderIndex) {
            final script = pinnedScripts[index];
            return _buildFolderHomeGridScriptCard(
              script,
              index,
              draggable: false,
            );
          }

          if (index < firstRegularIndex) {
            final group = groups[index - firstFolderIndex];
            return _ScriptFolderCard(
              key: ValueKey('home_group_grid_${group.id}'),
              name: _displayGroupName(group.name),
              masked: _maskScriptNames,
              count:
                  group.id == null ? 0 : provider.scriptCountInGroup(group.id!),
              grid: true,
              onTap: _multiSelectMode ? null : () => _openGroup(group),
              onLongPress:
                  _multiSelectMode ? null : () => _showGroupContextMenu(group),
            );
          }

          final script = regularScripts[index - firstRegularIndex];
          return _buildFolderHomeGridScriptCard(
            script,
            index - groups.length,
            draggable: !_multiSelectMode && !_searchMode,
          );
        },
      );
    }

    final canDrag = !_multiSelectMode && !_searchMode;
    if (!canDrag) {
      return ListView.builder(
        itemExtentBuilder: (index, _) {
          if (index < firstFolderIndex) return _scriptListItemExtent;
          if (index < firstRegularIndex) return _folderListItemExtent;
          return _scriptListItemExtent;
        },
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (index < firstFolderIndex) {
            return _buildFolderHomeScriptListItem(
              pinnedScripts[index],
              index,
              reorderIndex: null,
            );
          }

          if (index < firstRegularIndex) {
            final group = groups[index - firstFolderIndex];
            return _ScriptFolderCard(
              key: ValueKey('home_group_list_${group.id}'),
              name: _displayGroupName(group.name),
              masked: _maskScriptNames,
              count:
                  group.id == null ? 0 : provider.scriptCountInGroup(group.id!),
              grid: false,
              onTap: _multiSelectMode ? null : () => _openGroup(group),
              onLongPress:
                  _multiSelectMode ? null : () => _showGroupContextMenu(group),
            );
          }

          return _buildFolderHomeScriptListItem(
            regularScripts[index - firstRegularIndex],
            index - groups.length,
            reorderIndex: null,
          );
        },
      );
    }

    return ListView.builder(
      itemExtentBuilder: (index, _) {
        if (index < firstFolderIndex) return _scriptListItemExtent;
        if (index < firstRegularIndex) return _folderListItemExtent;
        return _scriptListItemExtent;
      },
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index < firstFolderIndex) {
          return _buildFolderHomeScriptListItem(
            pinnedScripts[index],
            index,
            reorderIndex: null,
          );
        }

        if (index < firstRegularIndex) {
          final group = groups[index - firstFolderIndex];
          return _ScriptFolderCard(
            key: ValueKey('home_group_reorder_${group.id}'),
            name: _displayGroupName(group.name),
            masked: _maskScriptNames,
            count:
                group.id == null ? 0 : provider.scriptCountInGroup(group.id!),
            grid: false,
            onTap: _multiSelectMode ? null : () => _openGroup(group),
            onLongPress:
                _multiSelectMode ? null : () => _showGroupContextMenu(group),
          );
        }

        return _buildFolderHomeScriptListItem(
          regularScripts[index - firstRegularIndex],
          index - groups.length,
          reorderIndex: index,
        );
      },
    );
  }

  Widget _buildFolderHomeScriptListItem(dynamic script, int index,
      {required int? reorderIndex}) {
    final colors = Theme.of(context).colorScheme;
    final displayName = _displayScriptName(script.name, index);
    final selected = _selectedScripts.contains(script.name);
    final canDragScript = reorderIndex != null && !script.isPinned;

    final card = _ScriptCardSurface(
      key: ValueKey('home_script_${script.name}'),
      colors: colors,
      selected: _multiSelectMode && selected,
      pinned: script.isPinned,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _multiSelectMode
            ? setState(() {
                if (selected) {
                  _selectedScripts.remove(script.name);
                } else {
                  _selectedScripts.add(script.name);
                }
              })
            : _openEditor(script.name),
        onLongPress: () => _multiSelectMode
            ? null
            : _showContextMenu(script.name, script.isPinned,
                groupId: script.groupId),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              if (_multiSelectMode)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Checkbox(
                    value: selected,
                    onChanged: (_) => setState(() {
                      if (selected) {
                        _selectedScripts.remove(script.name);
                      } else {
                        _selectedScripts.add(script.name);
                      }
                    }),
                  ),
                )
              else ...[
                if (canDragScript)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _buildListDragHandle(
                      script.name,
                      colors.onSurfaceVariant,
                    ),
                  ),
                _ScriptIcon(colors: colors, size: 44),
              ],
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildMaskedScriptNameText(
                            displayName,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            maxLines: 1,
                          ),
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
    );

    if (!canDragScript) return card;
    return _buildListDragTarget(
      scriptName: script.name,
      groupId: null,
      child: card,
    );
  }

  Widget _buildFolderHomeGridScriptCard(dynamic script, int index,
      {required bool draggable}) {
    final selected = _selectedScripts.contains(script.name);

    Widget card({Widget? dragHandle, bool feedback = false}) {
      return _ScriptGridCard(
        key: feedback ? null : ValueKey('home_script_grid_${script.name}'),
        name: _displayScriptName(script.name, index),
        masked: _maskScriptNames,
        modifiedAt: script.modifiedAt,
        runCount: script.runCount,
        dateFormat: _dateFormat,
        pinned: script.isPinned,
        selected: feedback ? null : (_multiSelectMode ? selected : null),
        dragHandle: dragHandle,
        onTap: feedback
            ? () {}
            : () => _multiSelectMode
                ? setState(() {
                    if (selected) {
                      _selectedScripts.remove(script.name);
                    } else {
                      _selectedScripts.add(script.name);
                    }
                  })
                : _openEditor(script.name),
        onLongPress: feedback
            ? () {}
            : () => _multiSelectMode
                ? null
                : _showContextMenu(script.name, script.isPinned,
                    groupId: script.groupId),
        onRun:
            feedback || _multiSelectMode ? null : () => _runScript(script.name),
      );
    }

    if (!draggable) {
      return card();
    }

    final dragHandle = Draggable<String>(
      data: script.name,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedbackOffset: const Offset(90, 62.5),
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 180,
          height: 125,
          child: card(
            feedback: true,
            dragHandle: _GridDragHandle(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: _GridDragHandle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      child: _GridDragHandle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );

    return DragTarget<String>(
      key: ValueKey('home_script_grid_target_${script.name}'),
      onWillAcceptWithDetails: (details) {
        final draggedName = details.data;
        if (draggedName == script.name) return true;
        final dragged = context
            .read<ScriptProvider>()
            .ungroupedScripts
            .where((s) => s.name == draggedName)
            .cast<dynamic>()
            .toList();
        return dragged.isNotEmpty && dragged.first.isPinned == false;
      },
      onAcceptWithDetails: (details) {
        if (details.data == script.name) return;
        context
            .read<ScriptProvider>()
            .swapScriptPositionsByName(details.data, script.name);
      },
      builder: (context, candidateData, rejectedData) {
        return AnimatedScale(
          scale: candidateData.isEmpty ? 1 : 0.98,
          duration: const Duration(milliseconds: 120),
          child: card(dragHandle: dragHandle),
        );
      },
    );
  }

  void _beginGridDrag(String scriptName) {
    _gridDraggingScriptName = scriptName;
    _gridDragPreviewTargetName = null;
  }

  void _endGridDrag() {
    if (_gridDraggingScriptName == null && _gridDragPreviewTargetName == null) {
      return;
    }
    setState(() {
      _gridDraggingScriptName = null;
      _gridDragPreviewTargetName = null;
    });
  }

  void _previewGridDragTarget(String draggedName, String targetName) {
    if (_gridDraggingScriptName != draggedName) return;
    final nextTargetName = draggedName == targetName ? null : targetName;
    if (_gridDragPreviewTargetName == nextTargetName) return;

    setState(() {
      _gridDragPreviewTargetName = nextTargetName;
    });
  }

  void _commitGridDragTarget(String draggedName, String targetName) {
    if (draggedName != targetName) {
      context
          .read<ScriptProvider>()
          .swapScriptPositionsByName(draggedName, targetName);
    }
    _endGridDrag();
  }

  Widget _buildListView(List<dynamic> scripts) {
    final colors = Theme.of(context).colorScheme;
    final canDrag = !_multiSelectMode && !_searchMode;

    Widget buildItem(int index) {
      final script = scripts[index];
      final displayName = _displayScriptName(script.name, index);
      final selected = _selectedScripts.contains(script.name);
      final canDragScript = canDrag && !script.isPinned;
      final card = _ScriptCardSurface(
        key: ValueKey('script_${script.name}'),
        colors: colors,
        selected: _multiSelectMode && selected,
        pinned: script.isPinned,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _multiSelectMode
              ? setState(() {
                  if (selected) {
                    _selectedScripts.remove(script.name);
                  } else {
                    _selectedScripts.add(script.name);
                  }
                })
              : _openEditor(script.name),
          onLongPress: () => _multiSelectMode
              ? null
              : _showContextMenu(script.name, script.isPinned,
                  groupId: script.groupId),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                if (_multiSelectMode)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Checkbox(
                      value: selected,
                      onChanged: (_) => setState(() {
                        if (selected) {
                          _selectedScripts.remove(script.name);
                        } else {
                          _selectedScripts.add(script.name);
                        }
                      }),
                    ),
                  )
                else ...[
                  if (canDragScript)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: _buildListDragHandle(
                        script.name,
                        colors.onSurfaceVariant,
                      ),
                    ),
                  _ScriptIcon(colors: colors, size: 44),
                ],
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildMaskedScriptNameText(
                              displayName,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              maxLines: 1,
                            ),
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
      );

      if (!canDragScript) return card;
      return _buildListDragTarget(
        scriptName: script.name,
        groupId: _activeGroupId,
        child: card,
      );
    }

    if (!canDrag) {
      return ListView.builder(
        itemExtentBuilder: (_, __) => _scriptListItemExtent,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: scripts.length,
        itemBuilder: (context, index) => buildItem(index),
      );
    }

    return ListView.builder(
      itemExtentBuilder: (_, __) => _scriptListItemExtent,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: scripts.length,
      itemBuilder: (context, index) => buildItem(index),
    );
  }

  Widget _buildGridView(List<dynamic> scripts) {
    final canDrag = !_multiSelectMode && !_searchMode;
    final indexByName = <String, int>{};
    for (int i = 0; i < scripts.length; i++) {
      indexByName[scripts[i].name] = i;
    }

    Widget buildStaticGridItem(int index) {
      final script = scripts[index];
      final selected = _selectedScripts.contains(script.name);
      return _ScriptGridCard(
        key: ValueKey('script_grid_static_${script.name}'),
        name: _displayScriptName(script.name, index),
        masked: _maskScriptNames,
        modifiedAt: script.modifiedAt,
        runCount: script.runCount,
        dateFormat: _dateFormat,
        pinned: script.isPinned,
        selected: _multiSelectMode ? selected : null,
        onTap: () => _multiSelectMode
            ? setState(() {
                if (selected) {
                  _selectedScripts.remove(script.name);
                } else {
                  _selectedScripts.add(script.name);
                }
              })
            : _openEditor(script.name),
        onLongPress: () => _multiSelectMode
            ? null
            : _showContextMenu(script.name, script.isPinned,
                groupId: script.groupId),
        onRun: _multiSelectMode ? null : () => _runScript(script.name),
      );
    }

    dynamic previewScriptForSlot(int index) {
      final draggedName = _gridDraggingScriptName;
      final targetName = _gridDragPreviewTargetName;
      if (draggedName == null || targetName == null) return scripts[index];

      final originIndex = indexByName[draggedName];
      final targetIndex = indexByName[targetName];
      if (originIndex == null || targetIndex == null) return scripts[index];

      if (index == originIndex) return scripts[targetIndex];
      if (index == targetIndex) return null;
      return scripts[index];
    }

    Widget buildGridItem(int index) {
      final slotScript = scripts[index];
      final displayScript = previewScriptForSlot(index);
      final selected = displayScript == null
          ? false
          : _selectedScripts.contains(displayScript.name);
      final canDragScript = displayScript != null &&
          _gridDraggingScriptName == null &&
          canDrag &&
          !displayScript.isPinned;
      final targetKey = GlobalKey();

      if (displayScript == null) {
        return DragTarget<String>(
          key: ValueKey('script_grid_placeholder_${slotScript.name}'),
          onWillAcceptWithDetails: (details) {
            final draggedName = details.data;
            if (draggedName == slotScript.name) return true;
            final oldIndex = indexByName[draggedName];
            if (oldIndex == null || oldIndex >= scripts.length) return false;
            return !scripts[oldIndex].isPinned && !slotScript.isPinned;
          },
          onMove: (details) {
            _previewGridDragTarget(details.data, slotScript.name);
          },
          onAcceptWithDetails: (details) {
            _commitGridDragTarget(details.data, slotScript.name);
          },
          builder: (context, candidateData, rejectedData) {
            return KeyedSubtree(
              key: targetKey,
              child: _ScriptGridPlaceholder(
                colors: Theme.of(context).colorScheme,
              ),
            );
          },
        );
      }

      Widget card({Widget? dragHandle, bool feedback = false}) {
        return _ScriptGridCard(
          key: feedback ? null : ValueKey('script_grid_${displayScript.name}'),
          name: _displayScriptName(displayScript.name, index),
          masked: _maskScriptNames,
          modifiedAt: displayScript.modifiedAt,
          runCount: displayScript.runCount,
          dateFormat: _dateFormat,
          pinned: displayScript.isPinned,
          selected: feedback ? null : (_multiSelectMode ? selected : null),
          dragHandle: dragHandle,
          onTap: feedback
              ? () {}
              : () => _multiSelectMode
                  ? setState(() {
                      if (selected) {
                        _selectedScripts.remove(displayScript.name);
                      } else {
                        _selectedScripts.add(displayScript.name);
                      }
                    })
                  : _openEditor(displayScript.name),
          onLongPress: feedback
              ? () {}
              : () => _multiSelectMode
                  ? null
                  : _showContextMenu(displayScript.name, displayScript.isPinned,
                      groupId: displayScript.groupId),
          onRun: feedback || _multiSelectMode
              ? null
              : () => _runScript(displayScript.name),
        );
      }

      final dragHandle = canDragScript
          ? Draggable<String>(
              data: displayScript.name,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              feedbackOffset: const Offset(90, 62.5),
              onDragStarted: () => _beginGridDrag(displayScript.name),
              onDragEnd: (_) => _endGridDrag(),
              onDraggableCanceled: (_, __) => _endGridDrag(),
              onDragCompleted: _endGridDrag,
              feedback: Material(
                color: Colors.transparent,
                child: SizedBox(
                  width: 180,
                  height: 125,
                  child: card(
                    feedback: true,
                    dragHandle: _GridDragHandle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.35,
                child: _GridDragHandle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              child: _GridDragHandle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          : null;

      return DragTarget<String>(
        key: ValueKey('script_grid_target_${displayScript.name}'),
        onWillAcceptWithDetails: (details) {
          final draggedName = details.data;
          if (draggedName == slotScript.name) return true;
          final oldIndex = indexByName[draggedName];
          if (oldIndex == null || oldIndex >= scripts.length) return false;
          return !scripts[oldIndex].isPinned && !slotScript.isPinned;
        },
        onMove: (details) {
          _previewGridDragTarget(details.data, slotScript.name);
        },
        onAcceptWithDetails: (details) {
          _commitGridDragTarget(details.data, slotScript.name);
        },
        builder: (context, candidateData, rejectedData) {
          return AnimatedScale(
            scale: candidateData.isEmpty ? 1 : 0.98,
            duration: const Duration(milliseconds: 120),
            child: KeyedSubtree(
              key: targetKey,
              child: card(dragHandle: dragHandle),
            ),
          );
        },
      );
    }

    const gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      childAspectRatio: 1.44,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
    );

    if (!canDrag) {
      return GridView.builder(
        key: _gridViewKey,
        controller: _gridScrollController,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        gridDelegate: gridDelegate,
        itemCount: scripts.length,
        itemBuilder: (context, index) => buildStaticGridItem(index),
      );
    }

    final generatedChildren =
        List.generate(scripts.length, (index) => buildGridItem(index));

    return ReorderableBuilder(
      scrollController: _gridScrollController,
      enableDraggable: false,
      children: generatedChildren,
      builder: (children) {
        return GridView(
          key: _gridViewKey,
          controller: _gridScrollController,
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          gridDelegate: gridDelegate,
          children: children,
        );
      },
    );
  }
}

class _ScriptFolderCard extends StatelessWidget {
  final String name;
  final bool masked;
  final int count;
  final bool grid;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _ScriptFolderCard({
    super.key,
    required this.name,
    required this.masked,
    required this.count,
    required this.grid,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final content = InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: EdgeInsets.all(grid ? 12 : 14),
        child: grid
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.folder_rounded, size: 42, color: colors.primary),
                  const Spacer(),
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color:
                          masked ? const Color(0xFF050505) : colors.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '$count 个脚本',
                    style:
                        TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                  ),
                ],
              )
            : Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.folder_rounded,
                        color: colors.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: masked
                                ? const Color(0xFF050505)
                                : colors.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '$count 个脚本',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: colors.onSurfaceVariant),
                ],
              ),
      ),
    );

    return _ScriptCardSurface(
      colors: colors,
      selected: false,
      pinned: false,
      margin: grid
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: content,
    );
  }
}

class _ScriptGridCard extends StatelessWidget {
  final String name;
  final bool masked;
  final DateTime modifiedAt;
  final int runCount;
  final DateFormat dateFormat;
  final bool pinned;
  final bool? selected;
  final Widget? dragHandle;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onRun;

  const _ScriptGridCard({
    super.key,
    required this.name,
    required this.masked,
    required this.modifiedAt,
    required this.runCount,
    required this.dateFormat,
    required this.pinned,
    this.selected,
    this.dragHandle,
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
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _ScriptIcon(colors: colors, size: 36, fontSize: 13),
                      const Spacer(),
                      if (pinned && selected == null)
                        _PinnedBadge(colors: colors),
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
                          color: masked
                              ? const Color(0xFF050505)
                              : colors.onSurface),
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
            if (dragHandle != null)
              Positioned(
                right: 8,
                bottom: 20,
                child: dragHandle!,
              ),
          ],
        ),
      ),
    );
  }
}

class _GridDragHandle extends StatelessWidget {
  final Color color;

  const _GridDragHandle({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 28,
      child: Center(
        child: Icon(Icons.drag_indicator, size: 18, color: color),
      ),
    );
  }
}

class _ScriptGridPlaceholder extends StatelessWidget {
  final ColorScheme colors;

  const _ScriptGridPlaceholder({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.primary.withValues(alpha: 0.32),
          width: 1.2,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.open_with_rounded,
        size: 24,
        color: colors.primary.withValues(alpha: 0.55),
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
    super.key,
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
