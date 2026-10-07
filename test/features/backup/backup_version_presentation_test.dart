import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/backup/application/backup_controller.dart';
import 'package:python_runner/features/backup/infrastructure/backup_native_bridge.dart';

import 'backup_presentation_test.dart' show BackupUiFixture;
import 'future_version_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('backup-version-fixture');
  const events = EventChannel('backup-version-fixture-events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late BackupUiFixture f;
  setUp(() async {
    f = BackupUiFixture();
    await f.setUp();
    final gate = f.controller.workspaceAccess;
    f.controller.dispose();
    messenger.setMockMethodCallHandler(
      const MethodChannel('backup-version-fixture-events'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'pickBackupArchive':
          return {
            'uri': 'fixture://future-version.zip',
            'name': 'future-version.zip',
          };
        case 'stageArchive':
          return {
            // Decode the same real ZIP staged by BackupArchiveTest. The real
            // bridge and Dart parser classify this metadata; no error is injected.
            'manifest': await futureVersionFixture(),
            'legacy': false,
            'stagingId': (call.arguments as Map)['operationId'],
          };
        case 'discardOperation':
          return null;
        default:
          throw StateError('Unexpected fixture call ${call.method}');
      }
    });
    f.controller = BackupController(
      listScriptFiles: f.native.listScriptFiles,
      database: f.db,
      native: BackupNativeBridge(channel: channel, events: events),
      configStore: f.store,
      workspaceAccess: gate,
    );
    await f.controller.loadLibrary();
  });
  tearDown(() async {
    await f.dispose();
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('backup-version-fixture-events'),
      null,
    );
  });
  for (final locale in ['en', 'zh']) {
    testWidgets(
      'real future-version ZIP metadata shows update guidance in $locale',
      (tester) async {
        await f.pump(tester, locale: locale);
        await f.tap(tester, 'backup-restore-local');
        expect(f.controller.state.error?.code, 'UNSUPPORTED_VERSION');
        expect(f.controller.state.preview, isNull);
        expect(
          find.text(
            locale == 'en'
                ? 'This backup version is not supported. Update the app before trying again.'
                : '暂不支持此备份版本，请更新应用后重试。',
          ),
          findsOneWidget,
        );
      },
    );
  }
}
