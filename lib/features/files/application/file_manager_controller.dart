import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../models/app_file_entry.dart';
import '../domain/file_manager_location.dart';

/// Stable error categories surfaced by the file manager.
///
/// Native layer reports numeric codes (1040 invalid path/argument,
/// 1043 permission, 1044 state conflict such as exists/not-empty);
/// this enum is what the UI localizes.
enum FileManagerErrorCode {
  invalidPath,
  notFound,
  permissionDenied,
  alreadyExists,
  notEmpty,
  ioError,
  unknown,
}

class FileManagerError implements Exception {
  final FileManagerErrorCode code;
  final String message;

  const FileManagerError({required this.code, required this.message});

  @override
  String toString() => message;
}

enum FileManagerState { loading, ready, empty, error }

/// State holder for the file manager page.
///
/// The controller keeps the current mode (working directory / root), the
/// directory being browsed, and the listing for that directory. All native
/// access is injected so tests can drive it with fakes.
class FileManagerController extends ChangeNotifier {
  FileManagerController({
    required Future<List<AppFileEntry>> Function(String path) listDirectory,
    required Future<List<int>> Function(String path) readFile,
    required Future<void> Function(String parent, String name) createDirectory,
    required Future<void> Function(String path, String newName) renameEntry,
    required Future<void> Function(String path) deleteEntry,
    Future<void> Function(String path, String content)? writeFile,
    required Future<String?> Function() workingDirectoryProvider,
    required Future<bool> Function(String path) isPathAccessible,
    Future<List<AppFileEntry>> Function()? appDataRootsProvider,
  })  : _listDirectory = listDirectory,
        _readFile = readFile,
        _createDirectory = createDirectory,
        _renameEntry = renameEntry,
        _deleteEntry = deleteEntry,
        _writeFile = writeFile,
        _workingDirectoryProvider = workingDirectoryProvider,
        _isPathAccessible = isPathAccessible,
        _appDataRootsProvider = appDataRootsProvider;

  static const _protectedSystemPrefixes = [
    '/system',
    '/proc',
    '/sys',
    '/dev',
  ];

  final Future<List<AppFileEntry>> Function(String path) _listDirectory;
  final Future<List<int>> Function(String path) _readFile;
  final Future<void> Function(String parent, String name) _createDirectory;
  final Future<void> Function(String path, String newName) _renameEntry;
  final Future<void> Function(String path) _deleteEntry;
  final Future<void> Function(String path, String content)? _writeFile;
  final Future<String?> Function() _workingDirectoryProvider;
  final Future<bool> Function(String path) _isPathAccessible;
  final Future<List<AppFileEntry>> Function()? _appDataRootsProvider;

  /// Paths of the app-private data roots (data, android_data, android_obb,
  /// user_de_data) surfaced in root mode, mirroring the MT provider mapping.
  final Set<String> _appDataRootPaths = {};

  FileManagerLocation _location =
      FileManagerLocation.workingDirectory(defaultScriptWorkingDirectory);
  String? _workingRoot;
  List<AppFileEntry> _entries = const [];
  FileManagerState _state = FileManagerState.loading;
  String? _errorMessage;
  FileManagerErrorCode? _errorCode;
  String _query = '';
  int _generation = 0;
  bool _disposed = false;

  FileManagerLocation get location => _location;

  FileManagerState get state => _state;

  String? get errorMessage => _errorMessage;

  /// Stable error category of the last failed load, for UI localization.
  FileManagerErrorCode? get errorCode => _errorCode;

  /// Top-level path of the current mode: `/` in root mode, or the resolved
  /// working directory in working-directory mode.
  String get modeRootPath => _location.isRoot ? '/' : (_workingRoot ?? '/');

  bool get canGoUp => _location.path != modeRootPath;

