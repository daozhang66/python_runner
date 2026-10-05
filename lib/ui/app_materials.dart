import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:g1455/g1455.dart' as glass;

import 'app_visual_style.dart';
import 'app_glass_feedback.dart';

@immutable
class AppMaterials extends ThemeExtension<AppMaterials> {
  const AppMaterials({
    required this.style,
    required this.control,
    required this.content,
    required this.overlay,
    required this.edge,
    required this.shadow,
    this.pressScale = 0.97,
  });
  factory AppMaterials.fromColors(ColorScheme colors, AppVisualStyle style) {
    final dark = colors.brightness == Brightness.dark;
    return AppMaterials(
      style: style,
      control: Color.alphaBlend(
        colors.primary.withValues(alpha: dark ? 0.04 : 0.03),
        dark ? const Color(0xff222429) : const Color(0xfff3f5fa),
      ),
      content: Color.alphaBlend(
        colors.primary.withValues(alpha: dark ? 0.025 : 0.025),
        dark ? const Color(0xff1d2025) : const Color(0xfff8faff),
      ),
      overlay: dark ? const Color(0xff22262d) : const Color(0xfff8faff),
      edge: dark
          ? Colors.white.withValues(alpha: 0.18)
          : colors.primary.withValues(alpha: 0.16),
      shadow: colors.shadow.withValues(alpha: dark ? 0.14 : 0.06),
    );
  }
  final AppVisualStyle style;
  final Color control, content, overlay, edge, shadow;
  final double pressScale;
  bool get liquid => style == AppVisualStyle.liquid;
  BoxDecoration decoration(
    BuildContext context,
    BorderRadius radius, {
    Color? base,
    bool transparent = false,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final contrast = MediaQuery.highContrastOf(context);
    final surface = base ?? content;
    final alpha = transparent && !contrast ? (dark ? 0.72 : 0.78) : 1.0;
    return BoxDecoration(
      borderRadius: radius,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(
            Colors.white.withValues(
              alpha: contrast
                  ? 0
                  : dark
                  ? 0.045
                  : 0.5,
            ),
            surface,
          ).withValues(alpha: alpha),
          surface.withValues(alpha: alpha),
        ],
      ),
      border: Border.all(
        color: contrast ? Theme.of(context).colorScheme.outline : edge,
      ),
      boxShadow: [
        BoxShadow(color: shadow, blurRadius: 12, offset: const Offset(0, 3)),
      ],
    );
  }

  static AppMaterials of(BuildContext context) =>
      Theme.of(context).extension<AppMaterials>() ??
      AppMaterials.fromColors(
        Theme.of(context).colorScheme,
        AppVisualStyle.classic,
      );
  static bool hasGlassHost(BuildContext context) =>
      glass.GlassScope.maybeOf(context) != null;
  @override
  AppMaterials copyWith({
    AppVisualStyle? style,
    Color? control,
    Color? content,
    Color? overlay,
    Color? edge,
    Color? shadow,
    double? pressScale,
  }) => AppMaterials(
    style: style ?? this.style,
    control: control ?? this.control,
    content: content ?? this.content,
    overlay: overlay ?? this.overlay,
    edge: edge ?? this.edge,
    shadow: shadow ?? this.shadow,
    pressScale: pressScale ?? this.pressScale,
  );
  @override
  AppMaterials lerp(covariant AppMaterials? other, double t) {
    if (other == null) return this;
    return AppMaterials(
      style: t < 0.5 ? style : other.style,
      control: Color.lerp(control, other.control, t)!,
      content: Color.lerp(content, other.content, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      edge: Color.lerp(edge, other.edge, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      pressScale: ui.lerpDouble(pressScale, other.pressScale, t)!,
    );
  }
}

/// Stable wrapper: changing materials never replaces the interactive subtree.
class AppGlassSurface extends StatelessWidget {
  const AppGlassSurface({
    super.key,
    required this.child,
    this.radius = const BorderRadius.all(Radius.circular(20)),
    this.overlay = false,
    this.baseColor,
    this.sampleBackdrop = false,
    this.opaque = false,
    this.interactive = false,
    this.materialize = 1,
    this.cardSurface = false,
    this.borderColor,
    this.classicDecoration,
    this.enabled,
  });
  final Widget child;
  final BorderRadius radius;
  final bool overlay, sampleBackdrop;
  final bool opaque, interactive;
  final double materialize;
  final bool cardSurface;
  final Color? borderColor;
  final Color? baseColor;
  final bool? enabled;
  final Decoration? classicDecoration;
  @override
  Widget build(BuildContext context) {
    final material = AppMaterials.of(context);
    final active = enabled ?? material.liquid;
    final nested =
        context.dependOnInheritedWidgetOfExactType<_GlassScope>()?.active ??
        false;
    final contrast = MediaQuery.highContrastOf(context);
    final native =
        active && !opaque && glass.GlassScope.maybeOf(context) != null;
    final finish = glass.GlassFinish.regular(
      appearance: Theme.of(context).brightness,
      backdrop: Theme.of(context).colorScheme.surface,
    );
    final blur = active && !native && sampleBackdrop && !nested && !contrast;
    final color =
        baseColor ??
        (overlay
            ? material.overlay
            : cardSurface
            ? material.content
            : material.control);
    final cardFinish = finish.copyWith(
      tint: color.withValues(alpha: 0.90),
      // Give the theme-colored outline ownership of the card silhouette.
      rim: Colors.white.withValues(alpha: 0.06),
    );
    final surface = DecoratedBox(
      decoration: active
          ? BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: material.shadow,
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            )
          : const BoxDecoration(),
      child: ClipRRect(
        borderRadius: radius,
        clipBehavior: active ? Clip.antiAlias : Clip.none,
        child: BackdropFilter(
          enabled: blur,
          filter: ui.ImageFilter.blur(
            sigmaX: overlay ? 12 : 6,
            sigmaY: overlay ? 12 : 6,
          ),
          child: DecoratedBox(
            // Overlay text must remain readable even before an atlas/shader
            // is ready. Keep a real opaque surface under all modal glass.
            decoration: active && (!native || overlay)
                ? material.decoration(
                    context,
                    radius,
                    base: color,
                    transparent: blur && !overlay,
                  )
                : native
                ? const BoxDecoration()
                : classicDecoration ?? const BoxDecoration(),
            child: CustomPaint(
              foregroundPainter: active && !native && !contrast
                  ? _MaterialRim(radius: radius, color: material.edge)
                  : null,
              child: glass.GlassSurface(
                // Keep the same content subtree while switching visual style.
                presence: native ? 1 : 0,
                borderRadius: radius,
                finish: overlay
                    ? finish.copyWith(tint: color.withValues(alpha: 0.96))
                    : cardSurface
                    ? cardFinish
                    : baseColor == null
                    ? finish
                    : finish.copyWith(
                        tint: baseColor!.withValues(alpha: finish.tint.a),
                      ),
                materialize: materialize,
                ripple: native && interactive && !contrast
                    ? const glass.GlassRipple(amplitude: 4.5)
                    : null,
                child: DecoratedBox(
                  // Draw this over the optics, so pale backgrounds cannot
                  // swallow the outline. Recomputed from the current theme.
                  decoration: native && cardSurface
                      ? BoxDecoration(
                          borderRadius: radius,
                          border: Border.all(
                            color: contrast
                                ? Theme.of(context).colorScheme.outline
                                : borderColor ?? material.edge,
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withValues(
                                alpha:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? 0.045
                                    : 0.30,
                              ),
                              Colors.white.withValues(alpha: 0),
                            ],
                          ),
                        )
                      : const BoxDecoration(),
                  child: AppGlassFeedbackLayer(
                    child: Material(
                      type: MaterialType.transparency,
                      textStyle: DefaultTextStyle.of(context).style,
                      child: _GlassScope(active: nested || blur, child: child),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return overlay
        ? glass.GlassAbove(lift: glass.kGlassModalLift, child: surface)
        : surface;
  }
}

class _GlassScope extends InheritedWidget {
  const _GlassScope({required this.active, required super.child});
  final bool active;
  @override
  bool updateShouldNotify(_GlassScope oldWidget) => active != oldWidget.active;
}

class _MaterialRim extends CustomPainter {
  const _MaterialRim({required this.radius, required this.color});
  final BorderRadius radius;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = (Offset.zero & size).deflate(0.5);
    canvas.drawRRect(
      radius.toRRect(bounds),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color,
            color.withValues(alpha: color.a * 0.12),
            color.withValues(alpha: color.a * 0.4),
          ],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_MaterialRim oldDelegate) =>
      radius != oldDelegate.radius || color != oldDelegate.color;
}

/// Fixed app bars have no underlying content; only sliver bars sample it.
class AppGlassBarBackground extends StatelessWidget {
  const AppGlassBarBackground({super.key, this.sampleBackdrop = false});
  final bool sampleBackdrop;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (sampleBackdrop && AppMaterials.hasGlassHost(context)) {
      // A full-width pinned header is a continuation of the page, not a glass
      // card. An atlas-backed rectangle adds a rim and samples beyond screen
      // edges, producing visible seams. A page-colored surface also avoids an
      // extra upper-level capture every time the settings list scrolls.
      return ColoredBox(color: colors.surface, child: const SizedBox.expand());
    }
    // A toolbar is not a framed card. Keep its surface continuous with the page.
    return ClipRect(
      child: BackdropFilter(
        enabled: sampleBackdrop && !MediaQuery.highContrastOf(context),
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: ColoredBox(
          color: colors.surface.withValues(alpha: sampleBackdrop ? 0.9 : 1),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

Widget? appGlassBarBackground(
  BuildContext context, {
  bool sampleBackdrop = false,
}) => AppMaterials.of(context).liquid
    ? AppGlassBarBackground(sampleBackdrop: sampleBackdrop)
    : null;

AnimationStyle? appMenuAnimation(BuildContext context) {
  if (MediaQuery.disableAnimationsOf(context)) {
    return AnimationStyle.noAnimation;
  }
  if (!AppMaterials.of(context).liquid) return null;
  return const AnimationStyle(
    duration: Duration(milliseconds: 220),
    reverseDuration: Duration(milliseconds: 160),
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
}
