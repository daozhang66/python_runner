import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/script_file.dart';
import '../models/script_group.dart';

class DatabaseService {
  static Database? _db;
  static Future<Database>? _dbFuture;

  Future<Database> get database {
    if (_db != null) return Future.value(_db!);
    _dbFuture ??= _initDb().then((db) {
      _db = db;
      return db;
    });
    return _dbFuture!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'python_runner.db');
    return openDatabase(
      path,
      version: 4,
      onCreate: (db, version) async => _createTables(db),
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE scripts (
        name TEXT PRIMARY KEY,
        path TEXT NOT NULL,
        createdAt INTEGER NOT NULL,
        modifiedAt INTEGER NOT NULL,
        runCount INTEGER DEFAULT 0,
        isPinned INTEGER DEFAULT 0,
        sortOrder INTEGER DEFAULT 0,
        groupId INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE script_groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        sortOrder INTEGER DEFAULT 0,
        createdAt INTEGER NOT NULL,
        modifiedAt INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db
          .execute('ALTER TABLE scripts ADD COLUMN isPinned INTEGER DEFAULT 0');
    }
    if (oldVersion < 3) {
      await db.execute(
          'ALTER TABLE scripts ADD COLUMN sortOrder INTEGER DEFAULT 0');
      await _migrateSortOrder(db);
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS script_groups (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          sortOrder INTEGER DEFAULT 0,
          createdAt INTEGER NOT NULL,
          modifiedAt INTEGER NOT NULL
        )
      ''');
      await db.execute('ALTER TABLE scripts ADD COLUMN groupId INTEGER');
    }
  }

  Future<void> _migrateSortOrder(Database db) async {
    final maps =
        await db.query('scripts', orderBy: 'isPinned DESC, modifiedAt DESC');
    final batch = db.batch();
    for (int i = 0; i < maps.length; i++) {
      batch.update(
        'scripts',
        {'sortOrder': i},
        where: 'name = ?',
        whereArgs: [maps[i]['name']],
      );
    }
    await batch.commit();
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
    final maps =
        await db.query('scripts', orderBy: 'isPinned DESC, sortOrder ASC');
    return maps.map((m) => ScriptFile.fromMap(m)).toList();
  }

  Future<ScriptFile?> getScript(String name) async {
    final db = await database;
    final maps =
        await db.query('scripts', where: 'name = ?', whereArgs: [name]);
    if (maps.isEmpty) return null;
    return ScriptFile.fromMap(maps.first);
  }

  Future<void> deleteScript(String name) async {
    final db = await database;
    await db.delete('scripts', where: 'name = ?', whereArgs: [name]);
  }

  Future<void> renameScript(
      String oldName, String newName, String newPath) async {
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

  Future<void> batchUpdateSortOrders(List<ScriptFile> scripts) async {
    final db = await database;
    final batch = db.batch();
    for (int i = 0; i < scripts.length; i++) {
      batch.update(
        'scripts',
        {'sortOrder': i},
        where: 'name = ?',
        whereArgs: [scripts[i].name],
      );
    }
    await batch.commit();
  }

  Future<List<ScriptGroup>> getAllGroups() async {
    final db = await database;
    final maps = await db.query('script_groups', orderBy: 'sortOrder ASC');
    return maps.map((m) => ScriptGroup.fromMap(m)).toList();
  }

  Future<int> createGroup(ScriptGroup group) async {
    final db = await database;
    return db.insert(
      'script_groups',
      group.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> renameGroup(int groupId, String name) async {
    final db = await database;
    await db.update(
      'script_groups',
      {
        'name': name,
        'modifiedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [groupId],
    );
  }

  Future<void> deleteGroup(int groupId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'scripts',
        {'groupId': null},
        where: 'groupId = ?',
        whereArgs: [groupId],
      );
      await txn.delete(
        'script_groups',
        where: 'id = ?',
        whereArgs: [groupId],
      );
    });
  }

  Future<void> moveScriptsToGroup(List<ScriptFile> scripts) async {
    final db = await database;
    final batch = db.batch();
    for (final script in scripts) {
      batch.update(
        'scripts',
        {
          'groupId': script.groupId,
          'sortOrder': script.sortOrder,
          'modifiedAt': script.modifiedAt.millisecondsSinceEpoch,
        },
        where: 'name = ?',
        whereArgs: [script.name],
      );
    }
    await batch.commit();
  }
}
