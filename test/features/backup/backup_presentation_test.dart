import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:python_runner/features/backup/application/backup_controller.dart';
import 'package:python_runner/features/backup/application/backup_providers.dart';
import 'package:python_runner/features/backup/infrastructure/backup_config_store.dart';
import 'package:python_runner/features/backup/infrastructure/backup_native_bridge.dart';
import 'package:python_runner/features/backup/domain/backup_manifest.dart';
import 'package:python_runner/features/backup/infrastructure/webdav_client.dart';
import 'package:python_runner/features/backup/presentation/backup_restore_page.dart';
import 'package:python_runner/features/backup/presentation/backup_webdav_page.dart';
import 'package:python_runner/features/backup/presentation/backup_history_page.dart';
import 'package:python_runner/features/backup/presentation/backup_preview_page.dart';
import 'package:python_runner/features/backup/presentation/backup_selection_page.dart';
import 'package:python_runner/features/backup/domain/backup_selection.dart';
import 'package:python_runner/features/backup/domain/restore_plan.dart';
import 'package:python_runner/l10n/app_localizations.dart';
import 'package:python_runner/providers/theme_provider.dart';
import 'package:python_runner/services/database_service.dart';
import 'package:python_runner/services/workspace_access.dart';
import 'package:python_runner/ui/app_theme.dart';
import 'package:python_runner/ui/app_liquid_host.dart';

import 'backup_controller_test.dart' show FakeBackupNative, MemoryDav;
import 'backup_config_test.dart' show MemorySecrets;

class PresentationDav extends MemoryDav {
  PresentationDav(super.config);
  bool authError = false;
  List<RemoteBackup> entries = [];
  @override
  Future<List<RemoteBackup>> listBackups({
    BackupCancellation? cancellation,
  }) async {
    if (authError) {
      throw const WebDavException(
        WebDavErrorKind.authentication,
        statusCode: 401,
      );
    }
    return entries;
  }

  @override
  Future<void> testConnection({
    required String operationId,
    BackupCancellation? cancellation,
  }) async {
    if (authError) {
      throw const WebDavException(
        WebDavErrorKind.authentication,
        statusCode: 401,
      );
    }
  }
}

class BackupUiFixture {
  static bool _ffiInitialized = false;
  late Directory dir;
  late DatabaseService db;
  late FakeBackupNative native;
  late SharedPreferences preferences;
  late BackupConfigStore store;
  late MemorySecrets secrets;
  late BackupController controller;
  late PresentationDav dav;
  int reloads = 0;
  Future<void> setUp({bool seed = true}) async {
    if (!_ffiInitialized) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _ffiInitialized = true;
    }
    dir = await Directory.systemTemp.createTemp('backup_ui_');
    final gate = WorkspaceAccess();
    db = DatabaseService(
      databasePath: '${dir.path}/library.db',
      workspaceAccess: gate,
    );
    native = FakeBackupNative(dir);
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    secrets = MemorySecrets();
    store = BackupConfigStore(preferences: preferences, storage: secrets);
    dav = PresentationDav(
      WebDavConfig(
        baseUri: Uri.parse('https://dav.example.com'),
        username: 'me',
      ),
    );
    controller = BackupController(
      database: db,
      native: native,
      configStore: store,
      listScriptFiles: native.listScriptFiles,
      workspaceAccess: gate,
      webDavFactory: (_, _) => dav,
      reloadWorkspace: () async {
        reloads++;
      },
    );
    if (seed) {
      await native.seedScriptFiles();
      for (final group in native.manifest.groups) {
        await db.createGroup(group);
      }
      for (final script in native.manifest.scripts) {
        await db.upsertScript(script);
      }
    }
    await controller.loadLibrary();
  }

  Future<void> dispose() async {
    controller.dispose();
    await native.progressEvents.close();
    await db.closeForTest();
    await dir.delete(recursive: true);
  }

  Future<void> pump(
    WidgetTester tester, {
    Widget page = const BackupRestorePage(),
    double width = 390,
    double textScale = 1,
    String locale = 'en',
    Brightness brightness = Brightness.light,
    AppVisualStyle style = AppVisualStyle.classic,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          backupControllerProvider.overrideWith((ref) => controller),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale(locale),
          theme: AppTheme.build(
            ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: brightness,
            ),
            fontFamily: 'MiSans',
            visualStyle: style,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: AppLiquidHost(child: child!),
          ),
          home: page,
        ),
      ),
    );
    await idle(tester);
  }

  Future<void> idle(WidgetTester tester) async {
    await tester.runAsync(() async {
      for (var n = 0; n < 200; n++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        if (!controller.state.busy) break;
      }
    });
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey(key));
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        target,
        300,
        scrollable: find.byType(Scrollable).last,
      );
    }
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(target), alignment: .5);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(target);
      for (var n = 0; n < 200; n++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        if (!controller.state.busy && n > 5) break;
      }
    });
    await idle(tester);
  }
}

