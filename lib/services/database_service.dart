import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/script_file.dart';

class DatabaseService {
  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'python_runner.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE scripts (
            name TEXT PRIMARY KEY,
            path TEXT NOT NULL,
            createdAt INTEGER NOT NULL,
            modifiedAt INTEGER NOT NULL,
            runCount INTEGER DEFAULT 0
          )
        ''');
      },
    );
  }

  Future<void> upsertScript(ScriptFile script) async {
    final db = await database;
    await db.insert(
      'scripts',
      script.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ScriptFile>> getAllScripts() async {
    final db = await database;
    final maps = await db.query('scripts', orderBy: 'modifiedAt DESC');
    return maps.map((m) => ScriptFile.fromMap(m)).toList();
  }

  Future<ScriptFile?> getScript(String name) async {
    final db = await database;
    final maps = await db.query('scripts', where: 'name = ?', whereArgs: [name]);
    if (maps.isEmpty) return null;
    return ScriptFile.fromMap(maps.first);
  }

  Future<void> deleteScript(String name) async {
    final db = await database;
    await db.delete('scripts', where: 'name = ?', whereArgs: [name]);
  }

  Future<void> renameScript(String oldName, String newName, String newPath) async {
    final db = await database;
    await db.update(
      'scripts',
      {
        'name': newName,
        'path': newPath,
        'modifiedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'name = ?',
      whereArgs: [oldName],
    );
  }

  Future<void> incrementRunCount(String name) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE scripts SET runCount = runCount + 1, modifiedAt = ? WHERE name = ?',
      [DateTime.now().millisecondsSinceEpoch, name],
    );
  }
}
