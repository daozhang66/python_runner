import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/log_entry.dart';

class LogViewer extends StatefulWidget {
  final List<LogEntry> logs;
  final bool autoScroll;
  final bool showCopyAll;

  const LogViewer({
    super.key,
    required this.logs,
    this.autoScroll = true,
    this.showCopyAll = false,
  });

  @override
  State<LogViewer> createState() => _LogViewerState();
}

class _LogViewerState extends State<LogViewer> {
  final _scrollController = ScrollController();
  final _hScrollController = ScrollController(); // 水平滚动
  double _fontSize = 13.0; // 字体缩放

  static const double _fontSizeMin = 9.0;
  static const double _fontSizeMax = 22.0;
  static const double _fontSizeStep = 1.0;

  @override
  void didUpdateWidget(covariant LogViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoScroll && widget.logs.length > oldWidget.logs.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          }
        });
      });
    }
  }

  Color _colorForType(LogType type, ColorScheme colors) {
    switch (type) {
      case LogType.stdout:
        return colors.onSurface;
      case LogType.stderr:
        return colors.error;
      case LogType.info:
        return colors.primary;
      case LogType.error:
        return colors.error;
    }
  }

  String _logsToText() {
    return widget.logs
        .where((e) =>
            e.type == LogType.stdout ||
            e.type == LogType.stderr ||
            e.type == LogType.error)
        .map((e) => e.content)
        .join('\n');
  }

  void _copyAll(BuildContext context) {
    final text = _logsToText();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('已复制 ${widget.logs.length} 条日志'),
          duration: const Duration(seconds: 1)),
    );
  }

  /// 估算内容区域水平宽度，保证最长行不被截断。
  double _contentWidth(double screenWidth) {
    if (widget.logs.isEmpty) return screenWidth;
    final charWidth = _fontSize * 0.6;
    int maxLen = 0;
    for (final log in widget.logs) {
      if (log.content.length > maxLen) maxLen = log.content.length;
    }
    final contentWidth = maxLen * charWidth + 20 + 40;
    return contentWidth > screenWidth ? contentWidth : screenWidth;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (widget.logs.isEmpty) {
      return Center(
        child: Text('暂无日志', style: TextStyle(color: colors.onSurfaceVariant)),
      );
    }

    return Column(
      children: [
        // 工具栏：字体缩放 + 复制全部
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.4)),
            ),
          ),
          child: Row(
            children: [
              // 字体缩小
              IconButton(
                icon: const Icon(Icons.text_decrease_rounded, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: _fontSize <= _fontSizeMin
                    ? null
                    : () => setState(() => _fontSize =
                        (_fontSize - _fontSizeStep).clamp(_fontSizeMin, _fontSizeMax)),
                tooltip: '缩小字体',
              ),
              // 当前字号显示
              Text(
                '${_fontSize.toInt()}',
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
              // 字体放大
              IconButton(
                icon: const Icon(Icons.text_increase_rounded, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: _fontSize >= _fontSizeMax
                    ? null
                    : () => setState(() => _fontSize =
                        (_fontSize + _fontSizeStep).clamp(_fontSizeMin, _fontSizeMax)),
                tooltip: '放大字体',
              ),
              const Spacer(),
              if (widget.showCopyAll)
                TextButton.icon(
                  onPressed: () => _copyAll(context),
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('全部复制', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                controller: _hScrollController,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: _contentWidth(constraints.maxWidth),
                  child: Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(10),
                      itemCount: widget.logs.length,
                      itemBuilder: (context, index) {
                        final log = widget.logs[index];
                        final color = _colorForType(log.type, colors);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 0.5),
                          child: SelectableText(
                            log.content,
                            maxLines: 1,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: _fontSize,
                              color: color,
                              height: 1.4,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _hScrollController.dispose();
    super.dispose();
  }
}
