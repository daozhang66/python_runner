import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'app_navigation_destinations.dart';
import 'app_navigation_icon.dart';
import 'navigation_glass.dart';
import 'navigation_lens_content.dart';
import 'navigation_motion.dart';
import 'navigation_indicator_geometry.dart';
import 'navigation_interaction_glow.dart';

/// Floating navigation: drag previews stay local until the user releases.
class AppBottomNavigation extends StatefulWidget {
  const AppBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  }) : assert(selectedIndex >= 0 &&
            selectedIndex < AppNavigationDestinations.count);

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  State<AppBottomNavigation> createState() => _AppBottomNavigationState();
}

class _AppBottomNavigationState extends State<AppBottomNavigation>
    with TickerProviderStateMixin {
  static const _barHeight = 64.0;
  late final _motion =
      NavigationMotion(vsync: this, index: widget.selectedIndex);
  final _glass = NavigationGlassResources();
  late final _clarity = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 160));
  bool _dragging = false;
  Offset _lastPointer = Offset.zero;

  @override
  void initState() {
    super.initState();
    _glass.initialize();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion.setReducedMotion(
        MediaQuery.disableAnimationsOf(context), widget.selectedIndex);
  }

  @override
  void didUpdateWidget(covariant AppBottomNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _dragging = false;
      _clarity.reverse();
      if (!_motion.settlingTo(widget.selectedIndex)) {
        _motion.settle(widget.selectedIndex);
      }
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    _clarity.dispose();
    _glass.dispose();
    super.dispose();
  }

  double _logicalPosition(Offset local, double width, TextDirection direction) {
    final physical = ((local.dx - NavigationIndicatorGeometry.inset) /
                ((width - NavigationIndicatorGeometry.inset * 2) /
                    AppNavigationDestinations.count) -
            0.5)
        .clamp(0.0, (AppNavigationDestinations.count - 1).toDouble());
    return direction == TextDirection.rtl
        ? AppNavigationDestinations.count - 1 - physical
        : physical;
  }

  void _commit(int index) {
    if (!mounted) return;
    final tap = !_dragging;
    _dragging = false;
    _clarity.reverse();
    _motion.settle(index, pulse: tap);
    if (index != widget.selectedIndex) widget.onDestinationSelected(index);
  }

  void _cancel() {
    if (!mounted) return;
    _dragging = false;
    _clarity.reverse();
    _motion.settle(widget.selectedIndex);
  }

  Widget _buildLabels(List<String> labels, List<IconData> icons, Color color,
          {double magnification = 1}) =>
      Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: NavigationIndicatorGeometry.inset),
        child: Row(children: [
          for (var index = 0; index < labels.length; index++)
            Expanded(
                child: Transform.scale(
                    scale: magnification,
                    transformHitTests: false,
                    child: _NavigationLabel(
                        label: labels[index],
                        icon: icons[index],
                        color: color))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = colors.brightness == Brightness.dark;
    // Blur cannot separate two pale surfaces. A neutral tint gives light
    // glass some depth while retaining the current palette and live backdrop.
    final trackColor = dark
        ? colors.surfaceContainer.withValues(alpha: 0.54)
        : Color.alphaBlend(
                colors.onSurfaceVariant.withValues(alpha: 0.12),
                colors.surfaceContainer)
            .withValues(alpha: 0.70);
    final l10n = AppLocalizations.of(context)!;
    final direction = Directionality.of(context);
    final labels = AppNavigationDestinations.labels(l10n);
    const icons = AppNavigationDestinations.icons;
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Align(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: LayoutBuilder(builder: (context, constraints) {
              final width = constraints.maxWidth;
              // Android may briefly report a zero-width viewport on startup.
              if (width <= 8) return const SizedBox(height: _barHeight);
              return Listener(
                onPointerDown: (event) {
                  if (event.buttons == 1) {
                    _motion.pressAt(
                        _logicalPosition(event.localPosition, width, direction),
                        time: event.timeStamp);
                  }
                },
                onPointerCancel: (_) => _cancel(),
                child: GestureDetector(
                  key: const ValueKey('navigation-gesture-area'),
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (details) {
                    _dragging = true;
                    if (!MediaQuery.disableAnimationsOf(context)) {
                      _clarity.forward();
                    }
                    _lastPointer = details.localPosition;
                    _motion.follow(
                        _logicalPosition(_lastPointer, width, direction),
                        time: details.sourceTimeStamp);
                  },
                  onHorizontalDragUpdate: (details) {
                    if (!_dragging) return;
                    _lastPointer = details.localPosition;
                    _motion.follow(
                        _logicalPosition(_lastPointer, width, direction),
                        time: details.sourceTimeStamp);
                  },
                  onHorizontalDragEnd: (_) {
                    if (!_dragging) return;
                    if (_lastPointer.dy < -32 ||
                        _lastPointer.dy > _barHeight + 32) {
                      _cancel();
                    } else {
                      _commit(_motion.preview!
                          .round()
                          .clamp(0, AppNavigationDestinations.count - 1));
                    }
                  },
                  onHorizontalDragCancel: _cancel,
                  child: SizedBox(
                    height: _barHeight,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_motion, _glass, _clarity]),
                      builder: (context, _) {
                        final logical = _motion.position.clamp(0.0,
                            (AppNavigationDestinations.count - 1).toDouble());
                        final visual = direction == TextDirection.rtl
                            ? AppNavigationDestinations.count - 1 - logical
                            : logical;
                        final progress = _motion.progress;
                        final clarity =
                            Curves.easeInOut.transform(_clarity.value);
                        // Keep dark glass readable, but use a translucent veil
                        // on light surfaces instead of an opaque gray button.
                        final restingTint = Color.alphaBlend(
                            colors.onSurface
                                .withValues(alpha: dark ? 0.16 : 0.10),
                            colors.surfaceContainer);
                        final indicatorFill = Color.lerp(
                            dark
                                ? restingTint.withValues(alpha: 0.86)
                                : colors.onSurface.withValues(alpha: 0.055),
                            dark
                                ? colors.surfaceContainer
                                    .withValues(alpha: 0.10)
                                : colors.onSurface.withValues(alpha: 0.045),
                            clarity)!;
                        final indicator = NavigationIndicatorGeometry.resolve(
                            width: width,
                            position: visual,
                            press: _motion.press,
                            speed: _motion.speed);
                        final panelOffset = _motion.panelOffset *
                            (direction == TextDirection.rtl ? -1 : 1);

                        return Transform.translate(
                          key: const ValueKey('navigation-panel-motion'),
                          offset: Offset(panelOffset, 0),
                          transformHitTests: false,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                  child: IgnorePointer(
                                      child: CustomPaint(
                                          painter: _GlassShadow(
                                              dark: dark, contact: !dark)))),
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: ClipPath(
                                      key: const ValueKey(
                                          'navigation-track-surface'),
                                      clipper: const ShapeBorderClipper(
                                          shape: StadiumBorder()),
                                      child: Transform.scale(
                                          key: const ValueKey(
                                              'navigation-track-expansion'),
                                          scaleX: 1 + progress * 8 / width,
                                          scaleY: 1 + progress * 0.06,
                                          child: ClipPath(
                                            clipper: const ShapeBorderClipper(
                                                shape: StadiumBorder()),
                                            child: NavigationGlassBackdrop(
                                              resources: _glass,
                                              lens: false,
                                              pixelRatio: dpr,
                                              progress: progress,
                                              viewport:
                                                  MediaQuery.sizeOf(context),
                                              child: Material(
                                                key: const ValueKey(
                                                    'navigation-surface'),
                                                color: trackColor,
                                                surfaceTintColor:
                                                    Colors.transparent,
                                                shape: StadiumBorder(
                                                    side: BorderSide(
                                                        color: Colors.white
                                                            .withValues(
                                                                alpha: dark
                                                                    ? 0.18
                                                                    : 0),
                                                        width: 1)),
                                                child: dark
                                                    ? null
                                                    : CustomPaint(
                                                        painter: _GlassTrackRim(
                                                            shade: colors
                                                                .onSurface)),
                                              ),
                                            ),
                                          ))),
                                ),
                              ),
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    key: const ValueKey(
                                        'navigation-interaction-glow'),
                                    painter: NavigationInteractionGlow(
                                      lens: indicator,
                                      intensity: progress,
                                      dark: dark,
                                      color: dark
                                          ? Color.lerp(Colors.white,
                                              colors.primary, 0.15)!
                                          : colors.primary,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned.fromRect(
                                rect: indicator,
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    painter: _GlassShadow(
                                        dark: dark,
                                        strength:
                                            dark ? progress : progress * 0.5,
                                        contact: !dark),
                                  ),
                                ),
                              ),
                              Positioned.fromRect(
                                rect: indicator,
                                child: IgnorePointer(
                                    child: ClipPath(
                                        clipper: const ShapeBorderClipper(
                                            shape: StadiumBorder()),
                                        child: BackdropFilter(
                                            key: const ValueKey(
                                                'navigation-resting-blur'),
                                            enabled: clarity < 0.999,
                                            filter: ui.ImageFilter.blur(
                                                sigmaX: 3.2 * (1 - clarity),
                                                sigmaY: 3.2 * (1 - clarity)),
                                            child: DecoratedBox(
                                              key: const ValueKey(
                                                  'navigation-resting-fill'),
                                              decoration: ShapeDecoration(
                                                color: indicatorFill,
                                                shape: StadiumBorder(
                                                    side: BorderSide(
                                                        color: colors.onSurface
                                                            .withValues(
                                                                alpha: (dark
                                                                        ? 0.14
                                                                        : 0.025) *
                                                                    (1 -
                                                                        clarity)),
                                                        width:
                                                            dark ? 0.7 : 0.5)),
                                              ),
                                            )))),
                              ),
                              Positioned.fill(
                                  child: NavigationLensContent(
                                lens: indicator,
                                unselected: _buildLabels(
                                    labels, icons, colors.onSurface),
                                // Paint the enlarged glyphs before refraction.
                                // Each tab keeps its own center; the moving
                                // capsule reveals only the covered portion.
                                selected: _buildLabels(
                                    labels, icons, colors.primary,
                                    magnification: 1 + 0.24 * progress),
                              )),
                              Positioned(
                                left: indicator.left,
                                top: indicator.top,
                                width: indicator.width,
                                height: indicator.height,
                                child: IgnorePointer(
                                  child: ClipPath(
                                    clipper: const ShapeBorderClipper(
                                        shape: StadiumBorder()),
                                    child: NavigationGlassBackdrop(
                                      resources: _glass,
                                      lens: true,
                                      pixelRatio: dpr,
                                      progress: progress,
                                      viewport: MediaQuery.sizeOf(context),
                                      child: DecoratedBox(
                                        key: const ValueKey(
                                            'navigation-indicator'),
                                        decoration: ShapeDecoration(
                                          // Tint belongs beneath the glyphs;
                                          // covering the sampled labels here
                                          // would wash out their contrast.
                                          color: Colors.transparent,
                                          shape: StadiumBorder(
                                              side: BorderSide(
                                                  color: Colors.white
                                                      .withValues(
                                                          alpha: progress *
                                                              (dark
                                                                  ? 0.25
                                                                  : 0.40)),
                                                  width: 1)),
                                        ),
                                        child: CustomPaint(
                                            // The shader supplies the optical
                                            // rim. A neutral outline is enough
                                            // on backends without refraction.
                                            painter: _glass.available
                                                ? null
                                                : _GlassHighlight(
                                                    progress: progress,
                                                    dark: dark),
                                            foregroundPainter: dark
                                                ? null
                                                : _LightGlassRim(
                                                    progress: progress,
                                                    shade: colors.onSurface)),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal:
                                        NavigationIndicatorGeometry.inset),
                                child: Row(children: [
                                  for (var index = 0;
                                      index < labels.length;
                                      index++)
                                    Expanded(
                                        child: _NavigationItem(
                                      index: index,
                                      label: labels[index],
                                      selected: widget.selectedIndex == index,
                                      onTap: () => _commit(index),
                                      onTapCancel: () {
                                        if (!_dragging) _cancel();
                                      },
                                    )),
                                ]),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavigationLabel extends StatelessWidget {
  const _NavigationLabel(
      {required this.label, required this.icon, required this.color});
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        AppNavigationIcon(icon: icon, color: color),
        const SizedBox(height: 3),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium!
                    .copyWith(letterSpacing: 0, color: color)),
          ),
        ),
      ]);
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem(
      {required this.index,
      required this.label,
      required this.selected,
      required this.onTap,
      required this.onTapCancel});
  final int index;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onTapCancel;

  @override
  Widget build(BuildContext context) => Semantics(
        key: ValueKey('navigation-item-$index'),
        button: true,
        selected: selected,
        label: label,
        onTap: onTap,
        child: ExcludeSemantics(
          child: Tooltip(
            triggerMode: TooltipTriggerMode.manual,
            message: label,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(32),
                splashFactory: NoSplash.splashFactory,
                highlightColor: Colors.transparent,
                onTap: onTap,
                onTapCancel: onTapCancel,
                child: const SizedBox(
                    height: _AppBottomNavigationState._barHeight),
              ),
            ),
          ),
        ),
      );
}

/// A narrow bevel distinguishes the whole light track from a pale page.
/// Painted inside the track so the active lens can refract its real edge.
class _GlassTrackRim extends CustomPainter {
  const _GlassTrackRim({required this.shade});
  final Color shade;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    final outer = const StadiumBorder().getOuterPath(bounds.deflate(0.4));
    final inner = const StadiumBorder().getOuterPath(bounds.deflate(1.3));
    // A shaded lower edge anchors the white upper highlight on pale pages.
    canvas.drawPath(
        outer,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7
          ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                shade.withValues(alpha: 0.10),
                shade.withValues(alpha: 0.18),
                shade.withValues(alpha: 0.28),
              ]).createShader(bounds));
    canvas.drawPath(
        inner,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.55),
                Colors.white.withValues(alpha: 0.10),
                Colors.white.withValues(alpha: 0.25),
              ]).createShader(bounds)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.65));
    canvas.drawPath(
        inner,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.85
          ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.92),
                Colors.white.withValues(alpha: 0.38),
                Colors.white.withValues(alpha: 0.72),
              ]).createShader(bounds));
  }

  @override
  bool shouldRepaint(_GlassTrackRim oldDelegate) => shade != oldDelegate.shade;
}

