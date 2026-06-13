import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/log_entry.dart';
import '../utils/ansi_parser.dart';

enum TerminalColorMode { dark, light, system, monochrome }

extension on TerminalColorMode {
  String get label {
    switch (this) {
      case TerminalColorMode.dark:
        return '深色终端';
      case TerminalColorMode.light:
        return '浅色终端';
      case TerminalColorMode.system:
        return '跟随系统';
      case TerminalColorMode.monochrome:
        return '黑白输出';
    }
  }

  IconData get icon {
    switch (this) {
      case TerminalColorMode.dark:
        return Icons.dark_mode_outlined;
      case TerminalColorMode.light:
        return Icons.light_mode_outlined;
      case TerminalColorMode.system:
        return Icons.contrast_outlined;
      case TerminalColorMode.monochrome:
        return Icons.format_color_reset_outlined;
    }
  }
}

/// Unified terminal widget. Log lines stay virtualized for large output, while
/// SelectionArea owns text selection so dragging can cross visible lines.
/// Toolbar provides copy-all; scrolling works on the whole output area.
class TerminalView extends StatefulWidget {
  final List<LogEntry> logs;
  final bool isRunning;
  final bool waitingForInput;
  final ValueChanged<String>? onStdin;
  final VoidCallback? onClear;
  final String? emptyMessage;
  final IconData? emptyIcon;
  final bool showLineNumberToggle;
  final int logVersion;

  const TerminalView({
    super.key,
    required this.logs,
    this.isRunning = false,
    this.waitingForInput = false,
    this.onStdin,
    this.onClear,
    this.emptyMessage,
    this.emptyIcon,
    this.showLineNumberToggle = true,
    this.logVersion = 0,
  });

  @override
  State<TerminalView> createState() => TerminalViewState();
}

class TerminalViewState extends State<TerminalView> {
  final _scrollController = ScrollController();
  final _stdinController = TextEditingController();
  final _stdinFocusNode = FocusNode();
  bool _autoScroll = true;
  double _fontSize = 10.0;
  double? _scaleStartFontSize;
  bool _showLineNumbers = false;
  bool _searchVisible = false;
  String _searchQuery = '';
  bool _filterErrors = false;
  TerminalColorMode _colorMode = TerminalColorMode.dark;
  final _searchController = TextEditingController();
  final Map<int, Offset> _scalePointers = {};
  double? _pointerScaleStartDistance;

  static const double _fontSizeMin = 6.0;
  static const double _fontSizeMax = 32.0;
  static const String _fontSizePrefsKey = 'terminal_font_size';
  static const String _colorModePrefsKey = 'terminal_color_mode';
  static const int _maxAnsiCacheEntries = 6000;

