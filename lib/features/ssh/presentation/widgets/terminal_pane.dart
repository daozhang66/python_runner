import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm2/xterm.dart'
    show Terminal, TerminalController, TerminalKey, TerminalStyle, TerminalView;

import '../pages/terminal_text_page.dart';
import '../ssh_text.dart';

/// Applies a sticky Ctrl modifier to text typed on the soft keyboard.
///
/// Owners run everything the terminal emits through [apply] before sending it.
class TerminalInputFilter {
  final ValueNotifier<bool> ctrl = ValueNotifier<bool>(false);

  String apply(String data) {
    if (!ctrl.value || data.isEmpty) return data;
    ctrl.value = false;
    if (data.length != 1) return data;
    final unit = data.codeUnitAt(0);
    if (unit >= 0x61 && unit <= 0x7a) return String.fromCharCode(unit - 0x60);
    if (unit >= 0x41 && unit <= 0x5a) return String.fromCharCode(unit - 0x40);
    switch (unit) {
      case 0x5b:
        return '\x1b';
      case 0x5c:
        return '\x1c';
      case 0x5d:
        return '\x1d';
      case 0x20:
        return '\x00';
    }
    return data;
  }

  void dispose() => ctrl.dispose();
}

/// Terminal view plus the touch helpers around it: a selection bar (copy /
/// paste / cancel), a scrollable key bar with a sticky Ctrl key, font size
/// buttons and a "select text" page that uses the system selection handles.
class TerminalPane extends StatefulWidget {
  const TerminalPane({
    super.key,
    required this.terminal,
    required this.filter,
  });

  final Terminal terminal;
  final TerminalInputFilter filter;

  @override
  State<TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends State<TerminalPane> {
  final TerminalController _controller = TerminalController();
  double _fontSize = 14;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onSelectionChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    if (mounted) setState(() {});
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _copySelection() async {
    final t = SshText.of(context);
    final selection = _controller.selection;
    if (selection == null) {
      _toast(
        t(
          '先长按终端文字进行选择，或点“选文本”',
          'Long-press terminal text to select, or tap "Select"',
        ),
      );
      return;
    }
    final text = widget.terminal.buffer.getText(selection);
    await Clipboard.setData(ClipboardData(text: text));
    _controller.clearSelection();
    if (mounted) _toast(t('已复制', 'Copied'));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    _controller.clearSelection();
    widget.terminal.paste(text);
  }

  void _openTextView() {
    var text = widget.terminal.buffer.getText();
    final lines = text.split('\n');
    if (lines.length > 3000) {
      text = lines.sublist(lines.length - 3000).join('\n');
    }
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TerminalTextPage(text: text.trimRight()),
      ),
    );
  }

  void _changeFont(double delta) {
    setState(() => _fontSize = (_fontSize + delta).clamp(8, 28).toDouble());
  }

  Widget _keyButton(
    String label,
    VoidCallback onTap, {
    bool highlighted = false,
  }) {
    return InkWell(
      canRequestFocus: false,
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        color: highlighted ? const Color(0xFF3B5BDB) : null,
        child: Text(
          label,
          style: TextStyle(
            color: highlighted ? Colors.white : Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildKeyBar(SshText t) {
    final terminal = widget.terminal;
    return Material(
      color: const Color(0xFF16181C),
      child: SizedBox(
        height: 42,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: widget.filter.ctrl,
              builder: (context, active, _) => _keyButton(
                'Ctrl',
                () => widget.filter.ctrl.value = !active,
                highlighted: active,
              ),
            ),
            _keyButton('Esc', () => terminal.keyInput(TerminalKey.escape)),
            _keyButton('Tab', () => terminal.keyInput(TerminalKey.tab)),
            _keyButton('↑', () => terminal.keyInput(TerminalKey.arrowUp)),
            _keyButton('↓', () => terminal.keyInput(TerminalKey.arrowDown)),
            _keyButton('←', () => terminal.keyInput(TerminalKey.arrowLeft)),
            _keyButton('→', () => terminal.keyInput(TerminalKey.arrowRight)),
            _keyButton('Home', () => terminal.keyInput(TerminalKey.home)),
            _keyButton('End', () => terminal.keyInput(TerminalKey.end)),
            _keyButton('PgUp', () => terminal.keyInput(TerminalKey.pageUp)),
            _keyButton('PgDn', () => terminal.keyInput(TerminalKey.pageDown)),
            _keyButton(
              '^C',
              () => terminal.keyInput(TerminalKey.keyC, ctrl: true),
            ),
            _keyButton(
              '^D',
              () => terminal.keyInput(TerminalKey.keyD, ctrl: true),
            ),
            _keyButton(
              '^Z',
              () => terminal.keyInput(TerminalKey.keyZ, ctrl: true),
            ),
            _keyButton(
              '^L',
              () => terminal.keyInput(TerminalKey.keyL, ctrl: true),
            ),
            _keyButton('/', () => terminal.textInput('/')),
            _keyButton('-', () => terminal.textInput('-')),
            _keyButton('|', () => terminal.textInput('|')),
            _keyButton('~', () => terminal.textInput('~')),
            _keyButton(t('粘贴', 'Paste'), _paste),
            _keyButton(t('复制', 'Copy'), _copySelection),
            _keyButton(t('选文本', 'Select'), _openTextView),
            _keyButton('A−', () => _changeFont(-1)),
            _keyButton('A+', () => _changeFont(1)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = SshText.of(context);
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              TerminalView(
                widget.terminal,
                controller: _controller,
                autofocus: true,
                deleteDetection: true,
                textStyle: TerminalStyle(fontSize: _fontSize),
                padding: const EdgeInsets.all(6),
              ),
              if (_controller.selection != null)
                Positioned(
                  top: 8,
                  right: 8,
                  child: _SelectionBar(
                    copyLabel: t('复制', 'Copy'),
                    pasteLabel: t('粘贴', 'Paste'),
                    cancelLabel: t('取消', 'Cancel'),
                    onCopy: _copySelection,
                    onPaste: _paste,
                    onCancel: _controller.clearSelection,
                  ),
                ),
            ],
          ),
        ),
        _buildKeyBar(t),
      ],
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.copyLabel,
    required this.pasteLabel,
    required this.cancelLabel,
    required this.onCopy,
    required this.onPaste,
    required this.onCancel,
  });

  final String copyLabel;
  final String pasteLabel;
  final String cancelLabel;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      color: const Color(0xFF2A2D33),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _barButton(Icons.copy, copyLabel, onCopy),
          _barButton(Icons.content_paste, pasteLabel, onPaste),
          _barButton(Icons.close, cancelLabel, onCancel),
        ],
      ),
    );
  }

  Widget _barButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      canRequestFocus: false,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
