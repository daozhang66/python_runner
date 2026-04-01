import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/python.dart';
import '../providers/script_provider.dart';
import '../providers/execution_provider.dart';
import '../widgets/log_viewer.dart';
import '../widgets/scene_view.dart';
import 'run_console_page.dart';

class ScriptEditorPage extends StatefulWidget {
  final String scriptName;
  const ScriptEditorPage({super.key, required this.scriptName});

  @override
  State<ScriptEditorPage> createState() => _ScriptEditorPageState();
}

class _ScriptEditorPageState extends State<ScriptEditorPage> {
  late CodeController _codeController;
  final _stdinController = TextEditingController();
  final _undoController = UndoHistoryController();
  final _stdinFocusNode = FocusNode();
  bool _loading = false;
  bool _modified = false;
  bool _readOnly = true;
  bool _outputExpanded = false;
  bool _outputFullscreen = false;
  double _outputRatio = 0.50;
  Size? _lastSentCanvasSize;
  bool _searchVisible = false;
  String _searchQuery = '';
  int _searchMatchIndex = 0;
  List<int> _searchMatches = [];
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _codeFocusNode = FocusNode();
  final _codeFieldKey = GlobalKey();
  double _fontSize = 14.0;

  static const _minFontSize = 10.0;
  static const _maxFontSize = 28.0;
  // The gutter icons (fold toggle, error) are hardcoded at 16px in
  // flutter_code_editor.  We must ensure each code line is at least that tall
  // so the gutter Table rows and the TextField lines stay aligned.
  static const _gutterIconSize = 16.0;

  String get _displayName => widget.scriptName.replaceAll('.py', '');

  /// Compute a stable line-height multiplier so that:
  ///   fontSize * height  >=  _gutterIconSize  (16px)
  /// At large sizes we clamp to 1.3 for comfortable reading.
  double get _lineHeight {
    final minHeight = (_gutterIconSize + 1) / _fontSize; // +1 for rounding safety
    return minHeight.clamp(1.3, 1.8);
  }

  @override
  void initState() {
    super.initState();
    _codeController = CodeController(language: python);
    _loadContent();
    // No longer auto-stop: user may return from RunConsolePage while script runs
  }

  Future<void> _loadContent() async {
    final prefs = await SharedPreferences.getInstance();
    final content = await context.read<ScriptProvider>().readScript(widget.scriptName);
    _codeController.text = content;
    _codeController.addListener(_onTextChanged);
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
    if (_searchQuery.isNotEmpty) _updateSearchMatches();
  }

  /// [queryChanged] – the user typed a new search term → reset index to 0, don't jump
  /// [jump]         – the user pressed Enter → keep current index & jump
  /// Both false     – code text changed → just update match list, don't jump
  void _updateSearchMatches({bool queryChanged = false, bool jump = false}) {
    final text = _codeController.text;
    final q = _searchQuery.toLowerCase();
    final matches = <int>[];
    if (q.isNotEmpty) {
      int idx = 0;
      while (true) {
        final found = text.toLowerCase().indexOf(q, idx);
        if (found == -1) break;
        matches.add(found);
        idx = found + 1;
      }
    }
    setState(() {
      _searchMatches = matches;
      if (queryChanged) {
        _searchMatchIndex = 0;
      } else {
        _searchMatchIndex = matches.isEmpty ? 0 : _searchMatchIndex.clamp(0, matches.length - 1);
      }
    });
    if (matches.isNotEmpty && (jump || queryChanged)) {
      _jumpToMatch(_searchMatchIndex);
    }
  }

  void _searchNext() {
    if (_searchMatches.isEmpty) return;
    setState(() => _searchMatchIndex = (_searchMatchIndex + 1) % _searchMatches.length);
    _jumpToMatch(_searchMatchIndex);
  }

  void _searchPrev() {
    if (_searchMatches.isEmpty) return;
    setState(() => _searchMatchIndex =
        (_searchMatchIndex - 1 + _searchMatches.length) % _searchMatches.length);
    _jumpToMatch(_searchMatchIndex);
  }

