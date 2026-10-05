import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/backup/domain/backup_manifest.dart';
import 'package:python_runner/features/backup/domain/backup_selection.dart';

import 'future_version_fixture.dart';

Map<String, dynamic> manifestFixture() => {
  'format': 'python_runner_backup',
  'version': 1,
  'createdAt': 1710000000123,
  'scripts': [
    {
      'name': '你好.py',
      'createdAt': 1700000000000,
      'modifiedAt': 1700000001000,
      'runCount': 12,
      'isPinned': true,
      'sortOrder': 4,
      'groupId': 81,
      'homeSortOrder': null,
    },
    {
      'name': 'alone.py',
      'createdAt': 1700000000000,
      'modifiedAt': 1700000001000,
      'runCount': 0,
      'isPinned': false,
      'sortOrder': 5,
      'groupId': null,
      'homeSortOrder': 2,
    },
  ],
  'groups': [
    {
      'id': 81,
      'name': '工具',
      'sortOrder': 0,
      'createdAt': 1700000000000,
      'modifiedAt': 1700000001000,
      'isProject': false,
      'projectKey': null,
      'mainFilePath': null,
      'homeSortOrder': 0,
    },
    {
      'id': 82,
      'name': 'Empty',
      'sortOrder': 1,
      'createdAt': 1700000000000,
      'modifiedAt': 1700000001000,
      'isProject': false,
      'projectKey': null,
      'mainFilePath': null,
      'homeSortOrder': 1,
    },
    {
      'id': 83,
      'name': 'Project',
      'sortOrder': 2,
      'createdAt': 1700000000000,
      'modifiedAt': 1700000001000,
      'isProject': true,
      'projectKey': 'donor_project',
      'mainFilePath': 'src/main.py',
      'homeSortOrder': 3,
    },
  ],
  'files': [
    fileJson('scripts/你好.py'),
    fileJson('scripts/alone.py'),
    fileJson('projects/donor_project', directory: true),
    fileJson('projects/donor_project/src/main.py'),
    fileJson('projects/donor_project/.hidden/data.bin'),
    fileJson('projects/donor_project/empty', directory: true),
  ],
};

Map<String, dynamic> fileJson(String path, {bool directory = false}) => {
  'path': path,
  'isDirectory': directory,
  'size': directory ? 0 : 15,
  'sha256': directory ? null : List.filled(64, 'a').join(),
  'modifiedAt': 1700000001000,
};

