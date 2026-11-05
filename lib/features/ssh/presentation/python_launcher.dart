import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as legacy_provider;
import 'package:python_runner/features/console/presentation/pages/run_console_page.dart';
import 'package:python_runner/features/scripts/application/script_workspace_controller.dart';
import 'package:python_runner/providers/execution_provider.dart';

import '../application/python_launch.dart';
import 'run_conflict_dialog.dart';
import 'ssh_text.dart';

/// The script that carries a terminal command into the embedded Python. It is
/// rewritten every time, so it only ever holds the latest command.
const String pythonLauncherScriptName = 'python_launcher.py';

/// Runs [launch] in the embedded Python and opens a new run console for it.
///
/// Only one script can run at a time. If another one is still running the user
/// decides: view it, stop it and run the new one, or cancel. Returns true when
/// the new run was started.
Future<bool> launchPython(
  BuildContext context,
  WidgetRef ref,
  PythonLaunch launch,
) async {
  final t = SshText.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final exec = legacy_provider.Provider.of<ExecutionProvider>(
    context,
    listen: false,
  );
  try {
    if (exec.isRunning) {
      final running = exec.currentScriptName ?? pythonLauncherScriptName;
      final choice = await askRunConflict(
        context,
        runningName: running,
        newName: launch.label,
      );
      if (choice == RunConflictChoice.view) {
        if (navigator.mounted) {
          await navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => RunConsolePage(scriptName: running),
            ),
          );
        }
        return false;
      }
      if (choice != RunConflictChoice.replace) return false;
    }
    final source = buildLauncherSource(launch);
    final controller = ref.read(scriptWorkspaceControllerProvider.notifier);
    final exists = ref
        .read(scriptWorkspaceControllerProvider)
        .scripts
        .any((script) => script.name == pythonLauncherScriptName);
    if (exists) {
      await controller.saveScript(pythonLauncherScriptName, source);
    } else {
      await controller.createScript(pythonLauncherScriptName, content: source);
    }
    await exec.executeScript(pythonLauncherScriptName);
    if (!navigator.mounted) return true;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const RunConsolePage(scriptName: pythonLauncherScriptName),
      ),
    );
    return true;
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          t('无法启动 Python：$error', 'Could not start Python: $error'),
        ),
      ),
    );
    return false;
  }
}
