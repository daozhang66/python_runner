import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ssh_text.dart';

/// Shows the terminal text in a normal scrollable view so the system text
/// selection handles and toolbar can be used to pick exactly what to copy.
class TerminalTextPage extends StatefulWidget {
  const TerminalTextPage({super.key, required this.text});

  final String text;

  @override
  State<TerminalTextPage> createState() => _TerminalTextPageState();
}

class _TerminalTextPageState extends State<TerminalTextPage> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _jumpToEnd() {
    if (_scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  }

  Future<void> _copy(String text) async {
    final t = SshText.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(
      SnackBar(
        content: Text(t('已复制', 'Copied')),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  String _lastLines(int count) {
    final lines = widget.text.split('\n');
    if (lines.length <= count) return widget.text;
    return lines.sublist(lines.length - count).join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final t = SshText.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t('选择文字', 'Select text')),
        actions: [
          IconButton(
            icon: const Icon(Icons.vertical_align_bottom),
            tooltip: t('跳到末尾', 'Jump to end'),
            onPressed: _jumpToEnd,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'all') {
                _copy(widget.text);
              } else if (value == 'last50') {
                _copy(_lastLines(50));
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'all', child: Text(t('复制全部', 'Copy all'))),
              PopupMenuItem(
                value: 'last50',
                child: Text(t('复制最后 50 行', 'Copy last 50 lines')),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              t(
                '长按文字，拖动手柄选择范围，再点系统弹出的“复制”。右上角菜单可以直接复制全部。',
                'Long-press text, drag the handles, then tap the system "Copy". The menu can copy everything at once.',
              ),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Scrollbar(
              controller: _scroll,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  widget.text,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
