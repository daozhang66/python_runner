import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as legacy_provider;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import '../../../../features/scripts/application/script_workspace_controller.dart';
import '../../../../models/script_file.dart';
import '../../../../models/script_group.dart';
import '../../../../providers/script_workspace_ui_provider.dart';
import '../../../../providers/execution_provider.dart';
import '../../../../runtime/runtime_manager.dart';
import '../../../../services/native_bridge.dart';
import '../../../../services/script_project_service.dart';
import '../../../../ui/app_design_tokens.dart';
import '../../../../ui/app_badges.dart';
import '../../../../ui/app_empty_state.dart';
import '../../../../ui/app_responsive.dart';
import '../../../../ui/app_state_views.dart';
import '../../../../ui/app_skeleton.dart';
import '../../../../ui/app_surfaces.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../utils/app_page_transitions.dart';
import '../../../../widgets/confirm_dialog.dart';
import 'script_project_page.dart';
import 'script_editor_page.dart';
import '../../../console/presentation/pages/run_console_page.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../../../../pages/app_file_picker_page.dart';

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

class ScriptListPage extends ConsumerStatefulWidget {
  final VoidCallback? onSettingsTap;
  final ScriptListPageController? controller;

  const ScriptListPage({
    super.key,
    this.onSettingsTap,
    this.controller,
  });

  @override
  ConsumerState<ScriptListPage> createState() => _ScriptListPageState();
}

class _ScriptListPageState extends ConsumerState<ScriptListPage> {
  static const double _scriptListItemExtent = 94;
  static const double _folderListItemExtent = 84;

  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');
  bool _isGridView = false;
  bool _maskScriptNames = false;
  final _bridge = NativeBridge();
  final _searchController = TextEditingController();
  final _gridScrollController = ScrollController();
  final _gridViewKey = GlobalKey();
  final Map<String, GlobalKey> _gridItemKeys = {};
  String? _gridDraggingScriptName;
  String? _gridDragPreviewTargetName;
  String _searchQuery = '';
  bool _searchMode = false;
  bool _multiSelectMode = false;
  bool _groupSelectMode = false;
  bool _reorderMode = false;
  bool _linuxLikeSelected = false;
  bool _linuxLikeAvailable = false;
  int? _activeGroupId;
  String? _activeGroupName;
  final Set<String> _selectedScripts = {};
  final Set<int> _selectedGroupIds = {};

  bool get _canUseProjects => _linuxLikeSelected && _linuxLikeAvailable;

