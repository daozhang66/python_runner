import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class SceneView extends StatelessWidget {
  final List<dynamic> frameCommands;
  final Size canvasSize;
  final void Function(String touchJson) onTouch;

  const SceneView({
    super.key,
    required this.frameCommands,
    required this.canvasSize,
    required this.onTouch,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (details) => _sendTouch('began', details.localPosition),
      onTapUp: (details) => _sendTouch('ended', details.localPosition),
      onPanStart: (details) => _sendTouch('began', details.localPosition),
      onPanUpdate: (details) => _sendTouch('moved', details.localPosition),
      onPanEnd: (_) => _sendTouch('ended', Offset.zero),
      child: ClipRect(
        child: CustomPaint(
          size: canvasSize,
          painter: _SceneFramePainter(frameCommands, canvasSize),
        ),
      ),
    );
  }

  void _sendTouch(String type, Offset position) {
    final flippedY = canvasSize.height - position.dy;
    onTouch(jsonEncode({
      'type': type,
      'x': position.dx,
      'y': flippedY,
      'id': 0,
    }));
  }
}

class _SceneFramePainter extends CustomPainter {
  final List<dynamic> commands;
  final Size canvasSize;

  _SceneFramePainter(this.commands, this.canvasSize);

  @override
  void paint(Canvas canvas, Size size) {
    // Flip Y axis: origin at bottom-left (Pythonista convention)
    canvas.save();
    canvas.translate(0, size.height);
    canvas.scale(1, -1);

    for (final cmd in commands) {
      if (cmd is! Map) continue;
      final c = cmd['c'] as String? ?? '';
      switch (c) {
        case 'bg':
          _drawBackground(canvas, size, cmd);
          break;
        case 'r':
          _drawRect(canvas, cmd);
          break;
        case 'e':
          _drawEllipse(canvas, cmd);
          break;
        case 'l':
          _drawLine(canvas, cmd);
          break;
        case 't':
          _drawText(canvas, size, cmd);
          break;
      }
    }

    canvas.restore();
  }

  Color _colorFromList(List fl) {
    final r = ((fl[0] as num) * 255).round().clamp(0, 255);
    final g = ((fl[1] as num) * 255).round().clamp(0, 255);
    final b = ((fl[2] as num) * 255).round().clamp(0, 255);
    final a = fl.length > 3 ? (fl[3] as num).toDouble() : 1.0;
    return Color.fromRGBO(r, g, b, a);
  }

  void _drawBackground(Canvas canvas, Size size, Map cmd) {
    final r = ((cmd['r'] as num) * 255).round().clamp(0, 255);
    final g = ((cmd['g'] as num) * 255).round().clamp(0, 255);
    final b = ((cmd['b'] as num) * 255).round().clamp(0, 255);
    final paint = Paint()..color = Color.fromRGBO(r, g, b, 1.0);
    canvas.drawRect(Offset.zero & size, paint);
  }

  void _drawRect(Canvas canvas, Map cmd) {
    final rect = Rect.fromLTWH(
      (cmd['x'] as num).toDouble(),
      (cmd['y'] as num).toDouble(),
      (cmd['w'] as num).toDouble(),
      (cmd['h'] as num).toDouble(),
    );
    if (cmd['fl'] != null) {
      final paint = Paint()
        ..color = _colorFromList(cmd['fl'] as List)
        ..style = PaintingStyle.fill;
      canvas.drawRect(rect, paint);
    }
    if (cmd['sk'] != null) {
      final paint = Paint()
        ..color = _colorFromList(cmd['sk'] as List)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (cmd['sw'] as num?)?.toDouble() ?? 1.0;
      canvas.drawRect(rect, paint);
    }
  }

  void _drawEllipse(Canvas canvas, Map cmd) {
    final rect = Rect.fromLTWH(
      (cmd['x'] as num).toDouble(),
      (cmd['y'] as num).toDouble(),
      (cmd['w'] as num).toDouble(),
      (cmd['h'] as num).toDouble(),
    );
    if (cmd['fl'] != null) {
      final paint = Paint()
        ..color = _colorFromList(cmd['fl'] as List)
        ..style = PaintingStyle.fill;
      canvas.drawOval(rect, paint);
    }
    if (cmd['sk'] != null) {
      final paint = Paint()
        ..color = _colorFromList(cmd['sk'] as List)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (cmd['sw'] as num?)?.toDouble() ?? 1.0;
      canvas.drawOval(rect, paint);
    }
  }

  void _drawLine(Canvas canvas, Map cmd) {
    final p1 = Offset(
      (cmd['x1'] as num).toDouble(),
      (cmd['y1'] as num).toDouble(),
    );
    final p2 = Offset(
      (cmd['x2'] as num).toDouble(),
      (cmd['y2'] as num).toDouble(),
    );
    final sk = cmd['sk'] as List?;
    final color = sk != null ? _colorFromList(sk) : const Color.fromRGBO(255, 255, 255, 1);
    final paint = Paint()
      ..color = color
      ..strokeWidth = (cmd['sw'] as num?)?.toDouble() ?? 1.0;
    canvas.drawLine(p1, p2, paint);
  }

  void _drawText(Canvas canvas, Size size, Map cmd) {
    // Text needs un-flipped Y axis for correct rendering
    canvas.save();
    canvas.scale(1, -1);

    final fontSize = (cmd['z'] as num?)?.toDouble() ?? 16.0;
    final x = (cmd['x'] as num).toDouble();
    // Convert from bottom-left y to top-left y (we're in flipped space)
    final y = -(cmd['y'] as num).toDouble();

    final fl = cmd['fl'] as List?;
    final color = fl != null ? _colorFromList(fl) : Colors.white;

    final textStyle = TextStyle(
      fontSize: fontSize,
      color: color,
      fontFamily: _mapFont(cmd['f'] as String? ?? 'Helvetica'),
    );
    final textSpan = TextSpan(text: cmd['s'] as String? ?? '', style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: ui.TextDirection.ltr,
    );
    textPainter.layout();

    final alignment = (cmd['a'] as num?)?.toInt() ?? 5;
    double dx = x;
    double dy = y;
    if (alignment == 5) {
      // Center alignment
      dx -= textPainter.width / 2;
      dy -= textPainter.height / 2;
    }

    textPainter.paint(canvas, Offset(dx, dy));
    canvas.restore();
  }

  String _mapFont(String fontName) {
    // Map common Pythonista font names to available system fonts
    final lower = fontName.toLowerCase();
    if (lower.contains('arial') || lower.contains('helvetica')) {
      return 'sans-serif';
    }
    if (lower.contains('courier') || lower.contains('mono')) {
      return 'monospace';
    }
    if (lower.contains('times')) {
      return 'serif';
    }
    return 'sans-serif';
  }

  @override
  bool shouldRepaint(covariant _SceneFramePainter oldDelegate) {
    return !identical(commands, oldDelegate.commands);
  }
}
