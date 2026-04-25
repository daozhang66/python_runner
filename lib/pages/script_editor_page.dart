import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/styles/vs.dart';
import 'package:re_highlight/styles/vs2015.dart';
import '../providers/script_provider.dart';
import '../providers/execution_provider.dart';
import 'run_console_page.dart';

class ScriptEditorPage extends StatefulWidget {
  final String scriptName;
  const ScriptEditorPage({super.key, required this.scriptName});

  @override
  State<ScriptEditorPage> createState() => _ScriptEditorPageState();
}

class _ScriptEditorPageState extends State<ScriptEditorPage> {
  late CodeLineEditingController _controller;
  CodeFindController? _findController;
  bool _loading = true;
  bool _modified = false;
  bool _readOnly = true;
  double _fontSize = 14.0;

  static const _minFontSize = 10.0;
  static const _maxFontSize = 28.0;

  String get _displayName => widget.scriptName.replaceAll('.py', '');

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController();
    _findController = CodeFindController(_controller);
    _loadContent();
  }

  Future<void> _loadContent() async {
    final prefs = await SharedPreferences.getInstance();
    final content = await context.read<ScriptProvider>().readScript(widget.scriptName);
    _controller.text = content;
    _controller.addListener(_onTextChanged);
    setState(() {
      _fontSize = prefs.getDouble('editor_font_size_${widget.scriptName}') ?? 14.0;
      _loading = false;
    });
  }

  Future<void> _changeFontSize(double delta) async {
    final newSize = (_fontSize + delta).clamp(_minFontSize, _maxFontSize);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('editor_font_size_${widget.scriptName}', newSize);
    setState(() => _fontSize = newSize);
  }

  void _onTextChanged() {
    if (!_modified) setState(() => _modified = true);
  }

  Future<void> _save() async {
    final success = await context.read<ScriptProvider>().saveScript(
        widget.scriptName, _controller.text);
    if (success && mounted) {
      setState(() => _modified = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存'), duration: Duration(seconds: 1)));
    }
  }

  Future<bool> _saveSilently() async {
    final success = await context.read<ScriptProvider>().saveScript(
        widget.scriptName, _controller.text);
    if (success && mounted) setState(() => _modified = false);
    return success;
  }

  Future<void> _run() async {
    try {
      if (_modified) {
        final saved = await _saveSilently();
        if (!saved || !mounted) return;
      }
      final scriptProvider = context.read<ScriptProvider>();
      final execProvider = context.read<ExecutionProvider>();
      await scriptProvider.incrementRunCount(widget.scriptName);
      execProvider.clearLogs();
      await execProvider.executeScript(widget.scriptName);
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RunConsolePage(scriptName: widget.scriptName),
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('运行失败: $e'), duration: const Duration(seconds: 3)));
    }
  }

  Widget _buildToolbar() {
    if (_readOnly) return const SizedBox.shrink();
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      height: 36,
      child: Row(
        children: [
          const SizedBox(width: 8),
          _ToolbarBtn(label: '⇥ 缩进', onTap: () => _controller.applyIndent()),
          const SizedBox(width: 4),
          _ToolbarBtn(label: '⇤ 取消', onTap: () => _controller.applyOutdent()),
          const SizedBox(width: 4),
          _ToolbarBtn(label: '↩ 撤回', onTap: () => _controller.undo()),
          const SizedBox(width: 4),
          _ToolbarBtn(label: '↪ 重做', onTap: () => _controller.redo()),
          const Spacer(),
          _ToolbarBtn(label: '搜索', onTap: () => _findController?.findMode()),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final execProvider = context.watch<ExecutionProvider>();
    final isThisRunning = execProvider.isRunning &&
        execProvider.currentScriptName == widget.scriptName;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(_displayName),
        actions: [
          IconButton(
            icon: Icon(_readOnly ? Icons.lock : Icons.lock_open, size: 20),
            onPressed: () => setState(() => _readOnly = !_readOnly),
            tooltip: _readOnly ? '只读模式' : '编辑模式',
          ),
          IconButton(
            icon: const Icon(Icons.search, size: 20),
            onPressed: () {
              if (_readOnly) {
                _findController?.findMode();
              } else {
                _findController?.findMode();
              }
            },
            tooltip: '搜索',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.format_size, size: 20),
            tooltip: '字体大小',
            position: PopupMenuPosition.under,
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                enabled: false,
                padding: EdgeInsets.zero,
                child: StatefulBuilder(
                  builder: (ctx, setLocal) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.text_decrease),
                        onPressed: _fontSize > _minFontSize
                            ? () {
                                _changeFontSize(-2);
                                setLocal(() {});
                              }
                            : null,
                      ),
                      Text('${_fontSize.toInt()}px',
                          style: const TextStyle(fontSize: 14)),
                      IconButton(
                        icon: const Icon(Icons.text_increase),
                        onPressed: _fontSize < _maxFontSize
                            ? () {
                                _changeFontSize(2);
                                setLocal(() {});
                              }
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_modified)
            IconButton(
                icon: const Icon(Icons.save), onPressed: _save, tooltip: '保存'),
          IconButton(
            icon: Icon(isThisRunning ? Icons.stop : Icons.play_arrow),
            onPressed: isThisRunning
                ? () => context.read<ExecutionProvider>().stopExecution()
                : _run,
            tooltip: isThisRunning ? '停止' : '运行',
          ),
          IconButton(
            icon: const Icon(Icons.fullscreen),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RunConsolePage(scriptName: widget.scriptName),
              ),
            ),
            tooltip: '全屏终端',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildToolbar(),
                Expanded(
                  child: CodeEditor(
                    controller: _controller,
                    findController: _findController,
                    readOnly: _readOnly,
                    style: CodeEditorStyle(
                      fontFamily: 'monospace',
                      fontSize: _fontSize,
                      codeTheme: CodeHighlightTheme(
                        languages: {'python': CodeHighlightThemeMode(mode: langPython)},
                        theme: isDark ? vs2015Theme : vsTheme,
                      ),
                    ),
                    wordWrap: false,
                    indicatorBuilder: (context, editingController, chunkController, notifier) {
                      return Row(
                        children: [
                          DefaultCodeLineNumber(
                            controller: editingController,
                            notifier: notifier,
                          ),
                        ],
                      );
                    },
                    findBuilder: (context, controller, readOnly) {
                      return CodeFindPanelView(
                        controller: controller,
                        readOnly: readOnly,
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _findController?.close();
    super.dispose();
  }
}

class _ToolbarBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ToolbarBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
      ),
    );
  }
}

