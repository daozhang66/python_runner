import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backup_providers.dart';

/// This recovery shell intentionally never constructs [child] while the native
/// file journal and SQLite marker disagree. Retrying preserves both stores.
class BackupBootstrap extends ConsumerWidget {
  const BackupBootstrap({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startup = ref.watch(backupStartupProvider);
    if (startup.hasValue && !startup.isLoading && !startup.hasError) {
      return child;
    }
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: startup.hasError
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Backup recovery could not finish. Files and recovery data are preserved. Check available storage and retry.',
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () =>
                              ref.invalidate(backupStartupProvider),
                          child: const Text('Retry recovery'),
                        ),
                      ],
                    )
                  : const CircularProgressIndicator(),
            ),
          ),
        ),
      ),
    );
  }
}
