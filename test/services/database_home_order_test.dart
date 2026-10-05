import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:python_runner/models/script_file.dart';
import 'package:python_runner/models/script_group.dart';
import 'package:python_runner/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  for (final failGroupWrite in [false, true]) {
    test('v5 migration and atomic home ordering: failure=$failGroupWrite',
        () async {
      final dir = await Directory.systemTemp.createTemp('home_order_db_');
      final path = p.join(dir.path, 'test.db');
      final seed = await openDatabase(path, singleInstance: false);
      await DatabaseService.createSchemaForTest(seed, 5);
      final script = ScriptFile(
          name: 'demo.py',
          path: 'demo.py',
          createdAt: DateTime(2025, 1, 1),
          modifiedAt: DateTime(2025, 1, 2),
          runCount: 5);
      final group = ScriptGroup(
          id: 1,
          name: 'Project',
          sortOrder: 0,
          createdAt: DateTime(2025, 1, 1),
          modifiedAt: DateTime(2025, 1, 3),
          isProject: true,
          projectKey: 'project_1',
          mainFilePath: 'main.py');
      await seed.insert('scripts', script.toMap()..remove('homeSortOrder'));
      await seed.insert(
          'script_groups', group.toMap()..remove('homeSortOrder'));
      await seed.close();
      final service = DatabaseService.test(databasePath: path);
      try {
        expect((await service.getScript('demo.py'))!.toMap(), script.toMap());
        expect((await service.getAllGroups()).single.toMap(), group.toMap());
        final updatedScript = script.copyWith(homeSortOrder: 1, sortOrder: 3);
        final updatedGroup = group.copyWith(homeSortOrder: 0, sortOrder: 2);
        if (failGroupWrite) {
          final db = await service.database;
          await db.execute(
              '''CREATE TRIGGER reject_group_order BEFORE UPDATE ON script_groups
              BEGIN SELECT RAISE(ABORT, 'test write failure'); END''');
          await expectLater(
              service
                  .batchUpdateHomeSortOrders([updatedScript], [updatedGroup]),
              throwsA(isA<DatabaseException>()));
        } else {
          await service
              .batchUpdateHomeSortOrders([updatedScript], [updatedGroup]);
        }
        await service.closeForTest();
        expect((await service.getScript('demo.py'))!.toMap(),
            (failGroupWrite ? script : updatedScript).toMap());
        expect((await service.getAllGroups()).single.toMap(),
            (failGroupWrite ? group : updatedGroup).toMap());
      } finally {
        await service.closeForTest();
        await dir.delete(recursive: true);
      }
    });
  }
}
