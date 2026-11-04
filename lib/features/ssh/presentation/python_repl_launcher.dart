import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as legacy_provider;
import 'package:python_runner/features/console/presentation/pages/run_console_page.dart';
import 'package:python_runner/features/scripts/application/script_workspace_controller.dart';
import 'package:python_runner/providers/execution_provider.dart';

import 'ssh_text.dart';

const String _replScriptName = 'python_repl.py';

const String _replSource = '''import code
import sys

banner = "Python %s  (type exit() to quit)" % sys.version.split()[0]
console = code.InteractiveConsole({"__name__": "__console__"})
console.interact(banner=banner, exitmsg="")
''';

/// Opens an interactive Python console on this phone.
///
/// It runs `code.InteractiveConsole` as a normal script, so it uses the
/// embedded Python (and the packages installed with pip) and the existing run
/// console for input and output. Works on every device, including HarmonyOS.
Future<void> openPythonRepl(BuildContext context, WidgetRef ref) async {
  final t = SshText.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final exec = legacy_provider.Provider.of<ExecutionProvider>(
    context,
    listen: false,
  );
  try {
    if (exec.isRunning) {
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => RunConsolePage(
            scriptName: exec.currentScriptName ?? _replScriptName,
          ),
        ),
      );
      return;
    }
    final controller = ref.read(scriptWorkspaceControllerProvider.notifier);
    final exists = ref
        .read(scriptWorkspaceControllerProvider)
        .scripts
        .any((script) => script.name == _replScriptName);
    if (exists) {
      await controller.saveScript(_replScriptName, _replSource);
    } else {
      await controller.createScript(_replScriptName, content: _replSource);
    }
    exec.clearLogs();
    await exec.executeScript(_replScriptName);
    if (!navigator.mounted) return;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const RunConsolePage(scriptName: _replScriptName),
      ),
    );
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          t('无法启动 Python 交互环境：$error', 'Could not start the Python console: $error'),
        ),
      ),
    );
  }
}
