import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/styles/vs.dart';
import 'package:re_highlight/styles/vs2015.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/script_group.dart';
import '../providers/execution_provider.dart';
import '../providers/script_provider.dart';
import '../services/native_bridge.dart';
import '../services/script_project_service.dart';
import '../ui/app_toolbars.dart';
import '../utils/app_page_transitions.dart';
import 'run_console_page.dart';
import 'script_editor_page.dart';

class ProjectFileEditorPage extends StatefulWidget {
  final ScriptGroup group;
  final String filePath;
  final VoidCallback? onSaved;

  const ProjectFileEditorPage({
    super.key,
    required this.group,
    required this.filePath,
    this.onSaved,
  });

  @override
  State<ProjectFileEditorPage> createState() => _ProjectFileEditorPageState();
}

class _ProjectFileEditorPageState extends State<ProjectFileEditorPage> {
  late final ScriptProjectService _service;
  late final CodeLineEditingController _controller;
  CodeFindController? _findController;
  late final SelectionToolbarController _toolbarController;
  bool _loading = true;
  bool _modified = false;
  bool _readOnly = true;
  double _fontSize = 10.0;
  double? _scaleStartFontSize;
  String _savedText = '';

  static const _minFontSize = 6.0;
  static const _maxFontSize = 36.0;

  String get _title => widget.filePath.split('/').last;

  @override
  void initState() {
    super.initState();
    _service = ScriptProjectService(NativeBridge());
    _controller = CodeLineEditingController();
    _findController = CodeFindController(_controller);
    _toolbarController = _buildSelectionToolbarController();
    _loadContent();
  }

