import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/script_file.dart';
import '../models/script_group.dart';
import '../features/backup/domain/backup_manifest.dart';
import '../features/backup/domain/restore_plan.dart';
import 'script_name_validator.dart';
import 'workspace_access.dart';

class DatabaseService {
  DatabaseService({String? databasePath, WorkspaceAccess? workspaceAccess})
    : _databasePath = databasePath, _workspaceAccess = workspaceAccess ?? WorkspaceAccess.instance;

  @visibleForTesting
  DatabaseService.test({required String databasePath})
    : _databasePath = databasePath, _workspaceAccess = WorkspaceAccess.instance;

  final WorkspaceAccess _workspaceAccess;
  /// Set before opening metadata whenever native restore journals are pending.
  /// An unreadable marker ledger must never be mistaken for an empty ledger.
  bool preserveRestoreEvidence = false;

  static const int schemaVersion = 7;
  static const String databaseFileName = 'python_runner.db';
  static const int maxBackupBundles = 5;

  Database? _db;
  Future<Database>? _dbFuture;

  final String? _databasePath;

  Future<Database> get database async {
    _workspaceAccess.assertReadable();
    if (_db != null) return Future.value(_db!);
    final existing = _dbFuture;
    if (existing != null) return existing;

    final future = _initDb().then((db) {
      _db = db;
      return db;
    });
    _dbFuture = future;
    try {
      return await future;
    } catch (_) {
      // Do not cache an initialization failure forever. A transient storage
      // error (or a restored database) must be recoverable in this process.
      if (identical(_dbFuture, future)) {
        _dbFuture = null;
      }
      rethrow;
    }
  }

  Future<Database> _initDb() async {
    final path =
        _databasePath ?? join(await getDatabasesPath(), databaseFileName);
    try {
      final futureVersion = await _futureSchemaVersion(path);
      if (futureVersion != null) {
        return await _archiveAndRebuild(
          path,
          reason: 'future_v$futureVersion',
          cause: UnsupportedDatabaseVersionException(
            currentVersion: schemaVersion,
            foundVersion: futureVersion,
          ),
        );
      }
      return await _openCurrentSchema(path);
    } catch (error) {
      if (error is _DatabaseDowngradeSignal) {
        return _archiveAndRebuild(
          path,
          reason: 'future_v${error.foundVersion}',
          cause: error,
        );
      }
      if (await _isRecoverableDatabaseFailure(path, error)) {
        return _archiveAndRebuild(path, reason: 'corrupt', cause: error);
      }
      final backupPath = await _copyDatabaseBackup(path, reason: 'open_failed');
      throw DatabaseOpenException(
        '无法打开数据库，已保留原数据库${backupPath == null ? '' : '并备份到 $backupPath'}。',
        cause: error,
        backupPath: backupPath,
      );
    }
  }

  Future<Database> _openCurrentSchema(String path) {
    return openDatabase(
      path,
      version: schemaVersion,
      onCreate: (db, version) async => _createTables(db),
      onUpgrade: _onUpgrade,
      onDowngrade: _onDowngrade,
    );
  }

  Future<int?> _futureSchemaVersion(String path) async {
    if (!await databaseExists(path)) return null;
    Database? db;
    try {
      db = await openDatabase(path, readOnly: true, singleInstance: false);
      final version = await db.getVersion();
      if (version > schemaVersion) {
        return version;
      }
    } finally {
      await db?.close();
    }
    return null;
  }

  Future<Database> _archiveAndRebuild(
    String path, {
    required String reason,
    required Object cause,
  }) async {
    if (preserveRestoreEvidence) {
      throw DatabaseOpenException(
        'Restore recovery cannot read its commit ledger. Original database and journal were preserved. Retry recovery after fixing storage.',
        cause: cause,
      );
    }
    final backupPath = await _archiveDatabaseBundle(path, reason: reason);
    if (backupPath == null) {
      throw DatabaseOpenException('数据库恢复前无法归档原数据库。', cause: cause);
    }
    try {
      await deleteDatabase(path);
      final database = await _openCurrentSchema(path);
      debugPrint(
        'DatabaseService recovered database after $reason; archive: $backupPath',
      );
      return database;
    } catch (error) {
      throw DatabaseOpenException(
        '数据库已归档到 $backupPath，但无法重建新的数据库。',
        cause: error,
        backupPath: backupPath,
      );
    }
  }

  Future<bool> _isRecoverableDatabaseFailure(String path, Object error) async {
    if (await FileSystemEntity.type(path) != FileSystemEntityType.file) {
      return false;
    }
    final message = error.toString().toLowerCase();
    return message.contains('malformed') ||
        message.contains('corrupt') ||
        message.contains('not a database') ||
        message.contains('file is encrypted');
  }

