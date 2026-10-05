import 'package:flutter/material.dart';
import 'package:g1455/g1455.dart' as glass;

import 'app_glass_press.dart';
import 'app_glass_feedback.dart';

/// A paint-only layer over each button's own fill, including tonal/disabled
/// variants. Widget states also cover keyboard activation and accessibility.
Widget appGlassButtonBackground(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child,
) {
  // This is the button's own element; its Material descendants do not exist
  // yet. An ancestor lookup would read the surrounding card instead.
  final button = context.widget is ButtonStyleButton
      ? context.widget as ButtonStyleButton
      : null;
  // The layer callback must preserve the owning button's primary/tonal/icon
  // defaults. Flutter exposes no resolved-style argument to this callback.
  // These read-only methods are verified by the pinned SDK integration tests.
  // ignore: invalid_use_of_protected_member
  final defaults = button?.defaultStyleOf(context);
  // ignore: invalid_use_of_protected_member
  final themed = button?.themeStyleOf(context);
  final shape =
      button?.style?.shape?.resolve(states) ??
      themed?.shape?.resolve(states) ??
      defaults?.shape?.resolve(states) ??
      const StadiumBorder();
  final base =
      button?.style?.backgroundColor?.resolve(states) ??
      defaults?.backgroundColor?.resolve(states);
  if (glass.GlassScope.maybeOf(context) == null) {
    return DecoratedBox(
      decoration: ShapeDecoration(shape: shape, color: base),
      child: _GlassButtonLayer(states: states, child: child),
    );
  }
  final colors = Theme.of(context).colorScheme;
  final radius = shape is RoundedRectangleBorder
      ? shape.borderRadius.resolve(Directionality.of(context))
      : const BorderRadius.all(Radius.circular(999));
  final disabled = states.contains(WidgetState.disabled);
  final contrast = MediaQuery.highContrastOf(context);
  final finish = glass.GlassFinish.regular(
    appearance: Theme.of(context).brightness,
    backdrop: colors.surface,
  );
  final effective = base == null || base.a == 0
      ? finish.copyWith(optics: glass.kGlassDropOptics)
      : finish.copyWith(
          tint: base.withValues(alpha: disabled ? 0.12 : 0.86),
          // Compact buttons need the gentler optics used by g1455's control drops.
          optics: glass.kGlassDropOptics,
        );
  return AppGlassPress(
    feedbackInsideSurface: true,
    enabled: !disabled,
    scaleOnPress: false,
    clipShape: shape,
    child: glass.GlassSurface(
      borderRadius: radius,
      finish: effective,
      // Keep Material's primary/tonal label colors and disabled semantics.
      labelled: false,
      ripple: disabled || contrast
          ? null
          : const glass.GlassRipple(amplitude: 4.5),
      child: AppGlassFeedbackLayer(
        child: CustomPaint(
          painter: states.contains(WidgetState.pressed) && !disabled
              ? _GlassHeldLight(shape, Directionality.of(context))
              : null,
          child: child,
        ),
      ),
    ),
  );
}

class _GlassHeldLight extends CustomPainter {
  const _GlassHeldLight(this.shape, this.direction);
  final ShapeBorder shape;
  final TextDirection direction;
  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    shape.getOuterPath(Offset.zero & size, textDirection: direction),
    Paint()
      ..color = const Color(0x18ffffff)
      ..blendMode = BlendMode.plus,
  );
  @override
  bool shouldRepaint(_GlassHeldLight oldDelegate) =>
      shape != oldDelegate.shape || direction != oldDelegate.direction;
}

Widget appGlassButtonForeground(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child,
) {
  final reduced = MediaQuery.disableAnimationsOf(context);
  return AnimatedScale(
    scale: !reduced && states.contains(WidgetState.pressed) ? 0.96 : 1,
    duration: reduced ? Duration.zero : const Duration(milliseconds: 160),
    curve: Curves.easeOutCubic,
    child: child,
  );
}

class _GlassButtonLayer extends StatelessWidget {
  const _GlassButtonLayer({required this.states, required this.child});
  final Set<WidgetState> states;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final disabled = states.contains(WidgetState.disabled);
    final contrast = MediaQuery.highContrastOf(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shape =
        context.findAncestorWidgetOfExactType<Material>()?.shape ??
        const StadiumBorder();
    return TweenAnimationBuilder<double>(
      tween: Tween(end: states.contains(WidgetState.pressed) ? 1 : 0),
      duration: reduced ? Duration.zero : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (_, pressure, child) => CustomPaint(
        painter: disabled || contrast
            ? null
            : _ButtonSheen(
                dark: dark,
                pressure: pressure,
                shape: shape,
                textDirection: Directionality.of(context),
              ),
        child: child,
      ),
      child: child,
    );
  }
}

class _ButtonSheen extends CustomPainter {
  const _ButtonSheen({
    required this.dark,
    required this.pressure,
    required this.shape,
    required this.textDirection,
  });
  final bool dark;
  final double pressure;
  final ShapeBorder shape;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    // FilledButton and IconButton explicitly default to Clip.none. Paint the
    // resolved shape itself so their corners never reveal a rectangular sheen.
    canvas.drawPath(
      shape.getOuterPath(bounds, textDirection: textDirection),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment(-0.8 + pressure, -1),
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(
              alpha: (dark ? 0.12 : 0.23) + pressure * 0.08,
            ),
            Colors.white.withValues(alpha: 0.02),
            Colors.white.withValues(alpha: 0.07 + pressure * 0.04),
          ],
        ).createShader(bounds),
    );
    canvas.drawPath(
      shape.getOuterPath(bounds.deflate(0.75), textDirection: textDirection),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.75
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: dark ? 0.24 : 0.5),
            Colors.white.withValues(alpha: 0.02),
          ],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_ButtonSheen oldDelegate) =>
      dark != oldDelegate.dark ||
      pressure != oldDelegate.pressure ||
      shape != oldDelegate.shape ||
      textDirection != oldDelegate.textDirection;
}
