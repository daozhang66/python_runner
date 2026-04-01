import 'package:flutter/foundation.dart';
import '../models/script_file.dart';
import '../services/native_bridge.dart';
import '../services/database_service.dart';

class ScriptProvider extends ChangeNotifier {
  final NativeBridge _bridge;
  final DatabaseService _db;

  List<ScriptFile> _scripts = [];
  bool _loading = false;

  List<ScriptFile> get scripts => _scripts;
  bool get loading => _loading;

  ScriptProvider(this._bridge, this._db);

  void _sortScripts() {
    _scripts.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
  }

  Future<void> loadScripts() async {
    _loading = true;
    notifyListeners();
    try {
      final names = await _bridge.listScripts();
      final dbScripts = await _db.getAllScripts();
      final dbMap = {for (var s in dbScripts) s.name: s};

      final now = DateTime.now();
      _scripts = [];
      for (final name in names) {
        if (dbMap.containsKey(name)) {
          _scripts.add(dbMap[name]!);
        } else {
          final script = ScriptFile(
            name: name,
            path: name,
            createdAt: now,
            modifiedAt: now,
          );
          await _db.upsertScript(script);
          _scripts.add(script);
        }
      }
      _sortScripts();
    } catch (e) {
      debugPrint('loadScripts error: $e');
    }
    _loading = false;
    notifyListeners();
  }

  Future<bool> createScript(String name, {String content = ''}) async {
    try {
      final path = await _bridge.createScript(name, content: content);
      final now = DateTime.now();
      final script = ScriptFile(
        name: name,
        path: path,
        createdAt: now,
        modifiedAt: now,
      );
      await _db.upsertScript(script);
      _scripts.insert(0, script);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('createScript error: $e');
      return false;
    }
  }

  Future<bool> deleteScript(String name) async {
    try {
      await _bridge.deleteScript(name);
      await _db.deleteScript(name);
      _scripts.removeWhere((s) => s.name == name);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('deleteScript error: $e');
      return false;
    }
  }

  Future<bool> renameScript(String oldName, String newName) async {
    try {
      await _bridge.renameScript(oldName, newName);
      await _db.renameScript(oldName, newName, newName);
      final idx = _scripts.indexWhere((s) => s.name == oldName);
      if (idx >= 0) {
        _scripts[idx] = _scripts[idx].copyWith(name: newName, path: newName, modifiedAt: DateTime.now());
        _sortScripts();
      }
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('renameScript error: $e');
      return false;
    }
  }

  Future<String> readScript(String name) async {
    try {
      return await _bridge.readScript(name);
    } catch (e) {
      debugPrint('readScript error: $e');
      return '';
    }
  }

  Future<bool> saveScript(String name, String content) async {
    try {
      await _bridge.saveScript(name, content);
      final now = DateTime.now();
      final idx = _scripts.indexWhere((s) => s.name == name);
      if (idx >= 0) {
        final updated = _scripts[idx].copyWith(modifiedAt: now);
        await _db.upsertScript(updated);
        _scripts[idx] = updated;
        _sortScripts();
        notifyListeners();
      } else {
        final existing = await _db.getScript(name);
        if (existing != null) {
          await _db.upsertScript(existing.copyWith(modifiedAt: now));
        }
      }
      return true;
    } catch (e) {
      debugPrint('saveScript error: $e');
      return false;
    }
  }

  Future<String?> importScript(String uri, String name) async {
    try {
      final path = await _bridge.importScriptFromUri(uri, name);
      final now = DateTime.now();
      final script = ScriptFile(
        name: name,
        path: path,
        createdAt: now,
        modifiedAt: now,
      );
      await _db.upsertScript(script);
      _scripts.insert(0, script);
      notifyListeners();
      return path;
    } catch (e) {
      debugPrint('importScript error: $e');
      return null;
    }
  }

  Future<void> incrementRunCount(String name) async {
    await _db.incrementRunCount(name);
    final idx = _scripts.indexWhere((s) => s.name == name);
    if (idx >= 0) {
      _scripts[idx] = _scripts[idx].copyWith(runCount: _scripts[idx].runCount + 1);
      notifyListeners();
    }
  }
}
