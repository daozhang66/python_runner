import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm2/xterm.dart'
    show
        CellOffset,
        Terminal,
        TerminalController,
        TerminalKey,
        TerminalStyle,
        TerminalView,
        TerminalViewState;

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
/// paste / cancel), draggable handles to grow or shrink the selection, a
/// scrollable key bar with a sticky Ctrl key, font size buttons and a
/// "select text" page that uses the system selection handles.
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
  final GlobalKey<TerminalViewState> _viewKey = GlobalKey<TerminalViewState>();
  final GlobalKey _stackKey = GlobalKey();
  final ScrollController _scroll = ScrollController();
  double _fontSize = 14;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onSelectionChanged);
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onSelectionChanged);
    _scroll.removeListener(_onScroll);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    // Handles follow the text, so they only need a rebuild while selecting.
    if (_controller.selection != null) _onSelectionChanged();
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

  static int _compare(CellOffset a, CellOffset b) =>
      a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x);

  /// The two selection handles, positioned under the first and last selected
  /// cell. Empty when nothing is selected or the view is not laid out yet.
  List<Widget> _buildHandles() {
    final selection = _controller.selection;
    final state = _viewKey.currentState;
    final stackBox = _stackKey.currentContext?.findRenderObject();
    if (selection == null || state == null || stackBox is! RenderBox) {
      return const <Widget>[];
    }
    try {
      final render = state.renderTerminal;
      var begin = selection.begin;
      var end = selection.end;
      if (_compare(begin, end) > 0) {
        final swap = begin;
        begin = end;
        end = swap;
      }
      final cellHeight = render.getOffset(CellOffset(0, 1)).dy -
          render.getOffset(CellOffset(0, 0)).dy;
      Offset toStack(Offset local) =>
          stackBox.globalToLocal(render.localToGlobal(local));
      final startPoint = toStack(render.getOffset(begin));
      final endPoint = toStack(render.getOffset(end));
      return [
        _handle(startPoint.translate(0, cellHeight), true, cellHeight),
        _handle(endPoint.translate(0, cellHeight), false, cellHeight),
      ];
    } catch (_) {
      return const <Widget>[];
    }
  }

  Widget _handle(Offset anchor, bool isStart, double cellHeight) {
    const size = 44.0;
    return Positioned(
      left: anchor.dx - size / 2,
      top: anchor.dy - 6,
      width: size,
      height: size,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanUpdate: (details) =>
            _dragHandle(isStart, details.globalPosition, cellHeight),
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ),
    );
  }

  void _dragHandle(bool isStart, Offset global, double cellHeight) {
    final state = _viewKey.currentState;
    final selection = _controller.selection;
    if (state == null || selection == null) return;
    try {
      final render = state.renderTerminal;
      // The finger sits below the handle; aim at the line the handle points to.
      final local = render.globalToLocal(global.translate(0, -cellHeight * 1.2));
      final cell = render.getCellOffset(local);
      var begin = selection.begin;
      var end = selection.end;
      if (_compare(begin, end) > 0) {
        final swap = begin;
        begin = end;
        end = swap;
      }
      if (isStart) {
        begin = cell;
        if (_compare(begin, end) >= 0) {
          end = CellOffset(begin.x + 1, begin.y);
        }
      } else {
        end = CellOffset(cell.x + 1, cell.y);
        if (_compare(end, begin) <= 0) {
          begin = CellOffset(end.x > 1 ? end.x - 1 : 0, end.y);
        }
      }
      final buffer = widget.terminal.buffer;
      _controller.setSelection(
        buffer.createAnchorFromOffset(begin),
        buffer.createAnchorFromOffset(end),
      );
    } catch (_) {
      return;
    }
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
            key: _stackKey,
            fit: StackFit.expand,
            children: [
              TerminalView(
                widget.terminal,
                key: _viewKey,
                controller: _controller,
                scrollController: _scroll,
                autofocus: true,
                deleteDetection: true,
                textStyle: TerminalStyle(fontSize: _fontSize),
                padding: const EdgeInsets.all(6),
              ),
              if (_controller.selection != null) ..._buildHandles(),
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
