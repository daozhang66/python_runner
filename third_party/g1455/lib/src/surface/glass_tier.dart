// The finish ladder: what a surface actually paints, and why.
//
// Phase D reads the ladder as one axis with **four reasons and one mechanism**
// (D58, D59): glass -> a cheap finish -> an opaque fill, reached because of the
// backend, of accessibility, of thermals, or of the device's class. That
// sentence has been in the brief since 2026-09-06 and it was written before any
// of the four had been checked against what the project measured afterwards.
// Three of them do not reach this axis:
//
//  - **the backend was removed by D165.** It was the only one of the four that
//    could be detected without asking anybody, and it is the one that does not
//    fire: the route is byte-identical on all four backends and 29% *cheaper*
//    on Skia at equal sample count (D55), so there is nothing to degrade away
//    from. Nothing in the package switches on the backend at all.
//  - **thermals act on a different knob, and that knob is measured.** A frame
//    of staleness costs 0.43 ΔE behind a σ = 8 blur and 1.35 without one (D30),
//    so throttling under a matte finish is nearly free and forbidden under a
//    transparent one — which makes the thermal lever the *retake ceiling*, not
//    the ladder. Flutter carries no thermal state either (B1: the number that
//    turned out to be readable is `thermal_pwrlevel` off kgsl, in a
//    profile build, on Adreno). **Built as that since D205:**
//    `GlassThermalPolicy` spends an allowance in ΔE on the retake, and the
//    state is the application's to read and pass (D202, D219).
//  - **accessibility has no flag to read.** D59 established that; this file's
//    step re-read it at 3.47.1 and went one layer deeper than D59 did — not
//    just `MediaQueryData` and `AccessibilityFeatures`, but the iOS shell that
//    fills them in (`AccessibilityFeatures.swift`, eleven flags, `reduceMotion`
//    among them and nothing about transparency). The platform switch exists and
//    the engine does not observe it. Native code the application runs can read
//    it (D202 built that channel in the research application, and D219 kept it
//    there rather than in the package) — which changes where the value comes
//    from and not that the application passes it: a reading is still an input
//    to [GlassTierPolicy], not a switch the package throws on its own.
//
// So **the ladder has no automatic input at all**, and `auto` is not a value —
// it would be a synonym for [GlassTier.full]. That is a conclusion rather than
// a gap, and pricing the rung did not change it. The cheap step is now priced
// on both GPU families (x0.79…1.09 of a stock Material card on Adreno 830,
// D193; x0.98…1.08 on the M2 iPad Pro, D194), and what the price says is how
// much a degradation saves, not whether the application wanted one: the rung
// is a visible loss, and a package that took it on its own would be deciding
// the application's picture from the application's frame budget, which it
// does not know.
//
// What is left is a declaration, and the count matters (the rule is in
// CLAUDE.md): an application that wants the ladder keeps **one** value, and the
// package supplies the arithmetic that turns whatever signals the application
// does have into it.

import 'package:flutter/foundation.dart';

/// What a surface paints. The rungs of phase D's ladder, in order of what they
/// draw rather than of what they cost.
enum GlassTier {
  /// The route: proxy, atlas, residual blur, refraction, rim.
  full,

  /// The same shape, the same rim, and the finish's own tint drawn straight
  /// over whatever is behind — **no backdrop read at all**.
  ///
  /// The "no read" half is a requirement rather than an optimisation (D58): a
  /// `BackdropFilter` on Skia grows with the number of surfaces (0.37 M cycles
  /// at 6 against 1.26 M at 36, D55), and Skia is exactly where this rung will
  /// spend its life. Here it is satisfied by construction — a screen whose
  /// surfaces are all below [full] takes no capture, so there is no texture to
  /// read even by accident.
  ///
  /// The *level* it produces is not a new constant and not a guess: drawing a
  /// tint of alpha `a` over the backdrop is `mix(backdrop, tint, a)`, which is
  /// the same affine law D70 fitted to Apple's own materials on four backdrops
  /// (R² = 1.0000). So this rung transmits `1 - a` of what is behind it, which
  /// for [GlassFinish.regularDark] is the 0.307 measured off `.regular` itself
  /// (D66) — the material's level survives the rung, and what is lost is the
  /// low-pass and the refraction.
  cheap,

