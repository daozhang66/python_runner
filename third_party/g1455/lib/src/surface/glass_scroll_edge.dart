// The scroll edge effect: what iOS 26 draws where content scrolls under a bar.
//
// Read off Apple's own `UIScrollEdgeEffect` (spike 31): a navigation bar and a
// toolbar over a scroll view on iOS 26.5 simulators, iPhone 17 Pro (bars 116 /
// 86 pt) and iPad Pro 11" (86 / 64 pt), each photographed with the effect
// `soft`, `hard` and hidden — the hidden frame being the known answer — over a
// fixture of 1 pt lines every 6 pt beside a flat field, dark in one run and
// light in the other. Row by row the lines' contrast is the blur and the
// field's level the tint, and the two fields solve `mix(x, C, a)` for C and a.
//
// **Soft, top.** A blur of σ ≈ 1.6 pt (1.55–1.67 over four readings) and a
// tint laid on top, each with its own ramp — and both ramps sit at a constant
// distance from the bar's edge B on both devices, to within a point:
//
//  - the tint is an erf: centred 10.5 pt above B, σ 17 pt (16.9 / 17.2);
//  - the blur goes from whole at B − 37 to none at B + 14 (90% at B − 27, 10%
//    at B + 4) — drawn here as a smoothstep through those two, which puts its
//    middle 5 pt above the measured one: the measured ramp is asymmetric;
//  - the tint's colour is **chosen by the content**: over content whose mean
//    was a mid grey it was black at 0.25, over light content white at 0.85,
//    with the same left half of the frame in both runs. The package cannot
//    read the content, so it reads the declared backdrop instead
//    ([GlassThemeData.backdrop]), or takes [GlassScrollEdge.appearance].
//
// **Soft, bottom: no blur at all.** The lines keep their whole contrast once
// the tint is divided out (1.00 / 1.10 / 1.00 / 1.09), so the bottom edge is a
// tint and nothing else — no capture, no glass, a gradient. Its ramp does not
// sit at a constant distance from the toolbar (20 pt below its top on the
// phone, 7.5 on the iPad); as a fraction of the inset from the screen edge it
// is 0.753 and 0.883, and their mean 0.82 is used — 5.7 and 3.7 pt off on the
// two devices. Neither a constant offset from the toolbar nor one from the home
// indicator does better, and two points cannot tell a third model from these.
//
// **Hard.** A near-opaque white, 0.90 over both fields, with an edge 10 pt
// above B at the top on both devices and, at the bottom, 9.5 pt into the
// toolbar on the phone and on its edge on the iPad (5 pt used). Under it the
// lines are at one code value, which says the blur is at least σ 2.15 and
// nothing more: no blur behind 0.9 white can be read off these frames, so the
// bound is what is drawn. Not chosen by the content in these frames; a dark
// appearance was not photographed.
//
// What it costs: the soft top is one glass surface of the screen's width and
// B + 14 tall — a slot in the atlas, captured when what is under it changes,
// which under a scrolling list is every frame of the scroll. The bottom is a
// gradient. Either side, lifted ([GlassAbove]) so that glass scrolling under
// it is drawn into its capture: a level, and therefore one more snapshot per
// recorded frame — but only when there is glass under it; over plain content
// it is level 0 and costs its slot and nothing else.
//
// **Its finish wears a measured material's name, and that is the price.** The
// divisor reads its damage table by the finish's name, and a name with no
// table is held at full resolution — which is how `identity` is protected.
// Named `scrollEdge`, the edge's level went to 1/1 while the cards' stayed at
// 1/4, and on the iPad the edge cost 2.3 ms of a scrolling frame where a plain
// glass strip of its size cost 0.3 (D227). The soft edge borrows
// `thinLight`'s table, the hard one `regular`'s — see each.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'glass_above.dart';
import 'glass_finish.dart';
import 'glass_surface.dart';
import 'glass_theme.dart';

