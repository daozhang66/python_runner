import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:python_runner/features/backup/application/backup_providers.dart';
import 'package:python_runner/features/backup/domain/backup_selection.dart';
import 'package:python_runner/features/backup/infrastructure/backup_config_store.dart';
import 'package:python_runner/features/mcp/application/mcp_server_controller.dart';
import 'package:python_runner/features/scripts/application/script_repository.dart';
import 'package:python_runner/providers/execution_provider.dart';
import 'package:python_runner/providers/infrastructure_providers.dart';
import 'package:python_runner/providers/script_project_provider.dart';
import 'package:python_runner/services/database_service.dart';
import 'package:python_runner/services/native_bridge.dart';
import 'package:python_runner/services/script_project_service.dart';
import 'package:python_runner/services/workspace_access.dart';

import '../../support/script_test_helper.dart';
import 'backup_config_test.dart' show MemorySecrets;
import 'backup_controller_test.dart' show FakeBackupNative;
import 'project_restore_refresh_test.dart' show ProjectFiles;
import 'restore_planner_test.dart' show localGroup;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'production provider binding does not refresh unrelated dirty projects',
    () async {
      final dir = await Directory.systemTemp.createTemp('provider_restore_');
      final gate = WorkspaceAccess();
      final db = DatabaseService(
        databasePath: '${dir.path}/test.db',
        workspaceAccess: gate,
      );
      final native = FakeBackupNative(dir);
      SharedPreferences.setMockInitialValues({});
      final config = BackupConfigStore(
        preferences: await SharedPreferences.getInstance(),
        storage: MemorySecrets(),
      );
      final execution = ExecutionProvider(
        NativeBridge.named(eventStreamFactory: (_) => const Stream.empty()),
        workspaceAccess: gate,
      );
      final container = ProviderContainer(
        overrides: [
          databaseServiceProvider.overrideWithValue(db),
          workspaceAccessProvider.overrideWithValue(gate),
          backupNativeBridgeProvider.overrideWithValue(native),
          backupConfigStoreProvider.overrideWithValue(config),
          mcpExecutionOwnerProvider.overrideWithValue(execution),
          scriptRepositoryProvider.overrideWithValue(FakeScriptRepository()),
        ],
      );
      final group = localGroup(7, 'Unrelated', project: true, key: 'unrelated');
      await db.createGroup(group);
      final files = ProjectFiles();
      final project = ScriptProjectProvider(
        group: group,
        service: ScriptProjectService(files),
      );
      addTearDown(() async {
        container.dispose();
        project.dispose();
        execution.dispose();
        await native.progressEvents.close();
        await db.closeForTest();
        await dir.delete(recursive: true);
      });
      await project.load();
      await project.selectFile('main.py');
      project.updateContent('unsaved unrelated');
      final controller = container.read(backupControllerProvider);
      await controller.pickAndStageLocal();
      await controller.updateRestoreSelection(
        BackupSelection(scriptNames: {'alone.py'}),
      );
      await controller.confirmRestore(confirmed: true);
      expect(controller.state.error, isNull);
      expect(await db.getScript('alone.py'), isNotNull);
      expect(project.content, 'unsaved unrelated');
      expect(project.dirty, true);
      expect(project.selectedPath, 'main.py');
      expect(files.loads, 1);
    },
  );
}