  /// A fill: the same shape and rim, nothing behind it showing through.
  ///
  /// "The reason is extreme, not economy" (phase D). It is the rung Apple's own
  /// Reduce Transparency lands on, and the only one that answers a reader who
  /// cannot read text over a moving background at all.
  ///
  /// **What it fills with is the same law as the other two rungs, evaluated at
  /// the declared backdrop** — `mix(GlassThemeData.backdrop, tint, a)`, see
  /// [GlassFinish.opaqueFillOver]. It used to be the tint itself — that law at
  /// `a = 1`, which is the colour the material lays on rather than the level it
  /// shows; over a light screen that is 23.3 ΔE from the glass it stands in for,
  /// two thirds of the distance between Apple's own `.regular` and `.clear`, and
  /// through the declaration the same arm reads 2.4 (D179). This is the one rung that needs something declared about the
  /// backdrop, and for the reason the ladder itself needs declaring: it reads
  /// nothing, so it can measure nothing.
  opaque;

  /// Whether this rung reads a proxy. True for [full] and nothing else, and it
  /// is the whole structural consequence of the axis: the host captures for the
  /// surfaces where this is true and for no others.
  bool get readsBackdrop => this == GlassTier.full;
}

/// Why the rung in force is the one in force.
///
/// Carried next to the rung rather than derived from it, for the reason
/// [ProxyDivisorReason] and [RetakeReason] exist: a screen that came out
/// [GlassTier.cheap] because the user asked for it and one that came out cheap
/// because a host pinned it look identical on a screenshot and in a report.
enum GlassTierReason {
  /// Nothing asked for anything else.
  byDefault,

  /// The host named the rung outright.
  ///
  /// It wins over every other input, including the accessibility one, and that
  /// ordering is a decision with a consequence worth saying plainly: **a host
  /// that pins [GlassTier.full] has overridden the user's own switch.** The
  /// alternative — accessibility winning over the pin — would make the full
  /// route unmeasurable on a device with the switch on, and a package whose
  /// most expensive path cannot be forced is a package whose most expensive
  /// path cannot be benchmarked. Same shape, and the same justification, as
  /// [ProxyDivisorReason.pinnedByHost].
  pinnedByHost,

  /// The application read the platform's reduce-transparency switch and passed
  /// it in.
  ///
  /// Flutter does not carry it (D59, re-read at 3.47.1 down to the iOS shell),
  /// so this reason arrives from outside — a settings flag, or native code the
  /// application runs that reads `UIAccessibility.isReduceTransparencyEnabled`
  /// on iOS and `NSWorkspace.accessibilityDisplayShouldReduceTransparency` on
  /// macOS. Android has no such switch (D202).
  reduceTransparency,

  /// The application declared a ceiling for this device and the ceiling bound.
  ///
  /// The fourth of D59's reasons, and the only one of the four that survives as
  /// itself. It is a declaration because the package has no way to earn it:
  /// the rung is priced on two GPU families (D193, D194), and the price is not
  /// the question — whether this screen needs the saving is, and that is a
  /// fact about the application's frame.
  deviceCeiling,
}

/// One rung and the reason it holds.
@immutable
class GlassTierChoice {
  const GlassTierChoice(this.tier, this.reason);

  /// What every surface under this configuration paints.
  final GlassTier tier;

  /// Why. Quoted by reports; never read by the painting.
  final GlassTierReason reason;

  /// The rung a screen gets when nobody has said anything.
  static const GlassTierChoice byDefault = GlassTierChoice(
    GlassTier.full,
    GlassTierReason.byDefault,
  );