/// Which side of the scroll view the effect is on.
enum GlassScrollEdgeSide { top, bottom }

/// Apple's two styles of scroll edge effect.
enum GlassScrollEdgeStyle {
  /// iOS's default: content blurs and fades as it goes under the bar.
  soft,

  /// macOS's default: an opaque band with a sharp edge.
  hard,
}

/// Which way a soft edge tints: toward white over light content, toward black
/// over dark. Apple picks it from the content; see [GlassScrollEdge.appearance].
enum GlassScrollEdgeAppearance { light, dark }

/// The soft edge's blur, logical px (spike 31: 1.55–1.67).
const double kGlassScrollEdgeSigma = 1.6;

/// The hard edge's blur: a bound, not a reading — see the file comment.
const double kGlassScrollEdgeHardSigma = 2.15;

/// The soft edge's tint at the edge, by appearance.
const Color kGlassScrollEdgeLightTint = Color.fromRGBO(255, 255, 255, 0.85);
const Color kGlassScrollEdgeDarkTint = Color.fromRGBO(0, 0, 0, 0.25);

/// The hard edge's band.
const Color kGlassScrollEdgeHardFill = Color.fromRGBO(255, 255, 255, 0.90);

/// Where the soft top's tint is centred and how wide its erf is, against the
/// bar's edge, logical px.
const double _kTopTintCentre = -10.5;
const double _kTopTintSigma = 17;

/// The soft top's blur: whole at the first, none at the second, against B.
const double _kTopBlurWhole = -36.7;
const double _kTopBlurNone = 13.8;

/// The soft bottom's tint, as fractions of the inset from the screen edge.
const double _kBottomTintCentre = 0.82;
const double _kBottomTintSigma = 0.30;

/// The hard band's edge against B, top and bottom (inward is negative).
const double _kHardTop = -10;
const double _kHardBottom = -5;

/// The scroll edge effect under a bar, and the bar.
///
/// Put it over the scroll view, against the edge it is for, the full width of
/// the screen; [extent] is how far the bar reaches in from that edge — the
/// status bar and the bar together at the top, the toolbar and the home
/// indicator at the bottom. [child] is the bar, laid in that extent and lifted
/// with the effect, so it sees glass scrolling under it as the effect does
/// ([GlassAbove]).
///
/// ```dart
/// Positioned(
///   top: 0, left: 0, right: 0,
///   child: GlassScrollEdge(
///     side: GlassScrollEdgeSide.top,
///     extent: MediaQuery.paddingOf(context).top + 60,
///     child: myAppBar,
///   ),
/// )
/// ```
///
/// It takes no touches outside [child]: the effect reaches past the bar and
/// what is under it is still the list.
class GlassScrollEdge extends StatelessWidget {
  const GlassScrollEdge({
    required this.side,
    required this.extent,
    this.style = GlassScrollEdgeStyle.soft,
    this.appearance,
    this.blurSigma = kGlassScrollEdgeSigma,
    this.child,
    super.key,
  }) : assert(extent >= 0);

  /// The soft edge's blur, logical px. Apple's is [kGlassScrollEdgeSigma];
  /// see the file comment for what a sigma other than the host's costs.
  final double blurSigma;

  final GlassScrollEdgeSide side;

  /// From the screen edge to the bar's inner edge, logical px.
  final double extent;

  final GlassScrollEdgeStyle style;

  /// Which way a soft edge tints. Null reads the theme's declared backdrop —
  /// dark below a relative luminance of 0.4, light otherwise or undeclared.
  /// Apple reads the content itself: mid-grey content (code 128) went dark,
  /// light content (code 217) light; the threshold is somewhere between,
  /// at relative luminance 0.22 and 0.69, and 0.4 is a guess inside that.
  final GlassScrollEdgeAppearance? appearance;

  /// The bar, laid out in [extent] from the edge.
  final Widget? child;