/// Search/replace panel for CodeEditor.
class CodeFindPanelView extends StatelessWidget implements PreferredSizeWidget {
  final CodeFindController controller;
  final bool readOnly;

  const CodeFindPanelView({
    super.key,
    required this.controller,
    required this.readOnly,
  });

  @override
  Size get preferredSize => Size(
    double.infinity,
    controller.value == null ? 0 : 40,
  );

  @override
  Widget build(BuildContext context) {
    if (controller.value == null) {
      return const SizedBox(width: 0, height: 0);
    }
    final value = controller.value!;
    final result = value.result == null
        ? '无结果'
        : '${value.result!.index + 1}/${value.result!.matches.length}';
    return Container(
      margin: const EdgeInsets.only(right: 10),
      alignment: Alignment.topRight,
      height: preferredSize.height,
      child: SizedBox(
        width: 320,
        child: Row(
          children: [
            SizedBox(
              width: 150,
              height: 32,
              child: TextField(
                maxLines: 1,
                focusNode: controller.findInputFocusNode,
                controller: controller.findInputController,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  hintText: '搜索...',
                  filled: true,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  border: OutlineInputBorder(gapPadding: 0),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(result, style: const TextStyle(fontSize: 11)),
            const Spacer(),
            IconButton(
              onPressed: value.result == null ? null : () => controller.previousMatch(),
              icon: const Icon(Icons.arrow_upward, size: 14),
              constraints: const BoxConstraints(maxWidth: 28, maxHeight: 28),
              splashRadius: 14,
              tooltip: '上一个',
            ),
            IconButton(
              onPressed: value.result == null ? null : () => controller.nextMatch(),
              icon: const Icon(Icons.arrow_downward, size: 14),
              constraints: const BoxConstraints(maxWidth: 28, maxHeight: 28),
              splashRadius: 14,
              tooltip: '下一个',
            ),
            IconButton(
              onPressed: () => controller.close(),
              icon: const Icon(Icons.close, size: 14),
              constraints: const BoxConstraints(maxWidth: 28, maxHeight: 28),
              splashRadius: 14,
              tooltip: '关闭',
            ),
          ],
        ),
      ),
    );
  }
}
