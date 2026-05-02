import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/log_entry.dart';
import '../utils/ansi_parser.dart';

/// Unified terminal widget — all log lines rendered as ONE SelectableText
/// so the user can freely drag-select across multiple lines.
/// Long-press any line for a context menu with range-copy options.
class TerminalView extends StatefulWidget {
  final List<LogEntry> logs;
  final bool isRunning;
  final bool waitingForInput;
  final ValueChanged<String>? onStdin;
  final VoidCallback? onClear;
  final String? emptyMessage;
  final IconData? emptyIcon;
  final bool showLineNumberToggle;

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
  });

  @override
  State<TerminalView> createState() => TerminalViewState();
}

class TerminalViewState extends State<TerminalView> {
  final _scrollController = ScrollController();
  final _stdinController = TextEditingController();
  final _stdinFocusNode = FocusNode();
  bool _autoScroll = true;
  double _fontSize = 13.0;
  bool _showLineNumbers = false;
  bool _searchVisible = false;
  String _searchQuery = '';
  bool _filterErrors = false;
  final _searchController = TextEditingController();

  static const double _fontSizeMin = 9.0;
  static const double _fontSizeMax = 22.0;
  static const double _fontSizeStep = 1.0;

  final Map<int, List<TextSpan>> _ansiCache = {};
  int _lastLogCount = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant TerminalView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.logs.isEmpty && _ansiCache.isNotEmpty) _ansiCache.clear();
    if (_autoScroll && widget.logs.length > _lastLogCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
    _lastLogCount = widget.logs.length;
    if (widget.waitingForInput) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _stdinFocusNode.canRequestFocus && !_stdinFocusNode.hasFocus) {
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
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  void forceAutoScroll() { _autoScroll = true; _scrollToBottom(); }

  void _submitStdin() {
    if (widget.onStdin == null) return;
    final input = _stdinController.text;
    _stdinController.clear();
    widget.onStdin!(input);
    _autoScroll = true;
    _scrollToBottom();
    if (mounted && _stdinFocusNode.canRequestFocus) _stdinFocusNode.requestFocus();
  }

  // ── Colors ──

  Color _logColor(LogType type, ColorScheme colors) {
    switch (type) {
      case LogType.stderr:
      case LogType.error:
        return colors.error;
      case LogType.info:
        return colors.primary;
      case LogType.stdout:
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return isDark ? const Color(0xFFE6EDF3) : colors.onSurface;
    }
  }

  List<TextSpan> _getSpans(LogEntry log, Color defaultColor) {
    final key = log.content.hashCode ^ defaultColor.hashCode;
    return _ansiCache.putIfAbsent(
        key, () => AnsiParser.parse(log.content, defaultColor: defaultColor));
  }

  List<LogEntry> _filteredLogs() {
    var result = widget.logs;
    if (_filterErrors) {
      result = result.where((l) => l.type == LogType.stderr || l.type == LogType.error).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((l) => l.content.toLowerCase().contains(q)).toList();
    }
    return result;
  }

  // ── Build the single SelectableText with all lines ──

  /// Build one big TextSpan tree: each log line is a group of spans
  /// followed by a `\n`. This lets the user drag-select across lines.
  List<TextSpan> _buildAllSpans(ColorScheme colors) {
    final all = <TextSpan>[];
    final filteredLogs = _filteredLogs();
    for (int i = 0; i < filteredLogs.length; i++) {
      final log = filteredLogs[i];
      final color = _logColor(log.type, colors);

      // Optional line number prefix
      if (_showLineNumbers) {
        all.add(TextSpan(
          text: '${i + 1}'.padLeft(4) + '  ',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: _fontSize * 0.85,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white24
                : Colors.black26,
          ),
        ));
      }

      // The actual log content (with ANSI colors)
      final spans = _getSpans(log, color);
      // Wrap each span to inherit the base font size
      for (final span in spans) {
        all.add(TextSpan(
          text: span.text,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: _fontSize,
            height: 1.5,
            color: span.style?.color ?? color,
            fontWeight: span.style?.fontWeight,
          ),
        ));
      }

      // Newline between lines (but not after the last one)
      if (i < widget.logs.length - 1) {
        all.add(TextSpan(text: '\n', style: TextStyle(fontSize: _fontSize, height: 1.5)));
      }
    }
    return all;
  }

  void _copyAll() {
    final text = widget.logs.map((e) => AnsiParser.strip(e.content)).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    _showToast('已复制全部 ${widget.logs.length} 行');
  }

  void _copyRange(int from, int to) {
    final lo = from < to ? from : to;
    final hi = from < to ? to : from;
    final text = widget.logs
        .getRange(lo, hi + 1)
        .map((e) => AnsiParser.strip(e.content))
        .join('\n');
    Clipboard.setData(ClipboardData(text: text));
    _showToast('已复制第 ${lo + 1}-${hi + 1} 行 (${hi - lo + 1} 行)');
  }

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 1)),
    );
  }

  // ── Long-press menu ──

  void _showLineMenu(int index) {
    final log = widget.logs[index];
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(width: 36, height: 4,
                decoration: BoxDecoration(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (log.content.length > 60)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  AnsiParser.strip(log.content).substring(0, 60) + '...',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: colors.onSurfaceVariant),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.copy, size: 20),
              title: const Text('复制该行'),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: AnsiParser.strip(log.content)));
                _showToast('已复制第 ${index + 1} 行');
              },
            ),
            if (index > 0)
              ListTile(
                dense: true,
                leading: const Icon(Icons.content_copy, size: 20),
                title: Text('复制第 1-${index + 1} 行'),
                onTap: () { Navigator.pop(ctx); _copyRange(0, index); },
              ),
            if (index < widget.logs.length - 1)
              ListTile(
                dense: true,
                leading: const Icon(Icons.content_copy, size: 20),
                title: Text('复制第 ${index + 1}-${widget.logs.length} 行'),
                onTap: () { Navigator.pop(ctx); _copyRange(index, widget.logs.length - 1); },
              ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.select_all, size: 20),
              title: Text('复制全部 (${widget.logs.length} 行)'),
              onTap: () { Navigator.pop(ctx); _copyAll(); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  bool _looksLikeJson(String text) {
    final s = AnsiParser.strip(text).trim();
    return (s.startsWith('{') && s.endsWith('}')) || (s.startsWith('[') && s.endsWith(']'));
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final logs = widget.logs;
    final displayLogs = _filteredLogs();
    final bgColor = isDark ? const Color(0xFF0D1117) : const Color(0xFFFAFAFA);
    final inputBarColor = isDark ? const Color(0xFF161B22) : const Color(0xFFF0F0F0);
    final barColor = isDark ? const Color(0xFF161B22) : colors.surfaceContainerHighest;

    return Column(
      children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: barColor,
            border: Border(bottom: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.3))),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.text_decrease_rounded, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: _fontSize <= _fontSizeMin
                    ? null
                    : () => setState(() => _fontSize = (_fontSize - _fontSizeStep).clamp(_fontSizeMin, _fontSizeMax)),
                tooltip: '缩小字体',
              ),
              Text('${_fontSize.toInt()}', style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
              IconButton(
                icon: const Icon(Icons.text_increase_rounded, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: _fontSize >= _fontSizeMax
                    ? null
                    : () => setState(() => _fontSize = (_fontSize + _fontSizeStep).clamp(_fontSizeMin, _fontSizeMax)),
                tooltip: '放大字体',
              ),
              if (widget.showLineNumberToggle)
                IconButton(
                  icon: Icon(Icons.format_list_numbered,
                      size: 18, color: _showLineNumbers ? colors.primary : colors.onSurfaceVariant),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _showLineNumbers = !_showLineNumbers),
                  tooltip: _showLineNumbers ? '隐藏行号' : '显示行号',
                ),
              IconButton(
                icon: Icon(Icons.search, size: 18,
                    color: _searchVisible || _filterErrors ? colors.primary : colors.onSurfaceVariant),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() {
                  _searchVisible = !_searchVisible;
                  if (!_searchVisible) { _searchQuery = ''; _searchController.clear(); }
                }),
                tooltip: '搜索',
              ),
              if (_filterErrors)
                IconButton(
                  icon: Icon(Icons.error_outline, size: 18, color: colors.error),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _filterErrors = false),
                  tooltip: '显示全部',
                ),
              const Spacer(),
              if (logs.isNotEmpty)
                TextButton.icon(
                  onPressed: _copyAll,
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('全部复制', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              if (widget.onClear != null && logs.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onClear,
                  tooltip: '清空',
                ),
            ],
          ),
        ),

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
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: '搜索日志内容...',
                      border: InputBorder.none, isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.error_outline, size: 18,
                      color: _filterErrors ? colors.error : colors.onSurfaceVariant),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _filterErrors = !_filterErrors),
                  tooltip: _filterErrors ? '显示全部' : '只看错误',
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() {
                    _searchVisible = false; _searchQuery = ''; _searchController.clear();
                  }),
                  tooltip: '关闭搜索',
                ),
              ],
            ),
          ),

        // Terminal output — single SelectableText for multi-line drag select
        Expanded(
          child: Container(
            color: bgColor,
            child: displayLogs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.emptyIcon ?? (widget.isRunning ? Icons.terminal : Icons.code_off),
                          size: 48,
                          color: isDark ? Colors.white12 : Colors.black12,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          (_searchQuery.isNotEmpty || _filterErrors)
                              ? '无匹配结果'
                              : (widget.emptyMessage ?? (widget.isRunning ? '等待输出...' : '暂无输出')),
                          style: TextStyle(color: isDark ? Colors.white24 : Colors.black26, fontSize: 14),
                        ),
                      ],
                    ),
                  )
                : Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: MediaQuery.sizeOf(context).width > 20
                                ? MediaQuery.sizeOf(context).width - 20
                                : MediaQuery.sizeOf(context).width,
                          ),
                          child: SelectableText.rich(
                            TextSpan(children: _buildAllSpans(colors)),
                            onSelectionChanged: (selection, cause) {},
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
            onTap: () { setState(() => _autoScroll = true); _scrollToBottom(); },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6),
              color: colors.primary.withValues(alpha: 0.2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.arrow_downward, size: 14, color: colors.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('新输出，点击回到底部',
                      style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
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
                padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: widget.waitingForInput
                            ? colors.primary.withValues(alpha: 0.15)
                            : colors.onSurface.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('>',
                        style: TextStyle(
                          fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.bold,
                          color: widget.waitingForInput
                              ? colors.primary
                              : colors.onSurface.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _stdinController,
                        focusNode: _stdinFocusNode,
                        enabled: widget.waitingForInput,
                        style: TextStyle(
                          fontFamily: 'monospace', fontSize: 14,
                          color: isDark ? Colors.white : colors.onSurface,
                        ),
                        cursorColor: colors.primary,
                        decoration: InputDecoration(
                          hintText: widget.waitingForInput ? '请输入...' : '等待脚本请求输入...',
                          hintStyle: TextStyle(
                            color: isDark ? Colors.white30 : colors.onSurfaceVariant.withValues(alpha: 0.4),
                            fontSize: 13,
                          ),
                          border: InputBorder.none, isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        ),
                        onSubmitted: widget.waitingForInput ? (_) => _submitStdin() : null,
                      ),
                    ),
                    if (widget.waitingForInput)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _submitStdin,
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Icon(Icons.send_rounded, size: 20, color: colors.primary),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
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
