import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../models/log_entry.dart';
import '../../../../utils/ansi_parser.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../ui/app_design_tokens.dart';

AppLocalizations _terminalLocalizations(BuildContext context) {
  return AppLocalizations.of(context) ??
      lookupAppLocalizations(const Locale('zh'));
}

enum TerminalColorMode { dark, light, system, monochrome }

extension on TerminalColorMode {
  String label(AppLocalizations l10n) {
    switch (this) {
      case TerminalColorMode.dark:
        return l10n.darkTerminal;
      case TerminalColorMode.light:
        return l10n.lightTerminal;
      case TerminalColorMode.system:
        return l10n.followSystem;
      case TerminalColorMode.monochrome:
        return l10n.monochromeOutput;
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
  final Future<void> Function(String content)? onExport;
  final bool autoFollowInitiallyEnabled;
  final ValueChanged<bool>? onAutoFollowPreferenceChanged;
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
    this.onExport,
    this.autoFollowInitiallyEnabled = true,
    this.onAutoFollowPreferenceChanged,
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
  static const int _maxAnsiCacheBytes = 1024 * 1024;

  final LinkedHashMap<String, List<TextSpan>> _ansiCache =
      LinkedHashMap<String, List<TextSpan>>();
  int _ansiCacheBytes = 0;
  int _lastLogCount = 0;
  int _lastLogVersion = 0;
  String? _lastLogTailSignature;
  bool _hasUnreadOutput = false;

  // Filtering is only expensive when the user asks for it. Keep the result
  // across unrelated rebuilds (font gestures, toolbar state, etc.) while the
  // immutable log snapshot and filter inputs are unchanged.
  List<LogEntry>? _filteredLogsCache;
  List<LogEntry>? _filteredLogsSource;
  int? _filteredLogsVersion;
  String? _filteredLogsQuery;
  bool? _filteredLogsErrorsOnly;

  @override
  void initState() {
    super.initState();
    _autoScroll = widget.autoFollowInitiallyEnabled;
    _lastLogCount = widget.logs.length;
    _lastLogVersion = widget.logVersion;
    _lastLogTailSignature = _logTailSignature(widget.logs);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncUnreadOutputWithViewport(),
    );
    _loadDisplayPreferences();
  }

  Future<void> _loadDisplayPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final savedFontSize = prefs.getDouble(_fontSizePrefsKey);
    final savedColorMode = prefs.getString(_colorModePrefsKey);
    final colorMode =
        TerminalColorMode.values.cast<TerminalColorMode?>().firstWhere(
              (item) => item?.name == savedColorMode,
              orElse: () => null,
            );
    if (!mounted) return;
    if (savedFontSize != null || colorMode != null) {
      setState(() {
        if (savedFontSize != null) {
          _fontSize =
              savedFontSize.clamp(_fontSizeMin, _fontSizeMax).toDouble();
        }
        if (colorMode != null) {
          _colorMode = colorMode;
          _ansiCache.clear();
          _ansiCacheBytes = 0;
        }
      });
    }
    if (savedColorMode == null) {
      unawaited(
          prefs.setString(_colorModePrefsKey, TerminalColorMode.dark.name));
    }
  }

