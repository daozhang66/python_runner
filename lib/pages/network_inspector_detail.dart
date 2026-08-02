part of 'network_inspector_page.dart';

class _HttpRecordDetailPage extends StatelessWidget {
  final HttpRecord record;
  const _HttpRecordDetailPage({required this.record});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final timeFmt = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');

    return Scaffold(
      appBar: AppBar(
        title: Text('${record.method} ${record.statusText}',
            style: const TextStyle(fontSize: 15)),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: record.toExportText()));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(l10n.requestDetailsCopied),
                    duration: const Duration(seconds: 1)),
              );
            },
            tooltip: l10n.copy,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // --- Overview ---
          AppSectionCard(
            title: l10n.overview,
            icon: Icons.info_outline,
            children: [
              _DetailRow(l10n.timeLabel, timeFmt.format(record.timestamp)),
              _DetailRow(l10n.method, record.method),
              _DetailRow('URL', record.url),
              _DetailRow(l10n.library, record.library),
              _DetailRow(l10n.duration, record.durationText),
              _DetailRow(l10n.proxy, record.usedProxy ? l10n.yes : l10n.no),
              _DetailRow(
                  l10n.sslVerification, record.sslVerify ? l10n.yes : l10n.no),
            ],
          ),
          const SizedBox(height: 8),
          // --- Request Headers ---
          AppSectionCard(
            title: l10n.requestHeaders(record.requestHeaders.length),
            icon: Icons.arrow_upward,
            children: record.requestHeaders.entries
                .map((e) => _DetailRow(e.key, e.value))
                .toList(),
          ),
          if (record.requestBody != null && record.requestBody!.isNotEmpty) ...[
            const SizedBox(height: 8),
            AppSectionCard(
              title: l10n.requestBody,
              icon: Icons.upload,
              children: [_CodeBlock(record.requestBody!)],
            ),
          ],
          const SizedBox(height: 8),
          // --- Response ---
          AppSectionCard(
            title: l10n.response,
            icon: Icons.arrow_downward,
            children: [
              if (record.statusCode != null)
                _DetailRow(l10n.statusCode, record.statusCode.toString()),
              if (record.errorType != null)
                _DetailRow(l10n.errorType, record.errorType!,
                    valueColor: colors.error),
              if (record.errorMessage != null)
                _DetailRow(l10n.errorMessage, record.errorMessage!,
                    valueColor: colors.error),
            ],
          ),
          if (record.responseHeaders != null &&
              record.responseHeaders!.isNotEmpty) ...[
            const SizedBox(height: 8),
            AppSectionCard(
              title: l10n.responseHeaders(record.responseHeaders!.length),
              icon: Icons.arrow_downward,
              children: record.responseHeaders!.entries
                  .map((e) => _DetailRow(e.key, e.value))
                  .toList(),
            ),
          ],
          if (record.responseBodyPreview != null &&
              record.responseBodyPreview!.isNotEmpty) ...[
            const SizedBox(height: 8),
            AppSectionCard(
              title: record.isImageBody
                  ? l10n.responseImage
                  : record.isMediaBody
                      ? l10n.responseMedia
                      : l10n.responsePreview,
              icon: record.isImageBody
                  ? Icons.image
                  : record.isMediaBody
                      ? Icons.audiotrack
                      : Icons.description_outlined,
              children: [
                if (record.responseBodyTruncated) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colors.errorContainer.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: colors.error.withValues(alpha: 0.24)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 16, color: colors.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            record.responseBodyBytes != null
                                ? l10n.largeResponseCaptured(
                                    _formatByteSize(
                                        record.capturedResponseBodyBytes),
                                    _formatByteSize(record.responseBodyBytes!),
                                  )
                                : l10n.largeResponse,
                            style: TextStyle(
                                fontSize: 11, color: colors.onErrorContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (record.isImageBody)
                  _ImagePreview(dataUri: record.responseBodyPreview!)
                else if (record.isMediaBody)
                  _MediaInfoCard(meta: record.mediaMeta!)
                else
                  _CodeBlock(record.responseBodyPreview!),
                if (!record.isMediaBody) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => record.isImageBody
                              ? _ImageFullViewPage(
                                  dataUri: record.responseBodyPreview!)
                              : _BodyFullViewPage(
                                  body: record.responseBodyPreview!,
                                  bodyBytes: record.responseBodyBytes,
                                  wasTruncated: record.responseBodyTruncated,
                                  title: l10n.responseBody,
                                ),
                        ),
                      ),
                      icon: Icon(
                          record.isImageBody
                              ? Icons.zoom_in
                              : Icons.open_in_full,
                          size: 14),
                      label: Text(
                          record.isImageBody
                              ? l10n.viewOriginalImage
                              : l10n.viewFullContent,
                          style: const TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailRow(this.label, this.value, {this.valueColor});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasLongValue = value.length > 24;
        final useStackedLayout = constraints.maxWidth < 360 || hasLongValue;
        final labelStyle =
            TextStyle(fontSize: 11, color: colors.onSurfaceVariant);
        final valueStyle = TextStyle(
          fontSize: 11,
          height: 1.35,
          color: valueColor,
          fontFamily: _looksTechnical(value) ? 'monospace' : null,
        );

        if (useStackedLayout) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: labelStyle),
                const SizedBox(height: 2),
                SelectableText(value, style: valueStyle),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 90, child: Text(label, style: labelStyle)),
              Expanded(child: SelectableText(value, style: valueStyle)),
            ],
          ),
        );
      },
    );
  }

  bool _looksTechnical(String text) {
    return text.contains('/') ||
        text.contains(':') ||
        text.contains(';') ||
        text.contains('_') ||
        text.contains('-') ||
        text.length > 32;
  }
}

