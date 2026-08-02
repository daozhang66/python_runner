import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:python_runner/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DatabaseService migrations', () {
    for (final version in [1, 2, 3, 4, 5]) {
      test('opens schema v$version and migrates to current schema', () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'database_service_migration_v${version}_',
        );
        final dbPath = p.join(tempDir.path, DatabaseService.databaseFileName);
        final seed = await openDatabase(dbPath, singleInstance: false);
        await DatabaseService.createSchemaForTest(seed, version);
        await seed.insert('scripts', {
          'name': 'demo.py',
          'path': '/scripts/demo.py',
          'createdAt': 1710000000000,
          'modifiedAt': 1710000001000,
          'runCount': 1,
        });
        await seed.close();

        final service = DatabaseService.test(databasePath: dbPath);
        try {
          final scripts = await service.getAllScripts();
          expect(scripts, hasLength(1));
          expect(scripts.single.name, 'demo.py');

          final db = await service.database;
          expect(await db.getVersion(), DatabaseService.schemaVersion);
          final groupColumns = await db.rawQuery(
            'PRAGMA table_info(script_groups)',
          );
          expect(
            groupColumns.map((row) => row['name']),
            containsAll(['projectKey', 'mainFilePath', 'isProject']),
          );
        } finally {
          await service.closeForTest();
          await tempDir.delete(recursive: true);
        }
      });
    }

    test('archives newer schema and rebuilds an empty current database',
        () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'database_service_future_schema_',
      );
      final dbPath = p.join(tempDir.path, DatabaseService.databaseFileName);
      await DatabaseService.createFutureSchemaForTest(
        dbPath,
        DatabaseService.schemaVersion + 1,
      );
      await File('$dbPath-wal').writeAsString('sidecar');

      final service = DatabaseService.test(databasePath: dbPath);
      try {
        final database = await service.database;
        expect(await database.getVersion(), DatabaseService.schemaVersion);
        expect(await service.getAllScripts(), isEmpty);
        expect(await File(dbPath).exists(), isTrue);
        expect(await File('$dbPath-wal').exists(), isFalse);

        final backups = await tempDir
            .list()
            .where((entity) => entity is File)
            .map((entity) => entity.path)
            .where((path) => path.contains('.backup.future_v6.'))
            .toList();
        final primaryBackup = backups.singleWhere((path) =>
            path.endsWith('.db') ||
            RegExp(r'\.db\.backup\.future_v6\.\d+$').hasMatch(path));
        expect(await File(primaryBackup).exists(), isTrue);
        expect(
          await File('$primaryBackup-wal').readAsString(),
          'sidecar',
        );
        final archived = await openDatabase(
          primaryBackup,
          readOnly: true,
          singleInstance: false,
        );
        expect(await archived.getVersion(), DatabaseService.schemaVersion + 1);
        await archived.close();
      } finally {
        await service.closeForTest();
        await tempDir.delete(recursive: true);
      }
    });

    test('archives a corrupt database and rebuilds the current schema',
        () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'database_service_corrupt_',
      );
      final dbPath = p.join(tempDir.path, DatabaseService.databaseFileName);
      const corruptContent = 'this is not a sqlite database';
      await File(dbPath).writeAsString(corruptContent);
      final service = DatabaseService.test(databasePath: dbPath);
      try {
        final database = await service.database;
        expect(await database.getVersion(), DatabaseService.schemaVersion);
        expect(await service.getAllScripts(), isEmpty);

        final backups = await tempDir
            .list()
            .where((entity) => entity is File)
            .map((entity) => entity.path)
            .where((path) => path.contains('.backup.corrupt.'))
            .toList();
        expect(backups, hasLength(1));
        expect(await File(backups.single).readAsString(), corruptContent);
      } finally {
        await service.closeForTest();
        await tempDir.delete(recursive: true);
      }
    });

    test('retains only the five newest complete backup bundles', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'database_service_backup_prune_',
      );
      final dbPath = p.join(tempDir.path, DatabaseService.databaseFileName);
      try {
        for (var index = 0;
            index < DatabaseService.maxBackupBundles + 2;
            index++) {
          final timestamp = 1700000000000 + index;
          final prefix = '$dbPath.backup.corrupt.$timestamp';
          await File(prefix).writeAsString('backup $index');
          await File('$prefix-wal').writeAsString('wal $index');
          await File('$prefix-shm').writeAsString('shm $index');
        }
        // Trigger pruning via a recoverable database open; existing backups are
        // older than the newly-created corrupt bundle.
        await File(dbPath).writeAsString('not a database');
        await File('$dbPath-wal').writeAsString('current wal');
        await File('$dbPath-shm').writeAsString('current shm');
        final service = DatabaseService.test(databasePath: dbPath);
        await service.database;
        await service.closeForTest();

        final backups = await tempDir
            .list()
            .where((entity) => entity is File)
            .map((entity) => p.basename(entity.path))
            .where((name) => name.contains('.backup.'))
            .toList();
        final timestamps = backups
            .map((name) => RegExp(r'\.(\d+)(?:-(?:wal|shm))?$')
                .firstMatch(name)!
                .group(1)!)
            .toSet();
        expect(timestamps, hasLength(DatabaseService.maxBackupBundles));
        for (final timestamp in timestamps) {
          expect(
              backups.where((name) => name.endsWith(timestamp)), hasLength(1));
          expect(backups.where((name) => name.endsWith('$timestamp-wal')),
              hasLength(1));
          expect(backups.where((name) => name.endsWith('$timestamp-shm')),
              hasLength(1));
        }
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('retries initialization after a transient open failure', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'database_service_retry_',
      );
      final dbPath = p.join(tempDir.path, DatabaseService.databaseFileName);
      final blockedPath = Directory(dbPath);
      await blockedPath.create();
      final service = DatabaseService.test(databasePath: dbPath);
      try {
        await expectLater(
            service.database, throwsA(isA<DatabaseOpenException>()));
        await blockedPath.delete(recursive: true);

        final database = await service.database;
        expect(await database.getVersion(), DatabaseService.schemaVersion);
      } finally {
        await service.closeForTest();
        await tempDir.delete(recursive: true);
      }
    });
  });
}