  Future<String?> _copyDatabaseBackup(
    String path, {
    required String reason,
  }) async {
    final source = File(path);
    if (!await source.exists()) return null;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final backupPath = '$path.backup.$reason.$timestamp';
    await source.copy(backupPath);
    await _pruneBackupBundles(path);
    return backupPath;
  }

  Future<String?> _archiveDatabaseBundle(
    String path, {
    required String reason,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final moved = <(File source, File archive)>[];
    try {
      // Move WAL/SHM first, then the primary database. If any move fails, put
      // already moved sidecars back so the source database stays intact.
      for (final suffix in ['-wal', '-shm', '']) {
        final source = File('$path$suffix');
        if (!await source.exists()) continue;
        final archive = File('$path.backup.$reason.$timestamp$suffix');
        await source.rename(archive.path);
        moved.add((source, archive));
      }
    } catch (_) {
      for (final move in moved.reversed) {
        if (await move.$2.exists() && !await move.$1.exists()) {
          await move.$2.rename(move.$1.path);
        }
      }
      rethrow;
    }
    final primaryArchive = moved
        .where((move) => move.$1.path == path)
        .map((move) => move.$2.path)
        .firstOrNull;
    if (primaryArchive != null) {
      await _pruneBackupBundles(path);
      return primaryArchive;
    }
    for (final move in moved.reversed) {
      if (await move.$2.exists() && !await move.$1.exists()) {
        await move.$2.rename(move.$1.path);
      }
    }
    return null;
  }

  Future<void> _pruneBackupBundles(String path) async {
    try {
      final databaseFile = File(path);
      final pattern = RegExp(
        '^${RegExp.escape(databaseFile.uri.pathSegments.last)}\\.backup\\.[^.]+\\.(\\d+)(?:-(?:wal|shm))?'
        r'$',
      );
      final bundles = <String, List<File>>{};
      await for (final entity in databaseFile.parent.list()) {
        if (entity is! File) continue;
        final match = pattern.firstMatch(entity.uri.pathSegments.last);
        if (match == null) continue;
        bundles.putIfAbsent(match.group(1)!, () => <File>[]).add(entity);
      }
      final timestamps = bundles.keys.toList()..sort((a, b) => b.compareTo(a));
      for (final timestamp in timestamps.skip(maxBackupBundles)) {
        for (final file in bundles[timestamp]!) {
          try {
            await file.delete();
          } catch (error) {
            debugPrint('DatabaseService backup cleanup failed: $error');
          }
        }
      }
    } catch (error) {
      debugPrint('DatabaseService backup scan failed: $error');
    }
  }

  Future<void> _onDowngrade(Database db, int oldVersion, int newVersion) async {
    throw _DatabaseDowngradeSignal(oldVersion);
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
  static Future<void> createSchemaForTest(Database db, int version) async {
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
    if (version >= 6) {
      await _addHomeSortOrder(db);
    }
    if (version >= 7) {
      await _createRestoreCommitTable(db);
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
    await _addHomeSortOrder(db);
    await _createRestoreCommitTable(db);
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE scripts ADD COLUMN isPinned INTEGER DEFAULT 0',
      );
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE scripts ADD COLUMN sortOrder INTEGER DEFAULT 0',
      );
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
      await db.execute(
        'ALTER TABLE script_groups ADD COLUMN mainFilePath TEXT',
      );
      await db.execute(
        'ALTER TABLE script_groups ADD COLUMN isProject INTEGER DEFAULT 0',
      );
      await _createProjectGroupIndexes(db);
    }
    if (oldVersion < 6) {
      await _addHomeSortOrder(db);
    }
    if (oldVersion < 7) {
      await _createRestoreCommitTable(db);
    }
  }

