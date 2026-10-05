import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/backup/application/backup_bootstrap.dart';
import 'package:python_runner/features/backup/application/backup_providers.dart';

void main() {
  testWidgets(
    'workspace child stays unmounted until recovery succeeds; failure offers retry',
    (tester) async {
      var tries = 0;
      final wait = Completer<void>();
      final container = ProviderContainer(
        overrides: [
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
}