  final LinkedHashMap<String, List<TextSpan>> _ansiCache =
      LinkedHashMap<String, List<TextSpan>>();
  int _lastLogCount = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFontSize();
    _loadColorMode();
  }

  Future<void> _loadFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_fontSizePrefsKey);
    if (!mounted || saved == null) return;
    setState(() {
      _fontSize = saved.clamp(_fontSizeMin, _fontSizeMax).toDouble();
    });
  }

  Future<void> _persistFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizePrefsKey, _fontSize);
  }

  Future<void> _loadColorMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_colorModePrefsKey);
    if (!mounted) return;
    if (saved == null) {
      await prefs.setString(_colorModePrefsKey, TerminalColorMode.dark.name);
      return;
    }
    final mode = TerminalColorMode.values.cast<TerminalColorMode?>().firstWhere(
          (item) => item?.name == saved,
          orElse: () => null,
        );
    if (mode == null) return;
    setState(() => _colorMode = mode);
  }

  Future<void> _setColorMode(TerminalColorMode mode) async {
    if (_colorMode == mode) return;
    setState(() {
      _colorMode = mode;
      _ansiCache.clear();
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_colorModePrefsKey, mode.name);
  }

  double? _currentPointerDistance() {
    if (_scalePointers.length < 2) return null;
    final positions = _scalePointers.values.take(2).toList(growable: false);
    return (positions[0] - positions[1]).distance;
  }

  void _handlePointerDown(PointerDownEvent event) {
    _scalePointers[event.pointer] = event.localPosition;
    if (_scalePointers.length == 2) {
      _scaleStartFontSize = _fontSize;
      _pointerScaleStartDistance = _currentPointerDistance();
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_scalePointers.containsKey(event.pointer)) return;
    _scalePointers[event.pointer] = event.localPosition;
    final startSize = _scaleStartFontSize;
    final startDistance = _pointerScaleStartDistance;
    final currentDistance = _currentPointerDistance();
    if (startSize == null ||
        startDistance == null ||
        currentDistance == null ||
        startDistance <= 0) {
      return;
    }
    final nextSize = (startSize * currentDistance / startDistance)
        .clamp(_fontSizeMin, _fontSizeMax)
        .toDouble();
    if ((nextSize - _fontSize).abs() < 0.1) return;
    setState(() => _fontSize = nextSize);
  }

  void _finishPointerScale() {
    if (_scaleStartFontSize != null) {
      _scaleStartFontSize = null;
      _pointerScaleStartDistance = null;
      unawaited(_persistFontSize());
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    _scalePointers.remove(event.pointer);
    if (_scalePointers.length < 2) _finishPointerScale();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _scalePointers.remove(event.pointer);
    if (_scalePointers.length < 2) _finishPointerScale();
  }

  @override
  void didUpdateWidget(covariant TerminalView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.logs.isEmpty && _ansiCache.isNotEmpty) _ansiCache.clear();
    if (_autoScroll &&
        (widget.logs.length > _lastLogCount ||
            widget.logVersion != oldWidget.logVersion)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
    _lastLogCount = widget.logs.length;
    if (widget.waitingForInput) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _stdinFocusNode.canRequestFocus &&
            !_stdinFocusNode.hasFocus) {
          _stdinFocusNode.requestFocus();
        }
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final atBottom = pos.pixels >= pos.maxScrollExtent - 60;
    if (_autoScroll != atBottom) setState(() => _autoScroll = atBottom);
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (_autoScroll) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  void forceAutoScroll() {
    _autoScroll = true;
    _scrollToBottom();
  }

  void _submitStdin() {
    if (widget.onStdin == null) return;
    final input = _stdinController.text;
    _stdinController.clear();
    widget.onStdin!(input);
    _autoScroll = true;
    _scrollToBottom();
    if (mounted && _stdinFocusNode.canRequestFocus) {
      _stdinFocusNode.requestFocus();
    }
  }

  // --- Colors ---

  Color _logColor(LogType type, ColorScheme colors) {
    switch (type) {
      case LogType.stderr:
      case LogType.error:
        return colors.error;
      case LogType.info:
        return colors.primary;
      case LogType.stdout:
        final isDark = _terminalBrightness() == Brightness.dark;
        return isDark ? const Color(0xFFE6EDF3) : colors.onSurface;
    }
  }

  Brightness _terminalBrightness() {
    switch (_colorMode) {
      case TerminalColorMode.dark:
      case TerminalColorMode.monochrome:
        return Brightness.dark;
      case TerminalColorMode.light:
        return Brightness.light;
      case TerminalColorMode.system:
        return Theme.of(context).brightness;
    }
  }

  AnsiPalette _ansiPalette() {
    if (_colorMode == TerminalColorMode.monochrome) {
      return AnsiPalette.monochrome;
    }
    return _terminalBrightness() == Brightness.dark
        ? AnsiPalette.dark
        : AnsiPalette.light;
  }

  List<TextSpan> _getSpans(LogEntry log, Color defaultColor) {
    final palette = _ansiPalette();
    final key =
        '${log.type.name}|${defaultColor.toARGB32()}|${palette.name}|${log.content}';
    final cached = _ansiCache.remove(key);
    if (cached != null) {
      _ansiCache[key] = cached;
      return cached;
    }

    final parsed = AnsiParser.parse(
      log.content,
      defaultColor: defaultColor,
      palette: palette,
    );
    _ansiCache[key] = parsed;
    if (_ansiCache.length > _maxAnsiCacheEntries) {
      _ansiCache.remove(_ansiCache.keys.first);
    }
    return parsed;
  }

  List<LogEntry> _filteredLogs() {
    var result = widget.logs;
    if (_filterErrors) {
      result = result
          .where((l) => l.type == LogType.stderr || l.type == LogType.error)
          .toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result =
          result.where((l) => l.content.toLowerCase().contains(q)).toList();
    }
    return result;
  }

  TextSpan _buildLineSpan(
    LogEntry log,
    int index,
    ColorScheme colors,
  ) {
    final color = _logColor(log.type, colors);
    final spans = <InlineSpan>[];

    if (_showLineNumbers) {
      spans.add(TextSpan(
        text: '${'${index + 1}'.padLeft(4)}  ',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: _fontSize * 0.85,
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white24
              : Colors.black26,
        ),
      ));
    }

    for (final span in _getSpans(log, color)) {
      spans.add(TextSpan(
        text: span.text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: _fontSize,
          height: 1.5,
          color: span.style?.color ?? color,
          backgroundColor: span.style?.backgroundColor,
          fontWeight: span.style?.fontWeight,
        ),
      ));
    }

    return TextSpan(children: spans);
  }

  void _copyAll() {
    final text = widget.logs.map((e) => AnsiParser.strip(e.content)).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    _showToast('已复制全部 ${widget.logs.length} 行');
  }

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 1)),
    );
  }

  Widget _buildTerminalToolbar(
    ColorScheme colors,
    Color barColor,
    List<LogEntry> logs,
  ) {
    final isDark = _terminalBrightness() == Brightness.dark;
    final toolbarText = isDark ? const Color(0xFFC9D1D9) : colors.onSurface;
    final toolbarMuted =
        isDark ? const Color(0xFF8B949E) : colors.onSurfaceVariant;
    final toolbarActive = isDark ? const Color(0xFF79C0FF) : colors.primary;
    final toolbarError = isDark ? const Color(0xFFF85149) : colors.error;
    final toolbarBorder = isDark
        ? const Color(0xFF30363D)
        : colors.outlineVariant.withValues(alpha: 0.3);
    final copyButtonBg = isDark
        ? const Color(0xFF21262D)
        : colors.primaryContainer.withValues(alpha: 0.4);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: barColor,
        border: Border(
          bottom: BorderSide(color: toolbarBorder),
        ),
      ),
      child: Row(
        children: [
          if (widget.showLineNumberToggle)
            IconButton(
              icon: Icon(Icons.format_list_numbered,
                  size: 18,
                  color: _showLineNumbers ? toolbarActive : toolbarMuted),
              visualDensity: VisualDensity.compact,
              onPressed: () =>
                  setState(() => _showLineNumbers = !_showLineNumbers),
              tooltip: _showLineNumbers ? '隐藏行号' : '显示行号',
            ),
          IconButton(
            icon: Icon(Icons.search,
                size: 18,
                color: _searchVisible || _filterErrors
                    ? toolbarActive
                    : toolbarMuted),
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() {
              _searchVisible = !_searchVisible;
              if (!_searchVisible) {
                _searchQuery = '';
                _searchController.clear();
              }
            }),
            tooltip: '搜索',
          ),
          if (_filterErrors)
            IconButton(
              icon: Icon(Icons.error_outline, size: 18, color: toolbarError),
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _filterErrors = false),
              tooltip: '显示全部',
            ),
          PopupMenuButton<TerminalColorMode>(
            tooltip: '终端主题',
            icon: Icon(_colorMode.icon, size: 18, color: toolbarMuted),
            onSelected: _setColorMode,
            itemBuilder: (context) => TerminalColorMode.values
                .map(
                  (mode) => PopupMenuItem<TerminalColorMode>(
                    value: mode,
                    child: Row(
                      children: [
                        Icon(mode.icon,
                            size: 18,
                            color: mode == _colorMode
                                ? colors.primary
                                : colors.onSurfaceVariant),
                        const SizedBox(width: 12),
                        Text(mode.label),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
          const Spacer(),
          if (logs.isNotEmpty)
            TextButton.icon(
              onPressed: _copyAll,
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('全部复制', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: toolbarText,
                iconColor: toolbarActive,
                backgroundColor: copyButtonBg,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          if (widget.onClear != null && logs.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_outline, size: 18, color: toolbarMuted),
              visualDensity: VisualDensity.compact,
              onPressed: widget.onClear,
              tooltip: '清空',
            ),
        ],
      ),
    );
  }

  Widget _buildStdinPrompt(ColorScheme colors) {
    final isDark = _terminalBrightness() == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 8),
      child: Text(
        '>',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 18,
          height: 1,
          fontWeight: FontWeight.w700,
          color: widget.waitingForInput
              ? colors.primary
              : (isDark ? const Color(0xFF8B949E) : colors.onSurfaceVariant),
        ),
      ),
    );
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = _terminalBrightness() == Brightness.dark;
    final logs = widget.logs;
    final displayLogs = _filteredLogs();
    final bgColor = isDark ? const Color(0xFF0D1117) : const Color(0xFFFAFAFA);
    final inputBarColor =
        isDark ? const Color(0xFF161B22) : const Color(0xFFF0F0F0);
    final inputFillColor =
        isDark ? const Color(0xFF0D1117) : const Color(0xFFFFFFFF);
    final inputTextColor = isDark ? const Color(0xFFE6EDF3) : colors.onSurface;
    final inputHintColor = isDark
        ? const Color(0xFF8B949E)
        : colors.onSurfaceVariant.withValues(alpha: 0.55);
    final inputBorderColor = widget.waitingForInput
        ? colors.primary.withValues(alpha: 0.72)
        : colors.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.55);
    final barColor =
        isDark ? const Color(0xFF161B22) : colors.surfaceContainerHighest;
    final toolbarTextColor =
        isDark ? const Color(0xFFC9D1D9) : colors.onSurface;
    final toolbarHintColor =
        isDark ? const Color(0xFF8B949E) : colors.onSurfaceVariant;
    final toolbarErrorColor = isDark ? const Color(0xFFF85149) : colors.error;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: Column(
        children: [
          _buildTerminalToolbar(colors, barColor, logs),

          // Search bar
          if (_searchVisible)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: barColor,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      style: TextStyle(fontSize: 13, color: toolbarTextColor),
                      cursorColor:
                          isDark ? const Color(0xFF79C0FF) : colors.primary,
                      decoration: InputDecoration(
                        hintText: '搜索日志...',
                        hintStyle: TextStyle(color: toolbarHintColor),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.error_outline,
                        size: 18,
                        color: _filterErrors
                            ? toolbarErrorColor
                            : toolbarHintColor),
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        setState(() => _filterErrors = !_filterErrors),
                    tooltip: _filterErrors ? '显示全部' : '仅看错误',
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: toolbarHintColor),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() {
                      _searchVisible = false;
                      _searchQuery = '';
                      _searchController.clear();
                    }),
                    tooltip: '关闭搜索',
                  ),
                ],
              ),
            ),

          // Terminal output. SelectionArea keeps drag selection from being
          // trapped inside one log row.
          Expanded(
            child: Container(
              color: bgColor,
              child: displayLogs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.emptyIcon ??
                                (widget.isRunning
                                    ? Icons.terminal
                                    : Icons.code_off),
                            size: 48,
                            color: isDark ? Colors.white12 : Colors.black12,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            (_searchQuery.isNotEmpty || _filterErrors)
                                ? '无匹配输出'
                                : (widget.emptyMessage ??
                                    (widget.isRunning ? '等待输出...' : '暂无输出')),
                            style: TextStyle(
                                color: isDark ? Colors.white24 : Colors.black26,
                                fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : SelectionArea(
                      child: Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                          itemCount: displayLogs.length,
                          itemBuilder: (context, index) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: Text.rich(
                              _buildLineSpan(displayLogs[index], index, colors),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),

          // Scroll-to-bottom hint
          if (!_autoScroll && displayLogs.isNotEmpty)
            GestureDetector(
              onTap: () {
                setState(() => _autoScroll = true);
                _scrollToBottom();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6),
                color: colors.primary.withValues(alpha: 0.2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.arrow_downward,
                        size: 14, color: colors.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text('有新输出，点击跳转到底部',
                        style: TextStyle(
                            color: colors.onSurfaceVariant, fontSize: 12)),
                  ],
                ),
              ),
            ),

          // Stdin input area
          if (widget.waitingForInput || widget.isRunning)
            Container(
              decoration: BoxDecoration(
                color: inputBarColor,
                border: Border(
                  top: BorderSide(
                    color: widget.waitingForInput
                        ? colors.primary.withValues(alpha: 0.6)
                        : colors.outlineVariant.withValues(alpha: 0.3),
                    width: widget.waitingForInput ? 2 : 1,
                  ),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    decoration: BoxDecoration(
                      color: inputFillColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: inputBorderColor, width: 1.1),
                    ),
                    child: Row(
                      children: [
                        _buildStdinPrompt(colors),
                        Expanded(
                          child: TextField(
                            controller: _stdinController,
                            focusNode: _stdinFocusNode,
                            enabled: widget.waitingForInput,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 14,
                              color: inputTextColor,
                            ),
                            cursorColor: colors.primary,
                            decoration: InputDecoration(
                              hintText: widget.waitingForInput
                                  ? '输入内容...'
                                  : '等待脚本请求输入...',
                              hintStyle: TextStyle(
                                color: inputHintColor,
                                fontSize: 13,
                              ),
                              filled: false,
                              fillColor: Colors.transparent,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 0, vertical: 13),
                            ),
                            onSubmitted: widget.waitingForInput
                                ? (_) => _submitStdin()
                                : null,
                          ),
                        ),
                        if (widget.waitingForInput)
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _submitStdin,
                              borderRadius: BorderRadius.circular(10),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Icon(Icons.send_rounded,
                                    size: 20, color: colors.primary),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _stdinController.dispose();
    _stdinFocusNode.dispose();
    _searchController.dispose();
    _ansiCache.clear();
    super.dispose();
  }
}