String _formatByteSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _CodeBlock extends StatelessWidget {
  final String text;
  const _CodeBlock(this.text);

  String get _formatted {
    try {
      final parsed = jsonDecode(text);
      return const JsonEncoder.withIndent('  ').convert(parsed);
    } catch (_) {
      return text;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 300),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppThemeColors.codeSurface(colors),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          _formatted,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
        ),
      ),
    );
  }
}

// --- Media info card ---
class _MediaInfoCard extends StatelessWidget {
  final Map<String, dynamic> meta;
  const _MediaInfoCard({required this.meta});

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _mediaLabel(BuildContext context, String type) {
    final l10n = AppLocalizations.of(context)!;
    if (type.startsWith('audio/')) return l10n.audio;
    if (type.startsWith('video/')) return l10n.video;
    return l10n.media;
  }

  IconData _mediaIcon(String type) {
    if (type.startsWith('audio/')) return Icons.audiotrack;
    if (type.startsWith('video/')) return Icons.videocam;
    return Icons.perm_media;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final type = meta['type'] as String? ?? 'unknown';
    final size = meta['size'] as int? ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColors.softSurface(colors),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(_mediaIcon(type), size: 40, color: colors.primary),
          const SizedBox(height: 8),
          Text(_mediaLabel(context, type),
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.primary)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _MediaMetaItem(
                  label: AppLocalizations.of(context)!.type, value: type),
              const SizedBox(width: 24),
              _MediaMetaItem(
                label: AppLocalizations.of(context)!.size,
                value: _formatSize(size),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MediaMetaItem extends StatelessWidget {
  final String label;
  final String value;
  const _MediaMetaItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(label,
            style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

// --- Full body view page with JSON tree viewer ---
class _BodyFullViewPage extends StatefulWidget {
  final String body;
  final int? bodyBytes;
  final String title;
  final bool wasTruncated;
  const _BodyFullViewPage({
    required this.body,
    this.bodyBytes,
    required this.title,
    this.wasTruncated = false,
  });

  @override
  State<_BodyFullViewPage> createState() => _BodyFullViewPageState();
}

class _BodyFullViewPageState extends State<_BodyFullViewPage> {
  late final CodeLineEditingController _bodyController;
  late final CodeFindController _findController;
  late final CodeScrollController _codeScrollController;
  late final SelectionToolbarController _toolbarController;
  dynamic _parsedJson;
  String _formatted = '';
  List<String> _formattedLines = const [];
  int _lineCount = 0;
  double _fontSize = 10.0;
  double? _scaleStartFontSize;
  final Map<int, Offset> _scalePointers = {};
  double? _pointerScaleStartDistance;
  bool _showFab = false;

  @override
  void initState() {
    super.initState();
    _bodyController = CodeLineEditingController();
    _findController = CodeFindController(_bodyController);
    _codeScrollController = CodeScrollController();
    _toolbarController = _buildSelectionToolbarController();
    _codeScrollController.verticalScroller.addListener(_onCodeScrollChanged);
    _parseBody();
  }

  @override
  void dispose() {
    _codeScrollController.verticalScroller.removeListener(_onCodeScrollChanged);
    _findController.dispose();
    _bodyController.dispose();
    _codeScrollController.verticalScroller.dispose();
    _codeScrollController.horizontalScroller.dispose();
    _codeScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _BodyFullViewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.body != widget.body) {
      _findController.close();
      _parseBody();
    }
  }

  bool _isTruncated = false;
  CodeEditorStyle? _cachedEditorStyle;
  _BodyEditorStyleKey? _editorStyleKey;

  CodeEditorStyle _resolveEditorStyle(ColorScheme colors) {
    final backgroundColor = AppThemeColors.codeSurface(colors);
    final key = _BodyEditorStyleKey(
      fontSize: _fontSize,
      textColor: colors.onSurface,
      backgroundColor: backgroundColor,
      selectionColor: colors.primary.withValues(alpha: 0.24),
      highlightColor: colors.primaryContainer.withValues(alpha: 0.82),
      cursorColor: colors.primary,
    );
    if (_editorStyleKey == key && _cachedEditorStyle != null) {
      return _cachedEditorStyle!;
    }
    _editorStyleKey = key;
    return _cachedEditorStyle = CodeEditorStyle(
      fontFamily: 'monospace',
      fontSize: key.fontSize,
      fontHeight: 1.45,
      textColor: key.textColor,
      backgroundColor: key.backgroundColor,
      selectionColor: key.selectionColor,
      highlightColor: key.highlightColor,
      cursorColor: key.cursorColor,
    );
  }

  void _onCodeScrollChanged() {
    if (!_codeScrollController.verticalScroller.hasClients) return;
    final show = _codeScrollController.verticalScroller.offset > 300;
    if (show != _showFab && mounted) setState(() => _showFab = show);
  }

  void _parseBody() {
    _isTruncated = widget.wasTruncated;
    // Try 1: parse as-is
    try {
      _parsedJson = jsonDecode(widget.body);
      const encoder = JsonEncoder.withIndent('  ');
      _formatted = encoder.convert(_parsedJson);
    } catch (_) {
      // Try 2: repair truncated JSON
      final repaired = _tryRepairTruncatedJson(widget.body);
      if (repaired != null) {
        try {
          _parsedJson = jsonDecode(repaired);
          const encoder = JsonEncoder.withIndent('  ');
          _formatted = encoder.convert(_parsedJson);
          _isTruncated = true;
        } catch (_) {
          _parsedJson = null;
          _formatted = _formatTextBody(widget.body);
        }
      } else {
        _parsedJson = null;
        _formatted = _formatTextBody(widget.body);
      }
    }
    _formattedLines = _formatted.split('\n');
    _lineCount = _formattedLines.length;
    _bodyController.text = _formatted;
  }

  bool _looksLikeJson(String s) {
    final t = s.trimLeft();
    return t.startsWith('{') || t.startsWith('[');
  }

  String _formatTextBody(String input) {
    if (_looksLikeJson(input)) return _basicFormatJson(input);
    if (_looksLikeHtml(input)) return _basicFormatHtml(input);
    return input;
  }

  bool _looksLikeHtml(String s) {
    final t = s.trimLeft();
    if (t.isEmpty || !t.startsWith('<')) return false;
    final lower = t.toLowerCase();
    if (lower.startsWith('<!doctype html') || lower.startsWith('<html')) {
      return true;
    }
    final sample = t.length > 512 ? t.substring(0, 512) : t;
    return RegExp(r'</?[a-zA-Z][^>]*>').hasMatch(sample);
  }

  /// Try to repair a truncated JSON string by cutting back to last valid boundary
  /// and adding missing closing brackets.
  String? _tryRepairTruncatedJson(String input) {
    const marker = '...（已截断）';
    final idx = input.lastIndexOf(marker);
    if (idx <= 0) return null;

    var s = input.substring(0, idx).trimRight();

    // Find the last comma outside of strings —cut back to a valid boundary
    int lastComma = -1;
    bool inStr = false, esc = false;
    for (int i = 0; i < s.length; i++) {
      if (esc) {
        esc = false;
        continue;
      }
      if (s[i] == '\\') {
        esc = true;
        continue;
      }
      if (s[i] == '"') {
        inStr = !inStr;
        continue;
      }
      if (inStr) continue;
      if (s[i] == ',') lastComma = i;
    }
    if (lastComma > 0) s = s.substring(0, lastComma);

    // Count and close unclosed brackets
    int curly = 0, square = 0;
    inStr = false;
    esc = false;
    for (int i = 0; i < s.length; i++) {
      if (esc) {
        esc = false;
        continue;
      }
      if (s[i] == '\\') {
        esc = true;
        continue;
      }
      if (s[i] == '"') {
        inStr = !inStr;
        continue;
      }
      if (inStr) continue;
      if (s[i] == '{') curly++;
      if (s[i] == '}') curly--;
      if (s[i] == '[') square++;
      if (s[i] == ']') square--;
    }
    for (int i = 0; i < square; i++) {
      s += ']';
    }
    for (int i = 0; i < curly; i++) {
      s += '}';
    }

    return s;
  }

  /// Basic formatting for JSON-like content that can't be fully parsed.
  String _basicFormatJson(String input) {
    final buf = StringBuffer();
    int indent = 0;
    bool inStr = false, esc = false;
    for (int i = 0; i < input.length; i++) {
      final c = input[i];
      if (esc) {
        buf.write(c);
        esc = false;
        continue;
      }
      if (c == '\\' && inStr) {
        buf.write(c);
        esc = true;
        continue;
      }
      if (c == '"') {
        buf.write(c);
        inStr = !inStr;
        continue;
      }
      if (inStr) {
        buf.write(c);
        continue;
      }
      if (c == '{' || c == '[') {
        buf.writeln(c);
        indent++;
        buf.write('  ' * indent);
      } else if (c == '}' || c == ']') {
        buf.writeln();
        if (indent > 0) indent--;
        buf.write('  ' * indent);
        buf.write(c);
      } else if (c == ',') {
        buf.writeln(c);
        buf.write('  ' * indent);
      } else if (c == ':') {
        buf.write(': ');
      } else if (c != ' ' && c != '\n' && c != '\r' && c != '\t') {
        buf.write(c);
      }
    }
    return buf.toString();
  }

  String _basicFormatHtml(String input) {
    final normalized = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final expanded = normalized.replaceAllMapped(
      RegExp(r'>\s*<'),
      (_) => '>\n<',
    );
    final lines = expanded.split('\n');
    final buf = StringBuffer();
    int indent = 0;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (_isHtmlClosingTag(line) && indent > 0) indent--;
      buf.writeln('${'  ' * indent}$line');
      if (_isHtmlOpeningTag(line)) indent++;
    }

    return buf.toString().trimRight();
  }

  bool _isHtmlClosingTag(String line) {
    return line.startsWith('</');
  }

  bool _isHtmlOpeningTag(String line) {
    if (!line.startsWith('<') ||
        line.startsWith('</') ||
        line.startsWith('<!') ||
        line.startsWith('<?') ||
        line.endsWith('/>')) {
      return false;
    }

    final tagName = RegExp(r'^<\s*([a-zA-Z][a-zA-Z0-9:-]*)')
        .firstMatch(line)
        ?.group(1)
        ?.toLowerCase();
    if (tagName == null || _htmlVoidTags.contains(tagName)) return false;
    return !RegExp('</$tagName\\s*>', caseSensitive: false).hasMatch(line);
  }

  static const Set<String> _htmlVoidTags = {
    'area',
    'base',
    'br',
    'col',
    'embed',
    'hr',
    'img',
    'input',
    'link',
    'meta',
    'param',
    'source',
    'track',
    'wbr',
  };

  void _showFontSizeSlider() {
    double tempSize = _fontSize;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          contentPadding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${tempSize.round()} px',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('A', style: TextStyle(fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: tempSize,
                      min: 6.0,
                      max: 32.0,
                      divisions: 26,
                      onChanged: (v) {
                        setDialogState(() => tempSize = v);
                      },
                    ),
                  ),
                  const Text('A',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                setDialogState(() => tempSize = 12.0);
              },
              child: Text(AppLocalizations.of(ctx)!.reset),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() => _fontSize = tempSize);
              },
              child: Text(AppLocalizations.of(ctx)!.confirm),
            ),
          ],
        ),
      ),
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
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
        startDistance <= 0 ||
        currentDistance == null) {
      return;
    }
    final nextSize = (startSize * (currentDistance / startDistance))
        .clamp(6.0, 32.0)
        .toDouble();
    if ((nextSize - _fontSize).abs() < 0.1) return;
    setState(() => _fontSize = nextSize);
  }

  void _handlePointerEnd(PointerEvent event) {
    _scalePointers.remove(event.pointer);
    if (_scalePointers.length < 2) {
      _scaleStartFontSize = null;
      _pointerScaleStartDistance = null;
    }
  }

  double? _currentPointerDistance() {
    if (_scalePointers.length < 2) return null;
    final points = _scalePointers.values.take(2).toList(growable: false);
    return (points[1] - points[0]).distance;
  }

  Future<void> _exportJson() async {
    try {
      final bridge = NativeBridge();
      final now = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final path =
          await bridge.exportLog(_formatted, fileName: 'response_$now.json');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context)!.exportedTo(path)),
              duration: const Duration(seconds: 3)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.exportFailed),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
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
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(AppLocalizations.of(context)!.copied),
                      duration: Duration(seconds: 1),
                    ),
                  );
                }
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

  void _copyFormattedBody() {
    Clipboard.setData(ClipboardData(text: _formatted));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(AppLocalizations.of(context)!.copied),
          duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isJson = _parsedJson != null;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(widget.title, style: const TextStyle(fontSize: 15)),
            if (isJson) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('JSON',
                    style: TextStyle(
                        fontSize: 10, color: colors.onPrimaryContainer)),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, size: 20),
            onPressed: _findController.findMode,
            tooltip: AppLocalizations.of(context)!.search,
          ),
          if (isJson)
            IconButton(
              icon: const Icon(Icons.account_tree, size: 20),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _JsonTreePage(data: _parsedJson),
                ),
              ),
              tooltip: AppLocalizations.of(context)!.treeView,
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            tooltip: AppLocalizations.of(context)!.more,
            position: PopupMenuPosition.under,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                value: 'font',
                child: Row(
                  children: [
                    Icon(Icons.format_size, size: 18),
                    SizedBox(width: 8),
                    Text(AppLocalizations.of(context)!.fontSize,
                        style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'copy',
                child: Row(
                  children: [
                    Icon(Icons.copy, size: 18),
                    SizedBox(width: 8),
                    Text(AppLocalizations.of(context)!.copyAll,
                        style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.file_download_outlined, size: 18),
                    SizedBox(width: 8),
                    Text(AppLocalizations.of(context)!.exportJson,
                        style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ],
            onSelected: (v) {
              switch (v) {
                case 'font':
                  _showFontSizeSlider();
                case 'copy':
                  _copyFormattedBody();
                case 'export':
                  _exportJson();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // --- Info bar ---
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            color: AppThemeColors.softSurface(colors),
            child: Row(
              children: [
                if (_isTruncated) ...[
                  Icon(Icons.warning_amber, size: 12, color: colors.error),
                  const SizedBox(width: 3),
                  Text(AppLocalizations.of(context)!.truncated,
                      style: TextStyle(fontSize: 10, color: colors.error)),
                  const SizedBox(width: 8),
                ],
                Text(AppLocalizations.of(context)!.lineCount(_lineCount),
                    style: TextStyle(
                        fontSize: 10, color: colors.onSurfaceVariant)),
                if (widget.bodyBytes != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    _isTruncated
                        ? AppLocalizations.of(context)!.capturedBytes(
                            _formatByteSize(utf8.encode(widget.body).length),
                            _formatByteSize(widget.bodyBytes!))
                        : _formatByteSize(widget.bodyBytes!),
                    style:
                        TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
                  ),
                ],
                const Spacer(),
                Text(
                    AppLocalizations.of(context)!
                        .characterCount(_formatted.length),
                    style: TextStyle(
                        fontSize: 10, color: colors.onSurfaceVariant)),
              ],
            ),
          ),
          // --- Content: read-only editor with built-in search navigation ---
          Expanded(
            child: Stack(
              children: [
                Listener(
                  key: const ValueKey('network_full_body_zoom_gesture'),
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: _handlePointerDown,
                  onPointerMove: _handlePointerMove,
                  onPointerUp: _handlePointerEnd,
                  onPointerCancel: _handlePointerEnd,
                  child: CodeEditor(
                    key: const ValueKey('network_full_body_code_editor'),
                    controller: _bodyController,
                    scrollController: _codeScrollController,
                    findController: _findController,
                    toolbarController: _toolbarController,
                    readOnly: true,
                    showCursorWhenReadOnly: false,
                    autofocus: false,
                    wordWrap: true,
                    chunkAnalyzer: const NonCodeChunkAnalyzer(),
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.all(12),
                    borderRadius: BorderRadius.circular(8),
                    style: _resolveEditorStyle(colors),
                    indicatorBuilder: (context, editingController,
                        chunkController, notifier) {
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
                      return _BodyCodeFindPanel(
                        controller: controller,
                      );
                    },
                  ),
                ),
                if (_showFab)
                  Positioned(
                    right: 12,
                    bottom: 16,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: FloatingActionButton.small(
                            heroTag: 'body_top',
                            onPressed: () {
                              final scroller =
                                  _codeScrollController.verticalScroller;
                              if (!scroller.hasClients) return;
                              scroller.animateTo(0,
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOut);
                            },
                            child:
                                const Icon(Icons.keyboard_arrow_up, size: 20),
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: FloatingActionButton.small(
                            heroTag: 'body_bottom',
                            onPressed: () {
                              final scroller =
                                  _codeScrollController.verticalScroller;
                              if (!scroller.hasClients) return;
                              scroller.animateTo(
                                  scroller.position.maxScrollExtent,
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOut);
                            },
                            child:
                                const Icon(Icons.keyboard_arrow_down, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BodyEditorStyleKey {
  final double fontSize;
  final Color textColor;
  final Color backgroundColor;
  final Color selectionColor;
  final Color highlightColor;
  final Color cursorColor;

  const _BodyEditorStyleKey({
    required this.fontSize,
    required this.textColor,
    required this.backgroundColor,
    required this.selectionColor,
    required this.highlightColor,
    required this.cursorColor,
  });

  @override
  bool operator ==(Object other) =>
      other is _BodyEditorStyleKey &&
      fontSize == other.fontSize &&
      textColor == other.textColor &&
      backgroundColor == other.backgroundColor &&
      selectionColor == other.selectionColor &&
      highlightColor == other.highlightColor &&
      cursorColor == other.cursorColor;

  @override
  int get hashCode => Object.hash(
        fontSize,
        textColor,
        backgroundColor,
        selectionColor,
        highlightColor,
        cursorColor,
      );
}

class _BodyCodeFindPanel extends StatelessWidget
    implements PreferredSizeWidget {
  final CodeFindController controller;

  const _BodyCodeFindPanel({required this.controller});

  @override
  Size get preferredSize =>
      Size(double.infinity, controller.value == null ? 0 : 44);

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    if (value == null) return const SizedBox.shrink();

    final colors = Theme.of(context).colorScheme;
    final result = value.result;
    final hasResult =
        result != null && !result.dirty && result.matches.isNotEmpty;
    final resultText = value.searching
        ? AppLocalizations.of(context)!.searching
        : hasResult
            ? '${result.index + 1}/${result.matches.length}'
            : '0/0';

    return Container(
      height: preferredSize.height,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      color: AppThemeColors.softSurface(colors),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller.findInputController,
              focusNode: controller.findInputFocusNode,
              autofocus: true,
              maxLines: 1,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!.searchContent,
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 52,
            child: Text(
              resultText,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up, size: 18),
            onPressed: hasResult ? controller.previousMatch : null,
            tooltip: AppLocalizations.of(context)!.previous,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, size: 18),
            onPressed: hasResult ? controller.nextMatch : null,
            tooltip: AppLocalizations.of(context)!.next,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: controller.close,
            tooltip: AppLocalizations.of(context)!.close,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

// --- Full-screen JSON tree page ---
class _JsonTreePage extends StatelessWidget {
  final dynamic data;
  const _JsonTreePage({required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.jsonTreeView,
            style: const TextStyle(fontSize: 15)),
      ),
      body: SelectionArea(
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _JsonTreeNode(data: data, depth: 0, fontSize: 12),
          ),
        ),
      ),
    );
  }
}

class _JsonTreeNode extends StatefulWidget {
  final dynamic data;
  final int depth;
  final double fontSize;
  const _JsonTreeNode(
      {required this.data, required this.depth, required this.fontSize});

  @override
  State<_JsonTreeNode> createState() => _JsonTreeNodeState();
}

class _JsonTreeNodeState extends State<_JsonTreeNode> {
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    // Auto-collapse deep nodes
    _expanded = widget.depth < 2;
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final depth = widget.depth;
    final fs = widget.fontSize;

    if (data is Map) return _buildObject(data, depth, fs);
    if (data is List) return _buildArray(data, depth, fs);
    return _buildPrimitive(data, fs);
  }

  Widget _buildObject(Map<dynamic, dynamic> map, int depth, double fs) {
    final colors = Theme.of(context).colorScheme;
    final items = map.entries.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              SizedBox(
                width: 12,
                child: Text(_expanded ? '▼' : '▶',
                    style: TextStyle(fontSize: fs - 3, color: colors.primary)),
              ),
              Text('{',
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: fs,
                      color: colors.onSurface)),
              if (!_expanded) ...[
                Text(' ${map.length} keys ',
                    style: TextStyle(
                        fontSize: fs - 2, color: colors.onSurfaceVariant)),
                Text('}',
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: fs,
                        color: colors.onSurface)),
              ],
            ],
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < items.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('"${items[i].key}": ',
                            style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: fs,
                                color: colors.primary)),
                        _JsonValue(
                          data: items[i].value,
                          depth: depth + 1,
                          fontSize: fs,
                          trailing: i < items.length - 1 ? ',' : null,
                        ),
                      ],
                    ),
                  ),
                Text('}',
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: fs,
                        color: colors.onSurface)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildArray(List<dynamic> list, int depth, double fs) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              SizedBox(
                width: 12,
                child: Text(_expanded ? '▼' : '▶',
                    style: TextStyle(fontSize: fs - 3, color: colors.primary)),
              ),
              Text('[',
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: fs,
                      color: colors.onSurface)),
              if (!_expanded) ...[
                Text(' ${list.length} items ',
                    style: TextStyle(
                        fontSize: fs - 2, color: colors.onSurfaceVariant)),
                Text(']',
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: fs,
                        color: colors.onSurface)),
              ],
            ],
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < list.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: _JsonValue(
                      data: list[i],
                      depth: depth + 1,
                      fontSize: fs,
                      trailing: i < list.length - 1 ? ',' : null,
                    ),
                  ),
                Text(']',
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: fs,
                        color: colors.onSurface)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildPrimitive(dynamic value, double fs) {
    return Text(
      _primitiveText(value),
      style: TextStyle(
          fontFamily: 'monospace', fontSize: fs, color: _primitiveColor(value)),
    );
  }
}

