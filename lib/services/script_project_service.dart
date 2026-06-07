import '../models/script_group.dart';
import '../models/script_project_file.dart';
import 'native_bridge.dart';
import 'project_path_validator.dart';

class ScriptProjectService {
  final NativeBridge _bridge;

  ScriptProjectService(this._bridge);

  Future<String> createProject(String projectKey, String displayName) async {
    final safeKey = ProjectPathValidator.normalizeProjectKey(projectKey);
    final root = await _bridge.createScriptProject(safeKey);
    await _bridge.saveProjectFile(
      safeKey,
      'main.py',
      'print("Hello from $displayName")\n',
    );
    return root;
  }

  Future<String> createEmptyProject(String projectKey) {
    final safeKey = ProjectPathValidator.normalizeProjectKey(projectKey);
    return _bridge.createScriptProject(safeKey);
  }

  Future<bool> deleteProject(String projectKey) {
    final safeKey = ProjectPathValidator.normalizeProjectKey(projectKey);
    return _bridge.deleteScriptProject(safeKey);
  }

  String requireProjectKey(ScriptGroup group) {
    if (!group.isProject || group.projectKey == null) {
      throw StateError('Script group is not a project');
    }
    return ProjectPathValidator.normalizeProjectKey(group.projectKey!);
  }

  Future<List<ScriptProjectFile>> loadProjectFiles(ScriptGroup group) {
    return _bridge.listProjectFiles(requireProjectKey(group));
  }

  Future<String> readProjectFile(ScriptGroup group, String path) {
    final safePath = ProjectPathValidator.normalizeRelativePath(path);
    return _bridge.readProjectFile(requireProjectKey(group), safePath);
  }

  Future<bool> saveProjectFile(ScriptGroup group, String path, String content) {
    final safePath = ProjectPathValidator.normalizeRelativePath(path);
    return _bridge.saveProjectFile(requireProjectKey(group), safePath, content);
  }

  Future<bool> createProjectDirectory(ScriptGroup group, String path) {
    final safePath = ProjectPathValidator.normalizeRelativePath(path);
    return _bridge.createProjectDirectory(requireProjectKey(group), safePath);
  }

  Future<bool> deleteProjectEntry(ScriptGroup group, String path) {
    final safePath = ProjectPathValidator.normalizeRelativePath(path);
    return _bridge.deleteProjectEntry(requireProjectKey(group), safePath);
  }

  Future<bool> renameProjectEntry(
      ScriptGroup group, String oldPath, String newPath) {
    final safeOldPath = ProjectPathValidator.normalizeRelativePath(oldPath);
    final safeNewPath = ProjectPathValidator.normalizeRelativePath(newPath);
    return _bridge.renameProjectEntry(
      requireProjectKey(group),
      safeOldPath,
      safeNewPath,
    );
  }

  Future<List<ScriptProjectFile>> importZip(ScriptGroup group, String uri) {
    return _bridge.importScriptProjectZip(requireProjectKey(group), uri);
  }

  Future<String> exportZip(ScriptGroup group, {String? destDir}) {
    return _bridge.exportScriptProjectZip(
      requireProjectKey(group),
      destDir: destDir,
    );
  }

  List<String> pythonFilePaths(List<ScriptProjectFile> files) {
    final paths = files
        .where((file) => !file.isDirectory && file.path.endsWith('.py'))
        .map((file) => file.path)
        .toList();
    paths.sort();
    return paths;
  }

  List<String> recommendedMainFilePaths(List<ScriptProjectFile> files) {
    final pythonFiles = pythonFilePaths(files);
    const priorityNames = ['main.py', 'app.py', 'run.py', '__main__.py'];
    final ranked = <String>[];
    for (final name in priorityNames) {
      ranked.addAll(pythonFiles.where((path) => path.split('/').last == name));
    }
    ranked.addAll(pythonFiles.where((path) => !ranked.contains(path)));
    return ranked;
  }

  String validateMainFilePath(String path) {
    return ProjectPathValidator.validateMainFilePath(path);
  }
}
