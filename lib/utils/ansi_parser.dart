import 'package:flutter/material.dart';

/// Parses ANSI escape codes in text and returns colored TextSpans.
class AnsiParser {
  static final _ansiRegex = RegExp(r'\x1b\[([0-9;]*)m');

  static const Map<int, Color> _colors = {
    // Standard colors
    30: Color(0xFF555555), // black
    31: Color(0xFFE05050), // red
    32: Color(0xFF50E050), // green
    33: Color(0xFFE0E050), // yellow
    34: Color(0xFF5090E0), // blue
    35: Color(0xFFE050E0), // magenta
    36: Color(0xFF50E0E0), // cyan
    37: Color(0xFFCCCCCC), // white
    // Bright colors
    90: Color(0xFF808080), // bright black (gray)
    91: Color(0xFFFF6B6B), // bright red
    92: Color(0xFF69FF94), // bright green
    93: Color(0xFFFFFF69), // bright yellow
    94: Color(0xFF69AAFF), // bright blue
    95: Color(0xFFFF69FF), // bright magenta
    96: Color(0xFF69FFFF), // bright cyan
    97: Color(0xFFFFFFFF), // bright white
  };

  /// Parse [text] containing ANSI codes into a list of [TextSpan].
  static List<TextSpan> parse(String text, {Color defaultColor = Colors.white}) {
    if (!text.contains('\x1b[')) {
      return [TextSpan(text: text, style: TextStyle(color: defaultColor))];
    }

    final spans = <TextSpan>[];
    Color currentColor = defaultColor;
    bool bold = false;
    int lastEnd = 0;

    for (final match in _ansiRegex.allMatches(text)) {
      if (match.start > lastEnd) {
        final segment = text.substring(lastEnd, match.start);
        if (segment.isNotEmpty) {
          spans.add(TextSpan(
            text: segment,
            style: TextStyle(
              color: currentColor,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ));
        }
      }

      final codes = match.group(1)?.split(';') ?? [];
      for (final codeStr in codes) {
        final code = int.tryParse(codeStr) ?? 0;
        if (code == 0) {
          currentColor = defaultColor;
          bold = false;
        } else if (code == 1) {
          bold = true;
        } else if (_colors.containsKey(code)) {
          currentColor = _colors[code]!;
        }
      }

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: TextStyle(
          color: currentColor,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ));
    }

    return spans.isEmpty
        ? [TextSpan(text: text, style: TextStyle(color: defaultColor))]
        : spans;
  }

  /// Strip all ANSI escape codes, returning plain text.
  static String strip(String text) {
    return text.replaceAll(_ansiRegex, '');
  }
}