/// Wraps a value: shows inline for primitives, expandable for objects/arrays.
class _JsonValue extends StatelessWidget {
  final dynamic data;
  final int depth;
  final double fontSize;
  final String? trailing;
  const _JsonValue(
      {required this.data,
      required this.depth,
      required this.fontSize,
      this.trailing});

  @override
  Widget build(BuildContext context) {
    if (data is Map || data is List) {
      // Complex types: no trailing comma in tree view (avoids floating symbol)
      return _JsonTreeNode(data: data, depth: depth, fontSize: fontSize);
    }
    return Text(
      _primitiveText(data) + (trailing ?? ''),
      style: TextStyle(
          fontFamily: 'monospace',
          fontSize: fontSize,
          color: _primitiveColor(data)),
    );
  }
}

// --- Helpers ---

String _primitiveText(dynamic value) {
  if (value == null) return 'null';
  if (value is bool) return value.toString();
  if (value is num) return value.toString();
  if (value is String) return '"$value"';
  return value.toString();
}

Color _primitiveColor(dynamic value) {
  if (value == null) return AppThemeColors.jsonNull;
  if (value is bool) return AppThemeColors.jsonBoolean;
  if (value is num) return AppThemeColors.jsonNumber;
  if (value is String) return AppThemeColors.jsonString;
  return AppThemeColors.jsonNull;
}

