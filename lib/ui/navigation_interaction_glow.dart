import 'package:flutter/material.dart';

/// A soft contact light (or tint on pale tracks), before labels and refraction.
/// The lens therefore samples the lit surface without washing out its glyphs.
class NavigationInteractionGlow extends CustomPainter {
  const NavigationInteractionGlow({
    required this.lens,
    required this.intensity,
    required this.color,
    this.dark = true,
  });

  final Rect lens;
  final double intensity;
  final Color color;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0 || size.isEmpty) return;
    final bounds = Offset.zero & size;
    final track = const StadiumBorder().getOuterPath(bounds.deflate(0.5));
    final center = lens.center.translate(0, -size.height * 0.10);
    final radius = (lens.width * 1.15).clamp(88.0, 144.0);
    final strength = intensity.clamp(0.0, 1.0);
    final lightBounds = Rect.fromCircle(center: center, radius: radius);
    canvas.save();
    canvas.clipPath(track);
    canvas.drawRect(
        bounds,
        Paint()
          ..shader = RadialGradient(colors: [
            color.withValues(alpha: (dark ? 0.22 : 0.04) * strength),
            color.withValues(alpha: (dark ? 0.13 : 0.02) * strength),
            color.withValues(alpha: 0),
          ], stops: const [
            0,
            0.38,
            1
          ]).createShader(lightBounds));
    // Only the nearby part of the track rim catches the contact light.
    canvas.drawPath(
        track,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..shader = RadialGradient(colors: [
            (dark ? Colors.white : color)
                .withValues(alpha: (dark ? 0.68 : 0.09) * strength),
            color.withValues(alpha: 0),
          ]).createShader(lightBounds));
    canvas.restore();
  }

  @override
  bool shouldRepaint(NavigationInteractionGlow oldDelegate) =>
      lens != oldDelegate.lens ||
      intensity != oldDelegate.intensity ||
      color != oldDelegate.color ||
      dark != oldDelegate.dark;
}
