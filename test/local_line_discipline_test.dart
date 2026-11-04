import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/ssh/application/local_line_discipline.dart';

class _Harness {
  final StringBuffer echoed = StringBuffer();
  final List<String> sent = <String>[];
  int interrupts = 0;
  int eofs = 0;

  late final LineDiscipline line = LineDiscipline(
    echo: echoed.write,
    sendLine: sent.add,
    onInterrupt: () => interrupts++,
    onEof: () => eofs++,
  );
}

void main() {
  test('echoes typed text and sends the line on Enter', () {
    final h = _Harness();
    h.line.feed('ls -l\r');
    expect(h.sent, ['ls -l']);
    expect(h.echoed.toString(), 'ls -l\r\n');
  });

  test('CRLF and a pasted multi-line block each send every line once', () {
    final h = _Harness();
    h.line.feed('a\r\nb\nc\r');
    expect(h.sent, ['a', 'b', 'c']);
  });

  test('backspace edits both the echo and the line', () {
    final h = _Harness();
    h.line.feed('ab\x7fc\r');
    expect(h.sent, ['ac']);
    expect(h.echoed.toString(), 'ab\b \bc\r\n');
  });

  test('wide characters erase two cells', () {
    final h = _Harness();
    h.line.feed('你\x7f');
    expect(h.echoed.toString(), '你\b \b\b \b');
    expect(h.line.buffer, isEmpty);
  });

  test('up arrow recalls earlier lines', () {
    final h = _Harness();
    h.line.feed('one\r');
    h.line.feed('two\r');
    h.line.feed('\x1b[A\x1b[A\r');
    expect(h.sent, ['one', 'two', 'one']);
  });

  test('down arrow returns to the line being typed', () {
    final h = _Harness();
    h.line.feed('one\r');
    h.line.feed('dra');
    h.line.feed('\x1b[A');
    expect(h.line.buffer, 'one');
    h.line.feed('\x1b[B');
    expect(h.line.buffer, 'dra');
  });

  test('Ctrl+C drops the line and reports an interrupt', () {
    final h = _Harness();
    h.line.feed('abc\x03');
    expect(h.interrupts, 1);
    h.line.feed('x\r');
    expect(h.sent, ['x']);
  });

  test('Ctrl+D only reports EOF on an empty line', () {
    final h = _Harness();
    h.line.feed('a\x04');
    expect(h.eofs, 0);
    h.line.feed('\x15\x04');
    expect(h.eofs, 1);
  });

  test('unknown escape sequences are swallowed', () {
    final h = _Harness();
    h.line.feed('a\x1b[3~b\r');
    expect(h.sent, ['ab']);
  });
}