  /// Entries sorted app-data roots first, then directories before files with
  /// case-insensitive names, filtered by the current search query.
  List<AppFileEntry> get visibleEntries {
    int rank(AppFileEntry entry) {
      if (_appDataRootPaths.contains(entry.path)) return 0;
      return entry.isDirectory ? 1 : 2;
    }

    final filtered = _entries.where((entry) {
      if (_query.isEmpty) return true;
      return entry.name.toLowerCase().contains(_query);
    }).toList()
      ..sort((a, b) {
        final rankDiff = rank(a) - rank(b);
        if (rankDiff != 0) return rankDiff;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return filtered;
  }

  /// Mutations are only offered for absolute host paths the native layer
  /// does not protect. `content://` targets are never mutable here.
  bool canMutate(AppFileEntry entry) {
    final path = entry.path.trim();
    if (_appDataRootPaths.contains(path)) return false;
    if (!path.startsWith('/') || path.contains('\\"')) return false;
    if (path == '/') return false;
    return !_protectedSystemPrefixes.any((prefix) =>
        path == prefix || path.startsWith('$prefix/'));
  }

  Future<void> loadInitial() async {
    final resolved = await _resolveWorkingRoot();
    _workingRoot = resolved;
    await _load(
      FileManagerLocation.workingDirectory(resolved),
      generation: ++_generation,
    );
  }

  /// Resolves the effective working directory: the configured path when it
  /// is non-blank, absolute, and the native layer can access it; otherwise
  /// the default working directory. The default itself may still be
  /// inaccessible (surfaced as a retryable error), but it is never swapped
  /// for `/` automatically.
  Future<String> _resolveWorkingRoot() async {
    final configured = await _workingDirectoryProvider();
    var candidate = resolveWorkingDirectory(
      configuredPath: configured,
      isAccessible: (_) => true,
    );
    if (!await _isPathAccessible(candidate)) {
      candidate = defaultScriptWorkingDirectory;
    }
    return candidate;
  }

  Future<void> enterDirectory(AppFileEntry entry) async {
    if (!entry.isDirectory) return;
    await _load(
      FileManagerLocation.inMode(_location.mode, entry.path),
      generation: ++_generation,
    );
  }

  Future<void> goUp() async {
    if (!canGoUp) return;
    final parent = _parentPath(_location.path);
    if (parent == null) return;
    await _load(
      FileManagerLocation.inMode(_location.mode, parent),
      generation: ++_generation,
    );
  }

  Future<void> refresh() async {
    await _load(_location, generation: ++_generation);
  }

  Future<void> retry() => refresh();

  /// Switches between modes. Switching resets the path stack to the target
  /// mode's top-level directory; the working directory is re-resolved so a
  /// stale or newly configured value is honored.
  Future<void> switchMode(FileManagerLocationMode mode) async {
    final generation = ++_generation;
    if (mode == FileManagerLocationMode.root) {
      await _load(FileManagerLocation.root, generation: generation);
      return;
    }
    final resolved = await _resolveWorkingRoot();
    _workingRoot = resolved;
    await _load(
      FileManagerLocation.workingDirectory(resolved),
      generation: generation,
    );
  }

  void setSearchQuery(String query) {
    if (_query == query) return;
    _query = query.trim().toLowerCase();
    notifyListeners();
  }

  Future<void> createDirectory(String name) async {
    await _guard(() => _createDirectory(_location.path, name));
  }

  Future<void> renameEntry(AppFileEntry entry, String newName) async {
    await _guard(() => _renameEntry(entry.path, newName));
  }

  Future<void> deleteEntry(AppFileEntry entry) async {
    await _guard(() => _deleteEntry(entry.path));
  }

  Future<String> readTextPreview(AppFileEntry entry) async {
    if (entry.isDirectory) {
      throw const FileManagerError(
        code: FileManagerErrorCode.invalidPath,
        message: '目录不支持预览',
      );
    }
    final bytes = await _readFile(entry.path);
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Raw bytes of a file entry, used to detect binary content before
  /// opening the code viewer.
  Future<List<int>> readFileBytes(AppFileEntry entry) {
    if (entry.isDirectory) {
      throw const FileManagerError(
        code: FileManagerErrorCode.invalidPath,
        message: '目录不支持打开',
      );
    }
    return _readFile(entry.path);
  }

  /// Overwrites the file entry with [content]. Requires the injected write
  /// callback (the file manager page provides the native bridge one).
  Future<void> writeFile(AppFileEntry entry, String content) async {
    final write = _writeFile;
    if (write == null) {
      throw const FileManagerError(
        code: FileManagerErrorCode.ioError,
        message: '当前不支持写入',
      );
    }
    await _guard(() => write(entry.path, content));
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on FileManagerError {
      rethrow;
    } catch (e) {
      throw _mapError(e);
    }
    await refresh();
  }

  /// Pins the app-private data roots (mirroring the MT provider mapping) at
  /// the top of the root listing. Failures degrade to the plain filesystem
  /// listing.
  Future<List<AppFileEntry>> _mergeAppDataRoots(
    List<AppFileEntry> entries,
  ) async {
    final provider = _appDataRootsProvider;
    if (provider == null) {
      _appDataRootPaths.clear();
      return entries;
    }
    try {
      final roots = await provider();
      _appDataRootPaths
        ..clear()
        ..addAll(roots.map((e) => e.path));
      final listedPaths = entries.map((e) => e.path).toSet();
      return [...roots.where((e) => !listedPaths.contains(e.path)), ...entries];
    } catch (_) {
      _appDataRootPaths.clear();
      return entries;
    }
  }

  Future<void> _load(
    FileManagerLocation target, {
    required int generation,
  }) async {
    if (_disposed) return;
    // Point at the target immediately so retry after a failed load retries
    // the failed directory, not the previous one.
    _location = target;
    _state = FileManagerState.loading;
    _errorMessage = null;
    _errorCode = null;
    notifyListeners();
    try {
      var entries = await _listDirectory(target.path);
      if (_disposed || generation != _generation) return;
      if (target.path == '/') {
        entries = await _mergeAppDataRoots(entries);
        if (_disposed || generation != _generation) return;
      }
      _entries = entries;
      _state = entries.isEmpty && _query.isEmpty
          ? FileManagerState.empty
          : FileManagerState.ready;
      notifyListeners();
    } catch (e) {
      if (_disposed || generation != _generation) return;
      final error = _mapError(e);
      _state = FileManagerState.error;
      _errorMessage = error.message;
      _errorCode = error.code;
      notifyListeners();
    }
  }

  FileManagerError _mapError(Object error) {
    if (error is FileManagerError) return error;
    final message = error is Exception ? _errorMessageOf(error) : '$error';
    final code = _errorCodeOf(message);
    return FileManagerError(code: code, message: message);
  }

  String _errorMessageOf(Exception error) {
    final text = error.toString();
    final messageStart = text.indexOf('message: ');
    if (messageStart >= 0) {
      final raw = text.substring(messageStart + 'message: '.length);
      final end = raw.indexOf(", code=");
      if (end > 0) return raw.substring(0, end);
      return raw;
    }
    return text;
  }

  FileManagerErrorCode _errorCodeOf(String message) {
    if (message.contains('权限') ||
        message.contains('Permission denied') ||
        message.contains('Permission')) {
      return FileManagerErrorCode.permissionDenied;
    }
    if (message.contains('已存在')) {
      return FileManagerErrorCode.alreadyExists;
    }
    if (message.contains('非空')) {
      return FileManagerErrorCode.notEmpty;
    }
    if (message.contains('不存在')) {
      return FileManagerErrorCode.notFound;
    }
    return FileManagerErrorCode.ioError;
  }

  String? _parentPath(String path) {
    final normalized = path.replaceAll(RegExp(r'/+$'), '');
    if (normalized.isEmpty || normalized == '/') return null;
    final index = normalized.lastIndexOf('/');
    if (index < 0) return '/';
    return index == 0 ? '/' : normalized.substring(0, index);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
