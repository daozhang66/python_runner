import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/infrastructure_providers.dart';
import '../../../providers/script_project_provider.dart';
import '../../../providers/theme_provider.dart';
import '../../../services/workspace_access.dart';
import '../../files/domain/file_manager_location.dart';
import '../../mcp/application/mcp_server_controller.dart'
    show mcpExecutionOwnerProvider;
import '../../scripts/application/script_workspace_controller.dart';
import '../../scripts/application/script_repository.dart';
import '../infrastructure/backup_config_store.dart';
import '../infrastructure/backup_native_bridge.dart';
import '../infrastructure/webdav_client.dart';
import 'backup_controller.dart';
import 'backup_recovery.dart';

final backupNativeBridgeProvider = Provider<BackupNativeBridge>(
  (ref) => BackupNativeBridge(),
);
final backupConfigStoreProvider = Provider<BackupConfigStore>(
  (ref) => BackupConfigStore(preferences: ref.watch(sharedPreferencesProvider)),
);
final backupWebDavFactoryProvider = Provider<WebDavClientFactory>(
  (ref) =>
      (config, password) => WebDavClient(config: config, password: password),
);
final backupRecoveryProvider = Provider<BackupRecovery>(
  (ref) => BackupRecovery(
    database: ref.watch(databaseServiceProvider),
    native: ref.watch(backupNativeBridgeProvider),
    workspaceAccess: ref.watch(workspaceAccessProvider),
  ),
);

/// Must resolve before constructing workspace widgets or starting MCP services.
final backupStartupProvider = FutureProvider<void>((ref) async {
  await ref.read(backupRecoveryProvider).recover();
  // Recovery may have removed a staged operation. Rebuild the persistent UI
  // owner only after cleanup succeeded, before mounting the workspace again.
  ref.invalidate(backupControllerProvider);
  try {
    await ref
        .read(nativeBridgeProvider)
        .ensureFileManagerDirectory(defaultScriptWorkingDirectory);
  } catch (_) {}
});

/// Deliberately not auto-disposed: page changes retain operations and previews.
final backupControllerProvider = ChangeNotifierProvider<BackupController>((
  ref,
) {
  final database = ref.watch(databaseServiceProvider);
  final workspace = ref.read(scriptWorkspaceControllerProvider.notifier);
  return BackupController(
    database: database,
    native: ref.watch(backupNativeBridgeProvider),
    configStore: ref.watch(backupConfigStoreProvider),
    listScriptFiles: ref.watch(scriptRepositoryProvider).listScriptFiles,
    workspaceAccess: ref.watch(workspaceAccessProvider),
    webDavFactory: ref.watch(backupWebDavFactoryProvider),
    isExecutionRunning: () => ref.read(mcpExecutionOwnerProvider).isRunning,
    reloadWorkspace: workspace.load,
    reloadRestoredProjects: ScriptProjectProvider.refreshAfterRestore,
  );
});
