import 'package:flutter/material.dart';

import 'ssh_text.dart';

enum RunConflictChoice { view, replace, cancel }

/// Only one script can run at a time (one embedded interpreter). Ask what to
/// do when another one is started while [runningName] is still running.
Future<RunConflictChoice> askRunConflict(
  BuildContext context, {
  required String runningName,
  required String newName,
}) async {
  final t = SshText.of(context);
  final choice = await showDialog<RunConflictChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('已有脚本在运行', 'A script is already running')),
      content: Text(
        t(
          '“$runningName”还在运行。同一时间只能运行一个脚本，运行“$newName”会先停止它。',
          '"$runningName" is still running. Only one script can run at a time, so starting "$newName" stops it first.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, RunConflictChoice.cancel),
          child: Text(t('取消', 'Cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, RunConflictChoice.view),
          child: Text(t('查看运行中的', 'View it')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, RunConflictChoice.replace),
          child: Text(t('停止并运行新的', 'Stop it & run')),
        ),
      ],
    ),
  );
  return choice ?? RunConflictChoice.cancel;
}
