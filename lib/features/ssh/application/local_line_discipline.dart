/// Minimal line editing for a shell that is not attached to a pseudo terminal.
///
/// Without a PTY nobody echoes what the user types, so this class does it:
/// printable characters are echoed and collected, Backspace edits the line,
/// Enter sends the line, Up / Down walk through the history, Ctrl+C / Ctrl+D
/// are reported to the owner and other escape sequences are swallowed.
library;

class LineDiscipline {
  LineDiscipline({
    required this.echo,
    required this.sendLine,
    required this.onInterrupt,
    required this.onEof,
  });

  final void Function(String text) echo;
  final void Function(String line) sendLine;
  final void Function() onInterrupt;
  final void Function() onEof;

  final List<String> _history = <String>[];
  int _historyIndex = 0;
  String _buffer = '';
  String _draft = '';

  /// The line typed so far.
  String get buffer => _buffer;

  /// Feeds [data] as produced by the terminal widget (keys, paste, escapes).
  void feed(String data) {
    final runes = data.runes.toList();
    var i = 0;
    while (i < runes.length) {
      final rune = runes[i];
      if (rune == 0x1b) {
        i = _skipEscape(runes, i);
        continue;
      }
      i++;
      switch (rune) {
        case 0x0d:
          if (i < runes.length && runes[i] == 0x0a) i++;
          _enter();
        case 0x0a:
          _enter();
        case 0x7f:
        case 0x08:
          _backspace();
        case 0x03:
          _interrupt();
        case 0x04:
          if (_buffer.isEmpty) onEof();
        case 0x15:
          _clearLine();
        default:
          if (rune >= 0x20) _insert(String.fromCharCode(rune));
      }
    }
  }

  /// Handles `ESC [ A` / `ESC O A` (history) and skips every other sequence.
  int _skipEscape(List<int> runes, int start) {
    var i = start + 1;
    if (i >= runes.length) return i;
    final lead = runes[i];
    if (lead != 0x5b && lead != 0x4f) return i + 1;
    i++;
    while (i < runes.length && !(runes[i] >= 0x40 && runes[i] <= 0x7e)) {
      i++;
    }
    if (i >= runes.length) return i;
    final finalByte = runes[i];
    if (finalByte == 0x41) {
      _historyPrevious();
    } else if (finalByte == 0x42) {
      _historyNext();
    }
    return i + 1;
  }

  void _insert(String char) {
    _buffer += char;
    echo(char);
  }

  void _backspace() {
    if (_buffer.isEmpty) return;
    final runes = _buffer.runes.toList();
    final removed = runes.removeLast();
    _buffer = String.fromCharCodes(runes);
    echo(_erase(_cellWidth(removed)));
  }

  void _enter() {
    echo('\r\n');
    final line = _buffer;
    _buffer = '';
    if (line.trim().isNotEmpty && (_history.isEmpty || _history.last != line)) {
      _history.add(line);
    }
    _historyIndex = _history.length;
    _draft = '';
    sendLine(line);
  }

  void _interrupt() {
    echo('^C\r\n');
    _buffer = '';
    _draft = '';
    _historyIndex = _history.length;
    onInterrupt();
  }

  void _clearLine() {
    echo(_erase(_width(_buffer)));
    _buffer = '';
  }

  void _historyPrevious() {
    if (_history.isEmpty || _historyIndex == 0) return;
    if (_historyIndex == _history.length) _draft = _buffer;
    _historyIndex--;
    _replace(_history[_historyIndex]);
  }

  void _historyNext() {
    if (_historyIndex >= _history.length) return;
    _historyIndex++;
    _replace(_historyIndex == _history.length ? _draft : _history[_historyIndex]);
  }

  void _replace(String text) {
    echo(_erase(_width(_buffer)));
    _buffer = text;
    echo(text);
  }

  String _erase(int cells) => List<String>.filled(cells, '\b \b').join();

  int _width(String text) =>
      text.runes.fold<int>(0, (sum, rune) => sum + _cellWidth(rune));

  /// Terminal cells used by [rune]: 2 for CJK / full-width / emoji, else 1.
  int _cellWidth(int rune) {
    final wide = (rune >= 0x1100 && rune <= 0x115f) ||
        (rune >= 0x2e80 && rune <= 0xa4cf) ||
        (rune >= 0xac00 && rune <= 0xd7a3) ||
        (rune >= 0xf900 && rune <= 0xfaff) ||
        (rune >= 0xfe30 && rune <= 0xfe6f) ||
        (rune >= 0xff00 && rune <= 0xff60) ||
        (rune >= 0xffe0 && rune <= 0xffe6) ||
        (rune >= 0x1f300 && rune <= 0x1faff) ||
        (rune >= 0x20000 && rune <= 0x3fffd);
    return wide ? 2 : 1;
  }
}
