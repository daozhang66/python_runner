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

    test('refuses newer schema and leaves a backup copy', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'database_service_future_schema_',
      );
      final dbPath = p.join(tempDir.path, DatabaseService.databaseFileName);
      await DatabaseService.createFutureSchemaForTest(
        dbPath,
        DatabaseService.schemaVersion + 1,
      );

      final service = DatabaseService.test(databasePath: dbPath);
      try {
        Object? caught;
        try {
          await service.openForTest();
        } catch (error) {
          caught = error;
        }

        expect(caught, isA<UnsupportedDatabaseVersionException>());
        final error = caught! as UnsupportedDatabaseVersionException;
        expect(error.foundVersion, DatabaseService.schemaVersion + 1);
        expect(error.backupPath, isNotNull);
        expect(await File(error.backupPath!).exists(), isTrue);
        expect(await File(dbPath).exists(), isTrue);
      } finally {
        await service.closeForTest();
        await tempDir.delete(recursive: true);
      }
    });
  });
}
