import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../../ui/app_materials.dart';
import '../../../ui/app_settings_section.dart';
import '../application/backup_controller.dart';
import '../application/backup_providers.dart';
import '../domain/backup_manifest.dart';

String backupScope(AppLocalizations l, BackupLibrarySnapshot library) =>
    l.backupScope(
      library.scripts.length,
      library.groups.where((g) => g.isProject).length,
      library.groups.where((g) => !g.isProject).length,
    );

String backupDate(BuildContext context, DateTime? date) => date == null
    ? AppLocalizations.of(context)!.backupUnknownDate
    : DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag())
          .add_Hm()
          .format(date.toLocal());

String backupFailureMessage(
  AppLocalizations l,
  BackupFailure failure,
) => switch (failure.code) {
  'RECOVERY_REQUIRED' || 'TEMP_CLEANUP_PENDING' => l.backupRecoveryRequired,
  'WEBDAV_AUTHENTICATION' => l.backupErrorAuthentication,
  'PERMISSION_LOST' => l.backupErrorLocalPermission,
  'WEBDAV_PERMISSION' => l.backupErrorPermission,
  'UNSUPPORTED_VERSION' || 'UNSUPPORTED_BACKUP_VERSION' => l.backupErrorVersion,
  'INVALID_BACKUP' ||
  'INVALID_ARCHIVE' ||
  'INVALID_MANIFEST' ||
  'HASH_MISMATCH' ||
  'CRC_MISMATCH' ||
  'UNSAFE_PATH' => l.backupErrorInvalid,
  'OPERATION_BUSY' || 'WORKSPACE_BUSY' || 'PICKER_BUSY' => l.backupErrorBusy,
  'EXECUTION_RUNNING' => l.backupErrorRunning,
  'NOTHING_SELECTED' => l.backupNothingSelected,
  'LOCAL_DIRECTORY_REQUIRED' => l.backupFolderUnset,
  'WEBDAV_PROFILE_REQUIRED' => l.backupCloudUnset,
  'CONFIGURATION_UNAVAILABLE' => l.backupErrorConfiguration,
  'SOURCE_MISSING' => l.backupErrorSourceMissing,
  'SOURCE_CHANGED' => l.backupErrorSourceChanged,
  'NO_SPACE' => l.backupErrorStorage,
  'LIMIT_EXCEEDED' => l.backupErrorLimit,
  'WEBDAV_NETWORK' ||
  'WEBDAV_TIMEOUT' ||
  'WEBDAV_NOTFOUND' => l.backupErrorNetwork,
  _ => l.backupErrorGeneric,
};

/// Shared scrollable detail shell. No fixed control widths or text heights.
class BackupPageFrame extends StatelessWidget {
  const BackupPageFrame({
    super.key,
    required this.title,
    required this.children,
    this.canPop = true,
    this.onBack,
    this.scrollController,
  });
  final String title;
  final List<Widget> children;
  final bool canPop;
  final VoidCallback? onBack;
  final ScrollController? scrollController;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: canPop,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && onBack != null) onBack!();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 2),
        toolbarHeight: MediaQuery.textScalerOf(context).scale(20) > 30
            ? 96
            : null,
        flexibleSpace: appGlassBarBackground(context, sampleBackdrop: true),
        leading: onBack == null ? null : BackButton(onPressed: onBack),
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: children,
            ),
          ),
        ),
      ),
    ),
  );
}

class BackupSection extends StatelessWidget {
  const BackupSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => AppSettingsSection(
    title: title,
    icon: icon,
    framed: true,
    children: children,
  );
}

class BackupNote extends StatelessWidget {
  const BackupNote(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
  );
}

/// Errors deliberately take precedence over a simultaneous cancelled result.
class BackupStatusPanel extends ConsumerWidget {
  const BackupStatusPanel({super.key, this.onRetry, this.restoredSummary});
  final VoidCallback? onRetry;
  final String? restoredSummary;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(backupControllerProvider);
    final s = c.state;
    final l = AppLocalizations.of(context)!;
    final op = s.operation;
    if (op != null) {
      final stage = switch (op.stage) {
        BackupOperationStage.preparing => l.backupProgressPreparing,
        BackupOperationStage.selecting => l.backupProgressSelecting,
        BackupOperationStage.scanning => l.backupProgressScanning,
        BackupOperationStage.compressing => l.backupProgressCompressing,
        BackupOperationStage.copying => l.backupProgressCopying,
        BackupOperationStage.uploading => l.backupProgressUploading,
        BackupOperationStage.downloading => l.backupProgressDownloading,
        BackupOperationStage.validating => l.backupProgressValidating,
        BackupOperationStage.staging => l.backupProgressStaging,
        BackupOperationStage.committing => l.backupProgressCommitting,
        BackupOperationStage.finalizing => l.backupProgressFinalizing,
      };
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          liveRegion: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(stage),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: op.fraction),
              if (op.fraction != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    NumberFormat.percentPattern(
                      Localizations.localeOf(context).languageCode,
                    ).format(op.fraction),
                  ),
                ),
              if (op.cancellable)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const ValueKey('backup-cancel-operation'),
                    onPressed: c.cancel,
                    child: Text(l.cancel),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    if (s.error != null ||
        s.lastResult?.kind == BackupResultKind.restoredCleanupPending) {
      final recovery =
          {
            'RECOVERY_REQUIRED',
            'TEMP_CLEANUP_PENDING',
          }.contains(s.error?.code) ||
          s.lastResult?.kind == BackupResultKind.restoredCleanupPending;
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          liveRegion: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                s.error == null
                    ? l.backupRecoveryRequired
                    : backupFailureMessage(l, s.error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              if (recovery || onRetry != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const ValueKey('backup-retry'),
                    onPressed: recovery
                        ? () => ref.invalidate(backupStartupProvider)
                        : onRetry,
                    child: Text(
                      recovery ? l.backupRetryRecovery : l.backupRetry,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    final result = s.lastResult;
    final message = switch (result?.kind) {
      BackupResultKind.exportedLocal => l.backupSavedTo(
        '${s.localDirectory?.name ?? ''}/${result!.document!.name}',
      ),
      BackupResultKind.uploaded => l.backupSavedTo(
        result!.remote!.uri.toString(),
      ),
      BackupResultKind.connectionVerified => l.backupConnectionVerified,
      BackupResultKind.profileSaved => l.backupProfileSaved,
      BackupResultKind.previewUpdated => l.backupPreviewUpdated,
      BackupResultKind.restored => restoredSummary ?? l.backupRestoreComplete,
      BackupResultKind.restoredCleanupPending => l.backupRecoveryRequired,
      BackupResultKind.cancelled => l.backupCancelled,
      _ => null,
    };
    return message == null
        ? const SizedBox.shrink()
        : Semantics(liveRegion: true, child: BackupNote(message));
  }
}