  Future<void> _persistFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizePrefsKey, _fontSize);
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
    if (!identical(widget.logs, oldWidget.logs) ||
        widget.logVersion != oldWidget.logVersion) {
      _invalidateFilteredLogs();
    }
    if (widget.logs.isEmpty && _ansiCache.isNotEmpty) {
      _ansiCache.clear();
      _ansiCacheBytes = 0;
    }
    if (widget.logs.isEmpty) {
      _invalidateFilteredLogs();
    }
    final currentTailSignature = _logTailSignature(widget.logs);
    final hasAppendedOutput = widget.logs.isNotEmpty &&
        (widget.logs.length > _lastLogCount ||
            (widget.logVersion != _lastLogVersion &&
                currentTailSignature != _lastLogTailSignature));
    if (widget.logs.isEmpty || widget.logs.length < _lastLogCount) {
      _setUnreadOutput(false);
    } else if (hasAppendedOutput) {
      if (_autoScroll) {
        _setUnreadOutput(false);
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      } else {
        _setUnreadOutput(true);
      }
    }
    _lastLogCount = widget.logs.length;
    _lastLogVersion = widget.logVersion;
    _lastLogTailSignature = currentTailSignature;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncUnreadOutputWithViewport(),
    );
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
    final atBottom = pos.extentAfter <= 60;
    if (_autoScroll == atBottom && (!atBottom || !_hasUnreadOutput)) return;
    setState(() {
      _autoScroll = atBottom;
      if (atBottom) _hasUnreadOutput = false;
    });
  }

  String? _logTailSignature(List<LogEntry> logs) {
    if (logs.isEmpty) return null;
    final last = logs.last;
    return '${last.executionId}|${last.timestamp.microsecondsSinceEpoch}|'
        '${last.type.name}|${last.content}';
  }

  void _setUnreadOutput(bool value) {
    if (_hasUnreadOutput == value) return;
    if (!mounted) {
      _hasUnreadOutput = value;
      return;
    }
    setState(() => _hasUnreadOutput = value);
  }

  void _syncUnreadOutputWithViewport() {
    if (!mounted || !_scrollController.hasClients) return;
    final atBottom = _scrollController.position.extentAfter <= 60;
    if (!atBottom || (_autoScroll && !_hasUnreadOutput)) return;
    setState(() {
      _autoScroll = true;
      _hasUnreadOutput = false;
    });
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
    if (!mounted) return;
    setState(() {
      _autoScroll = true;
      _hasUnreadOutput = false;
    });
    _scrollToBottom();
  }

  void _submitStdin() {
    if (widget.onStdin == null) return;
    final input = _stdinController.text;
    _stdinController.clear();
    widget.onStdin!(input);
    setState(() {
      _autoScroll = true;
      _hasUnreadOutput = false;
    });
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
        return AppThemeColors.terminalText(colors, isDark);
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
    _ansiCacheBytes += _ansiCacheEntryBytes(key, parsed);
    _trimAnsiCache();
    return parsed;
  }

  int _ansiCacheEntryBytes(String key, List<TextSpan> spans) {
    var textLength = key.length;
    for (final span in spans) {
      textLength += span.text?.length ?? 0;
    }
    return textLength * 2;
  }

  void _trimAnsiCache() {
    while (_ansiCache.isNotEmpty &&
        (_ansiCache.length > _maxAnsiCacheEntries ||
            _ansiCacheBytes > _maxAnsiCacheBytes)) {
      final oldestKey = _ansiCache.keys.first;
      final oldestValue = _ansiCache.remove(oldestKey);
      if (oldestValue != null) {
        _ansiCacheBytes -= _ansiCacheEntryBytes(oldestKey, oldestValue);
      }
    }
    if (_ansiCacheBytes < 0) _ansiCacheBytes = 0;
  }

  List<LogEntry> _filteredLogs() {
    if (!_filterErrors && _searchQuery.isEmpty) {
      return widget.logs;
    }

    final cached = _filteredLogsCache;
    if (cached != null &&
        identical(_filteredLogsSource, widget.logs) &&
        _filteredLogsVersion == widget.logVersion &&
        _filteredLogsQuery == _searchQuery &&
        _filteredLogsErrorsOnly == _filterErrors) {
      return cached;
    }

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
    final snapshot = List<LogEntry>.unmodifiable(result);
    _filteredLogsCache = snapshot;
    _filteredLogsSource = widget.logs;
    _filteredLogsVersion = widget.logVersion;
    _filteredLogsQuery = _searchQuery;
    _filteredLogsErrorsOnly = _filterErrors;
    return snapshot;
  }

  void _invalidateFilteredLogs() {
    _filteredLogsCache = null;
    _filteredLogsSource = null;
    _filteredLogsVersion = null;
    _filteredLogsQuery = null;
    _filteredLogsErrorsOnly = null;
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
              ? AppThemeColors.terminalDarkText.withValues(alpha: 0.24)
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.26),
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
    _showToast(
      _terminalLocalizations(context).copiedAllLines(widget.logs.length),
    );
  }

  Future<void> _exportAll() async {
    if (widget.onExport == null) return;
    final l10n = _terminalLocalizations(context);
    final content =
        widget.logs.map((entry) => AnsiParser.strip(entry.content)).join('\n');
    try {
      await widget.onExport!(content);
    } catch (_) {
      _showToast(l10n.exportFailedTryAgain);
    }
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
    final toolbarText =
        isDark ? AppThemeColors.terminalDarkToolbarText : colors.onSurface;
    final toolbarMuted = AppThemeColors.terminalMuted(colors, isDark);
    final toolbarActive = AppThemeColors.terminalAccent(colors, isDark);
    final toolbarError = AppThemeColors.terminalError(colors, isDark);
    final toolbarBorder = AppThemeColors.terminalBorder(colors, isDark);
    final copyButtonBg = isDark
        ? AppThemeColors.terminalDarkControl
        : colors.primaryContainer.withValues(alpha: 0.4);
    final localizations = _terminalLocalizations(context);

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
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              onPressed: () =>
                  setState(() => _showLineNumbers = !_showLineNumbers),
              tooltip: _showLineNumbers
                  ? localizations.hideLineNumbers
                  : localizations.showLineNumbers,
            ),
          IconButton(
            icon: Icon(Icons.search,
                size: 18,
                color: _searchVisible || _filterErrors
                    ? toolbarActive
                    : toolbarMuted),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            onPressed: () => setState(() {
              _searchVisible = !_searchVisible;
              if (!_searchVisible) {
                _searchQuery = '';
                _searchController.clear();
                _invalidateFilteredLogs();
              }
            }),
            tooltip: localizations.search,
          ),
          IconButton(
            icon: Icon(
              _autoScroll ? Icons.vertical_align_bottom_rounded : Icons.pause,
              size: 18,
              color: _autoScroll ? toolbarActive : toolbarMuted,
            ),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            onPressed: () {
              final nextValue = !_autoScroll;
              setState(() {
                _autoScroll = nextValue;
                if (nextValue) _hasUnreadOutput = false;
              });
              widget.onAutoFollowPreferenceChanged?.call(nextValue);
              if (_autoScroll) _scrollToBottom();
            },
            tooltip: _autoScroll
                ? localizations.disableAutoFollow
                : localizations.enableAutoFollow,
          ),
          if (_filterErrors)
            IconButton(
              icon: Icon(Icons.error_outline, size: 18, color: toolbarError),
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              onPressed: () => setState(() {
                _filterErrors = false;
                _invalidateFilteredLogs();
              }),
              tooltip: localizations.showAll,
            ),
          PopupMenuButton<TerminalColorMode>(
            tooltip: localizations.terminalTheme,
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
                        Text(mode.label(localizations)),
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
              label: Text(localizations.copyAll,
                  style: const TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: toolbarText,
                iconColor: toolbarActive,
                backgroundColor: copyButtonBg,
                visualDensity: VisualDensity.compact,
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          if (widget.onExport != null && logs.isNotEmpty)
            IconButton(
              icon: Icon(Icons.file_download_outlined,
                  size: 18, color: toolbarMuted),
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              onPressed: _exportAll,
              tooltip: localizations.exportLogs,
            ),
          if (widget.onClear != null && logs.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_outline, size: 18, color: toolbarMuted),
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              onPressed: widget.onClear,
              tooltip: localizations.clear,
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
              : AppThemeColors.terminalMuted(colors, isDark),
        ),
      ),
    );
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final localizations = _terminalLocalizations(context);
    final colors = Theme.of(context).colorScheme;
    final isDark = _terminalBrightness() == Brightness.dark;
    final logs = widget.logs;
    final displayLogs = _filteredLogs();
    final bgColor = AppThemeColors.terminalCanvas(isDark);
    final inputBarColor = AppThemeColors.terminalSurface(isDark);
    final inputFillColor = AppThemeColors.terminalInput(isDark);
    final inputTextColor = AppThemeColors.terminalText(colors, isDark);
    final inputHintColor = isDark
        ? AppThemeColors.terminalDarkMuted
        : colors.onSurfaceVariant.withValues(alpha: 0.55);
    final inputBorderColor = widget.waitingForInput
        ? colors.primary.withValues(alpha: 0.72)
        : colors.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.55);
    final barColor = isDark
        ? AppThemeColors.terminalDarkSurface
        : colors.surfaceContainerHighest;
    final toolbarTextColor =
        isDark ? AppThemeColors.terminalDarkToolbarText : colors.onSurface;
    final toolbarHintColor = AppThemeColors.terminalMuted(colors, isDark);
    final toolbarErrorColor = AppThemeColors.terminalError(colors, isDark);

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
                          AppThemeColors.terminalAccent(colors, isDark),
                      decoration: InputDecoration(
                        hintText: localizations.searchLogs,
                        hintStyle: TextStyle(color: toolbarHintColor),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                      ),
                      onChanged: (v) => setState(() {
                        _searchQuery = v;
                        _invalidateFilteredLogs();
                      }),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.error_outline,
                        size: 18,
                        color: _filterErrors
                            ? toolbarErrorColor
                            : toolbarHintColor),
                    constraints:
                        const BoxConstraints(minWidth: 44, minHeight: 44),
                    onPressed: () => setState(() {
                      _filterErrors = !_filterErrors;
                      _invalidateFilteredLogs();
                    }),
                    tooltip: _filterErrors
                        ? localizations.showAll
                        : localizations.onlyErrors,
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: toolbarHintColor),
                    constraints:
                        const BoxConstraints(minWidth: 44, minHeight: 44),
                    onPressed: () => setState(() {
                      _searchVisible = false;
                      _searchQuery = '';
                      _searchController.clear();
                      _invalidateFilteredLogs();
                    }),
                    tooltip: localizations.closeSearch,
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
                            color: colors.onSurface.withValues(alpha: 0.12),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            (_searchQuery.isNotEmpty || _filterErrors)
                                ? localizations.noMatchingOutput
                                : (widget.emptyMessage ??
                                    (widget.isRunning
                                        ? localizations.waitingForOutput
                                        : localizations.noOutput)),
                            style: TextStyle(
                                color: colors.onSurface.withValues(alpha: 0.24),
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
                          scrollCacheExtent:
                              const ScrollCacheExtent.pixels(200),
                          addAutomaticKeepAlives: false,
                          addRepaintBoundaries: true,
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
          if (_hasUnreadOutput && displayLogs.isNotEmpty)
            GestureDetector(
              onTap: () {
                setState(() {
                  _autoScroll = true;
                  _hasUnreadOutput = false;
                });
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
                    Text(localizations.newOutputAvailable,
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
                                  ? localizations.inputContent
                                  : localizations.waitingForInput,
                              hintStyle: TextStyle(
                                color: inputHintColor,
                                fontSize: 13,
                              ),
                              filled: false,
                              fillColor: AppThemeColors.transparent,
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
                            color: AppThemeColors.transparent,
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
    _ansiCacheBytes = 0;
    super.dispose();
  }
}
