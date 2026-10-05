import '../../../../ui/app_popup_menu.dart';
import '../../../../widgets/app_dialogs.dart';
import '../../../../ui/app_materials.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../models/app_file_entry.dart';
import '../../../../services/native_bridge.dart';
import '../../../../utils/app_page_transitions.dart';
import 'file_manager_file_viewer_page.dart';
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
      writeFile: bridge.writeFileManagerFile,
      transferEntry: bridge.transferFileManagerEntry,
      ensureDirectory: bridge.ensureFileManagerDirectory,
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
    if (_controller.transferring) return;
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
      builder: (ctx) => AppAlertDialog(
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
      builder: (ctx) => AppAlertDialog(
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
      builder: (ctx) => AppAlertDialog(
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

  void _openFile(AppFileEntry entry) {
    Navigator.push(
      context,
      AppPageTransitions.sharedAxisLeftRight(
        FileManagerFileViewerPage(
          entry: entry,
          controller: _controller,
        ),
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

  String _label(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  List<PopupMenuEntry<String>> _entryMenu(AppFileEntry entry) {
    final l10n = AppLocalizations.of(context)!;
    PopupMenuItem<String> item(String value, IconData icon, String label) =>
        PopupMenuItem(
            value: value,
            child: ListTile(
                leading: Icon(icon),
                title: Text(label),
                contentPadding: EdgeInsets.zero));
    return [
      if (_controller.canMutate(entry)) ...[
        item('copy', Icons.copy, l10n.copy),
        item('cut', Icons.content_cut, _label('剪切', 'Cut')),
        item('rename', Icons.drive_file_rename_outline, l10n.rename),
        item('delete', Icons.delete_outline, l10n.delete),
      ],
      item('path', Icons.link, _label('复制路径', 'Copy path')),
      item('details', Icons.info_outline, _label('属性', 'Properties')),
    ];
  }

  void _handleEntryAction(AppFileEntry entry, String action) {
    if (_controller.transferring) return;
    switch (action) {
      case 'copy':
      case 'cut':
        _controller.stageTransfer(entry, move: action == 'cut');
        break;
      case 'rename':
        _showRenameDialog(entry);
        break;
      case 'delete':
        _confirmDelete(entry);
        break;
      case 'path':
        Clipboard.setData(ClipboardData(text: entry.path));
        break;
      case 'details':
        showDialog<void>(
            context: context,
            builder: (context) => AppAlertDialog(
                  title: Text(entry.name),
                  content: SingleChildScrollView(
                      child: SelectableText(
                    '${entry.path}\n${entry.isDirectory ? _label('目录', 'Directory') : '${entry.size} B'}\n${entry.modifiedAt.toLocal()}',
                  )),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(AppLocalizations.of(context)!.back))
                  ],
                ));
        break;
    }
  }

  Future<void> _showEntryActions(AppFileEntry entry) async {
    final action = await showAppModalBottomSheet<String>(
        context: context,
        builder: (sheetContext) => SafeArea(
                child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(
                    title: Text(entry.name,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(entry.path,
                        maxLines: 2, overflow: TextOverflow.ellipsis)),
                ..._entryMenu(entry).cast<PopupMenuItem<String>>().map((item) =>
                    InkWell(
                        onTap: () => Navigator.pop(sheetContext, item.value),
                        child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: item.child))),
              ]),
            )));
    if (action != null && mounted) _handleEntryAction(entry, action);
  }

  Future<void> _paste() async {
    try {
      await _controller.paste();
      if (mounted && _controller.clipboardEntry == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_label('粘贴完成', 'Paste completed')),
        ));
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final location = _controller.location;
    final entries = _controller.visibleEntries;
    final switchLabel =
        location.isRoot ? l10n.switchToWorkingDirectory : l10n.switchToRoot;

    return PopScope(
      canPop: !_controller.canGoUp && !_controller.transferring,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goUpOrExit();
      },
      child: Scaffold(
        appBar: AppBar(
          flexibleSpace: appGlassBarBackground(context),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _goUpOrExit,
            tooltip: l10n.back,
          ),
          title: Text(l10n.fileManager, maxLines: 1),
          actions: [
            IconButton(
              icon: const Icon(Icons.arrow_upward),
              tooltip: l10n.upOneLevel,
              onPressed: _controller.canGoUp ? _controller.goUp : null,
            ),
            AppPopupMenuButton<String>(
              popUpAnimationStyle: appMenuAnimation(context),
              key: const ValueKey('file-manager-actions'),
              tooltip: l10n.more,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              onSelected: (action) {
                if (action == 'new_folder') _showCreateFolderDialog();
                if (action == 'refresh') _controller.refresh();
                if (action == 'paste') _paste();
                if (action == 'search') {
                  setState(() {
                    _searchVisible = !_searchVisible;
                    if (!_searchVisible) _searchController.clear();
                  });
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                    value: 'refresh',
                    child: ListTile(
                        leading: const Icon(Icons.refresh),
                        title: Text(l10n.refresh),
                        contentPadding: EdgeInsets.zero)),
                PopupMenuItem(
                    value: 'search',
                    child: ListTile(
                        leading: Icon(
                            _searchVisible ? Icons.search_off : Icons.search),
                        title: Text(l10n.search),
                        contentPadding: EdgeInsets.zero)),
                if (_controller.clipboardEntry != null)
                  PopupMenuItem(
                      value: 'paste',
                      enabled: _controller.canPaste,
                      child: ListTile(
                          leading: const Icon(Icons.content_paste),
                          title: Text(_label('粘贴', 'Paste')),
                          contentPadding: EdgeInsets.zero)),
                PopupMenuItem(
                  value: 'new_folder',
                  enabled: !_controller.transferring && location.path != '/',
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
                      IconButton(
                        icon: Icon(location.isRoot
                            ? Icons.folder_special_outlined
                            : Icons.my_location_outlined),
                        tooltip: switchLabel,
                        onPressed: _switchMode,
                      ),
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
        bottomNavigationBar: _controller.clipboardEntry == null
            ? null
            : SafeArea(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(children: [
                    Icon(
                        _controller.clipboardMove
                            ? Icons.content_cut
                            : Icons.copy,
                        size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(_controller.clipboardEntry!.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(
                              _controller.clipboardMove
                                  ? _label('待移动', 'Ready to move')
                                  : _label('待复制', 'Ready to copy'),
                              style: Theme.of(context).textTheme.labelSmall),
                        ])),
                    if (_controller.transferring)
                      const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      FilledButton.icon(
                          onPressed: _controller.canPaste ? _paste : null,
                          icon: const Icon(Icons.content_paste),
                          label: Text(_label('粘贴', 'Paste'))),
                    IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: l10n.cancel,
                        onPressed: _controller.transferring
                            ? null
                            : _controller.clearTransfer),
                  ]),
                ),
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
          onPreview: () => _openFile(entry),
          onLongPress: () => _showEntryActions(entry),
          onMenuSelected: (action) => _handleEntryAction(entry, action),
          menuBuilder: (_) => _entryMenu(entry),
        );
      },
    );
  }
}
