import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../models/app_file_entry.dart';
import '../../../../services/native_bridge.dart';
import '../../application/file_manager_controller.dart';
import '../../domain/file_manager_location.dart';
import '../widgets/file_manager_entry_tile.dart';

/// Standalone file manager opened from the script list top-right menu.
///
/// Opens in the ordinary script working directory and allows switching to
/// the filesystem root `/` from the AppBar.
class FileManagerPage extends StatefulWidget {
  final FileManagerController? controller;

  const FileManagerPage({super.key, this.controller});

  @override
  State<FileManagerPage> createState() => _FileManagerPageState();
}

class _FileManagerPageState extends State<FileManagerPage> {
  late final FileManagerController _controller;
  late final TextEditingController _searchController;
  final _searchFocusNode = FocusNode();
  bool _ownsController = false;
  bool _searchVisible = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? _buildDefaultController();
    _ownsController = widget.controller == null;
    _searchController = TextEditingController();
    _searchController.addListener(() {
      _controller.setSearchQuery(_searchController.text);
    });
    _controller.addListener(_onControllerChanged);
    _controller.loadInitial();
  }

  static FileManagerController _buildDefaultController() {
    final bridge = NativeBridge();
    return FileManagerController(
      listDirectory: bridge.listFilePickerDirectory,
      readFile: bridge.readFilePickerFile,
      createDirectory: bridge.createFileManagerDirectory,
      renameEntry: bridge.renameFileManagerEntry,
      deleteEntry: bridge.deleteFileManagerEntry,
      workingDirectoryProvider: () async =>
          (await SharedPreferences.getInstance()).getString('working_dir'),
      isPathAccessible: (path) async {
        try {
          await bridge.listFilePickerDirectory(path);
          return true;
        } catch (_) {
          return false;
        }
      },
      appDataRootsProvider: bridge.getFileManagerAppDataRoots,
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _goUpOrExit() async {
    if (_controller.canGoUp) {
      await _controller.goUp();
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _switchMode() async {
    await _controller.switchMode(
      _controller.location.isRoot
          ? FileManagerLocationMode.workingDirectory
          : FileManagerLocationMode.root,
    );
  }

  Future<void> _showCreateFolderDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.newFolder),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.folderName),
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      await _controller.createDirectory(name.trim());
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _showRenameDialog(AppFileEntry entry) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: entry.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.rename),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.newName),
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || name.trim() == entry.name) {
      return;
    }
    try {
      await _controller.renameEntry(entry, name.trim());
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _confirmDelete(AppFileEntry entry) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.delete),
        content: Text(l10n.deleteItemConfirm(entry.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _controller.deleteEntry(entry);
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _openPreview(AppFileEntry entry) async {
    final l10n = AppLocalizations.of(context)!;
    String? content;
    Object? error;
    try {
      content = await _controller.readTextPreview(entry);
    } catch (e) {
      error = e;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.filePreview),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.path,
                style: const TextStyle(fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: error != null
                      ? Text(
                          '${l10n.cannotReadFile}\n$error',
                          style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                        )
                      : SelectableText(
                          content ?? '',
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message, maxLines: 3)),
      );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final location = _controller.location;
    final entries = _controller.visibleEntries;
    final switchLabel = location.isRoot
        ? l10n.switchToWorkingDirectory
        : l10n.switchToRoot;

    return PopScope(
      canPop: !_controller.canGoUp,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goUpOrExit();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _goUpOrExit,
            tooltip: _controller.canGoUp ? l10n.upOneLevel : l10n.back,
          ),
          title: Text(l10n.fileManager),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l10n.refresh,
              onPressed: _controller.refresh,
            ),
            IconButton(
              icon: Icon(
                location.isRoot
                    ? Icons.folder_special_outlined
                    : Icons.my_location_outlined,
              ),
              tooltip: switchLabel,
              onPressed: _switchMode,
            ),
            IconButton(
              icon: Icon(
                _searchVisible ? Icons.search_off : Icons.search,
              ),
              tooltip: l10n.search,
              onPressed: () {
                setState(() {
                  _searchVisible = !_searchVisible;
                  if (!_searchVisible) _searchController.clear();
                });
              },
            ),
            PopupMenuButton<String>(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              onSelected: (action) {
                if (action == 'new_folder') _showCreateFolderDialog();
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'new_folder',
                  child: ListTile(
                    leading: const Icon(Icons.create_new_folder_outlined),
                    title: Text(l10n.newFolder),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          location.isRoot
                              ? l10n.rootDirectory
                              : l10n.workDirectory,
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          location.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_searchVisible) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: _searchController.clear,
                              ),
                        hintText: l10n.searchCurrentDirectory,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_controller.state == FileManagerState.loading)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(child: _buildBody(context, l10n, entries)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    List<AppFileEntry> entries,
  ) {
    final colors = Theme.of(context).colorScheme;
    if (_controller.state == FileManagerState.error) {
      final message = _controller.errorMessage ?? l10n.loadDirectoryFailed;
      final permissionDenied =
          _controller.errorCode == FileManagerErrorCode.permissionDenied;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.folder_off_outlined,
                size: 42,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                permissionDenied ? l10n.noPermissionDirectory : message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _controller.retry,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(l10n.retry),
              ),
            ],
          ),
        ),
      );
    }
    if (_controller.state == FileManagerState.empty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: 42,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.emptyDirectory,
              style: TextStyle(
                color: colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final canMutate = _controller.canMutate(entry);
        return FileManagerEntryTile(
          entry: entry,
          canMutate: canMutate,
          onOpen: () => _controller.enterDirectory(entry),
          onPreview: () => _openPreview(entry),
          onMenuSelected: (action) {
            if (action == 'rename') _showRenameDialog(entry);
            if (action == 'delete') _confirmDelete(entry);
          },
          menuBuilder: canMutate
              ? (menuContext) => [
                    PopupMenuItem(
                      value: 'rename',
                      child: ListTile(
                        leading: const Icon(Icons.drive_file_rename_outline),
                        title: Text(l10n.rename),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: const Icon(Icons.delete_outline),
                        title: Text(l10n.delete),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ]
              : null,
        );
      },
    );
  }
}
