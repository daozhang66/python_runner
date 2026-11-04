import 'package:flutter/material.dart';

import 'pages/ssh_profiles_page.dart';
import 'ssh_text.dart';

/// Entry for the script list's overflow menu that opens the terminal / SSH page.
PopupMenuItem<String> buildSshMenuItem(BuildContext context) {
  final t = SshText.of(context);
  return PopupMenuItem<String>(
    value: 'ssh_terminal',
    onTap: () {
      // The menu pops itself right after onTap, so navigate afterwards.
      Future<void>.delayed(Duration.zero, () {
        if (!context.mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const SshProfilesPage()),
        );
      });
    },
    child: ListTile(
      leading: const Icon(Icons.terminal),
      title: Text(t('终端 / SSH', 'Terminal / SSH')),
      contentPadding: EdgeInsets.zero,
    ),
  );
}
