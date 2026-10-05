// The configuration level of the three-level structure (research SS7.2): tokens
// above, the primitive below, components on top of that.
//
// §7.1 fixed the shape of this level before anything was built, and the reason
// it gave is the one that still holds: **configuration is inherited and
// geometry is not.** A surface moves every frame, so its place travels through
// [GlassLedger], which is a `Listenable` whose identity never changes and which
// therefore rebuilds nobody. What is in here changes when a user flips a switch
// or a screen picks a look — measured in events per session, not per frame — so
// it can afford to be an `InheritedWidget` and rebuild the subtree when it
// moves.
//
// Two tokens, and both earn their place by having an observable trace:
//
//  - [GlassThemeData.finish] is the material — blur, tint, rim, optics — and
//    its `name` is the key into every measured damage table the package holds.
//    It was already carried down the tree, but by [GlassProxyHandle], which is
//    the *pipeline*: a surface with no [GlassHost] above it had no finish at
//    all. That was invisible while every rung read a proxy and stops being
//    invisible now, because [GlassTier.cheap] is a rung that has no pipeline by
//    construction and still has to look like the same panel.
//  - [GlassThemeData.tier] is which rung of phase D's ladder is drawn, and
//    `glass_tier.dart` has the argument for why it is a declaration.
//  - [GlassThemeData.backdrop] is the level the screen is on average, and it is
//    here because it is the one thing the *bottom* rung needs and cannot get:
//    [GlassTier.opaque] reads no backdrop by construction (D58, D176), so the
//    mean it stands in for has to arrive from outside. Left out it costs 0.67 of
//    the material scale over a light screen (D179).
//
// Phase D's remainder added three more, each for a reason a reading could not
// supply (D203, D204):
//
//  - [GlassThemeData.highContrast] is the platform's increase-contrast switch.
//    The host fills it from `MediaQuery.highContrastOf`, which the engine sets
//    on iOS and on Android 34+ — **the first automatic input any token here
//    has** — and on macOS the application has to pass it, read from
//    `NSWorkspace.accessibilityDisplayShouldIncreaseContrast`, because the macOS
//    embedder relays nothing.
//  - [GlassThemeData.richBackdrop] says the screen under the glass is an image
//    rather than a colour, which is HIG's own distinction ("visually rich
//    backgrounds"). A declared mean is exact over a flat screen and says
//    nothing about a photograph's brightest corner, so legibility there is
//    computed against every backdrop instead — which needs only the finish.
//  - [GlassThemeData.minLabelContrast] is a floor the application chooses,
//    and the one place the package will change a colour to reach a number:
//    it dims under the glass, which is Apple's answer and in this machine a
//    change of tint, not a new layer.
//
// What is deliberately **not** here: a quality tier of its own. SS7.2 sketched
// `GlassQuality` (minimal / standard / premium, benchmarked at start-up) beside
// the ladder of SS7.4, as if they were two axes. They are one, and the sketch
// predates the measurements: the "quality" that is actually chosen at runtime
// is the proxy divisor and the retake ceiling, and those are already chosen —
// against a measured damage table, by `ProxyResolutionPolicy`, out of a budget
// in ΔE (D120, D124). A second quality knob would either duplicate that or
// overrule it with a name.

import 'package:flutter/widgets.dart';

import 'glass_finish.dart';
import 'glass_ripple.dart';
import 'glass_tier.dart';

/// The tokens a screen's glass reads.
@immutable
class GlassThemeData {
  const GlassThemeData({
    this.finish = GlassFinish.regularDark,
    this.tier = GlassTierChoice.byDefault,
    this.backdrop,
    this.highContrast = false,
    this.richBackdrop = false,
    this.minLabelContrast,
    this.ripple,
  });

  /// The material every surface wears unless it names its own.
  ///
  /// Defaults to [GlassFinish.regularDark] only as a constant: a [GlassHost]
  /// installs the branch of `.regular` the screen is on, and so does
  /// [GlassTheme.of] when nothing is above (D230).
  final GlassFinish finish;

  /// Which rung of the ladder is drawn, and why.
  final GlassTierChoice tier;