  static Future<void> _createRestoreCommitTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS backup_restore_commits (
        operationId TEXT PRIMARY KEY,
        committedAt INTEGER NOT NULL
      )
    ''');
  }

  /// Both metadata tables are read from the same SQLite transaction snapshot.
  Future<BackupLibrarySnapshot> readBackupSnapshot() async {
    final db = await database;
    return db.transaction(
      (txn) async => BackupLibrarySnapshot(
        scripts: (await txn.query(
          'scripts',
          orderBy: 'sortOrder ASC, name ASC',
        )).map(ScriptFile.fromMap),
        groups: (await txn.query(
          'script_groups',
          orderBy: 'sortOrder ASC, id ASC',
        )).map(ScriptGroup.fromMap),
      ),
    );
  }

  /// Must follow native file commit while the library write gate is held.
  /// Metadata and the recovery marker commit together or roll back together.
  /// Replaying a committed operation is harmless until its marker is forgotten.
  Future<void> applyRestorePlan(
    RestorePlan plan,
    String operationId,
    String localScriptsRoot,
  ) => _workspaceAccess.runMutation(() async {
    if (operationId.isEmpty ||
        operationId.trim() != operationId ||
        operationId.length > 255) {
      throw ArgumentError.value(operationId, 'operationId');
    }
    if (!isAbsolute(localScriptsRoot)) {
      throw ArgumentError.value(
        localScriptsRoot,
        'localScriptsRoot',
        'An absolute local root is required',
      );
    }
    final db = await database;
    await db.transaction((txn) async {
      final committed = await txn.query(
        'backup_restore_commits',
        columns: ['operationId'],
        where: 'operationId = ?',
        whereArgs: [operationId],
      );
      if (committed.isNotEmpty) return;
      final groupIds = <int, int>{};
      final ordinarySourceIds = <int>{};
      for (final planned in plan.groups) {
        if (groupIds.containsKey(planned.sourceId)) {
          throw StateError('Duplicate planned source group');
        }
        final group = planned.group;
        final values = group.toMap()..remove('id');
        final int targetId;
        if (planned.action == RestoreAction.create) {
          if (group.id != null) {
            throw StateError('New group cannot retain a source ID');
          }
          targetId = await txn.insert(
            'script_groups',
            values,
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        } else {
          final id = group.id;
          if (id == null) {
            throw StateError('Existing group requires a local ID');
          }
          final rows = await txn.query(
            'script_groups',
            where: 'id = ?',
            whereArgs: [id],
          );
          if (rows.length != 1 ||
              rows.single['name'] != group.name ||
              rows.single['projectKey'] != group.projectKey ||
              rows.single['isProject'] != (group.isProject ? 1 : 0)) {
            throw StateError('Restore group destination changed');
          }
          targetId = id;
          if (planned.action == RestoreAction.overwrite) {
            await txn.update(
              'script_groups',
              values,
              where: 'id = ?',
              whereArgs: [id],
            );
          }
        }
        groupIds[planned.sourceId] = targetId;
        if (!group.isProject) ordinarySourceIds.add(planned.sourceId);
      }
      for (final placement in plan.homePlacements) {
        final count = placement.scriptName != null
            ? await txn.update(
                'scripts',
                {'homeSortOrder': placement.homeSortOrder},
                where: 'name = ?',
                whereArgs: [placement.scriptName],
              )
            : await txn.update(
                'script_groups',
                {'homeSortOrder': placement.homeSortOrder},
                where: 'id = ?',
                whereArgs: [placement.groupId],
              );
        if (count != 1) {
          throw StateError('Restore placement destination changed');
        }
      }
      for (final planned in plan.scripts) {
        final script = planned.script;
        if (ScriptNameValidator.normalize(script.name) != script.name) {
          throw const FormatException('Invalid restore script name');
        }
        final sourceGroup = planned.sourceGroupId;
        if (sourceGroup != null && !ordinarySourceIds.contains(sourceGroup)) {
          throw StateError(
            'Missing ordinary group mapping for restored script',
          );
        }
        final values = script.toMap()
          ..['path'] = join(localScriptsRoot, script.name)
          ..['groupId'] = sourceGroup == null ? null : groupIds[sourceGroup];
        if (planned.action == RestoreAction.create) {
          await txn.insert(
            'scripts',
            values,
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        } else if (planned.action == RestoreAction.overwrite) {
          final count = await txn.update(
            'scripts',
            values,
            where: 'name = ?',
            whereArgs: [script.name],
          );
          if (count != 1) {
            throw StateError('Restore script destination changed');
          }
        } else {
          throw StateError('Scripts cannot use the group reuse action');
        }
      }
      await txn.insert('backup_restore_commits', {
        'operationId': operationId,
        'committedAt': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    });
  });

  Future<Set<String>> committedRestoreIds() async {
    final db = await database;
    final rows = await db.query(
      'backup_restore_commits',
      columns: ['operationId'],
    );
    return Set.unmodifiable(rows.map((row) => row['operationId'] as String));
  }

  Future<void> forgetRestoreCommit(String operationId) => _workspaceAccess.runMutation(() async {
    final db = await database;
    await db.delete(
      'backup_restore_commits',
      where: 'operationId = ?',
      whereArgs: [operationId],
    );
  });

  static Future<void> _addHomeSortOrder(Database db) async {
    await db.execute('ALTER TABLE scripts ADD COLUMN homeSortOrder INTEGER');
    await db.execute(
      'ALTER TABLE script_groups ADD COLUMN homeSortOrder INTEGER',
    );
  }

  static Future<void> _createProjectGroupIndexes(Database db) async {
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_script_groups_project_key
      ON script_groups(projectKey)
      WHERE projectKey IS NOT NULL
    ''');
  }

  static Future<void> _migrateSortOrder(Database db) async {
    final maps = await db.query(
      'scripts',
      orderBy: 'isPinned DESC, modifiedAt DESC',
    );
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

  Future<void> upsertScript(ScriptFile script) => _workspaceAccess.runMutation(() async {
    final db = await database;
    await db.insert(
      'scripts',
      script.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  });

  Future<List<ScriptFile>> getAllScripts() async {
    final db = await database;
    final maps = await db.query(
      'scripts',
      orderBy: 'isPinned DESC, sortOrder ASC',
    );
    return maps.map((m) => ScriptFile.fromMap(m)).toList();
  }

  Future<ScriptFile?> getScript(String name) async {
    final db = await database;
    final maps = await db.query(
      'scripts',
      where: 'name = ?',
      whereArgs: [name],
    );
    if (maps.isEmpty) return null;
    return ScriptFile.fromMap(maps.first);
  }

  Future<void> deleteScript(String name) => _workspaceAccess.runMutation(() async {
    final db = await database;
    await db.delete('scripts', where: 'name = ?', whereArgs: [name]);
  });

  Future<void> renameScript(
    String oldName,
    String newName,
    String newPath,
  ) => _workspaceAccess.runMutation(() async {
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
  });

  Future<void> incrementRunCount(String name) => _workspaceAccess.runMutation(() async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE scripts SET runCount = runCount + 1, modifiedAt = ? WHERE name = ?',
      [DateTime.now().millisecondsSinceEpoch, name],
    );
  });

  Future<void> batchUpdateSortOrders(List<ScriptFile> scripts) => _workspaceAccess.runMutation(() async {
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
  });

  Future<void> batchUpdateHomeSortOrders(
    List<ScriptFile> scripts,
    List<ScriptGroup> groups,
  ) => _workspaceAccess.runMutation(() async {
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final script in scripts) {
        batch.update(
          'scripts',
          {
            'sortOrder': script.sortOrder,
            'homeSortOrder': script.homeSortOrder,
          },
          where: 'name = ?',
          whereArgs: [script.name],
        );
      }
      for (final group in groups) {
        batch.update(
          'script_groups',
          {'sortOrder': group.sortOrder, 'homeSortOrder': group.homeSortOrder},
          where: 'id = ?',
          whereArgs: [group.id],
        );
      }
      await batch.commit(noResult: true);
    });
  });

  Future<List<ScriptGroup>> getAllGroups() async {
    final db = await database;
    final maps = await db.query('script_groups', orderBy: 'sortOrder ASC');
    return maps.map((m) => ScriptGroup.fromMap(m)).toList();
  }

  Future<int> createGroup(ScriptGroup group) => _workspaceAccess.runMutation(() async {
    final db = await database;
    return db.insert(
      'script_groups',
      group.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  });

  Future<void> renameGroup(int groupId, String name) => _workspaceAccess.runMutation(() async {
    final db = await database;
    await db.update(
      'script_groups',
      {'name': name, 'modifiedAt': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [groupId],
    );
  });

  Future<void> updateProjectMainFile(int groupId, String? mainFilePath) => _workspaceAccess.runMutation(() async {
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
  });

  Future<void> touchGroup(int groupId) => _workspaceAccess.runMutation(() async {
    final db = await database;
    await db.update(
      'script_groups',
      {'modifiedAt': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [groupId],
    );
  });

  Future<void> deleteGroup(int groupId) => _workspaceAccess.runMutation(() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'scripts',
        {'groupId': null, 'homeSortOrder': null},
        where: 'groupId = ?',
        whereArgs: [groupId],
      );
      await txn.delete('script_groups', where: 'id = ?', whereArgs: [groupId]);
    });
  });

  Future<void> moveScriptsToGroup(List<ScriptFile> scripts) => _workspaceAccess.runMutation(() async {
    final db = await database;
    final batch = db.batch();
    for (final script in scripts) {
      batch.update(
        'scripts',
        {
          'groupId': script.groupId,
          'sortOrder': script.sortOrder,
          'homeSortOrder': script.homeSortOrder,
          'modifiedAt': script.modifiedAt.millisecondsSinceEpoch,
        },
        where: 'name = ?',
        whereArgs: [script.name],
      );
    }
    await batch.commit();
  });
}

class DatabaseOpenException implements Exception {
  DatabaseOpenException(this.message, {this.cause, this.backupPath});

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

class _DatabaseDowngradeSignal implements Exception {
  const _DatabaseDowngradeSignal(this.foundVersion);

  final int foundVersion;
}