  SelectionToolbarController _buildSelectionToolbarController() {
    return MobileSelectionToolbarController(
      builder: ({
        required TextSelectionToolbarAnchors anchors,
        required BuildContext context,
        required CodeLineEditingController controller,
        required VoidCallback onDismiss,
        required VoidCallback onRefresh,
      }) {
        final buttonItems = <ContextMenuButtonItem>[];

        if (!controller.isEmpty) {
          buttonItems.add(
            ContextMenuButtonItem(
              type: ContextMenuButtonType.copy,
              onPressed: () async {
                await controller.copy();
                onDismiss();
              },
            ),
          );
        }

        if (!_readOnly && !controller.isEmpty) {
          buttonItems.add(
            ContextMenuButtonItem(
              type: ContextMenuButtonType.cut,
              onPressed: () {
                controller.cut();
                onDismiss();
              },
            ),
          );
        }

        if (!_readOnly) {
          buttonItems.add(
            ContextMenuButtonItem(
              type: ContextMenuButtonType.paste,
              onPressed: () {
                controller.paste();
                onDismiss();
              },
            ),
          );
        }

        if (!controller.isEmpty && !controller.isAllSelected) {
          buttonItems.add(
            ContextMenuButtonItem(
              type: ContextMenuButtonType.selectAll,
              onPressed: () {
                controller.selectAll();
                onRefresh();
              },
            ),
          );
        }

        if (buttonItems.isEmpty) return const SizedBox.shrink();
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: anchors,
          buttonItems: buttonItems,
        );
      },
    );
  }

  Future<void> _loadContent() async {
    final prefs = await SharedPreferences.getInstance();
    final content =
        await _service.readProjectFile(widget.group, widget.filePath);
    if (!mounted) return;
    _savedText = content;
    _controller.text = content;
    _controller.addListener(_onTextChanged);
    setState(() {
      _fontSize = prefs.getDouble('project_editor_font_size') ?? 10.0;
      _modified = false;
      _loading = false;
    });
  }

  Future<void> _persistFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('project_editor_font_size', _fontSize);
  }

  void _handleScaleStart(ScaleStartDetails details) {
    if (details.pointerCount >= 2) {
      _scaleStartFontSize = _fontSize;
    }
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    final startSize = _scaleStartFontSize;
    if (startSize == null || details.pointerCount < 2) return;
    final nextSize = (startSize * details.scale)
        .clamp(_minFontSize, _maxFontSize)
        .toDouble();
    if ((nextSize - _fontSize).abs() < 0.1) return;
    setState(() => _fontSize = nextSize);
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    if (_scaleStartFontSize != null) {
      _scaleStartFontSize = null;
      unawaited(_persistFontSize());
    }
  }

  void _onTextChanged() {
    final currentModified = _controller.text != _savedText;
    if (currentModified == _modified) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final latestModified = _controller.text != _savedText;
      if (latestModified != _modified) {
        setState(() => _modified = latestModified);
      }
    });
  }

  Future<void> _save() async {
    final success = await _service.saveProjectFile(
      widget.group,
      widget.filePath,
      _controller.text,
    );
    if (!success || !mounted) return;
    _savedText = _controller.text;
    widget.onSaved?.call();
    setState(() => _modified = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存'), duration: Duration(seconds: 1)),
    );
  }

  Future<bool> _saveSilently() async {
    final success = await _service.saveProjectFile(
      widget.group,
      widget.filePath,
      _controller.text,
    );
    if (success && mounted) {
      _savedText = _controller.text;
      widget.onSaved?.call();
      setState(() => _modified = false);
    }
    return success;
  }

  Future<void> _runProject() async {
    try {
      if (_modified) {
        final saved = await _saveSilently();
        if (!saved || !mounted) return;
      }
      final executionProvider = context.read<ExecutionProvider>();
      executionProvider.clearLogs();
      await executionProvider.executeScriptProject(widget.group);
      if (!mounted) return;
      if (!executionProvider.isRunning) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('项目启动失败')),
        );
        return;
      }
      await context.read<ScriptProvider>().markProjectGroupUsed(widget.group);
      if (!mounted) return;
      Navigator.push(
        context,
        AppPageTransitions.scaleIn(
          RunConsolePage(scriptName: widget.group.name),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('运行失败: $e')),
      );
    }
  }

  Widget _buildCommandBar(bool isThisProjectRunning) {
    if (_readOnly) return const SizedBox.shrink();
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      height: 36,
      child: Row(
        children: [
          const SizedBox(width: 8),
          AppToolbarButton(
            icon: Icons.format_indent_increase,
            tooltip: '缩进',
            onPressed: () => _controller.applyIndent(),
          ),
          AppToolbarButton(
            icon: Icons.format_indent_decrease,
            tooltip: '反缩进',
            onPressed: () => _controller.applyOutdent(),
          ),
          AppToolbarButton(
            icon: Icons.undo,
            tooltip: '撤销',
            onPressed: () => _controller.undo(),
          ),
          AppToolbarButton(
            icon: Icons.redo,
            tooltip: '重做',
            onPressed: () => _controller.redo(),
          ),
          const Spacer(),
          AppToolbarButton(
            icon: Icons.search,
            tooltip: '搜索',
            onPressed: () => _findController?.findMode(),
          ),
          AppToolbarButton(
            icon: isThisProjectRunning ? Icons.stop : Icons.play_arrow,
            active: true,
            tooltip: isThisProjectRunning ? '停止' : '运行项目',
            onPressed: isThisProjectRunning
                ? () => context.read<ExecutionProvider>().stopExecution()
                : _runProject,
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildEditorStatusBar() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.65),
        border: Border(
          top: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.35)),
        ),
      ),
      child: Row(
        children: [
          Text(
            _modified ? '已修改' : '已保存',
            style: TextStyle(
              fontSize: 11,
              color: _modified ? colors.primary : colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _readOnly ? '只读' : '编辑',
            style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
          ),
          const Spacer(),
          Text(
            '${_fontSize.toStringAsFixed(0)} px · ${widget.filePath}',
            style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isThisProjectRunning = context.select<ExecutionProvider, bool>(
      (p) => p.isRunning && p.currentScriptName == widget.group.name,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canRun = widget.group.mainFilePath != null &&
        widget.group.mainFilePath!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            icon: Icon(_readOnly ? Icons.lock : Icons.lock_open, size: 20),
            onPressed: () => setState(() => _readOnly = !_readOnly),
            tooltip: _readOnly ? '只读模式' : '编辑模式',
          ),
          IconButton(
            icon: const Icon(Icons.search, size: 20),
            onPressed: () => _findController?.findMode(),
            tooltip: '搜索',
          ),
          if (_modified)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _save,
              tooltip: '保存',
            ),
          if (canRun)
            IconButton(
              icon: Icon(isThisProjectRunning ? Icons.stop : Icons.play_arrow),
              onPressed: isThisProjectRunning
                  ? () => context.read<ExecutionProvider>().stopExecution()
                  : _runProject,
              tooltip: isThisProjectRunning ? '停止' : '运行项目',
            ),
          IconButton(
            icon: const Icon(Icons.fullscreen),
            onPressed: () => Navigator.push(
              context,
              AppPageTransitions.fadeThrough(
                RunConsolePage(scriptName: widget.group.name),
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
                _buildCommandBar(isThisProjectRunning),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onScaleStart: _handleScaleStart,
                    onScaleUpdate: _handleScaleUpdate,
                    onScaleEnd: _handleScaleEnd,
                    child: CodeEditor(
                      controller: _controller,
                      findController: _findController,
                      toolbarController: _toolbarController,
                      readOnly: _readOnly,
                      showCursorWhenReadOnly: false,
                      style: CodeEditorStyle(
                        fontFamily: 'monospace',
                        fontSize: _fontSize,
                        codeTheme: CodeHighlightTheme(
                          languages: {
                            'python': CodeHighlightThemeMode(mode: langPython),
                          },
                          theme: isDark ? vs2015Theme : vsTheme,
                        ),
                      ),
                      wordWrap: false,
                      indicatorBuilder: (
                        context,
                        editingController,
                        chunkController,
                        notifier,
                      ) {
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
                ),
                _buildEditorStatusBar(),
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
