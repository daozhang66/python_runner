import 'package:flutter/material.dart';

import 'pages/ssh_profiles_page.dart';
import 'ssh_text.dart';

/// App bar button that opens the SSH hosts / terminal page.
class SshEntryButton extends StatelessWidget {
  const SshEntryButton({super.key});

  @override
  Widget build(BuildContext context) {
    final t = SshText.of(context);
    return IconButton(
      icon: const Icon(Icons.terminal),
      tooltip: t('SSH 终端', 'SSH terminal'),
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const SshProfilesPage()),
      ),
    );
  }
}