  /// How far the effect reaches in from the screen edge, logical px.
  double get reach => switch ((side, style)) {
    (GlassScrollEdgeSide.top, GlassScrollEdgeStyle.soft) =>
      extent + math.max(_kTopBlurNone, _kTopTintCentre + 3 * _kTopTintSigma),
    (GlassScrollEdgeSide.bottom, GlassScrollEdgeStyle.soft) => extent * (_kBottomTintCentre + 3 * _kBottomTintSigma),
    (GlassScrollEdgeSide.top, GlassScrollEdgeStyle.hard) => extent + _kHardTop,
    (GlassScrollEdgeSide.bottom, GlassScrollEdgeStyle.hard) => extent + _kHardBottom,
  };

  /// The appearance in force for [theme].
  GlassScrollEdgeAppearance appearanceFor(GlassThemeData theme) {
    if (appearance case final GlassScrollEdgeAppearance chosen) {
      return chosen;
    }
    final Color? backdrop = theme.backdrop;
    return backdrop != null && backdrop.computeLuminance() < 0.4
        ? GlassScrollEdgeAppearance.dark
        : GlassScrollEdgeAppearance.light;
  }

  @override
  Widget build(BuildContext context) {
    final GlassThemeData theme = GlassTheme.of(context);
    final double reach = math.max(0, this.reach);
    final bool top = side == GlassScrollEdgeSide.top;
    final double height = math.max(reach, extent);
    final Widget effect = switch (style) {
      GlassScrollEdgeStyle.soft => _soft(theme, reach),
      GlassScrollEdgeStyle.hard => _hard(reach),
    };
    return GlassAbove(
      child: SizedBox(
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned(
              left: 0,
              right: 0,
              top: top ? 0 : null,
              bottom: top ? null : 0,
              height: reach,
              child: IgnorePointer(child: effect),
            ),
            if (child != null)
              Positioned(
                left: 0,
                right: 0,
                top: top ? 0 : null,
                bottom: top ? null : 0,
                height: extent,
                child: child!,
              ),
          ],
        ),
      ),
    );
  }

  Widget _soft(GlassThemeData theme, double reach) {
    final Color tint = appearanceFor(theme) == GlassScrollEdgeAppearance.dark
        ? kGlassScrollEdgeDarkTint
        : kGlassScrollEdgeLightTint;
    final bool top = side == GlassScrollEdgeSide.top;
    // Distances in from the screen edge.
    final double tintCentre = top ? extent + _kTopTintCentre : extent * _kBottomTintCentre;
    final double tintSigma = top ? _kTopTintSigma : extent * _kBottomTintSigma;
    final Widget tintLayer = CustomPaint(
      painter: _ErfTint(
        colour: tint,
        centre: tintCentre,
        sigma: tintSigma,
        fromBottom: !top,
      ),
    );
    if (!top) {
      // Measured with no blur at all: a gradient, and nothing captured.
      return tintLayer;
    }
    // The tint is the glass's child, not its sibling: a sibling painted over
    // the glass is content to the capture, and the glass then showed it under
    // itself and the tint was laid on twice — 1 - 0.75² = 0.44 against
    // Apple's 0.25, the first reading of this arm. And the glass ends where
    // its fade does, B + 14, with the tint overflowing it to its own reach
    // (B + 40.5): the slot and the shader stop where the glass is zero rather
    // than 27 pt below.
    final double blurEnd = math.max(0, extent + _kTopBlurNone);
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        // The whole width, said: under an `Align` the width is loose, and a
        // `CustomPaint` with no child takes the smallest it is offered — the
        // tint vanished at zero wide the first time this was an `Align`.
        width: double.infinity,
        height: blurEnd,
        child: GlassSurface(
          borderRadius: BorderRadius.zero,
          finish: GlassFinish(
            // A measured material's name, because the divisor reads its damage
            // table by name and a name without one is held at full resolution —
            // which is how `identity` is protected, and what made this edge cost
            // 1.7 ms of a scrolling frame on the iPad: its level went to 1/1 while
            // the cards' stayed at 1/4 (D227). `thinLight` (σ 2.6 under a light
            // 0.22) in both appearances. Borrowed, not measured: this blurs less,
            // which is the direction that underestimates. The light edge passes
            // only 0.15 of the backdrop and was tried on `regular`'s table, which
            // put it at 1/8 on a dpr-3 phone — and there the edge's own
            // instrument reads Apple's blur off by more than its tolerance
            // (residual contrast 0.220 against 0.168): a texel of 0.375 pt
            // breaks a point of detail before a tint can hide it.
            name: 'thinLight',
            blurSigmaLogical: blurSigma,
            tint: const Color(0x00000000),
            rim: const Color(0x00000000),
            optics: GlassOptics.none,
          ),
          labelled: false,
          fade: GlassFade.vertical(
            from: math.max(0, extent + _kTopBlurWhole),
            extent: _kTopBlurNone - _kTopBlurWhole,
          ),
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: reach,
            maxHeight: reach,
            child: tintLayer,
          ),
        ),
      ),
    );
  }

  Widget _hard(double reach) => GlassSurface(
    borderRadius: BorderRadius.zero,
    finish: const GlassFinish(
      // `regularDark`'s table: it transmits 0.307 of the backdrop and this
      // 0.10, so the borrowed damage is an overestimate (see the soft edge's
      // name).
      name: 'regularDark',
      blurSigmaLogical: kGlassScrollEdgeHardSigma,
      tint: kGlassScrollEdgeHardFill,
      rim: Color(0x00000000),
      optics: GlassOptics.none,
    ),
    labelled: false,
  );
}

