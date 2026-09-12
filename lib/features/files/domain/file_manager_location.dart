/// Location model for the file manager page.
///
/// The file manager has two top-level modes:
/// - [FileManagerLocationMode.workingDirectory]: the ordinary script working
///   directory resolved from `SharedPreferences['working_dir']`.
/// - [FileManagerLocationMode.root]: the host filesystem root `/`.
enum FileManagerLocationMode { workingDirectory, root }

/// Fallback working directory shared with the Linux-like runtime default.
const String defaultScriptWorkingDirectory =
    '/storage/emulated/0/Download/PythonRunner';

/// A concrete place the file manager is browsing.
class FileManagerLocation {
  final FileManagerLocationMode mode;
  final String path;

  const FileManagerLocation._(this.mode, this.path);

  /// The filesystem root `/`. This is the host Android filesystem root,
  /// not the PRoot guest rootfs.
  static const FileManagerLocation root =
      FileManagerLocation._(FileManagerLocationMode.root, '/');

  /// A working-directory location at [path].
  const FileManagerLocation.workingDirectory(this.path)
      : mode = FileManagerLocationMode.workingDirectory;

  bool get isRoot => mode == FileManagerLocationMode.root;

  String get displayName => isRoot ? '/' : _baseName(path);

  static String _baseName(String path) {
    final normalized = path.replaceAll(RegExp(r'/+$'), '');
    if (normalized.isEmpty) return '/';
    final index = normalized.lastIndexOf('/');
    return index < 0 ? normalized : normalized.substring(index + 1);
  }
}

/// Resolves the effective working directory for the file manager.
///
/// Returns [configuredPath] only when it is non-blank, absolute, and
/// accepted by [isAccessible]. Otherwise falls back to
/// [defaultScriptWorkingDirectory]. Never returns `/` as an implicit
/// working-directory fallback.
String resolveWorkingDirectory({
  required String? configuredPath,
  required bool Function(String path) isAccessible,
}) {
  final candidate = configuredPath?.trim() ?? '';
  if (candidate.startsWith('/') &&
      candidate != '/' &&
      isAccessible(candidate)) {
    return candidate;
  }
  return defaultScriptWorkingDirectory;
}

/// Builds the location the file manager opens with.
FileManagerLocation initialLocation({
  required String? configuredPath,
  required bool Function(String path) isAccessible,
}) {
  return FileManagerLocation.workingDirectory(
    resolveWorkingDirectory(
      configuredPath: configuredPath,
      isAccessible: isAccessible,
    ),
  );
}
