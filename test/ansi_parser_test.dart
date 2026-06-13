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

  test('AnsiParser uses a contrast palette for light terminal themes', () {
    const text = '\x1b[33myellow\x1b[0m \x1b[36mcyan\x1b[0m';

    final darkSpans = AnsiParser.parse(
      text,
      defaultColor: Colors.white,
      palette: AnsiPalette.dark,
    );
    final lightSpans = AnsiParser.parse(
      text,
      defaultColor: Colors.black,
      palette: AnsiPalette.light,
    );

    expect(darkSpans.first.style?.color, const Color(0xFFE0E050));
    expect(lightSpans.first.style?.color, const Color(0xFFA16207));
    expect(lightSpans[2].style?.color, const Color(0xFF0E7490));
  });

  test('AnsiParser monochrome mode strips color while preserving text', () {
    const text = 'A\x1b[31mB\x1b[0mC';

    final spans = AnsiParser.parse(
      text,
      defaultColor: Colors.black,
      palette: AnsiPalette.monochrome,
    );

    expect(spans.map((span) => span.text ?? '').join(), 'ABC');
    expect(spans[1].style?.color, Colors.black);
  });
}
