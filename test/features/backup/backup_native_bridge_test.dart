import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/backup/infrastructure/backup_native_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('backup-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late BackupNativeBridge bridge;
  setUp(() {
    bridge = BackupNativeBridge(channel: channel);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'picker cancellation is normal but malformed selections reject',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      expect(await bridge.pickBackupArchive(), isNull);
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'uri': 2, 'name': 'x'},
      );
      await expectLater(bridge.pickBackupDirectory(), throwsFormatException);
    },
  );
  test(
    'stage validates portable manifest before returning a typed result',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'stageArchive');
        expect(call.arguments, {
          'operationId': 'op',
          'source': 'content://archive',
          'displayName': 'a.zip',
        });
        return {
          'manifest': {
            'format': 'python_runner_backup',
            'version': 1,
            'createdAt': 1,
            'scripts': [],
            'groups': [],
            'files': [],
          },
          'legacy': false,
          'stagingId': 'op',
        };
      });
      final staged = await bridge.stageArchive(
        'op',
        'content://archive',
        'a.zip',
      );
      expect(staged.manifest.files, isEmpty);
      expect(staged.stagingId, 'op');
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'manifest': {'format': 'bad'},
          'legacy': false,
          'stagingId': 'op',
        },
      );
      await expectLater(
        bridge.stageArchive('op', 'content://archive', 'a.zip'),
        throwsFormatException,
      );
    },
  );
  test(
    'startup cleanup uses a global call without an operation reservation',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'cleanupAbandonedOperations');
        expect(call.arguments, isNull);
        return null;
      });
      await bridge.cleanupAbandonedOperations();
    },
  );

  test('native error codes stay available to orchestration', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(
        code: 'WORKSPACE_BUSY',
        message: 'Workspace busy',
      ),
    );
    await expectLater(
      bridge.acquireWorkspace('op'),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'WORKSPACE_BUSY',
        ),
      ),
    );
  });
  test('decodes nested standard-codec maps into manifest records', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'path': '/private/backup.zip',
        'fileName': 'backup.zip',
        'manifest': {
          'format': 'python_runner_backup',
          'version': 1,
          'createdAt': 1,
          'scripts': [
            {
              'name': 'a.py',
              'createdAt': 1,
              'modifiedAt': 1,
              'runCount': 0,
              'isPinned': true,
              'sortOrder': 0,
              'groupId': null,
              'homeSortOrder': null,
            },
          ],
          'groups': [],
          'files': [
            {
              'path': 'scripts/a.py',
              'isDirectory': false,
              'size': 0,
              'sha256': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
              'modifiedAt': 1,
            },
          ],
        },
      },
    );
    final created = await bridge.createArchive('op', {});
    expect(created.manifest.scripts.single.name, 'a.py');
    expect(created.manifest.scripts.single.isPinned, isTrue);
  });
  test('progress rejects unknown stages and invalid counters', () {
    expect(
      BackupProgress.fromJson({
        'operationId': 'op',
        'stage': 'copying',
        'completed': 3,
        'total': 10,
      }).fraction,
      .3,
    );
    expect(
      () => BackupProgress.fromJson({
        'operationId': 'op',
        'stage': 'secret',
        'completed': 0,
        'total': 1,
      }),
      throwsFormatException,
    );
    expect(
      () => BackupProgress.fromJson({
        'operationId': 'op',
        'stage': 'copying',
        'completed': -1,
        'total': 1,
      }),
      throwsFormatException,
    );
  });
}
