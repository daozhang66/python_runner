import 'package:flutter/material.dart';

/// Parses ANSI escape codes in text and returns colored TextSpans.
enum AnsiPalette { dark, light, monochrome }

class AnsiParser {
  static final _ansiRegex =
      RegExp(r'\x1B\[(?:[0-9;]*[A-Za-z]|[0-9;]*[ -/]*[@-~])'
          r'|\x1B[@-_]'
          r'|\x1B\[[0-9;:]*m');

  static const Map<int, Color> _fgColors = {
    30: Color(0xFF555555), // black
    31: Color(0xFFE05050), // red
    32: Color(0xFF50E050), // green
    33: Color(0xFFE0E050), // yellow
    34: Color(0xFF5090E0), // blue
    35: Color(0xFFE050E0), // magenta
    36: Color(0xFF50E0E0), // cyan
    37: Color(0xFFCCCCCC), // white
    90: Color(0xFF808080), // bright black (gray)
    91: Color(0xFFFF6B6B), // bright red
    92: Color(0xFF69FF94), // bright green
    93: Color(0xFFFFFF69), // bright yellow
    94: Color(0xFF69AAFF), // bright blue
    95: Color(0xFFFF69FF), // bright magenta
    96: Color(0xFF69FFFF), // bright cyan
    97: Color(0xFFFFFFFF), // bright white
  };

  static const Map<int, Color> _lightFgColors = {
    30: Color(0xFF1F2937), // black
    31: Color(0xFFB91C1C), // red
    32: Color(0xFF15803D), // green
    33: Color(0xFFA16207), // yellow
    34: Color(0xFF1D4ED8), // blue
    35: Color(0xFF9333EA), // magenta
    36: Color(0xFF0E7490), // cyan
    37: Color(0xFF374151), // white
    90: Color(0xFF6B7280), // bright black (gray)
    91: Color(0xFFDC2626), // bright red
    92: Color(0xFF16A34A), // bright green
    93: Color(0xFF854D0E), // bright yellow
    94: Color(0xFF2563EB), // bright blue
    95: Color(0xFFC026D3), // bright magenta
    96: Color(0xFF0891B2), // bright cyan
    97: Color(0xFF111827), // bright white
  };

  static const Map<int, Color> _bgColors = {
    40: Color(0xFF555555),
    41: Color(0xFFE05050),
    42: Color(0xFF50E050),
    43: Color(0xFFE0E050),
    44: Color(0xFF5090E0),
    45: Color(0xFFE050E0),
    46: Color(0xFF50E0E0),
    47: Color(0xFFCCCCCC),
    100: Color(0xFF808080),
    101: Color(0xFFFF6B6B),
    102: Color(0xFF69FF94),
    103: Color(0xFFFFFF69),
    104: Color(0xFF69AAFF),
    105: Color(0xFFFF69FF),
    106: Color(0xFF69FFFF),
    107: Color(0xFFFFFFFF),
  };

  static const Map<int, Color> _lightBgColors = {
    40: Color(0xFFE5E7EB),
    41: Color(0xFFFEE2E2),
    42: Color(0xFFDCFCE7),
    43: Color(0xFFFEF3C7),
    44: Color(0xFFDBEAFE),
    45: Color(0xFFF3E8FF),
    46: Color(0xFFCFFAFE),
    47: Color(0xFFF9FAFB),
    100: Color(0xFFD1D5DB),
    101: Color(0xFFFCA5A5),
    102: Color(0xFFBBF7D0),
    103: Color(0xFFFDE68A),
    104: Color(0xFFBFDBFE),
    105: Color(0xFFE9D5FF),
    106: Color(0xFFA5F3FC),
    107: Color(0xFFFFFFFF),
  };

