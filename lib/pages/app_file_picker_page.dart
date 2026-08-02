import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_file_entry.dart';
import '../services/native_bridge.dart';

enum PickerMode {
  file, // 选择文件
  folder, // 选择文件夹
}

class AppFilePickerPage extends StatefulWidget {
  final String title;
  final List<String> allowedExtensions;
  final String? exactFileName;
  final bool allowSystemPicker;
  final PickerMode mode;

  const AppFilePickerPage({
    super.key,
    required this.title,
    this.allowedExtensions = const [],
    this.exactFileName,
    this.allowSystemPicker = true,
    this.mode = PickerMode.file,
  });

  static Future<AppFilePickResult?> pickFile(
    BuildContext context, {
    required String title,
    List<String> allowedExtensions = const [],
    String? exactFileName,
    bool allowSystemPicker = true,
  }) {
    return Navigator.push<AppFilePickResult>(
      context,
      MaterialPageRoute(
        builder: (_) => AppFilePickerPage(
          title: title,
          allowedExtensions: allowedExtensions,
          exactFileName: exactFileName,
          allowSystemPicker: allowSystemPicker,
          mode: PickerMode.file,
        ),
      ),
    );
  }

  static Future<AppFilePickResult?> pickFolder(
    BuildContext context, {
    required String title,
  }) {
    return Navigator.push<AppFilePickResult>(
      context,
      MaterialPageRoute(
        builder: (_) => AppFilePickerPage(
          title: title,
          mode: PickerMode.folder,
          allowSystemPicker: false,
        ),
      ),
    );
  }

  @override
  State<AppFilePickerPage> createState() => _AppFilePickerPageState();
}

class _AppFilePickerPageState extends State<AppFilePickerPage> {
  static const _storageRootPath = '/storage/emulated/0';

  final _bridge = NativeBridge();
  final _searchController = TextEditingController();

