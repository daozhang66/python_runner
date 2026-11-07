import 'package:flutter/material.dart';
import 'package:provider/provider.dart' as legacy_provider;
import 'package:python_runner/providers/execution_provider.dart';

import '../application/log/run_log_recorder.dart';
import 'pages/ssh_profiles_page.dart';
import 'ssh_text.dart';

// The script list page imports only this file, so re-export what it needs.
export 'run_conflict_dialog.dart';

/// App bar button that opens the terminal / SSH page.
///
/// It also hooks the script run recorder to the shared execution provider the
/// first time the home screen is shown, so every run is logged from then on.
class SshEntryButton extends StatefulWidget {
  const SshEntryButton({super.key});

  @override
  State<SshEntryButton> createState() => _SshEntryButtonState();
}

class _SshEntryButtonState extends State<SshEntryButton> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        RunLogRecorder.instance.attach(
          legacy_provider.Provider.of<ExecutionProvider>(
            context,
            listen: false,
          ),
        );
      } catch (_) {
        // No execution provider in this tree (for example in a widget test).
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = SshText.of(context);
    return IconButton(
      icon: const Icon(Icons.terminal),
      tooltip: t('终端 / SSH', 'Terminal / SSH'),
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const SshProfilesPage()),
      ),
    );
  }
}