class _GlassShadow extends CustomPainter {
  const _GlassShadow(
      {required this.dark, this.strength = 1, this.contact = false});
  final bool dark;
  final double strength;
  final bool contact;
  @override
  void paint(Canvas canvas, Size size) {
    if (strength <= 0) return;
    final shape = const StadiumBorder().getOuterPath(Offset.zero & size);
    canvas.save();
    canvas.clipPath(Path.combine(PathOperation.difference,
        Path()..addRect((Offset.zero & size).inflate(32)), shape));
    canvas.drawPath(
        shape.shift(const Offset(0, 6)),
        Paint()
          ..color =
              Colors.black.withValues(alpha: (dark ? 0.22 : 0.10) * strength)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    if (contact) {
      canvas.drawPath(
          shape.shift(const Offset(0, 2)),
          Paint()
            ..color = Colors.black.withValues(alpha: 0.05 * strength)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlassShadow oldDelegate) =>
      dark != oldDelegate.dark ||
      strength != oldDelegate.strength ||
      contact != oldDelegate.contact;
}

/// On a pale track, a white highlight needs a shaded lower edge to read as
/// curved glass. This thin rim leaves the center and live refraction clear.
class _LightGlassRim extends CustomPainter {
  const _LightGlassRim({required this.progress, required this.shade});
  final double progress;
  final Color shade;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final bounds = Offset.zero & size;
    canvas.drawPath(
        const StadiumBorder().getOuterPath(bounds.deflate(1.3)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7
          ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.55 * progress),
                Colors.white.withValues(alpha: 0.15 * progress),
                shade.withValues(alpha: 0.04 * progress),
                shade.withValues(alpha: 0.10 * progress),
              ],
              stops: const [
                0,
                0.35,
                0.65,
                1
              ]).createShader(bounds));
  }

  @override
  bool shouldRepaint(_LightGlassRim oldDelegate) =>
      progress != oldDelegate.progress || shade != oldDelegate.shade;
}

class _GlassHighlight extends CustomPainter {
  const _GlassHighlight({required this.progress, required this.dark});
  final double progress;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final bounds = Offset.zero & size;
    canvas.drawPath(
        const StadiumBorder().getOuterPath(bounds.deflate(0.8)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: progress * (dark ? 0.52 : 0.78)),
                Colors.white.withValues(alpha: progress * 0.08),
                Colors.white.withValues(alpha: progress * 0.40),
              ]).createShader(bounds));
  }

  @override
  bool shouldRepaint(_GlassHighlight oldDelegate) =>
      progress != oldDelegate.progress || dark != oldDelegate.dark;
}