// --- Image preview widget ---
class _ImagePreview extends StatelessWidget {
  final String dataUri;
  const _ImagePreview({required this.dataUri});

  Uint8List? _decodeDataUri() {
    // data:image/png;base64,AAAA...
    final commaIdx = dataUri.indexOf(',');
    if (commaIdx < 0) return null;
    final base64Str = dataUri.substring(commaIdx + 1);
    try {
      return base64Decode(base64Str);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _decodeDataUri();
    if (bytes == null) {
      return Text(
        AppLocalizations.of(context)!.imageDecodeFailed,
        style: const TextStyle(fontSize: 12),
      );
    }
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: AppThemeColors.codeSurface(Theme.of(context).colorScheme),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Text(
              AppLocalizations.of(context)!.imageRenderFailed,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}

// --- Image full view page (pinch-to-zoom) ---
class _ImageFullViewPage extends StatelessWidget {
  final String dataUri;
  const _ImageFullViewPage({required this.dataUri});

  Uint8List? _decodeDataUri() {
    final commaIdx = dataUri.indexOf(',');
    if (commaIdx < 0) return null;
    try {
      return base64Decode(dataUri.substring(commaIdx + 1));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _decodeDataUri();
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context)!.imagePreview,
          style: const TextStyle(fontSize: 15),
        ),
      ),
      body: bytes == null
          ? Center(
              child: Text(AppLocalizations.of(context)!.imageDecodeFailed,
                  style: TextStyle(color: colors.error)))
          : InteractiveViewer(
              minScale: 0.2,
              maxScale: 8.0,
              child: Center(
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Center(
                      child: Text(
                          AppLocalizations.of(context)!.imageRenderFailed,
                          style: TextStyle(color: colors.error))),
                ),
              ),
            ),
    );
  }
}
