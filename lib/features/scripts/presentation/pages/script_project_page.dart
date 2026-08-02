import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as legacy_provider;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../features/packages/application/package_controller.dart';
import '../../../../features/packages/application/package_state.dart';
import '../../../../models/script_group.dart';
import '../../../../models/script_project_file.dart';
import '../../../../providers/execution_provider.dart';
import '../../../../providers/script_project_provider.dart';
import 'package:python_runner/features/scripts/application/script_workspace_controller.dart';
import '../../../../services/native_bridge.dart';
import '../../../../services/project_path_validator.dart';
import '../../../../services/script_project_service.dart';
import '../../../../utils/app_page_transitions.dart';
import '../../../../widgets/confirm_dialog.dart';
import '../../../../pages/app_file_picker_page.dart';
import 'project_file_editor_page.dart';
import '../../../console/presentation/pages/run_console_page.dart';
import '../../../../l10n/app_localizations.dart';

class ScriptProjectPage extends ConsumerStatefulWidget {
  final ScriptGroup group;

  const ScriptProjectPage({
    super.key,
    required this.group,
  });

  @override
  ConsumerState<ScriptProjectPage> createState() => _ScriptProjectPageState();
}

class _ScriptProjectPageState extends ConsumerState<ScriptProjectPage> {
  late final ScriptProjectProvider _projectProvider;
  String _currentDirectory = '';

