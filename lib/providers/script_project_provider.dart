import 'package:flutter/foundation.dart';

import '../models/script_group.dart';
import '../models/script_project_file.dart';
import '../services/script_project_service.dart';

class ScriptProjectProvider extends ChangeNotifier {
  final ScriptProjectService _service;

  ScriptGroup _group;
  List<ScriptProjectFile> _files = [];
  String? _selectedPath;
  String _content = '';
  bool _loading = false;
  bool _saving = false;
  bool _dirty = false;
  String? _error;

  ScriptProjectProvider({
    required ScriptGroup group,
    required ScriptProjectService service,
  })  : _group = group,
        _service = service;

  ScriptGroup get group => _group;
  List<ScriptProjectFile> get files => List.unmodifiable(_files);
  List<String> get pythonFiles => _service.pythonFilePaths(_files);
  List<String> get recommendedMainFiles =>
      _service.recommendedMainFilePaths(_files);
  String? get selectedPath => _selectedPath;
  String get content => _content;
  bool get loading => _loading;
  bool get saving => _saving;
  bool get dirty => _dirty;
  String? get error => _error;

  void updateGroup(ScriptGroup group) {
    _group = group;
    notifyListeners();
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _files = await _service.loadProjectFiles(_group);
      _files.sort((a, b) {
        if (a.isDirectory != b.isDirectory) {
          return a.isDirectory ? -1 : 1;
        }
        return a.path.compareTo(b.path);
      });
      final selected = _selectedPath;
      if (selected != null && !_files.any((file) => file.path == selected)) {
        _selectedPath = null;
        _content = '';
        _dirty = false;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> selectFile(String path) async {
    final file = _files.firstWhere(
      (item) => item.path == path,
      orElse: () => throw StateError('文件不存在: $path'),
    );
    if (file.isDirectory) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _content = await _service.readProjectFile(_group, path);
      _selectedPath = path;
      _dirty = false;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void updateContent(String value) {
    if (_content == value) return;
    _content = value;
    _dirty = true;
    notifyListeners();
  }

  Future<bool> saveSelectedFile() async {
    final path = _selectedPath;
    if (path == null) return false;
    _saving = true;
    _error = null;
    notifyListeners();
    try {
      final success = await _service.saveProjectFile(_group, path, _content);
      if (success) {
        _dirty = false;
        await load();
      }
      return success;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  Future<bool> createFile(String path, {String content = ''}) async {
    _error = null;
    try {
      final success = await _service.saveProjectFile(_group, path, content);
      if (success) {
        await load();
        await selectFile(path);
      }
      return success;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> createDirectory(String path) async {
    _error = null;
    try {
      final success = await _service.createProjectDirectory(_group, path);
      if (success) await load();
      return success;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteEntry(String path) async {
    _error = null;
    try {
      final success = await _service.deleteProjectEntry(_group, path);
      if (success) {
        if (_selectedPath == path ||
            (_selectedPath?.startsWith('$path/') ?? false)) {
          _selectedPath = null;
          _content = '';
          _dirty = false;
        }
        await load();
      }
      return success;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> renameEntry(String oldPath, String newPath) async {
    _error = null;
    try {
      final success =
          await _service.renameProjectEntry(_group, oldPath, newPath);
      if (success) {
        if (_selectedPath == oldPath) {
          _selectedPath = newPath;
        }
        await load();
      }
      return success;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<List<ScriptProjectFile>> importZip(String uri) async {
    _error = null;
    try {
      final imported = await _service.importZip(_group, uri);
      await load();
      return imported;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return const [];
    }
  }

  Future<String> exportZip({String? destDir}) async {
    _error = null;
    try {
      return await _service.exportZip(_group, destDir: destDir);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return '';
    }
  }
}