  GlobalKey _gridItemKey(String scriptName) =>
      _gridItemKeys.putIfAbsent(scriptName, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    _isGridView = ref.read(scriptWorkspaceUiProvider).isGridView;
    _loadScriptNameMaskPreference();
    _loadProjectAvailability();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(scriptWorkspaceControllerProvider.notifier).load();
      }
    });
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
    final l10n = AppLocalizations.of(context)!;
    return PopupMenuButton<String>(
      onSelected: _handleMoreAction,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'add',
          child: ListTile(
            leading: const Icon(Icons.add_circle_outline),
            title: Text(l10n.addScript),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'add_group',
          child: ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: Text(l10n.addGroup),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (_canUseProjects)
          PopupMenuItem(
            value: 'add_project',
            child: ListTile(
              leading: const Icon(Icons.account_tree_outlined),
              title: Text(l10n.newProject),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (_canUseProjects)
          PopupMenuItem(
            value: 'import_project_zip',
            child: ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text(l10n.importProjectZip),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        PopupMenuItem(
          value: 'search',
          child: ListTile(
            leading: const Icon(Icons.search),
            title: Text(l10n.searchScripts),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'toggle_view',
          child: ListTile(
            leading: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
            title: Text(_isGridView ? l10n.listView : l10n.gridView),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'reorder',
          child: ListTile(
            leading: const Icon(Icons.reorder_rounded),
            title: Text(l10n.reorderScripts),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'select',
          child: ListTile(
            leading: const Icon(Icons.checklist),
            title: Text(l10n.multiSelect),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  Widget _buildScriptNameVisibilityButton() {
    final l10n = AppLocalizations.of(context)!;
    return IconButton(
      icon: Icon(_maskScriptNames
          ? Icons.visibility_off_outlined
          : Icons.visibility_outlined),
      tooltip: _maskScriptNames ? l10n.showScriptNames : l10n.hideScriptNames,
      onPressed: _toggleScriptNameMask,
    );
  }

  bool get _isTabletWorkspace => AppBreakpoints.isTablet(context);

  void _handleScriptTap(String name) {
    if (_isTabletWorkspace) {
      ref.read(scriptWorkspaceUiProvider.notifier).setSelectedScript(name);
      return;
    }
    _openEditor(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = ref.read(scriptWorkspaceControllerProvider.notifier);
    final scriptSnapshot = ref.watch(
      scriptWorkspaceControllerProvider.select((state) => state.layout),
    );
    final allScripts = scriptSnapshot.scripts;
    final homeScripts = controller.ungroupedScripts;
    final baseScripts = _activeGroupId == null
        ? homeScripts
        : controller.scriptsInGroup(_activeGroupId);
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
        ? scriptSnapshot.groups.where((group) => group.id != null).toList()
        : <ScriptGroup>[];
    final allGroupsSelected = selectableGroups.isNotEmpty &&
        selectableGroups.every((group) => _selectedGroupIds.contains(group.id));
    final showFolderHome = _activeGroupId == null && _searchQuery.isEmpty;
    final hasBodyContent = showFolderHome
        ? scriptSnapshot.groups.isNotEmpty || scripts.isNotEmpty
        : scripts.isNotEmpty;
    final selectedScriptName = ref.watch(
      scriptWorkspaceUiProvider.select((state) => state.selectedScriptName),
    );
    if (_isTabletWorkspace &&
        selectedScriptName != null &&
        _findScriptByName(allScripts, selectedScriptName) == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(scriptWorkspaceUiProvider.notifier).setSelectedScript(null);
      });
    }

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
              title: Text(l10n.selectedGroupsCount(_selectedGroupIds.length)),
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
                  child: Text(
                      allGroupsSelected ? l10n.deselectAll : l10n.selectAll),
                ),
                if (_selectedGroupIds.isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error),
                    tooltip: l10n.bulkDeleteGroups,
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
                  title: Text(l10n.selectedItemsCount(_selectedScripts.length)),
                  actions: [
                    TextButton(
                      onPressed: () => setState(() {
                        if (allSelected) {
                          _selectedScripts.clear();
                        } else {
                          _selectedScripts.addAll(scripts.map((s) => s.name));
                        }
                      }),
                      child:
                          Text(allSelected ? l10n.deselectAll : l10n.selectAll),
                    ),
                    if (_selectedScripts.isNotEmpty) ...[
                      IconButton(
                        icon: const Icon(Icons.drive_file_move_outline),
                        tooltip: l10n.moveToGroup,
                        onPressed: _showMoveToGroupSheet,
                      ),
                      IconButton(
                        icon: const Icon(Icons.file_download_outlined),
                        tooltip: l10n.bulkExport,
                        onPressed: _exportSelected,
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline,
                            color: Theme.of(context).colorScheme.error),
                        tooltip: l10n.bulkDelete,
                        onPressed: _deleteSelected,
                      ),
                    ],
                  ],
                )
              : _reorderMode
                  ? AppBar(
                      leading: IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: l10n.finishReordering,
                        onPressed: () => setState(() => _reorderMode = false),
                      ),
                      title: Text(l10n.reorderScripts),
                      actions: [
                        IconButton(
                          icon: Icon(
                            _isGridView
                                ? Icons.view_list_outlined
                                : Icons.grid_view_outlined,
                          ),
                          tooltip: _isGridView ? l10n.listView : l10n.gridView,
                          onPressed: () => _setViewMode(!_isGridView),
                        ),
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
                              hintText: l10n.searchScriptsHint,
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
                                tooltip: l10n.clearSearch,
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
                                  _displayGroupName(
                                      _activeGroupName ?? l10n.group),
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
                                    tooltip: l10n.multiSelect,
                                    onPressed: _enterMultiSelect,
                                  ),
                                ],
                        ),
      body: Column(
        children: [
          if (!_multiSelectMode && _searchQuery.isNotEmpty)
            _buildSearchResultBar(searchSource.length, scripts.length),
          Expanded(
            child: scriptSnapshot.isLoading && allScripts.isEmpty
                ? const AppListSkeleton()
                : !hasBodyContent
                    ? AppEmptyState(
                        icon: Icons.code_off,
                        title: _searchQuery.isNotEmpty
                            ? l10n.noMatches
                            : l10n.noScripts,
                        subtitle: _searchQuery.isEmpty
                            ? l10n.createScriptFromMenu
                            : l10n.tryOtherKeywords,
                      )
                    : _buildWorkspaceBody(
                        controller: controller,
                        scripts: scripts,
                        showFolderHome: showFolderHome,
                        selectedScriptName: selectedScriptName,
                      ),
          ),
        ],
      ),
      floatingActionButton: null,
    );
  }
}