  @override
  void initState() {
    super.initState();
    _projectProvider = ScriptProjectProvider(
      group: widget.group,
      service: ScriptProjectService(NativeBridge()),
    );
    _projectProvider.load();
    Future.microtask(() {
      if (mounted) ref.read(packageControllerProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _projectProvider.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _runProject(ScriptProjectProvider project) async {
    final mainFile = project.group.mainFilePath;
    if (mainFile == null || mainFile.isEmpty) return;
    final executionProvider = context.read<ExecutionProvider>();
    await executionProvider.executeScriptProject(project.group);
    if (!mounted) return;
    if (!executionProvider.isRunning) {
      _showSnack(AppLocalizations.of(context)!.projectLaunchFailed);
      return;
    }
    await ref
        .read(scriptWorkspaceControllerProvider.notifier)
        .markProjectGroupUsed(project.group);
    if (!mounted) return;
    Navigator.push(
      context,
      AppPageTransitions.fadeThrough(
        RunConsolePage(
          scriptName: project.group.name,
          projectGroup: project.group,
        ),
      ),
    );
  }

  Future<void> _createEntry({required bool directory}) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(directory ? l10n.newDirectory : l10n.newFile),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: directory ? 'src' : 'src/main.py',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l10n.create),
          ),
        ],
      ),
    );
    if (path == null || path.isEmpty) return;
    final entryPath = _pathInCurrentDirectory(path);
    final ok = directory
        ? await _projectProvider.createDirectory(entryPath)
        : await _projectProvider.createFile(entryPath);
    _showSnack(ok ? l10n.fileCreated : l10n.createFailed);
    if (ok && !directory) {
      await _openProjectFile(entryPath);
    }
  }

  String _pathInCurrentDirectory(String path) {
    final trimmed = path.trim().replaceAll('\\', '/');
    if (_currentDirectory.isEmpty || trimmed.contains('/')) return trimmed;
    return '$_currentDirectory/$trimmed';
  }

  void _enterDirectory(String path) {
    setState(() => _currentDirectory = path);
  }

  Future<void> _openProjectFile(String path) async {
    await Navigator.push<void>(
      context,
      AppPageTransitions.sharedAxisLeftRight(
        ProjectFileEditorPage(
          group: _projectProvider.group,
          filePath: path,
          onSaved: () => _projectProvider.load(),
        ),
      ),
    );
    if (mounted) await _projectProvider.load();
  }

  void _goUpDirectory() {
    if (_currentDirectory.isEmpty) return;
    final index = _currentDirectory.lastIndexOf('/');
    setState(() {
      _currentDirectory =
          index < 0 ? '' : _currentDirectory.substring(0, index);
    });
  }

  Future<void> _renameEntry(ScriptProjectFile file) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: file.path);
    final newPath = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.rename),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (newPath == null || newPath.isEmpty || newPath == file.path) return;
    final ok = await _projectProvider.renameEntry(file.path, newPath);
    _showSnack(ok ? l10n.renamed : l10n.renameFailed);
  }

  Future<void> _deleteEntry(ScriptProjectFile file) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await ConfirmDialog.show(
      context,
      title: file.isDirectory ? l10n.deleteDirectory : l10n.deleteFile,
      content: l10n.deletePathConfirm(file.path),
      confirmText: l10n.delete,
      confirmColor: Theme.of(context).colorScheme.error,
    );
    if (!confirmed) return;
    final ok = await _projectProvider.deleteEntry(file.path);
    _showSnack(ok ? l10n.deleted : l10n.deleteFailed);
  }

  Future<void> _updateMainFile(
      ScriptProjectProvider project, String? path) async {
    final l10n = AppLocalizations.of(context)!;
    final scriptWorkspace =
        ref.read(scriptWorkspaceControllerProvider.notifier);
    final ok = await scriptWorkspace.updateProjectMainFile(project.group, path);
    if (!ok) {
      _showSnack(l10n.mainProgramUpdateFailed);
      return;
    }
    final groups = ref.read(scriptWorkspaceControllerProvider).groups;
    final updated = groups.firstWhere(
      (group) => group.id == project.group.id,
      orElse: () => project.group,
    );
    project.updateGroup(updated);
    _showSnack(path == null ? l10n.mainProgramNotSet : l10n.mainProgramSet);
  }

  Future<void> _chooseMainFile(ScriptProjectProvider project) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => MainFileDialog(
        files: project.pythonFiles,
        recommendedFiles: project.recommendedMainFiles,
        currentPath: project.group.mainFilePath,
      ),
    );
    if (selected == null) return;
    await _updateMainFile(project, selected.isEmpty ? null : selected);
  }

  Future<void> _importZip(ScriptProjectProvider project) async {
    final l10n = AppLocalizations.of(context)!;
    final pickedFile = await AppFilePickerPage.pickFile(
      context,
      title: l10n.importProjectZip,
      allowedExtensions: const ['zip'],
    );
    if (pickedFile == null) return;
    late final String zipPath;
    if (pickedFile.useSystemPicker) {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        withData: false,
      );
      if (picked == null || picked.files.isEmpty) return;
      final path = picked.files.first.path;
      if (path == null || path.isEmpty) {
        _showSnack(l10n.unableToReadZipPath);
        return;
      }
      zipPath = path;
    } else {
      zipPath = pickedFile.path;
    }
    final imported = await project.importZip(zipPath);
    setState(() => _currentDirectory = '');
    if (imported.isEmpty && project.files.isEmpty) {
      _showSnack(l10n.importFailed);
      return;
    }
    if (!mounted) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => MainFileDialog(
        files: project.pythonFiles,
        recommendedFiles: project.recommendedMainFiles,
        currentPath: project.group.mainFilePath,
      ),
    );
    if (selected != null) {
      await _updateMainFile(project, selected.isEmpty ? null : selected);
    }
    _showSnack(l10n.zipImportComplete);
  }

  Future<void> _exportZip(ScriptProjectProvider project) async {
    final l10n = AppLocalizations.of(context)!;
    final prefs = await SharedPreferences.getInstance();
    final destDir = prefs.getString('export_dir') ?? '';
    final path = await project.exportZip(destDir: destDir);
    _showSnack(path.isEmpty ? l10n.exportFailed : l10n.exportedTo(path));
  }

  bool _hasRootRequirements(ScriptProjectProvider project) {
    return project.files.any(
      (file) => !file.isDirectory && file.path == 'requirements.txt',
    );
  }

  String _requirementsMenuSubtitle({
    required bool supportsRequirementsInstall,
    required bool isInstalling,
  }) {
    if (!supportsRequirementsInstall) {
      return AppLocalizations.of(context)!.linuxLikeOnly;
    }
    if (isInstalling) {
      return AppLocalizations.of(context)!.installTaskInProgress;
    }
    return 'requirements.txt';
  }

  Future<void> _installProjectRequirements(
    ScriptProjectProvider project,
  ) async {
    final state = ref.read(packageControllerProvider);
    if (!state.supportsRequirementsInstall) {
      _showSnack(AppLocalizations.of(context)!.projectRequirementsLinuxOnly);
      return;
    }
    if (state.isInstalling) {
      _showSnack(AppLocalizations.of(context)!.installAlreadyInProgress);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final indexUrl = prefs.getString('pypi_index_url');
    unawaited(
      ref
          .read(packageControllerProvider.notifier)
          .installRequirementsFromProject(
            projectKey: project.group.projectKey ?? '',
            requirementsPath: 'requirements.txt',
            indexUrl: indexUrl,
          ),
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => const _RequirementsInstallDialog(),
    );
  }

  void _handleMenuAction(String action, ScriptProjectProvider project) {
    switch (action) {
      case 'new_file':
        _createEntry(directory: false);
        break;
      case 'new_dir':
        _createEntry(directory: true);
        break;
      case 'main':
        _chooseMainFile(project);
        break;
      case 'import_zip':
        _importZip(project);
        break;
      case 'export_zip':
        _exportZip(project);
        break;
      case 'install_requirements':
        _installProjectRequirements(project);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return legacy_provider.ChangeNotifierProvider<ScriptProjectProvider>.value(
      value: _projectProvider,
      child: legacy_provider.Consumer<ScriptProjectProvider>(
        builder: (context, project, _) {
          final canRun = project.group.mainFilePath != null &&
              project.group.mainFilePath!.isNotEmpty;
          final supportsRequirementsInstall = ref.watch(
            packageControllerProvider
                .select((s) => s.supportsRequirementsInstall),
          );
          final isInstalling = ref.watch(
            packageControllerProvider.select((s) => s.isInstalling),
          );
          final hasRootRequirements = _hasRootRequirements(project);
          final canInstallRequirements = hasRootRequirements &&
              supportsRequirementsInstall &&
              !isInstalling;
          return PopScope(
            canPop: _currentDirectory.isEmpty,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && _currentDirectory.isNotEmpty) {
                _goUpDirectory();
              }
            },
            child: Scaffold(
              appBar: AppBar(
                title: Text(project.group.name),
                actions: [
                  if (canRun)
                    IconButton(
                      icon: const Icon(Icons.play_arrow_rounded),
                      tooltip: AppLocalizations.of(context)!.runProject,
                      onPressed: () => _runProject(project),
                    ),
                  PopupMenuButton<String>(
                    onSelected: (action) => _handleMenuAction(action, project),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'new_file',
                        child: ListTile(
                          leading: Icon(Icons.note_add_outlined),
                          title: Text(AppLocalizations.of(context)!.newFile),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'new_dir',
                        child: ListTile(
                          leading: Icon(Icons.create_new_folder_outlined),
                          title:
                              Text(AppLocalizations.of(context)!.newDirectory),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'main',
                        child: ListTile(
                          leading: Icon(Icons.flag_outlined),
                          title: Text(
                              AppLocalizations.of(context)!.setMainProgram),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      if (hasRootRequirements)
                        PopupMenuItem(
                          value: 'install_requirements',
                          enabled: canInstallRequirements,
                          child: ListTile(
                            leading: const Icon(Icons.description_outlined),
                            title: Text(
                              AppLocalizations.of(context)!.installDependencies,
                            ),
                            subtitle: Text(
                              _requirementsMenuSubtitle(
                                supportsRequirementsInstall:
                                    supportsRequirementsInstall,
                                isInstalling: isInstalling,
                              ),
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      PopupMenuItem(
                        value: 'import_zip',
                        child: ListTile(
                          leading: Icon(Icons.archive_outlined),
                          title: Text(
                            AppLocalizations.of(context)!.importProjectZip,
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'export_zip',
                        child: ListTile(
                          leading: Icon(Icons.file_download_outlined),
                          title: Text(
                            AppLocalizations.of(context)!.exportProjectZip,
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              body: _ProjectBody(
                project: project,
                currentDirectory: _currentDirectory,
                onSelectFile: _openProjectFile,
                onEnterDirectory: _enterDirectory,
                onGoUpDirectory: _goUpDirectory,
                onRename: _renameEntry,
                onDelete: _deleteEntry,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RequirementsInstallDialog extends ConsumerStatefulWidget {
  const _RequirementsInstallDialog();

  @override
  ConsumerState<_RequirementsInstallDialog> createState() =>
      _RequirementsInstallDialogState();
}

class _RequirementsInstallDialogState
    extends ConsumerState<_RequirementsInstallDialog> {
  bool _closeScheduled = false;

  bool _hasSuccess(List<String> log) =>
      log.any((line) => line.contains('安装成功'));

  bool _hasError(List<String> log) =>
      log.any((line) => line.contains('安装失败') || line.contains('Error'));

  void _scheduleCloseOnSuccess(PackageState state) {
    if (_closeScheduled ||
        state.isInstalling ||
        !_hasSuccess(state.installLog)) {
      return;
    }
    _closeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(packageControllerProvider);
    _scheduleCloseOnSuccess(state);
    final hasError = _hasError(state.installLog);
    final logText = state.installLog.isEmpty
        ? (state.isInstalling
            ? AppLocalizations.of(context)!.waitingForInstallLog
            : AppLocalizations.of(context)!.installationComplete)
        : state.installLog.reversed.take(8).join('\n');
    return AlertDialog(
      title: Text(AppLocalizations.of(context)!.installDependencies),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (state.isInstalling) ...[
              const LinearProgressIndicator(minHeight: 3),
              const SizedBox(height: 12),
            ] else if (state.installLog.isNotEmpty && !hasError) ...[
              Text(
                AppLocalizations.of(context)!
                    .installationCompleteRefreshingPackages,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                logText,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.close),
        ),
      ],
    );
  }
}

class _ProjectBody extends StatelessWidget {
  final ScriptProjectProvider project;
  final String currentDirectory;
  final ValueChanged<String> onSelectFile;
  final ValueChanged<String> onEnterDirectory;
  final VoidCallback onGoUpDirectory;
  final ValueChanged<ScriptProjectFile> onRename;
  final ValueChanged<ScriptProjectFile> onDelete;

  const _ProjectBody({
    required this.project,
    required this.currentDirectory,
    required this.onSelectFile,
    required this.onEnterDirectory,
    required this.onGoUpDirectory,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (project.loading && project.files.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final files = _ProjectFileList(
          files: project.files,
          currentDirectory: currentDirectory,
          selectedPath: project.selectedPath,
          mainFilePath: project.group.mainFilePath,
          onSelect: onSelectFile,
          onEnterDirectory: onEnterDirectory,
          onGoUpDirectory: onGoUpDirectory,
          onRename: onRename,
          onDelete: onDelete,
        );
        if (wide) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: files,
            ),
          );
        }
        return files;
      },
    );
  }
}

class _ProjectFileList extends StatelessWidget {
  final List<ScriptProjectFile> files;
  final String currentDirectory;
  final String? selectedPath;
  final String? mainFilePath;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onEnterDirectory;
  final VoidCallback onGoUpDirectory;
  final ValueChanged<ScriptProjectFile> onRename;
  final ValueChanged<ScriptProjectFile> onDelete;

  const _ProjectFileList({
    required this.files,
    required this.currentDirectory,
    required this.selectedPath,
    required this.mainFilePath,
    required this.onSelect,
    required this.onEnterDirectory,
    required this.onGoUpDirectory,
    required this.onRename,
    required this.onDelete,
  });

  String _parentOf(String path) {
    final index = path.lastIndexOf('/');
    return index < 0 ? '' : path.substring(0, index);
  }

  List<ScriptProjectFile> _visibleFiles() {
    final visible = files
        .where((file) => _parentOf(file.path) == currentDirectory)
        .toList();
    visible.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return visible;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final visibleFiles = _visibleFiles();
    return Column(
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.only(left: 6, right: 12),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.36),
            border: Border(
              bottom: BorderSide(color: colors.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_upward_rounded),
                tooltip: AppLocalizations.of(context)!.upOneLevel,
                onPressed: currentDirectory.isEmpty ? null : onGoUpDirectory,
              ),
              Expanded(
                child: Text(
                  currentDirectory.isEmpty
                      ? AppLocalizations.of(context)!.projectRootDirectory
                      : currentDirectory,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                AppLocalizations.of(context)!.itemsCount(visibleFiles.length),
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Expanded(
          child: files.isEmpty
              ? Center(
                  child: Text(AppLocalizations.of(context)!.noFilesInProject),
                )
              : visibleFiles.isEmpty
                  ? Center(
                      child: Text(
                        AppLocalizations.of(context)!.currentDirectoryEmpty,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: visibleFiles.length,
                      itemBuilder: (context, index) {
                        final file = visibleFiles[index];
                        final selected = file.path == selectedPath;
                        final isMain = file.path == mainFilePath;
                        return ListTile(
                          dense: true,
                          selected: selected,
                          contentPadding:
                              const EdgeInsets.only(left: 16, right: 8),
                          leading: Icon(
                            file.isDirectory
                                ? Icons.folder_outlined
                                : Icons.description_outlined,
                            size: 22,
                          ),
                          title: Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: isMain
                              ? Text(AppLocalizations.of(context)!.mainProgram)
                              : null,
                          onTap: file.isDirectory
                              ? () => onEnterDirectory(file.path)
                              : () => onSelect(file.path),
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) {
                              if (action == 'rename') onRename(file);
                              if (action == 'delete') onDelete(file);
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'rename',
                                child:
                                    Text(AppLocalizations.of(context)!.rename),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child:
                                    Text(AppLocalizations.of(context)!.delete),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class MainFileDialog extends StatefulWidget {
  final List<String> files;
  final List<String> recommendedFiles;
  final String? currentPath;

  const MainFileDialog({
    super.key,
    required this.files,
    required this.recommendedFiles,
    required this.currentPath,
  });

  @override
  State<MainFileDialog> createState() => _MainFileDialogState();
}

class _MainFileDialogState extends State<MainFileDialog> {
  final _manualController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }

  List<String> get _rankedFiles {
    final ranked = <String>[
      ...widget.recommendedFiles,
      ...widget.files.where((path) => !widget.recommendedFiles.contains(path)),
    ];
    if (_query.trim().isEmpty) return ranked;
    final query = _query.trim().toLowerCase();
    return ranked.where((path) => path.toLowerCase().contains(query)).toList();
  }

  void _submitManual() {
    final path = _manualController.text.trim();
    if (path.isEmpty) return;
    try {
      Navigator.pop(context, ProjectPathValidator.validateMainFilePath(path));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.invalidPath(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ranked = _rankedFiles;
    return AlertDialog(
      title: Text(AppLocalizations.of(context)!.selectMainProgram),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: AppLocalizations.of(context)!.searchPythonFiles,
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ranked.isEmpty
                  ? Center(
                      child: Text(
                        AppLocalizations.of(context)!.noPythonFilesFound,
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: ranked.length,
                      itemBuilder: (context, index) {
                        final path = ranked[index];
                        final recommended =
                            widget.recommendedFiles.contains(path);
                        return ListTile(
                          dense: true,
                          title: Text(path,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: recommended
                              ? Text(AppLocalizations.of(context)!.recommended)
                              : null,
                          trailing: path == widget.currentPath
                              ? Icon(Icons.check, color: colors.primary)
                              : null,
                          onTap: () => Navigator.pop(context, path),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _manualController,
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!.enterMainProgramPath,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.keyboard_return),
                  onPressed: _submitManual,
                ),
              ),
              onSubmitted: (_) => _submitManual(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, ''),
          child: Text(AppLocalizations.of(context)!.doNotSet),
        ),
      ],
    );
  }
}
