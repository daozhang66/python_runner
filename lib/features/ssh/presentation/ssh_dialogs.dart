import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ssh_text.dart';

/// Shows [line] (an `authorized_keys` entry) with a copy button.
Future<void> showSshPublicKeyDialog(BuildContext context, String line) {
  final t = SshText.of(context);
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('公钥', 'Public key')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t(
                '把下面这一行追加到服务器的 ~/.ssh/authorized_keys：',
                'Append this line to ~/.ssh/authorized_keys on the server:',
              ),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            SelectableText(
              line,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: line));
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: Text(t('复制并关闭', 'Copy & close')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(t('关闭', 'Close')),
        ),
      ],
    ),
  );
}
