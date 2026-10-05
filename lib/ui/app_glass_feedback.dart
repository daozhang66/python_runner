import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Carries press state without notifying widgets on every animation tick.
class AppGlassFeedbackScope extends InheritedWidget {
  const AppGlassFeedbackScope({
    super.key,
    required this.animation,
    required this.point,
    required this.enabled,
    required this.shape,
    required super.child,
  });
  final Animation<double>? animation;
  final Offset point;
  final bool enabled;
  final ShapeBorder? shape;
  static AppGlassFeedbackScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppGlassFeedbackScope>();
  @override
  bool updateShouldNotify(AppGlassFeedbackScope oldWidget) =>
      animation != oldWidget.animation ||
      point != oldWidget.point ||
      enabled != oldWidget.enabled ||
      shape != oldWidget.shape;
}

/// Keep feedback inside the glass's excluded content, not in the captured
/// background. Paint ticks never rebuild or repaint the retained child.
class AppGlassFeedbackLayer extends StatelessWidget {
  const AppGlassFeedbackLayer({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final scope = AppGlassFeedbackScope.maybeOf(context);
    return CustomPaint(
      key: const ValueKey('glass-press-feedback'),
      foregroundPainter: scope?.enabled == true && scope!.animation != null
          ? _GlassRipplePainter(
              point: scope.point,
              animation: scope.animation!,
              color: Theme.of(context).colorScheme.primary,
              shape: scope.shape,
              direction: Directionality.of(context),
            )
          : null,
      child: RepaintBoundary(
        child: AppGlassFeedbackScope(
          animation: null,
          point: Offset.zero,
          enabled: false,
          shape: null,
          child: child,
        ),
      ),
    );
  }
}

/// A viscous touch wave, in the spirit of g1455's GlassRipple: a dimple under
/// the finger and one traveling front that fades as it crosses the surface.
/// It repaints only during the gesture and needs no backdrop capture.
class _GlassRipplePainter extends CustomPainter {
  _GlassRipplePainter({
    required this.point,
    required this.animation,
    required this.color,
    required this.shape,
    required this.direction,
  }) : super(repaint: animation);
  final Offset point;
  final Animation<double> animation;
  final Color color;
  final ShapeBorder? shape;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || animation.value <= 0.001) return;
    final progress = Curves.easeOutCubic.transform(animation.value);
    final bounds = Offset.zero & size;
    canvas.save();
    if (shape != null) {
      canvas.clipPath(shape!.getOuterPath(bounds, textDirection: direction));
    } else {
      canvas.clipRect(bounds);
    }
    final reach = math.max(size.width, size.height) * 0.9;
    final radius = math.max(reach * progress, 2.0);

    final dimple = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.16 * (1 - progress)),
          color.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: point, radius: radius * 0.55));
    canvas.drawRect(bounds, dimple);

    final front = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.6 * (1 - progress), 0.6)
      ..color = Colors.white.withValues(alpha: 0.55 * (1 - progress))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8);
    canvas.drawCircle(point, radius, front);

    final echo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.1 * (1 - progress), 0.4)
      ..color = color.withValues(alpha: 0.30 * (1 - progress));
    canvas.drawCircle(point, radius * 0.72, echo);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlassRipplePainter oldDelegate) =>
      point != oldDelegate.point ||
      animation != oldDelegate.animation ||
      color != oldDelegate.color ||
      shape != oldDelegate.shape ||
      direction != oldDelegate.direction;
}