  /// What is behind the glass, on average — the screen's own background colour.
  ///
  /// Read by exactly one rung, and only because that rung cannot read anything
  /// else: [GlassTier.opaque] transmits none of the backdrop, so the level it
  /// has to stand in for is the backdrop's mean, and a surface that reads no
  /// backdrop cannot measure a mean of it. Every other rung ignores this — the
  /// full one samples the real thing and the cheap one still transmits
  /// `1 - a` of it, which is why the cheap rung needs no declaration at all
  /// (its correction term is 1.7 code values at the calibrated finish, D179).
  ///
  /// **One value, and one the application already keeps.** The count is the
  /// test CLAUDE.md sets for closing a hole with a declaration: this is
  /// `ThemeData.colorScheme.surface`, or the `ColoredBox` at the bottom of the
  /// page — the same shape of claim as [SolidProxyPainter], which is the
  /// application saying "behind this subtree, this colour" for the same reason.
  ///
  /// Null means nobody said, and then [GlassTier.opaque] falls back to painting
  /// the finish's tint itself — the colour the material lays on rather than the
  /// level it shows, 29 code values against the 69 the glass shows over a
  /// mid-grey screen, and 23.3 ΔE wrong over a light one (D179). A debug assert
  /// says so at the moment the rung is painted rather than here, because a
  /// screen that never reaches [GlassTier.opaque] owes nothing.
  ///
  /// Deliberately **not** derived from `MediaQuery.platformBrightnessOf`: that
  /// answers which appearance the platform is in, not what this screen's average
  /// level is, and the gap between those two is exactly the quantity being
  /// fixed. The package has no automatic input to this axis for the same reason
  /// it has none to the ladder itself (D175).
  final Color? backdrop;

  /// Whether the platform's increase-contrast switch is on.
  ///
  /// Under it every rung draws its outline as an **opaque** line of the colour
  /// that stands out most against the level under it
  /// ([GlassFinish.highContrastRim]), [kHighContrastRimWidthLogical] wide,
  /// instead of the calibrated additive white. That is what Apple's switch does
  /// to its own glass — the translucency stays, the edge becomes visible — and
  /// the calibrated rim cannot be made to do it by turning it up, because it
  /// adds and a light level swallows an addition.
  ///
  /// Nothing else changes: not the rung, not the tint, not the label. A user
  /// who wants the translucency gone has the other switch, and it goes to
  /// [GlassTier.opaque].
  final bool highContrast;

  /// Whether what is behind the glass is an image — a photograph, a video, a
  /// map — rather than a colour.
  ///
  /// [backdrop] is a mean, and a mean is exact over a flat screen: every pixel
  /// under the glass *is* it. Over a photograph it says nothing about the
  /// brightest corner, which is where a white label disappears — the gap the
  /// label arithmetic left open in D184. So when this is set, the label and the
  /// high-contrast outline are chosen against **every** backdrop
  /// ([GlassFinish.foregroundOverAny]), which needs nothing declared at all,
  /// and [minLabelContrast] is met in the worst case rather than on average.
  ///
  /// [backdrop] keeps its one other job: [GlassTier.opaque] still fills with
  /// the level over the mean, because that rung shows no image to be legible
  /// against.
  final bool richBackdrop;

  /// The least contrast a component's label must have against the glass, or
  /// null to leave the finish alone.
  ///
  /// When the finish cannot reach it with either black or white, the glass is
  /// **dimmed** by the least amount that does ([GlassFinish.dimmingFor]):
  /// Apple's own answer for clear glass over bright content, and in this
  /// machine the same affine law with less transmission, so it is a change of
  /// tint and costs nothing to draw. Against a declared flat [backdrop] the
  /// floor is checked there; with [richBackdrop], or with no backdrop at all,
  /// over any backdrop — and there [GlassFinish.regularDark] needs no dim for AA
  /// (6.05 in the worst case), while [GlassFinish.clear] needs 0.682 where
  /// Apple's suggested 35% reaches 1.98 (D204).
  ///
  /// [kTextContrastAA] (4.5) is WCAG's floor for body text; the package picks
  /// no floor of its own, because it cannot see the text's size.
  final double? minLabelContrast;

  /// The wave every surface makes when touched, unless it declares its own;
  /// null for none, which is the platform's behaviour. See [GlassRipple].
  final GlassRipple? ripple;

  /// The finish surfaces draw, and the label and outline colours they use —
  /// everything the three tokens above decide, in one place, so the surface,
  /// the group and the components cannot disagree.
  ///
  /// [own] is a surface's own finish, when it names one: the dim is applied to
  /// it as well, because the floor is about the label on this screen and not
  /// about whose finish it is. Unless [labelled] is false: glass that carries
  /// no label has no floor to meet, and keeps the finish it names.
  GlassLegibility legibility([GlassFinish? own, bool labelled = true]) {
    final GlassFinish base = own ?? finish;
    // A rich backdrop has no single level to choose against, and neither has a
    // screen that declared none: both fall to the worst case.
    final Color? flat = richBackdrop ? null : backdrop;
    final double? floor = labelled ? minLabelContrast : null;
    var drawn = base;
    if (floor != null) {
      final Color label = flat == null ? base.foregroundOverAny() : base.foregroundOver(flat);
      final double reached = flat == null
          ? base.worstContrast(label)
          : GlassFinish.contrastRatio(base.opaqueFillOver(flat), label);
      if (reached < floor) {
        final double? dim = flat == null ? base.dimmingFor(floor) : _dimOver(base, flat, floor);
        // Null is "no dim reaches it", and then the most a dim can do is done:
        // a floor nobody can meet is still better approached than ignored.
        drawn = base.dimmed(dim ?? 1);
      }
    }
    final Color label = flat == null ? drawn.foregroundOverAny() : drawn.foregroundOver(flat);
    return GlassLegibility(
      finish: drawn,
      label: label,
      rim: highContrast ? drawn.highContrastRim(backdrop: flat) : null,
    );
  }