void main() {
  late BackupUiFixture f;
  setUp(() async {
    f = BackupUiFixture();
    await f.setUp();
  });
  tearDown(() async {
    await f.dispose();
  });

  for (final cloud in [false, true]) {
    testWidgets(
      '${cloud ? 'cloud' : 'local'} saved notice expires automatically',
      (tester) async {
        if (cloud) {
          await tester.runAsync(
            () => f.controller.saveWebDavProfile(
              f.dav.config,
              password: 'secret',
            ),
          );
        }
        await f.pump(tester);
        await f.tap(tester, cloud ? 'backup-upload' : 'backup-export-local');
        expect(find.textContaining('Saved:'), findsOneWidget);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 5)),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Saved:'), findsNothing);
        expect(f.controller.state.error, isNull);
        expect(f.controller.state.lastResult, isNull);
      },
    );
  }

  testWidgets(
    'destination buttons share their information row at normal size',
    (tester) async {
      await f.pump(tester);
      for (final (key, title, subtitle) in [
        (
          'backup-change-folder',
          'Device folder',
          'Choose a folder on your first export.',
        ),
        (
          'backup-configure',
          'WebDAV',
          'Add a secure WebDAV server to use cloud backups.',
        ),
      ]) {
        final button = find.byKey(ValueKey(key));
        await tester.scrollUntilVisible(
          button,
          300,
          scrollable: find.byType(Scrollable).last,
        );
        final buttonCenter = tester.getCenter(button);
        final information = tester
            .getRect(find.text(title))
            .expandToInclude(tester.getRect(find.text(subtitle)));
        expect(
          buttonCenter.dy,
          inInclusiveRange(information.top, information.bottom),
        );
        expect(buttonCenter.dx, greaterThan(information.right));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'device export picks a destination then exports selected actual library',
    (tester) async {
      await f.pump(tester);
      await f.tap(tester, 'backup-export-local');
      expect(
        f.controller.state.lastResult?.kind,
        BackupResultKind.exportedLocal,
      );
      expect(f.controller.state.localDirectory?.name, 'Backups');
      expect(f.native.metadata!['scripts'], hasLength(2));
      expect(find.text('Saved: Backups/backup.zip'), findsOneWidget);
    },
  );

  testWidgets(
    'device restore previews three policies and requires destructive confirmation',
    (tester) async {
      await f.pump(tester);
      await f.tap(tester, 'backup-restore-local');
      expect(f.controller.state.preview?.policy.name, 'keepBoth');
      expect(f.native.calls, isNot(contains('commit')));
      await f.tap(tester, 'policy-skip');
      expect(
        f.controller.state.preview!.plan.skippedScriptNames,
        contains('alone.py'),
      );
      await f.tap(tester, 'policy-overwrite');
      await f.tap(tester, 'restore-confirm');
      expect(find.textContaining('entire current directory'), findsOneWidget);
      expect(f.native.calls, isNot(contains('commit')));
      await f.tap(tester, 'restore-confirm-dialog');
      expect(f.controller.state.lastResult?.kind, BackupResultKind.restored);
      expect(f.reloads, 1);
      expect(find.byKey(const ValueKey('backup-export-local')), findsOneWidget);
    },
  );

  testWidgets(
    'WebDAV upload and history download use real controller commands',
    (tester) async {
      await tester.runAsync(
        () => f.controller.saveWebDavProfile(f.dav.config, password: 'secret'),
      );
      f.dav.entries = [
        RemoteBackup(
          uri: f.dav.config.folderUri.resolve('python-runner-backup-test.zip'),
          name: 'python-runner-backup-test.zip',
          size: 2048,
        ),
      ];
      await f.pump(tester);
      await f.tap(tester, 'backup-upload');
      expect(f.controller.state.lastResult?.kind, BackupResultKind.uploaded);
      await f.tap(tester, 'backup-restore-remote');
      await f.tap(tester, 'remote-python-runner-backup-test.zip');
      expect(f.controller.state.preview, isNotNull);
      expect(find.text('Review restore'), findsOneWidget);
    },
  );

  testWidgets(
    'form validates HTTPS and keeps saved password without putting it in fields',
    (tester) async {
      await tester.runAsync(
        () => f.controller.saveWebDavProfile(
          f.dav.config,
          password: 'saved-secret',
        ),
      );
      await f.pump(tester, page: const BackupWebDavPage());
      final password = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('webdav-password')),
          matching: find.byType(TextField),
        ),
      );
      expect(password.controller!.text, isEmpty);
      expect(password.obscureText, true);
      await tester.enterText(
        find.byKey(const ValueKey('webdav-url')),
        'http://unsafe.example',
      );
      await f.tap(tester, 'webdav-save');
      expect(find.textContaining('Enter an HTTPS URL'), findsOneWidget);
      expect((await f.store.readPassword()), 'saved-secret');
      await tester.enterText(
        find.byKey(const ValueKey('webdav-url')),
        'https://new.example',
      );
      await f.tap(tester, 'webdav-save');
      expect(f.store.loadProfile()!.baseUri.host, 'new.example');
      expect((await f.store.readPassword()), 'saved-secret');
    },
  );

  testWidgets(
    'first cloud action configures and tests connection before continuing upload',
    (tester) async {
      await f.pump(tester);
      await f.tap(tester, 'backup-upload');
      await tester.enterText(
        find.byKey(const ValueKey('webdav-url')),
        'https://dav.example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('webdav-username')),
        'me',
      );
      await tester.enterText(
        find.byKey(const ValueKey('webdav-password')),
        'new-secret',
      );
      await f.tap(tester, 'webdav-test');
      expect(
        f.controller.state.lastResult?.kind,
        BackupResultKind.connectionVerified,
      );
      expect(f.store.loadProfile(), isNull);
      await f.tap(tester, 'webdav-save');
      expect(f.controller.state.lastResult?.kind, BackupResultKind.uploaded);
      expect(await f.store.readPassword(), 'new-secret');
    },
  );

  testWidgets('failed secure save retains entered form values for retry', (
    tester,
  ) async {
    await f.pump(tester, page: const BackupWebDavPage());
    await tester.enterText(
      find.byKey(const ValueKey('webdav-url')),
      'https://dav.example.com',
    );
    await tester.enterText(find.byKey(const ValueKey('webdav-username')), 'me');
    await tester.enterText(
      find.byKey(const ValueKey('webdav-password')),
      'retry-secret',
    );
    f.secrets.fail = true;
    await f.tap(tester, 'webdav-save');
    expect(f.controller.state.error?.code, 'CONFIGURATION_UNAVAILABLE');
    expect(f.store.loadProfile(), isNull);
    final input = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('webdav-password')),
        matching: find.byType(TextField),
      ),
    );
    expect(input.controller!.text, 'retry-secret');
    f.secrets.fail = false;
    await f.tap(tester, 'webdav-save');
    expect(await f.store.readPassword(), 'retry-secret');
  });

  testWidgets(
    'history shows empty and authentication failure then refresh succeeds',
    (tester) async {
      await tester.runAsync(
        () => f.controller.saveWebDavProfile(f.dav.config, password: 'secret'),
      );
      await f.pump(tester, page: const BackupHistoryPage());
      expect(
        find.text('No completed backups in this folder yet.'),
        findsOneWidget,
      );
      f.dav.authError = true;
      await f.tap(tester, 'backup-history-refresh');
      expect(find.textContaining('Sign-in failed'), findsOneWidget);
      f.dav.authError = false;
      await f.tap(tester, 'backup-retry');
      expect(
        find.text('No completed backups in this folder yet.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'progress cancellation keeps cleanup failure visible with recovery retry',
    (tester) async {
      await tester.runAsync(f.controller.chooseLocalDirectory);
      f.native.createWait = Completer<void>();
      await f.pump(tester);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('backup-export-local')));
        while (!f.native.calls.contains('create')) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      f.native.progressEvents.add(
        BackupProgress(
          operationId: f.controller.state.operation!.id,
          stage: BackupStage.compressing,
          completed: 5,
          total: 10,
        ),
      );
      await tester.pump();
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .5,
      );
      f.native.failure = 'discard';
      await f.tap(tester, 'backup-cancel-operation');
      expect(f.controller.state.lastResult?.kind, BackupResultKind.cancelled);
      expect(f.controller.state.error?.code, 'TEMP_CLEANUP_PENDING');
      expect(find.text('Retry recovery'), findsOneWidget);
      expect(find.text('Operation cancelled.'), findsNothing);
    },
  );

  testWidgets(
    'a changed library requires a refreshed preview and new confirmation',
    (tester) async {
      await f.pump(tester);
      await f.tap(tester, 'backup-restore-local');
      await tester.runAsync(
        () => f.db.upsertScript(
          f.native.manifest.scripts.first.copyWith(runCount: 99),
        ),
      );
      await f.tap(tester, 'restore-confirm');
      await f.tap(tester, 'restore-confirm-dialog');
      expect(
        f.controller.state.lastResult?.kind,
        BackupResultKind.previewUpdated,
      );
      expect(f.native.calls, isNot(contains('commit')));
      expect(find.textContaining('Your library changed.'), findsOneWidget);
      await f.tap(tester, 'restore-confirm');
      await f.tap(tester, 'restore-confirm-dialog');
      expect(f.controller.state.lastResult?.kind, BackupResultKind.restored);
    },
  );

  testWidgets(
    'legacy ZIP edits display name and chooses an entrypoint without running code',
    (tester) async {
      final json = f.native.manifest.toJson();
      json['scripts'] = [];
      json['groups'] = [(json['groups'] as List).last];
      json['files'] = (json['files'] as List)
          .where((v) => (v['path'] as String).startsWith('projects/'))
          .toList();
      f.native.manifest = BackupManifest.fromJson(json);
      f.native.legacy = true;
      await f.pump(tester);
      await f.tap(tester, 'backup-restore-local');
      await tester.runAsync(() async {
        await tester.enterText(
          find.byKey(const ValueKey('legacy-project-name')),
          'Imported tools',
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await f.idle(tester);
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.runAsync(
        () => tester.tap(find.byType(DropdownButtonFormField<String>)),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Choose later').last);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await f.idle(tester);
      expect(
        f.controller.state.preview!.manifest.groups.single.name,
        'Imported tools',
      );
      expect(f.controller.state.preview!.legacyEntryPoint, isNull);
      expect(f.native.calls, isNot(contains('commit')));
      await tester.ensureVisible(
        find.byKey(const ValueKey('legacy-project-name')),
      );
      await tester.runAsync(() async {
        await tester.enterText(
          find.byKey(const ValueKey('legacy-project-name')),
          '',
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await f.idle(tester);
      await f.tap(tester, 'restore-choose-contents');
      await f.tap(tester, 'selection-confirm');
      final restoreButton = find.byKey(const ValueKey('restore-confirm'));
      if (restoreButton.evaluate().isEmpty) {
        await tester.scrollUntilVisible(restoreButton, 300);
      }
      expect(
        tester.widget<OutlinedButton>(restoreButton).onPressed,
        isNull,
        reason: 'A different preview update must not make an invalid displayed name restorable',
      );
      await f.tap(tester, 'restore-discard');
      expect(f.controller.state.preview, isNull);
      expect(f.native.reservation, isNull);
    },
  );

  testWidgets(
    'policy then Restore before the next frame cannot confirm stale policy',
    (tester) async {
      await f.pump(tester);
      await f.tap(tester, 'backup-restore-local');
      final policy = tester.widget<RadioGroup<RestoreConflictPolicy>>(
        find.byType(RadioGroup<RestoreConflictPolicy>),
      );
      final restoreButton = find.byKey(const ValueKey('restore-confirm'));
      if (restoreButton.evaluate().isEmpty) {
        await tester.scrollUntilVisible(restoreButton, 300);
      }
      final restore = tester.widget<OutlinedButton>(restoreButton).onPressed!;
      await tester.runAsync(() async {
        policy.onChanged(RestoreConflictPolicy.overwrite);
        restore();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await f.idle(tester);
      expect(
        find.byKey(const ValueKey('restore-confirm-dialog')),
        findsNothing,
      );
      expect(
        f.controller.state.preview!.policy,
        RestoreConflictPolicy.overwrite,
      );
      await f.tap(tester, 'restore-confirm');
      expect(find.textContaining('entire current directory'), findsOneWidget);
      expect(f.native.calls, isNot(contains('commit')));
    },
  );

  testWidgets('a rolled-back restore can close its failed preview', (
    tester,
  ) async {
    await f.pump(tester);
    await f.tap(tester, 'backup-restore-local');
    f.native.failure = 'commit';
    await f.tap(tester, 'restore-confirm');
    await f.tap(tester, 'restore-confirm-dialog');
    expect(f.controller.state.preview, isNull);
    expect(f.native.calls, contains('rollback'));
    await f.tap(tester, 'restore-discard');
    expect(find.byType(BackupPreviewPage), findsNothing);
    expect(find.byType(BackupRestorePage), findsOneWidget);
  });

  testWidgets(
    'commit hides cancel and blocks system back until restore finishes',
    (tester) async {
      await f.pump(tester);
      await f.tap(tester, 'backup-restore-local');
      f.native.commitWait = Completer<void>();
      await f.tap(tester, 'restore-confirm');
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('restore-confirm-dialog')));
        while (!f.native.calls.contains('commit')) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pump();
      expect(f.controller.state.operation!.cancellable, false);
      expect(
        find.byKey(const ValueKey('backup-cancel-operation')),
        findsNothing,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(BackupPreviewPage), findsOneWidget);
      await tester.runAsync(() async {
        f.native.commitWait!.complete();
        while (f.controller.state.busy) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await f.idle(tester);
      expect(f.controller.state.lastResult?.kind, BackupResultKind.restored);
    },
  );

  for (final locale in ['zh', 'en']) {
    for (final pageName in ['main', 'form', 'selection', 'preview']) {
      testWidgets('$pageName fits 320 width with 2x $locale text', (
        tester,
      ) async {
        if (pageName == 'preview') {
          await tester.runAsync(f.controller.pickAndStageLocal);
        }
        final page = switch (pageName) {
          'form' => const BackupWebDavPage(),
          'selection' => BackupSelectionPage(
            library: f.controller.state.library!,
            selection: BackupSelection(
              groupIds: [81, 82, 83],
              scriptNames: ['alone.py'],
            ),
          ),
          'preview' => const BackupPreviewPage(),
          _ => const BackupRestorePage(),
        };
        await f.pump(
          tester,
          page: page,
          width: 320,
          textScale: 2,
          locale: locale,
        );
        expect(tester.takeException(), isNull);
        for (var n = 0; n < 18; n++) {
          await tester.drag(find.byType(ListView).first, const Offset(0, -360));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