/// A tint whose alpha falls as `1 - Φ((d - centre) / sigma)` with the distance
/// d in from the screen edge — Apple's ramp is an erf to within the reading's
/// resolution (spike 31: (y75 - y25) / (y90 - y10) of 0.50–0.55, against
/// 0.526 for an erf and 0.572 for a smoothstep).
class _ErfTint extends CustomPainter {
  _ErfTint({required this.colour, required this.centre, required this.sigma, required this.fromBottom});

  final Color colour;
  final double centre;
  final double sigma;
  final bool fromBottom;

  static const int _stops = 17;

  @override
  void paint(Canvas canvas, Size size) {
    if (colour.a <= 0 || sigma <= 0) {
      return;
    }
    final double near = math.max(0, centre - 3 * sigma);
    final double far = centre + 3 * sigma;
    final colours = <Color>[];
    final stops = <double>[];
    for (var i = 0; i < _stops; i++) {
      final double t = i / (_stops - 1);
      final double d = near + (far - near) * t;
      colours.add(colour.withValues(alpha: colour.a * (1 - _phi((d - centre) / sigma))));
      stops.add(t);
    }
    final double y0 = fromBottom ? size.height - near : near;
    final double y1 = fromBottom ? size.height - far : far;
    // The gradient's clamp holds the near end's alpha out to the screen edge.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = ui.Gradient.linear(Offset(0, y0), Offset(0, y1), colours, stops),
    );
  }

  /// The standard normal's CDF, Abramowitz & Stegun 7.1.26 (|error| < 1.5e-7).
  static double _phi(double x) {
    final double z = x.abs() / math.sqrt2;
    final double t = 1 / (1 + 0.3275911 * z);
    final double erf =
        1 -
        (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) *
            t *
            math.exp(-z * z);
    return x >= 0 ? 0.5 * (1 + erf) : 0.5 * (1 - erf);
  }

  @override
  bool shouldRepaint(_ErfTint oldDelegate) =>
      oldDelegate.colour != colour ||
      oldDelegate.centre != centre ||
      oldDelegate.sigma != sigma ||
      oldDelegate.fromBottom != fromBottom;
}