  void _jumpToMatch(int index) {
    if (_searchMatches.isEmpty || _searchQuery.isEmpty) return;
    final pos = _searchMatches[index];
    _codeController.selection = TextSelection(
      baseOffset: pos,
      extentOffset: pos + _searchQuery.length,
    );
    _codeFocusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final editableState = _findEditableTextState();
      editableState?.bringIntoView(TextPosition(offset: pos));
    });
  }

  /// Walk down from the CodeField's GlobalKey to locate the inner
  /// [EditableTextState].  This is more reliable than using
  /// `_codeFocusNode.context.findAncestorStateOfType` because
  /// CodeField wraps the real TextField several layers deep.
  EditableTextState? _findEditableTextState() {
    final ctx = _codeFieldKey.currentContext;
    if (ctx == null) return null;
    EditableTextState? result;
    void visitor(Element element) {
      if (result != null) return;
      if (element is StatefulElement && element.state is EditableTextState) {
        result = element.state as EditableTextState;
        return;
      }
      element.visitChildren(visitor);
    }
    ctx.visitChildElements(visitor);
    return result;
  }

  void _insertIndent() {
    final ctrl = _codeController;
    final sel = ctrl.selection;
    if (!sel.isValid) return;
    const indent = '    ';
    final text = ctrl.text;
    final newText = text.replaceRange(sel.start, sel.end, indent);
    ctrl.value = ctrl.value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: sel.start + indent.length),
    );
    if (!_modified) setState(() => _modified = true);
  }

  void _removeIndent() {
    final ctrl = _codeController;
    final sel = ctrl.selection;
    if (!sel.isValid) return;
    final text = ctrl.text;
    final lineStart = text.lastIndexOf('\n', sel.start - 1) + 1;
    final linePrefix = text.substring(lineStart, sel.start);
    if (linePrefix.endsWith('    ')) {
      final newText = text.replaceRange(lineStart, lineStart + 4, '');
      ctrl.value = ctrl.value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: sel.start - 4),
      );
    } else if (linePrefix.endsWith(' ')) {
      final spaces = linePrefix.length - linePrefix.trimLeft().length;
      final remove = spaces % 4 == 0 ? 4 : spaces % 4;
      final newText = text.replaceRange(lineStart, lineStart + remove, '');
      ctrl.value = ctrl.value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: sel.start - remove),
      );
    }
    if (!_modified) setState(() => _modified = true);
  }

  Future<void> _save() async {
    final success = await context.read<ScriptProvider>().saveScript(
        widget.scriptName, _codeController.fullText);
    if (success && mounted) {
      setState(() => _modified = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存'), duration: Duration(seconds: 1)));
    }
  }

  Future<bool> _saveSilently() async {
    final success = await context.read<ScriptProvider>().saveScript(
        widget.scriptName, _codeController.fullText);
    if (success && mounted) setState(() => _modified = false);
    return success;
  }

  void _submitStdin(ExecutionProvider execProvider) {
    final input = _stdinController.text;
    _stdinController.clear();
    execProvider.sendStdin(input);
  }

  Future<void> _run() async {
    try {
      if (_modified) { final saved = await _saveSilently(); if (!saved || !mounted) return; }
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

  Widget _buildSearchBar() {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              autofocus: true,
              enableSuggestions: false,
              autocorrect: false,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: '输入后回车搜索...',
                border: InputBorder.none, isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              ),
              onSubmitted: (v) {
                _searchQuery = v;
                _updateSearchMatches(queryChanged: true);
              },
            ),
          ),
          Text(_searchMatches.isEmpty ? '无结果' : '${_searchMatchIndex + 1}/${_searchMatches.length}',
              style: const TextStyle(fontSize: 12)),
          IconButton(icon: const Icon(Icons.arrow_upward, size: 16),
              onPressed: _searchPrev, visualDensity: VisualDensity.compact),
          IconButton(icon: const Icon(Icons.arrow_downward, size: 16),
              onPressed: _searchNext, visualDensity: VisualDensity.compact),
          IconButton(icon: const Icon(Icons.close, size: 16),
              onPressed: () {
                _searchController.clear();
                // Collapse selection at current position to remove highlight
                // without jumping to a different location
                final curPos = _codeController.selection.baseOffset
                    .clamp(0, _codeController.text.length);
                _codeController.selection = TextSelection.collapsed(offset: curPos);
                setState(() { _searchVisible = false; _searchQuery = ''; _searchMatches = []; });
              }, visualDensity: VisualDensity.compact),
        ],
      ),
    );
  }

  Widget _buildIndentBar() {
    if (_readOnly) return const SizedBox.shrink();
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      height: 36,
      child: Row(
        children: [
          const SizedBox(width: 8),
          _IndentBtn(label: '⇥ 缩进', onTap: _insertIndent),
          const SizedBox(width: 4),
          _IndentBtn(label: '⇤ 取消缩进', onTap: _removeIndent),
          const SizedBox(width: 4),
          ValueListenableBuilder<UndoHistoryValue>(
            valueListenable: _undoController,
            builder: (context, value, _) => Row(children: [
              _IndentBtn(label: '↩ 撤回',
                  onTap: value.canUndo ? () => _undoController.undo() : () {}),
              const SizedBox(width: 4),
              _IndentBtn(label: '↪ 重做',
                  onTap: value.canRedo ? () => _undoController.redo() : () {}),
            ]),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final execProvider = context.watch<ExecutionProvider>();
    final isThisRunning = execProvider.isRunning &&
        execProvider.currentScriptName == widget.scriptName;

    // Auto-expand and fullscreen when scene becomes active
    if (execProvider.sceneActive && !_outputExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() { _outputExpanded = true; _outputFullscreen = true; });
      });
    }

    // When waiting for input, move focus from code editor to stdin field
    if (execProvider.waitingForInput && _codeFocusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _stdinFocusNode.canRequestFocus) {
          _stdinFocusNode.requestFocus();
        }
      });
    }

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
            onPressed: () => setState(() => _searchVisible = !_searchVisible),
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
                        onPressed: _fontSize > _minFontSize ? () {
                          _changeFontSize(-2);
                          setLocal(() {});
                        } : null,
                      ),
                      Text('${_fontSize.toInt()}px',
                          style: const TextStyle(fontSize: 14)),
                      IconButton(
                        icon: const Icon(Icons.text_increase),
                        onPressed: _fontSize < _maxFontSize ? () {
                          _changeFontSize(2);
                          setLocal(() {});
                        } : null,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_modified)
            IconButton(icon: const Icon(Icons.save), onPressed: _save, tooltip: '保存'),
          IconButton(
            icon: Icon(isThisRunning ? Icons.stop : Icons.play_arrow),
            onPressed: isThisRunning
                ? () => context.read<ExecutionProvider>().stopExecution() : _run,
            tooltip: isThisRunning ? '停止' : '运行',
          ),
          IconButton(
            icon: const Icon(Icons.terminal),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RunConsolePage(scriptName: widget.scriptName),
              ),
            ),
            tooltip: '全屏终端',
          ),
          IconButton(
            icon: Icon(_outputExpanded ? Icons.vertical_align_bottom : Icons.code),
            onPressed: () => setState(() => _outputExpanded = !_outputExpanded),
            tooltip: _outputExpanded ? '隐藏输出' : '显示输出',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_searchVisible) _buildSearchBar(),
                _buildIndentBar(),
                if (!_outputFullscreen)
                  Expanded(
                    flex: _outputExpanded ? ((1 - _outputRatio) * 100).round() : 1,
                    child: CodeTheme(
                      data: CodeThemeData(styles: _editorTheme(context)),
                      child: _readOnly
                        ? CodeField(
                            key: _codeFieldKey,
                            controller: _codeController,
                            focusNode: _codeFocusNode,
                            readOnly: true,
                            textStyle: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: _fontSize,
                              height: _lineHeight,
                            ),
                            gutterStyle: const GutterStyle(
                              showFoldingHandles: false,
                            ),
                            expands: true,
                            wrap: false)
                        : CodeField(
                            key: _codeFieldKey,
                            controller: _codeController,
                            focusNode: _codeFocusNode,
                            undoController: _undoController,
                            textStyle: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: _fontSize,
                              height: _lineHeight,
                            ),
                            gutterStyle: const GutterStyle(
                              showFoldingHandles: false,
                            ),
                            expands: true,
                            wrap: false),
                    ),
                  ),
                if (_outputExpanded) ...[
                  GestureDetector(
                    onVerticalDragUpdate: _outputFullscreen ? null : (details) {
                      final renderBox = context.findRenderObject() as RenderBox;
                      final totalHeight = renderBox.size.height;
                      setState(() {
                        _outputRatio = (_outputRatio - details.delta.dy / totalHeight).clamp(0.15, 0.85);
                      });
                    },
                    child: Container(
                      height: 28,
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Row(
                        children: [
                          const SizedBox(width: 16),
                          Icon(isThisRunning ? Icons.circle : Icons.circle_outlined,
                              size: 10, color: isThisRunning ? Colors.green
                                  : Theme.of(context).colorScheme.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Text('输出', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          const Spacer(),
                          if (!_outputFullscreen) const Icon(Icons.drag_handle, size: 16),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => setState(() => _outputFullscreen = !_outputFullscreen),
                            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Icon(_outputFullscreen ? Icons.fullscreen_exit : Icons.fullscreen, size: 16))),
                          InkWell(
                            onTap: () => execProvider.clearLogs(),
                            child: const Padding(padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Icon(Icons.delete_outline, size: 16))),
                          InkWell(
                            onTap: () => setState(() { _outputExpanded = false; _outputFullscreen = false; }),
                            child: const Padding(padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Icon(Icons.close, size: 16))),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    flex: _outputFullscreen ? 1 : (_outputRatio * 100).round(),
                    child: execProvider.sceneActive
                        ? _buildSceneOutput(execProvider)
                        : Column(children: [
                      Expanded(child: LogViewer(
                          logs: execProvider.logs,
                          showCopyAll: execProvider.logs.isNotEmpty)),
                      if (execProvider.waitingForInput)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          child: Row(children: [
                            Icon(Icons.chevron_right, size: 18,
                                color: Theme.of(context).colorScheme.primary),
                            Expanded(child: TextField(
                              controller: _stdinController,
                              focusNode: _stdinFocusNode,
                              autofocus: true,
                              enableSuggestions: false,
                              autocorrect: false,
                              enableIMEPersonalizedLearning: false,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                              decoration: const InputDecoration(
                                hintText: '输入内容...', border: InputBorder.none, isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
                              onSubmitted: (_) => _submitStdin(execProvider))),
                            IconButton(icon: const Icon(Icons.send, size: 18),
                                onPressed: () => _submitStdin(execProvider),
                                visualDensity: VisualDensity.compact),
                          ]),
                        ),
                    ]),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildSceneOutput(ExecutionProvider execProvider) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);

        // Send canvas size to Python on first frame or size change
        if (_lastSentCanvasSize != canvasSize) {
          _lastSentCanvasSize = canvasSize;
          execProvider.sendSceneTouch(jsonEncode({
            'type': 'size',
            'w': canvasSize.width,
            'h': canvasSize.height,
          }));
        }

        final frame = execProvider.currentSceneFrame;
        if (frame == null) {
          return Container(
            color: Colors.black,
            child: const Center(
              child: Text('Scene loading...',
                  style: TextStyle(color: Colors.white54)),
            ),
          );
        }

        return Container(
          color: Colors.black,
          child: SceneView(
            frameCommands: frame,
            canvasSize: canvasSize,
            onTouch: (touchJson) => execProvider.sendSceneTouch(touchJson),
          ),
        );
      },
    );
  }

  Map<String, TextStyle> _editorTheme(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      return {
        'root': const TextStyle(color: Color(0xFFD4D4D4), backgroundColor: Color(0xFF1E1E1E)),
        'keyword': const TextStyle(color: Color(0xFF569CD6)),
        'string': const TextStyle(color: Color(0xFFCE9178)),
        'number': const TextStyle(color: Color(0xFFB5CEA8)),
        'comment': const TextStyle(color: Color(0xFF6A9955)),
        'built_in': const TextStyle(color: Color(0xFFDCDCAA)),
        'function': const TextStyle(color: Color(0xFFDCDCAA)),
        'class': const TextStyle(color: Color(0xFF4EC9B0)),
        'params': const TextStyle(color: Color(0xFF9CDCFE)),
      };
    }
    return {
      'root': const TextStyle(color: Color(0xFF000000), backgroundColor: Color(0xFFFFFFFF)),
      'keyword': const TextStyle(color: Color(0xFF0000FF)),
      'string': const TextStyle(color: Color(0xFFA31515)),
      'number': const TextStyle(color: Color(0xFF098658)),
      'comment': const TextStyle(color: Color(0xFF008000)),
      'built_in': const TextStyle(color: Color(0xFF795E26)),
      'function': const TextStyle(color: Color(0xFF795E26)),
      'class': const TextStyle(color: Color(0xFF267F99)),
      'params': const TextStyle(color: Color(0xFF001080)),
    };
  }

  @override
  void dispose() {
    _codeController.removeListener(_onTextChanged);
    _codeController.dispose();
    _stdinController.dispose();
    _stdinFocusNode.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _undoController.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }
}

class _IndentBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _IndentBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.4)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
      ),
    );
  }
}
