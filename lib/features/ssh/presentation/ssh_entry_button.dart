import 'package:flutter/material.dart';

import 'pages/ssh_profiles_page.dart';
import 'ssh_text.dart';

// The script list page imports only this file, so re-export what it needs.
export 'run_conflict_dialog.dart';

/// App bar button that opens the terminal / SSH page.
class SshEntryButton extends StatelessWidget {
  const SshEntryButton({super.key});

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
