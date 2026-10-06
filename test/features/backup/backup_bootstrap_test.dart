import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:python_runner/providers/theme_provider.dart';
import 'package:python_runner/features/backup/application/backup_bootstrap.dart';
import 'package:python_runner/features/backup/application/backup_providers.dart';

void main() {
  testWidgets(
    'workspace child stays unmounted until recovery succeeds; failure offers retry',
    (tester) async {
      var tries = 0;
      final wait = Completer<void>();
      SharedPreferences.setMockInitialValues({'app_locale': 'en'});
      final preferences = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          backupStartupProvider.overrideWith((ref) async {
            tries++;
            if (tries == 1) throw StateError('preserved');
            await wait.future;
          }),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const BackupBootstrap(
            child: MaterialApp(home: Text('Workspace ready')),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Workspace ready'), findsNothing);
      expect(find.text('Retry recovery'), findsOneWidget);
      await tester.tap(find.text('Retry recovery'));
      await tester.pump();
      expect(find.text('Workspace ready'), findsNothing);
      wait.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Workspace ready'), findsOneWidget);
      expect(tries, 2);
    },
  );
  testWidgets(
    'recovery shell uses saved Chinese locale and dark theme before app exists',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'app_locale': 'zh',
        'theme_mode': 'dark',
      });
      final preferences = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            backupStartupProvider.overrideWith(
              (ref) async => throw StateError('preserved'),
            ),
          ],
          child: const BackupBootstrap(child: Text('workspace')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('重试恢复'), findsOneWidget);
      expect(
        Theme.of(tester.element(find.text('重试恢复'))).brightness,
        Brightness.dark,
      );
      expect(find.text('workspace'), findsNothing);
    },
  );
}
