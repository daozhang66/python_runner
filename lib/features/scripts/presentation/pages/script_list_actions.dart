// ignore_for_file: invalid_use_of_protected_member

part of 'script_list_page.dart';

// Script workspace actions stay in the presentation library for focused ownership.

extension _ScriptListActions on _ScriptListPageState {
  Future<void> _setViewMode(bool isGridView) async {
    if (_isGridView == isGridView) return;
    setState(() {
      _isGridView = isGridView;
    });
    await ref.read(scriptWorkspaceUiProvider.notifier).setGridView(isGridView);
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
    final groupScripts = ref
        .read(scriptWorkspaceControllerProvider.notifier)
        .scriptsInGroup(groupId);
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
    ref
        .read(scriptWorkspaceControllerProvider.notifier)
        .swapScriptPositionsByName(
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
          SnackBar(content: Text(AppLocalizations.of(context)!.linuxLikeOnly)),
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
      case 'reorder':
        setState(() => _reorderMode = true);
        break;
      case 'select':
        _enterMultiSelect();
        break;
    }
  }

  String _formatRunLabel(int runCount) => runCount > 0
      ? AppLocalizations.of(context)!.runsCount(runCount)
      : AppLocalizations.of(context)!.notRun;

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
              title: Text(AppLocalizations.of(context)!.newFile),
              subtitle:
                  Text(AppLocalizations.of(context)!.newScriptDescription),
              onTap: () {
                Navigator.pop(ctx);
                _createScript();
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_open_outlined),
              title: Text(AppLocalizations.of(context)!.addScript),
              subtitle:
                  Text(AppLocalizations.of(context)!.importScriptDescription),
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
        title: Text(AppLocalizations.of(ctx)!.addGroup),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: AppLocalizations.of(ctx)!.groupName,
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          maxLength: 30,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(ctx)!.cancel),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              final success = await ref
                  .read(scriptWorkspaceControllerProvider.notifier)
                  .createGroup(name);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(success
                      ? AppLocalizations.of(context)!.groupAdded(name)
                      : AppLocalizations.of(context)!.groupCreateFailed),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: Text(AppLocalizations.of(ctx)!.create),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  String _generateProjectKey() =>
      'project_${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';

  void _showCreateProjectDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx)!.newProject),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: AppLocalizations.of(ctx)!.projectName,
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          maxLength: 30,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(ctx)!.cancel),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              await _createProject(name);
            },
            child: Text(AppLocalizations.of(ctx)!.create),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _createProject(String name) async {
    final projectKey = _generateProjectKey();
    final service = ScriptProjectService(_bridge);
    final scriptProvider = ref.read(scriptWorkspaceControllerProvider.notifier);
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
            SnackBar(
                content:
                    Text(AppLocalizations.of(context)!.projectCreateFailed)),
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
          SnackBar(
              content:
                  Text(AppLocalizations.of(context)!.projectCreateError(e))),
        );
      }
    }
  }

  Future<void> _importProjectZip() async {
    final selected = await AppFilePickerPage.pickFile(
      context,
      title: AppLocalizations.of(context)!.importProjectZip,
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
            SnackBar(
                content:
                    Text(AppLocalizations.of(context)!.unableToReadZipPath)),
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
    final name = await _askProjectName(
        defaultName.isEmpty ? 'Imported project' : defaultName);
    if (name == null || name.isEmpty) return;
    if (!mounted) return;

    final projectKey = _generateProjectKey();
    final service = ScriptProjectService(_bridge);
    final scriptProvider = ref.read(scriptWorkspaceControllerProvider.notifier);
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
            SnackBar(
                content:
                    Text(AppLocalizations.of(context)!.projectCreateFailed)),
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
          SnackBar(
              content:
                  Text(AppLocalizations.of(context)!.projectImportFailed(e))),
        );
      }
    }
  }

  Future<String?> _askProjectName(String defaultName) {
    final controller = TextEditingController(text: defaultName);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx)!.projectName),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(ctx)!.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(AppLocalizations.of(ctx)!.confirm),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  void _createScript() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx)!.newFile),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: AppLocalizations.of(ctx)!.scriptName,
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(ctx)!.cancel)),
          TextButton(
            onPressed: () async {
              var name = controller.text.trim();
              if (name.isEmpty) return;
              if (!name.endsWith('.py')) name += '.py';
              Navigator.pop(ctx);
              final success = await ref
                  .read(scriptWorkspaceControllerProvider.notifier)
                  .createScript(
                    name,
                    content:
                        '# ${name.replaceAll(".py", "")}\n\nprint("Hello, Python!")\n',
                    groupId: _activeGroupId,
                  );
              if (success && mounted) _openEditor(name);
            },
            child: Text(AppLocalizations.of(ctx)!.create),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  void _importScript() async {
    final selected = await AppFilePickerPage.pickFile(
      context,
      title: AppLocalizations.of(context)!.addScript,
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!.onlyPythonFiles),
            duration: Duration(seconds: 2)));
      }
      return;
    }
    if (bytes == null || !mounted) return;
    final content = utf8.decode(bytes, allowMalformed: true);

    // Check if script with same name already exists
    final controller = ref.read(scriptWorkspaceControllerProvider.notifier);
    final exists = controller.scripts.any((s) => s.name == name);
    if (exists) {
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(AppLocalizations.of(ctx)!.scriptExists),
          content: Text(AppLocalizations.of(ctx)!.scriptExistsConfirm(name)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(AppLocalizations.of(ctx)!.cancel)),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(AppLocalizations.of(ctx)!.overwrite,
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            ),
          ],
        ),
      );
      if (overwrite != true) return;
      // Overwrite existing script content
      await controller.saveScript(name, content);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(AppLocalizations.of(context)!.scriptOverwritten(name)),
            duration: const Duration(seconds: 2)));
      }
    } else {
      await controller.createScript(name,
          content: content, groupId: _activeGroupId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!.scriptImported(name)),
            duration: const Duration(seconds: 2)));
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

  void _openConsole(String name) {
    Navigator.push(
      context,
      AppPageTransitions.fadeThrough(RunConsolePage(scriptName: name)),
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
              content: Text(AppLocalizations.of(context)!.exportedTo(path)),
              duration: const Duration(seconds: 3)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.exportFailed)),
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
            content: Text(AppLocalizations.of(context)!.exportedScriptsTo(
                ok, lastPath?.replaceAll(RegExp(r"/[^/]+$"), "") ?? destDir)),
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
        title: AppLocalizations.of(context)!.bulkDelete,
        content: AppLocalizations.of(context)!.deleteScriptsConfirm(count),
        confirmText: AppLocalizations.of(context)!.deleteCount(count),
        confirmColor: Theme.of(context).colorScheme.error);
    if (!confirmed || !mounted) return;
    final controller = ref.read(scriptWorkspaceControllerProvider.notifier);
    for (final name in _selectedScripts.toList()) {
      await controller.deleteScript(name);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)!.scriptsDeleted(count)),
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
    final controller = ref.read(scriptWorkspaceControllerProvider.notifier);
    final groups = controller.groups.where((group) {
      final id = group.id;
      return id != null && ids.contains(id);
    }).toList();
    if (groups.isEmpty) return;

    final projectCount = groups.where((group) => group.isProject).length;
    final regularCount = groups.length - projectCount;
    final content = projectCount > 0
        ? AppLocalizations.of(context)!
            .groupsDeleteConfirm(regularCount, projectCount)
        : AppLocalizations.of(context)!.groupsDeleteOnlyConfirm(regularCount);
    final confirmed = await ConfirmDialog.show(
      context,
      title: AppLocalizations.of(context)!.bulkDeleteGroups,
      content: content,
      confirmText: AppLocalizations.of(context)!.deleteCount(groups.length),
      confirmColor: Theme.of(context).colorScheme.error,
    );
    if (!confirmed || !mounted) return;

    var ok = 0;
    for (final group in groups) {
      final id = group.id;
      if (id == null) continue;
      final success = await controller.deleteGroup(id);
      if (success) ok++;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.groupsDeleted(ok)),
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
    await ref
        .read(scriptWorkspaceControllerProvider.notifier)
        .moveScriptsToGroup(names, groupId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(groupId == null
            ? AppLocalizations.of(context)!.scriptsMovedHome(names.length)
            : AppLocalizations.of(context)!.scriptsMovedTo(
                names.length,
                _maskScriptNames ? _maskedScriptName : targetLabel,
              )),
        duration: const Duration(seconds: 2),
      ),
    );
    setState(() {
      _multiSelectMode = false;
      _selectedScripts.clear();
    });
  }

  void _showMoveToGroupSheet({String? singleName}) {
    final controller = ref.read(scriptWorkspaceControllerProvider.notifier);
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
              ListTile(
                leading: Icon(Icons.drive_file_move_outline),
                title: Text(AppLocalizations.of(context)!.moveToGroup),
              ),
              if (_activeGroupId != null)
                ListTile(
                  leading: const Icon(Icons.home_outlined),
                  title: Text(AppLocalizations.of(context)!.moveToHome),
                  onTap: () {
                    Navigator.pop(ctx);
                    _moveScriptsToGroup(
                        names, null, AppLocalizations.of(context)!.all);
                  },
                ),
              for (final group in controller.groups)
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
                title: Text(AppLocalizations.of(context)!.newGroup),
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
      final scriptProvider =
          ref.read(scriptWorkspaceControllerProvider.notifier);
      final execProvider = legacy_provider.Provider.of<ExecutionProvider>(
          context,
          listen: false);
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
              content: Text(AppLocalizations.of(context)!.runFailed(e)),
              duration: const Duration(seconds: 3)),
        );
      }
    }
  }

  Future<void> _togglePinned(String name) async {
    await ref
        .read(scriptWorkspaceControllerProvider.notifier)
        .togglePinned(name);
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
                title: Text(isPinned
                    ? AppLocalizations.of(context)!.unpin
                    : AppLocalizations.of(context)!.pin),
                onTap: () {
                  Navigator.pop(ctx);
                  _togglePinned(name);
                }),
            ListTile(
                leading: const Icon(Icons.drive_file_move_outline),
                title: Text(AppLocalizations.of(context)!.moveToGroup),
                onTap: () {
                  Navigator.pop(ctx);
                  _showMoveToGroupSheet(singleName: name);
                }),
            if (groupId != null)
              ListTile(
                  leading: const Icon(Icons.home_outlined),
                  title: Text(AppLocalizations.of(context)!.moveToHome),
                  onTap: () {
                    Navigator.pop(ctx);
                    _moveScriptsToGroup(
                        {name}, null, AppLocalizations.of(context)!.all);
                  }),
            ListTile(
                leading: const Icon(Icons.edit),
                title: Text(AppLocalizations.of(context)!.rename),
                onTap: () {
                  Navigator.pop(ctx);
                  _renameScript(name);
                }),
            ListTile(
                leading: const Icon(Icons.copy),
                title: Text(AppLocalizations.of(context)!.copy),
                onTap: () {
                  Navigator.pop(ctx);
                  _duplicateScript(name);
                }),
            ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: Text(AppLocalizations.of(context)!.exportToDevice),
                onTap: () {
                  Navigator.pop(ctx);
                  _exportScript(name);
                }),
            ListTile(
                leading: Icon(Icons.delete,
                    color: Theme.of(context).colorScheme.error),
                title: Text(AppLocalizations.of(context)!.delete,
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
        title: Text(AppLocalizations.of(ctx)!.rename),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(ctx)!.cancel)),
          TextButton(
            onPressed: () {
              var newName = controller.text.trim();
              if (newName.isEmpty) return;
              if (!newName.endsWith('.py')) newName += '.py';
              if (newName == oldName) return;
              Navigator.pop(ctx);
              ref
                  .read(scriptWorkspaceControllerProvider.notifier)
                  .renameScript(oldName, newName);
            },
            child: Text(AppLocalizations.of(ctx)!.confirm),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _duplicateScript(String name) async {
    try {
      final controller = ref.read(scriptWorkspaceControllerProvider.notifier);
      final content = await controller.readScript(name);
      final copyName = name.replaceAll('.py', '_copy.py');
      await controller.createScript(copyName, content: content);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context)!.copyFailed(e)),
              duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  Future<void> _deleteScript(String name) async {
    final confirmed = await ConfirmDialog.show(context,
        title: AppLocalizations.of(context)!.deleteScript,
        content: AppLocalizations.of(context)!
            .deleteScriptConfirm(name.replaceAll('.py', '')),
        confirmText: AppLocalizations.of(context)!.delete,
        confirmColor: Theme.of(context).colorScheme.error);
    if (confirmed && mounted) {
      ref.read(scriptWorkspaceControllerProvider.notifier).deleteScript(name);
    }
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
              title: Text(AppLocalizations.of(context)!.multiSelect),
              onTap: () {
                Navigator.pop(ctx);
                _enterGroupSelect(initialGroup: group);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(AppLocalizations.of(context)!.rename),
              onTap: () {
                Navigator.pop(ctx);
                _renameGroup(group);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: Text(AppLocalizations.of(context)!.delete,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              subtitle: Text(group.isProject
                  ? AppLocalizations.of(context)!.projectFilesDeleted
                  : AppLocalizations.of(context)!.groupScriptsReturnHome),
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
        title: Text(AppLocalizations.of(ctx)!.rename),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          autofocus: true,
          maxLength: 30,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(ctx)!.cancel),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              final success = await ref
                  .read(scriptWorkspaceControllerProvider.notifier)
                  .renameGroup(group.id!, name);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (success && mounted && _activeGroupId == group.id) {
                setState(() => _activeGroupName = name);
              }
            },
            child: Text(AppLocalizations.of(ctx)!.confirm),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _deleteGroup(ScriptGroup group) async {
    if (group.id == null) return;
    final confirmed = await ConfirmDialog.show(
      context,
      title: group.isProject
          ? AppLocalizations.of(context)!.deleteProject
          : AppLocalizations.of(context)!.deleteGroup,
      content: group.isProject
          ? AppLocalizations.of(context)!.deleteProjectConfirm(group.name)
          : AppLocalizations.of(context)!.deleteGroupConfirm(group.name),
      confirmText: AppLocalizations.of(context)!.delete,
      confirmColor: Theme.of(context).colorScheme.error,
    );
    if (!confirmed || !mounted) return;
    final success = await ref
        .read(scriptWorkspaceControllerProvider.notifier)
        .deleteGroup(group.id!);
    if (success && mounted && _activeGroupId == group.id) {
      _closeGroup();
    }
  }
}
