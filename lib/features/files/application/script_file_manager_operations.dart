import 'dart:io';

import 'package:path/path.dart' as p;

import '../../scripts/application/script_workspace_controller.dart';
import '../../../services/native_bridge.dart';
import '../../../services/script_name_validator.dart';
import 'file_manager_controller.dart';

/// Routes file-manager mutations through script metadata handling when needed.
class ScriptFileManagerOperations {
  ScriptFileManagerOperations({required this.bridge, required this.workspace});
  final NativeBridge bridge;
  final ScriptWorkspaceController workspace;

  Future<String?> _libraryScriptName(String path) async {
    if (!p.isAbsolute(path) ||
        !path.endsWith('.py') ||
        await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.file) {
      return null;
    }
    // Compare canonical parents, not suffixes or basenames: a.py in the
    // working directory must never change the private library's a.py row.
    final parent = await Directory(p.dirname(path)).resolveSymbolicLinks();
    for (final root in await bridge.getFileManagerAppDataRoots()) {
      if (p.equals(parent, p.join(root.path, 'files', 'scripts'))) {
        return p.basename(path);
      }
    }
    return null;
  }

  Future<void> renameEntry(String path, String newName) async {
    final name = await _libraryScriptName(path);
    if (name == null ||
        ScriptNameValidator.tryNormalize(name) != name ||
        ScriptNameValidator.tryNormalize(newName) != newName) {
      // General file names must retain their exact identity. The script
      // controller normalizes names and could otherwise hit a different file.
      await bridge.renameFileManagerEntry(path, newName);
      if (name != null) await workspace.load();
      return;
    }
    if (!await workspace.renameScript(name, newName)) {
      throw const FileManagerError(
        code: FileManagerErrorCode.ioError,
        message: '重命名脚本失败',
      );
    }
    // Also handles renaming away from .py, which leaves the script library.
    await workspace.load();
  }

  Future<void> deleteEntry(String path) async {
    final name = await _libraryScriptName(path);
    if (name == null || ScriptNameValidator.tryNormalize(name) != name) {
      await bridge.deleteFileManagerEntry(path);
      if (name != null) await workspace.load();
      return;
    }
    if (!await workspace.deleteScript(name)) {
      throw const FileManagerError(
        code: FileManagerErrorCode.ioError,
        message: '删除脚本失败',
      );
    }
  }
}
