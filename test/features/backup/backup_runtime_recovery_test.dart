import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/backup/application/backup_bootstrap.dart';
import 'package:python_runner/features/backup/application/backup_controller.dart';
import 'package:python_runner/features/backup/application/backup_providers.dart';
import 'package:python_runner/features/backup/application/backup_recovery.dart';
import 'package:python_runner/features/backup/presentation/backup_restore_page.dart';
import 'package:python_runner/l10n/app_localizations.dart';
import 'package:python_runner/providers/theme_provider.dart';

import 'backup_presentation_test.dart' show BackupUiFixture;

void main() {
  testWidgets(
    'runtime recovery remount clears stale controller only after successful cleanup',
    (tester) async {
      final f = BackupUiFixture();
      await tester.runAsync(f.setUp);
      addTearDown(f.dispose);
      var constructions = 0;
      final gate = f.controller.workspaceAccess;
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(f.preferences),
          backupRecoveryProvider.overrideWithValue(
            BackupRecovery(
              database: f.db,
              native: f.native,
              workspaceAccess: gate,
            ),
          ),
          backupControllerProvider.overrideWith((ref) {
            if (constructions++ > 0) {
              f.controller = BackupController(
                listScriptFiles: f.native.listScriptFiles,
                database: f.db,
                native: f.native,
                configStore: f.store,
                workspaceAccess: gate,
              );
            }
            return f.controller;
          }),
        ],
      );
      addTearDown(container.dispose);
      await tester.runAsync(() => container.read(backupStartupProvider.future));
      await tester.runAsync(
        () => tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const BackupBootstrap(
              child: MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                locale: Locale('en'),
                home: BackupRestorePage(),
              ),
            ),
          ),
        ),
      );
      await f.idle(tester);
      final initialConstructions = constructions;
      await tester.runAsync(() async {
        await f.controller.chooseLocalDirectory();
        f.native.failure = 'discard';
        await f.controller.exportLocal();
      });
      await tester.pumpAndSettle();
      expect(find.text('Retry recovery'), findsOneWidget);
      expect(constructions, initialConstructions);
      // A failed recovery must retain the controller and its recovery evidence.
      await tester.runAsync(() async {
        await tester.tap(find.text('Retry recovery'));
        try {
          await container.read(backupStartupProvider.future);
        } catch (_) {}
      });
      await tester.pumpAndSettle();
      expect(constructions, initialConstructions);
      expect(gate.recoveryRequired, true);
      f.native.failure = null;
      // Bootstrap uses the saved default Chinese locale while the app is gated.
      await tester.runAsync(() async {
        await tester.tap(find.text('重试恢复'));
        await container.read(backupStartupProvider.future);
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await f.idle(tester);
      expect(gate.recoveryRequired, false);
      expect(constructions, initialConstructions + 1);
      expect(f.controller.state.error, isNull);
      expect(f.controller.state.lastResult, isNull);
      expect(find.text('Retry recovery'), findsNothing);
    },
  );
}
