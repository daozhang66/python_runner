import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/backup/domain/backup_manifest.dart';
import 'package:python_runner/features/backup/domain/backup_selection.dart';
import 'package:python_runner/features/backup/presentation/backup_selection_page.dart';
import 'package:python_runner/l10n/app_localizations.dart';

import 'restore_planner_test.dart' show localGroup, localScript;

void main() {
  testWidgets(
    'unchecking a child retains siblings without implicit whole group',
    (tester) async {
      final library = BackupLibrarySnapshot(
        scripts: [
          localScript('one.py', groupId: 1),
          localScript('two.py', groupId: 1),
        ],
        groups: [localGroup(1, 'Tools'), localGroup(2, 'Empty')],
      );
      BackupSelection? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<BackupSelection>(
                    MaterialPageRoute(
                      builder: (_) => BackupSelectionPage(
                        library: library,
                        selection: BackupSelection(groupIds: [1, 2]),
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tools'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('one.py'));
      await tester.tap(find.byKey(const ValueKey('selection-confirm')));
      await tester.pumpAndSettle();
      expect(result!.groupIds, {2});
      expect(result!.scriptNames, {'two.py'});
      expect(result!.selectSnapshot(library).scripts.map((s) => s.name), [
        'two.py',
      ]);
      expect(result!.selectSnapshot(library).groups.map((g) => g.name), [
        'Tools',
        'Empty',
      ]);
    },
  );
}