  List<AppFileEntry> _entries = const [];
  String? _currentPath;
  bool _loading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
    _loadInitialDirectory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberedPath = prefs.getString(_memoryKey);
    final initialPath = rememberedPath == null || rememberedPath.isEmpty
        ? _storageRootPath
        : rememberedPath;
    await _openDirectoryPath(
      _isInsideStorageRoot(initialPath) ? initialPath : _storageRootPath,
      fallbackToStorageRoot: true,
    );
  }

  Future<void> _loadStorageRoot() => _openDirectoryPath(_storageRootPath);

  Future<void> _openDirectory(AppFileEntry entry) =>
      _openDirectoryPath(entry.path);

  Future<void> _openDirectoryPath(
    String path, {
    bool fallbackToStorageRoot = false,
  }) async {
    setState(() {
      _loading = true;
      _error = null;
      _currentPath = path;
      _searchController.clear();
    });
    try {
      final entries = await _bridge.listFilePickerDirectory(path);
      if (!mounted) return;
      setState(() => _entries = entries);
    } catch (e) {
      if (fallbackToStorageRoot && path != _storageRootPath) {
        await _openDirectoryPath(_storageRootPath);
        return;
      }
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _goBack() async {
    final current = _currentPath;
    if (current == null) {
      Navigator.pop(context);
      return;
    }
    if (_normalizePath(current) == _storageRootPath) {
      Navigator.pop(context);
      return;
    }
    final parent = _parentPath(current);
    if (parent == null || !_isInsideStorageRoot(parent)) {
      await _loadStorageRoot();
      return;
    }
    await _openDirectoryPath(parent);
  }

  String get _memoryKey {
    final exactName = widget.exactFileName?.trim().toLowerCase();
    if (exactName != null && exactName.isNotEmpty) {
      return 'app_file_picker_last_dir_exact_$exactName';
    }
    if (widget.allowedExtensions.isEmpty) {
      return 'app_file_picker_last_dir_all';
    }
    final extensions = widget.allowedExtensions
        .map((extension) => extension.toLowerCase().replaceFirst('.', ''))
        .toList()
      ..sort();
    return 'app_file_picker_last_dir_${extensions.join("_")}';
  }

  Future<void> _rememberDirectoryFor(AppFileEntry entry) async {
    final directory = _parentPath(entry.path) ?? _currentPath;
    if (directory == null || directory.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_memoryKey, directory);
  }

  String _normalizePath(String path) =>
      path.replaceAll(RegExp(r'/+$'), '').isEmpty
          ? '/'
          : path.replaceAll(RegExp(r'/+$'), '');

  bool _isInsideStorageRoot(String path) {
    final normalized = _normalizePath(path);
    return normalized == _storageRootPath ||
        normalized.startsWith('$_storageRootPath/');
  }

  String? _parentPath(String path) {
    final normalized = _normalizePath(path);
    if (normalized.isEmpty || normalized == '/') return null;
    final index = normalized.lastIndexOf('/');
    if (index <= 0) return '/';
    return normalized.substring(0, index);
  }

  bool _matchesFilter(AppFileEntry entry) {
    if (entry.isDirectory) return true;
    final exactName = widget.exactFileName?.trim().toLowerCase();
    if (exactName != null && exactName.isNotEmpty) {
      return entry.name.toLowerCase() == exactName;
    }
    if (widget.allowedExtensions.isEmpty) return true;
    final lower = entry.name.toLowerCase();
    return widget.allowedExtensions.any((extension) {
      final normalized = extension.toLowerCase().replaceFirst('.', '');
      return lower.endsWith('.$normalized');
    });
  }

  List<AppFileEntry> _visibleEntries() {
    final entries = _entries.where(_matchesFilter).where((entry) {
      if (_query.isEmpty) return true;
      return entry.name.toLowerCase().contains(_query);
    }).toList();
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  String get _filterDescription {
    final exactName = widget.exactFileName?.trim();
    if (exactName != null && exactName.isNotEmpty) return exactName;
    if (widget.allowedExtensions.isEmpty) {
      return AppLocalizations.of(context)!.allFiles;
    }
    return widget.allowedExtensions
        .map((extension) =>
            extension.startsWith('.') ? extension : '.$extension')
        .join(' / ');
  }

  String _formatSize(int size) {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final visibleEntries = _visibleEntries();

    return PopScope(
      canPop: _currentPath == null ||
          _normalizePath(_currentPath!) == _storageRootPath,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _goBack,
            tooltip: _currentPath == null
                ? AppLocalizations.of(context)!.back
                : AppLocalizations.of(context)!.upOneLevel,
          ),
          title: Text(widget.title),
          actions: [
            if (widget.mode == PickerMode.folder && _currentPath != null)
              TextButton.icon(
                icon: const Icon(Icons.check, size: 20),
                label: Text(AppLocalizations.of(context)!.select),
                onPressed: () {
                  Navigator.pop(
                    context,
                    AppFilePickResult(
                      path: _currentPath!,
                      name: _currentPath!.split('/').last,
                    ),
                  );
                },
              ),
            IconButton(
              icon: const Icon(Icons.home_outlined),
              tooltip: AppLocalizations.of(context)!.internalStorage,
              onPressed: _loadStorageRoot,
            ),
            if (widget.allowSystemPicker)
              IconButton(
                icon: const Icon(Icons.upload_file_outlined),
                tooltip: AppLocalizations.of(context)!.systemFilePicker,
                onPressed: () => Navigator.pop(
                  context,
                  const AppFilePickResult.systemPicker(),
                ),
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
                  Text(
                    _currentPath ??
                        AppLocalizations.of(context)!.storageLocations,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: _searchController.clear,
                            ),
                      hintText: AppLocalizations.of(context)!
                          .searchFiles(_filterDescription),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: TextStyle(color: colors.error),
                ),
              ),
            Expanded(
              child: !_loading && visibleEntries.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _currentPath == null
                                  ? Icons.folder_open_outlined
                                  : Icons.filter_alt_off_outlined,
                              size: 42,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _currentPath == null
                                  ? AppLocalizations.of(context)!
                                      .noBrowsableFiles
                                  : AppLocalizations.of(context)!
                                      .noFilesInDirectory(_filterDescription),
                              style: TextStyle(
                                color: colors.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _currentPath == null
                                  ? AppLocalizations.of(context)!
                                      .systemFilePickerHint
                                  : AppLocalizations.of(context)!
                                      .goUpOrInternalStorageHint,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: colors.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: visibleEntries.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final entry = visibleEntries[index];
                        return ListTile(
                          leading: Icon(
                            entry.isDirectory
                                ? Icons.folder_outlined
                                : Icons.description_outlined,
                            color: entry.isDirectory
                                ? colors.primary
                                : colors.onSurfaceVariant,
                          ),
                          title: Text(
                            entry.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            entry.isDirectory
                                ? entry.path
                                : '${_formatSize(entry.size)} · ${entry.path}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: entry.isDirectory
                              ? const Icon(Icons.chevron_right)
                              : null,
                          onTap: () async {
                            if (entry.isDirectory) {
                              // 文件夹模式和文件模式：点击文件夹都是进入
                              _openDirectory(entry);
                            } else {
                              // 文件模式才能选择文件
                              if (widget.mode == PickerMode.file) {
                                await _rememberDirectoryFor(entry);
                                if (!context.mounted) return;
                                Navigator.pop(
                                  context,
                                  AppFilePickResult(
                                    path: entry.path,
                                    name: entry.name,
                                  ),
                                );
                              }
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
