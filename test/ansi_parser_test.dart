import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:python_runner/utils/ansi_parser.dart';

void main() {
  test('AnsiParser strips non-color terminal control sequences', () {
    const text = '\x1b[H\x1b[2J\x1b[3J请选择平台:';

    expect(AnsiParser.strip(text), '请选择平台:');

    final spans = AnsiParser.parse(text, defaultColor: Colors.white);
    expect(spans.length, 1);
    expect(spans.first.text, '请选择平台:');
  });

  test('AnsiParser still preserves SGR color text segments', () {
    const text = 'A\x1b[31mB\x1b[0mC';

    final spans = AnsiParser.parse(text, defaultColor: Colors.white);
    final rendered = spans.map((span) => span.text ?? '').join();

    expect(rendered, 'ABC');
    expect(AnsiParser.strip(text), 'ABC');
  });
}
