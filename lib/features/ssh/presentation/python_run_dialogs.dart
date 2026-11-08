import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:python_runner/pages/app_file_picker_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../application/local_shell_prefs.dart';
import '../application/python_launch.dart';
import 'python_launcher.dart';
import 'ssh_text.dart';

const String _lastFileKey = 'py_run_last_file';
const String _lastArgsKey = 'py_run_last_args';

class _RunFileRequest {
  const _RunFileRequest(this.path, this.args);

  final String path;
  final String args;
}

/// Asks for a .py file and its arguments, then runs it in the embedded Python
/// with a new run console.
Future<void> showRunPythonFileDialog(BuildContext context, WidgetRef ref) async {
  final t = SshText.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final prefs = await SharedPreferences.getInstance();
  if (!context.mounted) return;
  final request = await showDialog<_RunFileRequest>(
    context: context,
    builder: (_) => _RunFileDialog(
      initialPath: prefs.getString(_lastFileKey) ?? '',
      initialArgs: prefs.getString(_lastArgsKey) ?? '',
    ),
  );
  if (request == null) return;
  await prefs.setString(_lastFileKey, request.path);
  await prefs.setString(_lastArgsKey, request.args);
  try {
    final file = File(request.path);
    if (!file.existsSync()) {
      messenger.showSnackBar(
        SnackBar(content: Text(t('找不到文件：${request.path}', 'File not found: ${request.path}'))),
      );
      return;
    }
    final source = utf8.decode(await file.readAsBytes(), allowMalformed: true);
    final args =
        request.args.trim().isEmpty ? <String>[] : shellSplit(request.args);
    if (!context.mounted) return;
    await launchPython(
      context,
      ref,
      PythonLaunch(
        mode: PythonLaunchMode.file,
        displayName: file.uri.pathSegments.last,
        filePath: file.path,
        source: source,
        args: args,
        cwd: file.parent.path,
      ),
    );
  } on PythonCommandException catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(error.message)));
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('$error')));
  }
}

class _RunFileDialog extends StatefulWidget {
  const _RunFileDialog({required this.initialPath, required this.initialArgs});

  final String initialPath;
  final String initialArgs;

  @override
  State<_RunFileDialog> createState() => _RunFileDialogState();
}

class _RunFileDialogState extends State<_RunFileDialog> {
  late final TextEditingController _path =
      TextEditingController(text: widget.initialPath);
  late final TextEditingController _args =
      TextEditingController(text: widget.initialArgs);

  @override
  void dispose() {
    _path.dispose();
    _args.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final t = SshText.of(context);
    final result = await AppFilePickerPage.pickFile(
      context,
      title: t('选择 Python 文件', 'Choose a Python file'),
      allowedExtensions: const ['py'],
      allowSystemPicker: false,
    );
    if (result == null || result.path.isEmpty || !mounted) return;
    setState(() => _path.text = result.path);
  }

  @override
  Widget build(BuildContext context) {
    final t = SshText.of(context);
    return AlertDialog(
      title: Text(t('运行 Python 文件', 'Run a Python file')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _path,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: t('文件路径', 'File path'),
                hintText: '/sdcard/Download/demo.py',
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.folder_open, size: 18),
                label: Text(t('选择文件…', 'Choose a file…')),
              ),
            ),
            TextField(
              controller: _args,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: t('参数（可选）', 'Arguments (optional)'),
                helperText: t(
                  '相当于 sys.argv[1:]，空格分隔，可用引号',
                  'Becomes sys.argv[1:], space separated, quotes allowed',
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('取消', 'Cancel')),
        ),
        FilledButton(
          onPressed: () {
            final path = _path.text.trim();
            if (path.isEmpty) return;
            Navigator.pop(context, _RunFileRequest(path, _args.text));
          },
          child: Text(t('运行', 'Run')),
        ),
      ],
    );
  }
}

class _ShellDirChoice {
  const _ShellDirChoice.reset()
      : path = null,
        reset = true;
  const _ShellDirChoice.path(String this.path) : reset = false;

  final String? path;
  final bool reset;
}

/// Lets the user pick where the local shell starts, or restore the default.
/// Returns true when the setting changed.
Future<bool> showLocalShellSettingsDialog(BuildContext context) async {
  final defaultDir = (await getApplicationSupportDirectory()).path;
  final current = await LocalShellPrefs.loadStartDir();
  final scriptDir = await LocalShellPrefs.loadScriptWorkingDir();
  if (!context.mounted) return false;
  final choice = await showDialog<_ShellDirChoice>(
    context: context,
    builder: (_) => _ShellSettingsDialog(
      current: current ?? '',
      defaultDir: defaultDir,
      scriptDir: scriptDir,
    ),
  );
  if (choice == null) return false;
  await LocalShellPrefs.saveStartDir(choice.reset ? null : choice.path);
  return true;
}

class _ShellSettingsDialog extends StatefulWidget {
  const _ShellSettingsDialog({
    required this.current,
    required this.defaultDir,
    required this.scriptDir,
  });

  final String current;
  final String defaultDir;
  final String? scriptDir;

  @override
  State<_ShellSettingsDialog> createState() => _ShellSettingsDialogState();
}

class _ShellSettingsDialogState extends State<_ShellSettingsDialog> {
  late final TextEditingController _dir =
      TextEditingController(text: widget.current);
  String? _error;

  @override
  void dispose() {
    _dir.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final t = SshText.of(context);
    final result = await AppFilePickerPage.pickFolder(
      context,
      title: t('选择 shell 的启动目录', 'Choose the shell start directory'),
    );
    if (result == null || result.path.isEmpty || !mounted) return;
    setState(() {
      _dir.text = result.path;
      _error = null;
    });
  }

  void _use(String path) {
    setState(() {
      _dir.text = path;
      _error = null;
    });
  }

  void _save() {
    final t = SshText.of(context);
    final path = _dir.text.trim();
    if (path.isEmpty) {
      Navigator.pop(context, const _ShellDirChoice.reset());
      return;
    }
    if (!Directory(path).existsSync()) {
      setState(() => _error = t('目录不存在', 'Directory does not exist'));
      return;
    }
    Navigator.pop(context, _ShellDirChoice.path(path));
  }

  @override
  Widget build(BuildContext context) {
    final t = SshText.of(context);
    final scriptDir = widget.scriptDir;
    return AlertDialog(
      title: Text(t('本机 Shell 启动目录', 'Local shell start directory')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _dir,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: t('目录', 'Directory'),
                hintText: widget.defaultDir,
                errorText: _error,
                helperText: t(
                  '留空即使用默认（应用私有目录）',
                  'Leave empty for the default (the app private directory)',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: Text(t('默认', 'Default')),
                  onPressed: () => _use(''),
                ),
                if (scriptDir != null)
                  ActionChip(
                    label: Text(t('脚本工作目录', 'Script working dir')),
                    onPressed: () => _use(scriptDir),
                  ),
                ActionChip(
                  label: const Text('/sdcard/Download'),
                  onPressed: () => _use('/sdcard/Download'),
                ),
                ActionChip(
                  label: const Text('/sdcard'),
                  onPressed: () => _use('/sdcard'),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.folder_open, size: 18),
                label: Text(t('选择文件夹…', 'Choose a folder…')),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('取消', 'Cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, const _ShellDirChoice.reset()),
          child: Text(t('恢复默认', 'Restore default')),
        ),
        FilledButton(onPressed: _save, child: Text(t('保存', 'Save'))),
      ],
    );
  }
}
