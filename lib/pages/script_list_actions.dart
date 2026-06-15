// ignore_for_file: invalid_use_of_protected_member

part of 'script_list_page.dart';

extension _ScriptListActions on _ScriptListPageState {
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

  Future<void> _loadProjectAvailability() async {
    var selected = false;
    var available = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      selected = RuntimeManager.normalizePreferredBackendId(
            prefs.getString(RuntimeManager.prefsKey),
          ) ==
          RuntimeManager.linuxLikeBackendId;
      if (selected) {
        final info = await _bridge.getLinuxLikeRuntimeInfo();
        available = info['available'] == 'true';
      }
    } catch (_) {
      available = false;
    }
    if (!mounted) return;
    setState(() {
      _linuxLikeSelected = selected;
      _linuxLikeAvailable = available;
    });
  }

  String _displayScriptName(String name, int _) {
    if (!_maskScriptNames) return name.replaceAll('.py', '');
    return _maskedScriptName;
  }

  String _displayGroupName(String name) {
    if (!_maskScriptNames) return name;
    return _maskedScriptName;
  }

  TextStyle? get _maskedNameStyle => _maskScriptNames
      ? TextStyle(color: AppThemeColors.maskedText(context))
      : null;

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
    context.read<ScriptProvider>().swapScriptPositionsByName(
          draggedName,
          targetName,
          groupId: groupId,
        );
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
    if (_groupSelectMode) {
      setState(() {
        _groupSelectMode = false;
        _selectedGroupIds.clear();
      });
      return true;
    }
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
        color: _maskScriptNames
            ? AppThemeColors.maskedText(context)
            : colors.onSurface,
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
      _groupSelectMode = false;
      _selectedScripts.clear();
      _selectedGroupIds.clear();
    });
  }

  void _enterGroupSelect({ScriptGroup? initialGroup}) {
    final id = initialGroup?.id;
    setState(() {
      _groupSelectMode = true;
      _multiSelectMode = false;
      _searchMode = false;
      _searchQuery = '';
      _selectedScripts.clear();
      _selectedGroupIds.clear();
      if (id != null) _selectedGroupIds.add(id);
    });
  }

  void _toggleGroupSelection(ScriptGroup group) {
    final id = group.id;
    if (id == null) return;
    setState(() {
      if (_selectedGroupIds.contains(id)) {
        _selectedGroupIds.remove(id);
      } else {
        _selectedGroupIds.add(id);
      }
    });
  }

  void _openGroup(ScriptGroup group) {
    if (group.id == null) return;
    if (group.isProject) {
      if (!_canUseProjects) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('项目只能在 Linux-like 引擎下使用')),
        );
        _loadProjectAvailability();
        return;
      }
      Navigator.push(
        context,
        AppPageTransitions.sharedAxisLeftRight(
          ScriptProjectPage(group: group),
        ),
      );
      return;
    }
    setState(() {
      _activeGroupId = group.id;
      _activeGroupName = group.name;
      _searchMode = false;
      _searchQuery = '';
      _selectedScripts.clear();
      _multiSelectMode = false;
      _selectedGroupIds.clear();
      _groupSelectMode = false;
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
      _selectedGroupIds.clear();
      _groupSelectMode = false;
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
      case 'add_project':
        _showCreateProjectDialog();
        break;
      case 'import_project_zip':
        _importProjectZip();
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

  String _generateProjectKey() =>
      'project_${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';

  void _showCreateProjectDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建项目'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '项目名称',
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
              Navigator.pop(ctx);
              await _createProject(name);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  Future<void> _createProject(String name) async {
    final projectKey = _generateProjectKey();
    final service = ScriptProjectService(_bridge);
    final scriptProvider = context.read<ScriptProvider>();
    try {
      await service.createProject(projectKey, name);
      final group = await scriptProvider.createProjectGroup(
        name,
        projectKey: projectKey,
        mainFilePath: 'main.py',
      );
      if (group == null) {
        await service.deleteProject(projectKey);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('项目名称已存在或创建失败')),
          );
        }
        return;
      }
      if (!mounted) return;
      Navigator.push(
        context,
        AppPageTransitions.sharedAxisLeftRight(
          ScriptProjectPage(group: group),
        ),
      );
    } catch (e) {
      await service.deleteProject(projectKey);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建项目失败: $e')),
        );
      }
    }
  }

  Future<void> _importProjectZip() async {
    final selected = await AppFilePickerPage.pickFile(
      context,
      title: '导入项目 ZIP',
      allowedExtensions: const ['zip'],
    );
    if (selected == null) return;
    late final String zipPath;
    String fileName;
    if (selected.useSystemPicker) {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        withData: false,
      );
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.first;
      final path = file.path;
      fileName = file.name;
      if (path == null || path.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法读取 ZIP 路径')),
          );
        }
        return;
      }
      zipPath = path;
    } else {
      zipPath = selected.path;
      fileName = selected.name;
    }
    final defaultName =
        fileName.replaceFirst(RegExp(r'\.zip$', caseSensitive: false), '');
    final name =
        await _askProjectName(defaultName.isEmpty ? '导入项目' : defaultName);
    if (name == null || name.isEmpty) return;
    if (!mounted) return;

    final projectKey = _generateProjectKey();
    final service = ScriptProjectService(_bridge);
    final scriptProvider = context.read<ScriptProvider>();
    try {
      await service.createEmptyProject(projectKey);
      final group = await scriptProvider.createProjectGroup(
        name,
        projectKey: projectKey,
      );
      if (group == null) {
        await service.deleteProject(projectKey);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('项目名称已存在或创建失败')),
          );
        }
        return;
      }
      await _bridge.importScriptProjectZip(projectKey, zipPath);
      final files = await service.loadProjectFiles(group);
      if (!mounted) return;
      final selected = await showDialog<String>(
        context: context,
        builder: (ctx) => MainFileDialog(
          files: service.pythonFilePaths(files),
          recommendedFiles: service.recommendedMainFilePaths(files),
          currentPath: null,
        ),
      );
      if (selected != null) {
        await scriptProvider.updateProjectMainFile(
          group,
          selected.isEmpty ? null : selected,
        );
      }
      final updated = scriptProvider.groups.firstWhere(
        (item) => item.id == group.id,
        orElse: () => group,
      );
      if (!mounted) return;
      Navigator.push(
        context,
        AppPageTransitions.sharedAxisLeftRight(
          ScriptProjectPage(group: updated),
        ),
      );
    } catch (e) {
      final matches = scriptProvider.groups
          .where((group) => group.projectKey == projectKey);
      final createdGroup = matches.isEmpty ? null : matches.first;
      if (createdGroup?.id != null) {
        await scriptProvider.deleteGroup(createdGroup!.id!);
      }
      await service.deleteProject(projectKey);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入项目失败: $e')),
        );
      }
    }
  }

  Future<String?> _askProjectName(String defaultName) {
    final controller = TextEditingController(text: defaultName);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('项目名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确认'),
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
    final selected = await AppFilePickerPage.pickFile(
      context,
      title: '导入脚本',
      allowedExtensions: const ['py'],
    );
    if (selected == null) return;

    String name;
    List<int>? bytes;
    if (selected.useSystemPicker) {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['py'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      name = file.name;
      bytes = file.bytes;
    } else {
      name = selected.name;
      bytes = await _bridge.readFilePickerFile(selected.path);
    }

    if (!name.toLowerCase().endsWith('.py')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('只支持导入 .py 文件'), duration: Duration(seconds: 2)));
      }
      return;
    }
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

  Future<void> _deleteSelectedGroups() async {
    final ids = _selectedGroupIds.toList();
    if (ids.isEmpty) return;
    final provider = context.read<ScriptProvider>();
    final groups = provider.groups.where((group) {
      final id = group.id;
      return id != null && ids.contains(id);
    }).toList();
    if (groups.isEmpty) return;

    final projectCount = groups.where((group) => group.isProject).length;
    final regularCount = groups.length - projectCount;
    final content = projectCount > 0
        ? '确定要删除选中的 $regularCount 个分组和 $projectCount 个项目吗？项目文件会一并删除，普通分组内脚本会回到首页。'
        : '确定要删除选中的 $regularCount 个分组吗？分组内脚本会回到首页。';
    final confirmed = await ConfirmDialog.show(
      context,
      title: '批量删除分组',
      content: content,
      confirmText: '删除 ${groups.length} 个',
      confirmColor: Theme.of(context).colorScheme.error,
    );
    if (!confirmed || !mounted) return;

    var ok = 0;
    for (final group in groups) {
      final id = group.id;
      if (id == null) continue;
      final success = await provider.deleteGroup(id);
      if (success) ok++;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已删除 $ok 个分组'),
        duration: const Duration(seconds: 2),
      ),
    );
    setState(() {
      if (_activeGroupId != null && ids.contains(_activeGroupId)) {
        _activeGroupId = null;
        _activeGroupName = null;
      }
      _groupSelectMode = false;
      _selectedGroupIds.clear();
    });
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
                if (!group.isProject &&
                    group.id != null &&
                    group.id != _activeGroupId)
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
              leading: const Icon(Icons.library_add_check_outlined),
              title: const Text('多选管理'),
              onTap: () {
                Navigator.pop(ctx);
                _enterGroupSelect(initialGroup: group);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(group.isProject ? '重命名项目' : '重命名分组'),
              onTap: () {
                Navigator.pop(ctx);
                _renameGroup(group);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: Text(group.isProject ? '删除项目' : '删除分组',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              subtitle: Text(group.isProject ? '项目文件会一并删除' : '分组内脚本会回到首页'),
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
        title: Text(group.isProject ? '重命名项目' : '重命名分组'),
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
      title: group.isProject ? '删除项目' : '删除分组',
      content: group.isProject
          ? '确定要删除项目「${group.name}」吗？项目文件会一并删除。'
          : '确定要删除「${group.name}」吗？分组内脚本会回到首页。',
      confirmText: '删除',
      confirmColor: Theme.of(context).colorScheme.error,
    );
    if (!confirmed || !mounted) return;
    final success = await context.read<ScriptProvider>().deleteGroup(group.id!);
    if (success && mounted && _activeGroupId == group.id) {
      _closeGroup();
    }
  }
}
