import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import '../models/script_group.dart';
import '../providers/script_provider.dart';
import '../providers/execution_provider.dart';
import '../runtime/runtime_manager.dart';
import '../services/native_bridge.dart';
import '../services/script_project_service.dart';
import '../ui/app_design_tokens.dart';
import '../utils/app_page_transitions.dart';
import '../widgets/confirm_dialog.dart';
import 'script_project_page.dart';
import 'script_editor_page.dart';
import 'run_console_page.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'app_file_picker_page.dart';

part 'script_list_actions.dart';
part 'script_list_content.dart';
part 'script_list_widgets.dart';

const String _maskedScriptName = '●●●●●●';

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

  void refreshRuntimePreference() {
    _state?._loadProjectAvailability();
  }
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
  bool _groupSelectMode = false;
  bool _linuxLikeSelected = false;
  bool _linuxLikeAvailable = false;
  int? _activeGroupId;
  String? _activeGroupName;
  final Set<String> _selectedScripts = {};
  final Set<int> _selectedGroupIds = {};

  bool get _canUseProjects => _linuxLikeSelected && _linuxLikeAvailable;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    context.read<ScriptProvider>().loadScripts();
    _loadViewMode();
    _loadScriptNameMaskPreference();
    _loadProjectAvailability();
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
        if (_canUseProjects)
          const PopupMenuItem(
            value: 'add_project',
            child: ListTile(
              leading: Icon(Icons.account_tree_outlined),
              title: Text('新建项目'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (_canUseProjects)
          const PopupMenuItem(
            value: 'import_project_zip',
            child: ListTile(
              leading: Icon(Icons.archive_outlined),
              title: Text('导入项目 ZIP'),
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
    final selectableGroups = _activeGroupId == null
        ? provider.groups.where((group) => group.id != null).toList()
        : <ScriptGroup>[];
    final allGroupsSelected = selectableGroups.isNotEmpty &&
        selectableGroups.every((group) => _selectedGroupIds.contains(group.id));
    final showFolderHome = _activeGroupId == null && _searchQuery.isEmpty;
    final hasBodyContent = showFolderHome
        ? provider.groups.isNotEmpty || scripts.isNotEmpty
        : scripts.isNotEmpty;

    return Scaffold(
      appBar: _groupSelectMode
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _groupSelectMode = false;
                  _selectedGroupIds.clear();
                }),
              ),
              title: Text('已选 ${_selectedGroupIds.length} 个分组'),
              actions: [
                TextButton(
                  onPressed: () => setState(() {
                    if (allGroupsSelected) {
                      _selectedGroupIds.clear();
                    } else {
                      _selectedGroupIds
                        ..clear()
                        ..addAll(selectableGroups.map((group) => group.id!));
                    }
                  }),
                  child: Text(allGroupsSelected ? '取消全选' : '全选'),
                ),
                if (_selectedGroupIds.isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error),
                    tooltip: '批量删除分组',
                    onPressed: _deleteSelectedGroups,
                  ),
              ],
            )
          : _multiSelectMode
              ? AppBar(
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _multiSelectMode = false;
                      _selectedScripts.clear();
                      _groupSelectMode = false;
                      _selectedGroupIds.clear();
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
                        decoration: InputDecoration(
                          hintText: '搜索脚本...',
                          border: InputBorder.none,
                          prefixIcon: Icon(
                            Icons.search,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.6),
                          ),
                          filled: true,
                          fillColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHigh
                              .withValues(alpha: 0.5),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
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
                          : [
                              IconButton(
                                icon: const Icon(Icons.checklist),
                                tooltip: '多选管理',
                                onPressed: _enterMultiSelect,
                              ),
                            ],
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
}