void main() {
  test(
    'shared future-version ZIP metadata has a distinct typed failure',
    () async {
      final json = await futureVersionFixture();
      expect(
        () => BackupManifest.fromJson(json),
        throwsA(
          isA<UnsupportedBackupVersion>().having(
            (e) => e.version,
            'version',
            2,
          ),
        ),
      );
      json['version'] = 1;
      expect(BackupManifest.fromJson(json).scripts.single.name, 'hello.py');
    },
  );
  test('wrong format and malformed versions are not unsupported versions', () {
    for (final version in [null, '2', 2.0, 2.5, -1, 9007199254740992]) {
      final json = manifestFixture()..['version'] = version;
      expect(
        () => BackupManifest.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e is UnsupportedBackupVersion,
            'unsupported version',
            false,
          ),
        ),
      );
    }
    final json = manifestFixture()
      ..['format'] = 'other'
      ..['version'] = 2;
    expect(
      () => BackupManifest.fromJson(json),
      throwsA(
        isA<FormatException>().having(
          (e) => e is UnsupportedBackupVersion,
          'unsupported version',
          false,
        ),
      ),
    );
  });
  test(
    'roundtrips Unicode, metadata, binary entries and empty directories',
    () {
      final json = manifestFixture();
      final manifest = BackupManifest.fromJson(json);
      expect(jsonDecode(jsonEncode(manifest.toJson())), json);
      expect(manifest.scripts.first.path, isEmpty);
      expect(manifest.scripts.first.runCount, 12);
      expect(manifest.scripts.first.isPinned, isTrue);
      expect(manifest.groups.last.mainFilePath, 'src/main.py');
      expect(manifest.files.last.isDirectory, isTrue);
      expect(() => manifest.scripts.clear(), throwsUnsupportedError);
    },
  );

  final invalidCases = <String, void Function(Map<String, dynamic>)>{
    'unknown version': (m) => m['version'] = 2,
    'wrong format': (m) => m['format'] = 'other',
    'wrong scalar type': (m) => m['createdAt'] = '1710000000123',
    'nonintegral version': (m) => m['version'] = 1.0,
    'unsafe script name': (m) => m['scripts'][0]['name'] = '../bad.py',
    'absolute path': (m) => m['files'][0]['path'] = '/scripts/你好.py',
    'drive path': (m) => m['files'][0]['path'] = 'C:/scripts/你好.py',
    'parent traversal': (m) =>
        m['files'][3]['path'] = 'projects/donor_project/../x',
    'backslash': (m) => m['files'][3]['path'] = r'projects/donor_project/a\b',
    'empty component': (m) =>
        m['files'][3]['path'] = 'projects/donor_project//x',
    'duplicate file': (m) => m['files'].add(m['files'][0]),
    'duplicate script': (m) => m['scripts'].add(m['scripts'][0]),
    'duplicate group ID': (m) => m['groups'][1]['id'] = 81,
    'duplicate group name': (m) => m['groups'][1]['name'] = '工具',
    'missing group reference': (m) => m['scripts'][0]['groupId'] = 999,
    'script in project': (m) => m['scripts'][0]['groupId'] = 83,
    'unlisted standalone payload': (m) =>
        m['files'].add(fileJson('scripts/extra.py')),
    'missing script payload': (m) => m['files'].removeAt(0),
    'missing entrypoint': (m) => m['groups'][2]['mainFilePath'] = 'missing.py',
    'unknown project root': (m) => m['files'].add(fileJson('projects/other/a')),
    'unrelated payload': (m) => m['files'].add(fileJson('settings.json')),
    'file as ancestor': (m) =>
        m['files'].add(fileJson('projects/donor_project/src')),
    'bad hash': (m) => m['files'][0]['sha256'] = 'aa',
    'negative size': (m) => m['files'][0]['size'] = -1,
    'nonzero directory': (m) => m['files'][2]['size'] = 1,
    'negative run count': (m) => m['scripts'][0]['runCount'] = -1,
    'wrong boolean': (m) => m['scripts'][0]['isPinned'] = 1,
    'too many scripts': (m) =>
        m['scripts'] = List.filled(10001, m['scripts'][0]),
  };
  for (final entry in invalidCases.entries) {
    test('rejects ${entry.key}', () {
      final json = manifestFixture();
      entry.value(json);
      expect(() => BackupManifest.fromJson(json), throwsFormatException);
    });
  }

  test('ignores donor absolute script path and never serializes it', () {
    final json = manifestFixture();
    json['scripts'][0]['path'] = '/data/another/device/你好.py';
    final manifest = BackupManifest.fromJson(json);
    expect(manifest.scripts.first.path, '');
    expect(manifest.toJson()['scripts'][0].containsKey('path'), isFalse);
  });

  test('selection preserves group linkage, selects group children and whole projects', () {
    final manifest = BackupManifest.fromJson(manifestFixture());
    final partial = BackupSelection(
      scriptNames: {'你好.py'},
      groupIds: {82, 83},
    ).select(manifest);
    expect(partial.scripts.map((s) => s.name), ['你好.py']);
    expect(partial.groups.map((g) => g.id), [81, 82, 83]);
    expect(partial.files.map((f) => f.path), [
      'scripts/你好.py',
      'projects/donor_project',
      'projects/donor_project/src/main.py',
      'projects/donor_project/.hidden/data.bin',
      'projects/donor_project/empty',
    ]);
    expect(
      BackupSelection(groupIds: {81}).select(manifest).scripts.single.name,
      '你好.py',
    );
    expect(
      BackupSelection.all(manifest).select(manifest).toJson(),
      manifest.toJson(),
    );
    expect(
      () => BackupSelection(scriptNames: {'missing.py'}).select(manifest),
      throwsFormatException,
    );
    expect(
      () => BackupSelection(groupIds: {999}).select(manifest),
      throwsFormatException,
    );
  });
}
