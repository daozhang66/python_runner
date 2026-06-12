import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/script_file.dart';
import '../models/script_group.dart';

class DatabaseService {
  DatabaseService({String? databasePath}) : _databasePath = databasePath;

  @visibleForTesting
  DatabaseService.test({required String databasePath})
      : _databasePath = databasePath;

  static const int schemaVersion = 5;
  static const String databaseFileName = 'python_runner.db';

  Database? _db;
  Future<Database>? _dbFuture;

  final String? _databasePath;

  Future<Database> get database {
    if (_db != null) return Future.value(_db!);
    _dbFuture ??= _initDb().then((db) {
      _db = db;
      return db;
    });
    return _dbFuture!;
  }

  Future<Database> _initDb() async {
    final path =
        _databasePath ?? join(await getDatabasesPath(), databaseFileName);
    await _guardUnsupportedSchema(path);
    try {
      return await openDatabase(
        path,
        version: schemaVersion,
        onCreate: (db, version) async => _createTables(db),
        onUpgrade: _onUpgrade,
        onDowngrade: _onDowngrade,
      );
    } catch (error) {
      final backupPath = await _backupDatabase(path, reason: 'open_failed');
      throw DatabaseOpenException(
        '无法打开数据库，已保留原数据库${backupPath == null ? '' : '并备份到 $backupPath'}。',
        cause: error,
        backupPath: backupPath,
      );
    }
  }

  Future<void> _guardUnsupportedSchema(String path) async {
    if (!await databaseExists(path)) return;
    Database? db;
    try {
      db = await openDatabase(path, readOnly: true, singleInstance: false);
      final version = await db.getVersion();
      if (version > schemaVersion) {
        final backupPath =
            await _backupDatabase(path, reason: 'future_v$version');
        throw UnsupportedDatabaseVersionException(
          currentVersion: schemaVersion,
          foundVersion: version,
          backupPath: backupPath,
        );
      }
    } finally {
      await db?.close();
    }
  }

  Future<String?> _backupDatabase(String path, {required String reason}) async {
    final source = File(path);
    if (!await source.exists()) return null;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final backupPath = '$path.backup.$reason.$timestamp';
    await source.copy(backupPath);
    return backupPath;
  }

  Future<void> _onDowngrade(Database db, int oldVersion, int newVersion) async {
    throw UnsupportedDatabaseVersionException(
      currentVersion: newVersion,
      foundVersion: oldVersion,
      backupPath: null,
    );
  }

  @visibleForTesting
  Future<Database> openForTest() => _initDb();

  @visibleForTesting
  Future<void> closeForTest() async {
    await _db?.close();
    _db = null;
    _dbFuture = null;
  }

  @visibleForTesting
  static Future<void> createSchemaForTest(
    Database db,
    int version,
  ) async {
    if (version < 1 || version > schemaVersion) {
      throw ArgumentError.value(
        version,
        'version',
        'Unsupported schema version',
      );
    }
    await db.execute('''
      CREATE TABLE scripts (
        name TEXT PRIMARY KEY,
        path TEXT NOT NULL,
        createdAt INTEGER NOT NULL,
        modifiedAt INTEGER NOT NULL,
        runCount INTEGER DEFAULT 0${version >= 2 ? ',\n        isPinned INTEGER DEFAULT 0' : ''}${version >= 3 ? ',\n        sortOrder INTEGER DEFAULT 0' : ''}${version >= 4 ? ',\n        groupId INTEGER' : ''}
      )
    ''');
    if (version >= 4) {
      await db.execute('''
        CREATE TABLE script_groups (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          sortOrder INTEGER DEFAULT 0,
          createdAt INTEGER NOT NULL,
          modifiedAt INTEGER NOT NULL${version >= 5 ? ',\n          projectKey TEXT,\n          mainFilePath TEXT,\n          isProject INTEGER DEFAULT 0' : ''}
        )
      ''');
    }
    if (version >= 5) {
      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_script_groups_project_key
        ON script_groups(projectKey)
        WHERE projectKey IS NOT NULL
      ''');
    }
    await db.setVersion(version);
  }

  @visibleForTesting
  static Future<void> createFutureSchemaForTest(
    String path,
    int version,
  ) async {
    final db = await openDatabase(
      path,
      version: version,
      onCreate: (db, version) async => db.setVersion(version),
      singleInstance: false,
    );
    await db.setVersion(version);
    await db.close();
  }

  static Future<void> _createTables(Database db) async {
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
        modifiedAt INTEGER NOT NULL,
        projectKey TEXT,
        mainFilePath TEXT,
        isProject INTEGER DEFAULT 0
      )
    ''');
    await _createProjectGroupIndexes(db);
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
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
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE script_groups ADD COLUMN projectKey TEXT');
      await db
          .execute('ALTER TABLE script_groups ADD COLUMN mainFilePath TEXT');
      await db.execute(
          'ALTER TABLE script_groups ADD COLUMN isProject INTEGER DEFAULT 0');
      await _createProjectGroupIndexes(db);
    }
  }

  static Future<void> _createProjectGroupIndexes(Database db) async {
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_script_groups_project_key
      ON script_groups(projectKey)
      WHERE projectKey IS NOT NULL
    ''');
  }

  static Future<void> _migrateSortOrder(Database db) async {
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

  Future<void> updateProjectMainFile(int groupId, String? mainFilePath) async {
    final db = await database;
    await db.update(
      'script_groups',
      {
        'mainFilePath': mainFilePath,
        'modifiedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [groupId],
    );
  }

  Future<void> touchGroup(int groupId) async {
    final db = await database;
    await db.update(
      'script_groups',
      {'modifiedAt': DateTime.now().millisecondsSinceEpoch},
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

class DatabaseOpenException implements Exception {
  DatabaseOpenException(
    this.message, {
    this.cause,
    this.backupPath,
  });

  final String message;
  final Object? cause;
  final String? backupPath;

  @override
  String toString() => 'DatabaseOpenException: $message';
}

class UnsupportedDatabaseVersionException implements Exception {
  UnsupportedDatabaseVersionException({
    required this.currentVersion,
    required this.foundVersion,
    this.backupPath,
  });

  final int currentVersion;
  final int foundVersion;
  final String? backupPath;

  @override
  String toString() =>
      'UnsupportedDatabaseVersionException: database schema $foundVersion is newer than supported schema $currentVersion';
}