  /// Parse [text] containing ANSI codes into a list of [TextSpan].
  static List<TextSpan> parse(String text,
      {Color defaultColor = Colors.white,
      AnsiPalette palette = AnsiPalette.dark}) {
    if (!text.contains('\x1b')) {
      return [TextSpan(text: text, style: TextStyle(color: defaultColor))];
    }

    final useAnsiColors = palette != AnsiPalette.monochrome;
    final fgColors = palette == AnsiPalette.light ? _lightFgColors : _fgColors;
    final bgColors = palette == AnsiPalette.light ? _lightBgColors : _bgColors;

    final spans = <TextSpan>[];
    Color currentColor = defaultColor;
    Color? currentBgColor;
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
              backgroundColor: currentBgColor,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ));
        }
      }

      final escape = match.group(0) ?? '';
      if (escape.startsWith('\x1b[') && escape.endsWith('m')) {
        final codeStr = escape.substring(2, escape.length - 1);
        final codes = codeStr.split(';');
        int i = 0;
        while (i < codes.length) {
          final code = int.tryParse(codes[i]) ?? 0;
          if (code == 0) {
            currentColor = defaultColor;
            currentBgColor = null;
            bold = false;
          } else if (code == 1) {
            bold = true;
          } else if (fgColors.containsKey(code)) {
            if (useAnsiColors) currentColor = fgColors[code]!;
          } else if (bgColors.containsKey(code)) {
            if (useAnsiColors) currentBgColor = bgColors[code]!;
          } else if (code == 38 && i + 1 < codes.length) {
            final sub = int.tryParse(codes[i + 1]) ?? 0;
            if (sub == 5 && i + 2 < codes.length) {
              // 256-color: ESC[38;5;Nm
              if (useAnsiColors) {
                currentColor = _color256(
                  int.tryParse(codes[i + 2]) ?? 0,
                  palette: palette,
                );
              }
              i += 2;
            } else if (sub == 2 && i + 4 < codes.length) {
              // RGB: ESC[38;2;R;G;Bm
              if (useAnsiColors) {
                currentColor = Color.fromARGB(
                  255,
                  int.tryParse(codes[i + 2]) ?? 0,
                  int.tryParse(codes[i + 3]) ?? 0,
                  int.tryParse(codes[i + 4]) ?? 0,
                );
              }
              i += 4;
            }
          } else if (code == 48 && i + 1 < codes.length) {
            final sub = int.tryParse(codes[i + 1]) ?? 0;
            if (sub == 5 && i + 2 < codes.length) {
              if (useAnsiColors) {
                currentBgColor = _color256(
                  int.tryParse(codes[i + 2]) ?? 0,
                  palette: palette,
                );
              }
              i += 2;
            } else if (sub == 2 && i + 4 < codes.length) {
              if (useAnsiColors) {
                currentBgColor = Color.fromARGB(
                  255,
                  int.tryParse(codes[i + 2]) ?? 0,
                  int.tryParse(codes[i + 3]) ?? 0,
                  int.tryParse(codes[i + 4]) ?? 0,
                );
              }
              i += 4;
            }
          } else if (code == 39) {
            currentColor = defaultColor;
          } else if (code == 49) {
            currentBgColor = null;
          }
          i++;
        }
      }

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: TextStyle(
          color: currentColor,
          backgroundColor: currentBgColor,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ));
    }

    return spans.isEmpty
        ? [TextSpan(text: text, style: TextStyle(color: defaultColor))]
        : spans;
  }

  /// Map a 256-color index to a Flutter Color.
  static Color _color256(int n, {AnsiPalette palette = AnsiPalette.dark}) {
    if (n < 0 || n > 255) return const Color(0xFFCCCCCC);
    final fgColors = palette == AnsiPalette.light ? _lightFgColors : _fgColors;
    // 0-7: standard colors
    if (n < 8) return fgColors[30 + n] ?? const Color(0xFFCCCCCC);
    // 8-15: bright colors
    if (n < 16) return fgColors[82 + n] ?? const Color(0xFFCCCCCC);
    // 16-231: 6x6x6 color cube
    if (n < 232) {
      final v = n - 16;
      final b = v % 6;
      final g = (v ~/ 6) % 6;
      final r = v ~/ 36;
      return Color.fromARGB(255, _cubeValue(r), _cubeValue(g), _cubeValue(b));
    }
    // 232-255: grayscale ramp
    final gray = 8 + (n - 232) * 10;
    return Color.fromARGB(255, gray, gray, gray);
  }

  static int _cubeValue(int v) {
    const levels = [0, 95, 135, 175, 215, 255];
    return levels[v.clamp(0, 5)];
  }

  /// Strip all ANSI escape codes, returning plain text.
  static String strip(String text) {
    return text.replaceAll(_ansiRegex, '');
  }
}