  @override
  bool operator ==(Object other) => other is GlassTierChoice && other.tier == tier && other.reason == reason;

  @override
  int get hashCode => Object.hash(tier, reason);

  @override
  String toString() => 'GlassTierChoice(${tier.name}, ${reason.name})';
}

/// Turns whatever an application knows into one rung.
///
/// Every input is a declaration, for the reasons at the top of this file. The
/// policy exists anyway, and not as decoration: the application's signals
/// arrive from three unrelated places and the order they resolve in is a
/// decision — see [GlassTierReason.pinnedByHost] for the one that is not
/// obvious.
@immutable
class GlassTierPolicy {
  const GlassTierPolicy({this.pinned, this.reduceTransparency = false, this.ceiling});

  /// The rung the host named. Overrides everything below it.
  final GlassTier? pinned;

  /// The platform's reduce-transparency switch, as the application read it.
  ///
  /// [GlassTier.opaque] rather than [GlassTier.cheap] when it is set, because
  /// that is what the switch does on the platform it comes from: a
  /// `UIVisualEffectView` under Reduce Transparency stops sampling and fills.
  /// A cheap rung would still be translucent, which is the property the setting
  /// exists to remove.
  final bool reduceTransparency;

  /// The richest rung this device should run, if the application has worked
  /// that out — by its own benchmark, its own device table, or a user setting.
  ///
  /// Null means no ceiling, and **the package supplies none**: the rung is a
  /// visible loss, and whether a screen can afford the top one is a question
  /// about the application's frame, which the package does not see.
  ///
  /// What the saving is, on Adreno 830 (D193, two seeds): [GlassTier.cheap]
  /// keeps 15…24% of the full rung's addition over an opaque floor on
  /// two-surface screens, 41…42% on fifteen surfaces and 69…71% on twelve small ones
  /// — ×0.79…0.86 Material against ×0.93…1.09 for the full rung, and ×1.09
  /// against ×1.20 on the small ones. So it pays in proportion to the glass's
  /// area rather than its count, and least where the glass is many small
  /// panels. [GlassTier.opaque] is not the cheaper of the two: 0.6…2.7% of the
  /// frame dearer than [GlassTier.cheap] on every scene and both seeds, the
  /// depth-writing fill paying for itself here as M9 found.
  ///
  /// On the M2 iPad Pro, in GPU time (D194, two seeds, the two scenes at
  /// Adreno's two ends): [GlassTier.cheap] keeps **3…7%** of the full rung's
  /// addition on both, ×0.98…1.08 Material against ×1.80…2.69 for the full
  /// rung. The layout stops mattering because the full rung's price there is
  /// the capture (D56), which every rung below takes none of; so a ceiling
  /// saves more on Metal than anywhere measured, and most on the screens where
  /// Adreno's saving was least. [GlassTier.opaque] cannot be told from
  /// [GlassTier.cheap] there (-4.1…+1.8% of the frame, the sign moving).
  ///
  /// Rungs are ordered by what they draw, so a ceiling of [GlassTier.cheap]
  /// permits `cheap` and `opaque` and forbids `full`.
  final GlassTier? ceiling;

  GlassTierChoice choose() {
    final GlassTier? pin = pinned;
    if (pin != null) {
      return GlassTierChoice(pin, GlassTierReason.pinnedByHost);
    }
    if (reduceTransparency) {
      return const GlassTierChoice(GlassTier.opaque, GlassTierReason.reduceTransparency);
    }
    final GlassTier? cap = ceiling;
    if (cap != null && cap.index > GlassTier.full.index) {
      return GlassTierChoice(cap, GlassTierReason.deviceCeiling);
    }
    return GlassTierChoice.byDefault;
  }

  @override
  bool operator ==(Object other) =>
      other is GlassTierPolicy &&
      other.pinned == pinned &&
      other.reduceTransparency == reduceTransparency &&
      other.ceiling == ceiling;

  @override
  int get hashCode => Object.hash(pinned, reduceTransparency, ceiling);
}