  /// The least dim that puts a white label at [floor] over one flat level.
  static double? _dimOver(GlassFinish finish, Color backdrop, double floor) {
    const white = Color(0xFFFFFFFF);
    // At the next stored code up, for the reason `GlassFinish.dimmingFor` gives:
    // the least continuous dim sits on the floor, and rounding misses it.
    double up(double v) => (v * 255).ceilToDouble() / 255;
    double reach(double d) {
      final Color level = finish.dimmed(d).opaqueFillOver(backdrop);
      return GlassFinish.contrastRatio(
        Color.from(alpha: 1, red: up(level.r), green: up(level.g), blue: up(level.b)),
        white,
      );
    }

    if (reach(1) < floor) {
      return null;
    }
    var lo = 0.0;
    var hi = 1.0;
    for (var i = 0; i < 40; i++) {
      final double mid = (lo + hi) / 2;
      if (reach(mid) >= floor) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    return hi;
  }

  GlassThemeData copyWith({
    GlassFinish? finish,
    GlassTierChoice? tier,
    Color? backdrop,
    bool? highContrast,
    bool? richBackdrop,
    double? minLabelContrast,
    GlassRipple? ripple,
  }) => GlassThemeData(
    finish: finish ?? this.finish,
    tier: tier ?? this.tier,
    backdrop: backdrop ?? this.backdrop,
    highContrast: highContrast ?? this.highContrast,
    richBackdrop: richBackdrop ?? this.richBackdrop,
    minLabelContrast: minLabelContrast ?? this.minLabelContrast,
    ripple: ripple ?? this.ripple,
  );

  @override
  bool operator ==(Object other) =>
      other is GlassThemeData &&
      other.finish == finish &&
      other.tier == tier &&
      other.backdrop == backdrop &&
      other.highContrast == highContrast &&
      other.richBackdrop == richBackdrop &&
      other.minLabelContrast == minLabelContrast &&
      other.ripple == ripple;

  @override
  int get hashCode => Object.hash(finish, tier, backdrop, highContrast, richBackdrop, minLabelContrast, ripple);

  @override
  String toString() =>
      'GlassThemeData($finish, $tier, backdrop $backdrop'
      '${highContrast ? ', high contrast' : ''}'
      '${richBackdrop ? ', rich backdrop' : ''}'
      '${minLabelContrast == null ? '' : ', label >= $minLabelContrast'}'
      '${ripple == null ? '' : ', $ripple'})';
}

/// What a surface under a theme actually draws: the finish after any dim, the
/// label colour, and the outline under increase contrast.
@immutable
class GlassLegibility {
  const GlassLegibility({required this.finish, required this.label, this.rim});

  /// The finish to draw — the declared one, or it dimmed to meet
  /// [GlassThemeData.minLabelContrast]. Same name, so the same damage tables:
  /// a dim only lowers them (D204).
  final GlassFinish finish;

  /// The label colour: black or white, whichever stands out more against the
  /// declared flat backdrop, or — with a rich backdrop or none declared —
  /// whichever has the better **worst** case over every backdrop.
  final Color label;

  /// The opaque outline under increase contrast, or null for the calibrated
  /// additive one.
  final Color? rim;
}

/// Carries [GlassThemeData] down the tree.
///
/// Nestable, and that is the mechanism for a screen whose panels do not all
/// wear the same thing — a toolbar at [GlassTier.full] over a list of cards at
/// [GlassTier.cheap] is an inner theme, not a per-surface argument. Scoping
/// configuration by position is what the inherited level is *for*, and a
/// per-surface override would put the same decision in two places.
class GlassTheme extends InheritedWidget {
  const GlassTheme({required this.data, required super.child, super.key});

  final GlassThemeData data;

  /// The theme in force, or null if there is none above.
  ///
  /// Null rather than a default, because the callers differ on what to do about
  /// it: a surface falls back to [GlassThemeData]'s own defaults, and a host
  /// installs one rather than reading it.
  static GlassThemeData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassTheme>()?.data;

  /// The theme in force, or the defaults — with the branch of `.regular` the
  /// platform's appearance gives (D230), as a [GlassHost] would pick it.
  static GlassThemeData of(BuildContext context) =>
      maybeOf(context) ??
      GlassThemeData(
        finish: GlassFinish.regular(
          appearance: MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light,
        ),
      );

  @override
  bool updateShouldNotify(GlassTheme oldWidget) => oldWidget.data != data;
}
