// At what resolution the proxy is recorded — the first of the two large levers
// phase A has, and the only one that does not need a surface type to exist.
//
// The budget says why it is first: over the floor, the addition splits tax 34% /
// capture 40% / blur 17% / shader 9% (D63). Capture is the biggest single line,
// and resolution is the one knob on it that quality has already been priced for.
//
// **Three measured facts, and they do not agree with intuition.**
//
//  1. **The saving is not the area.** Halving the pixel ratio costs 0.53 of full
//     price and quartering it 0.27, against the ideals 0.25 and 0.0625 — the law
//     is roughly `ratio^0.9`, not `ratio^2` (D28, M10). And it is a property of
//     the capture rather than of what is under it: zero content and 24 draw ops
//     per cell give 0.528 ± 0.021 against 0.533 ± 0.010.
//  2. **That law is Adreno's, and on Metal the *capture* is not charged for
//     resolution at all — measured, on the scale axis itself (D119).** The
//     capture model there is not re-fitted but *refuted*: what fits is
//     `C_frame + C_pass·n` with **no area term**, and the area coefficient is
//     negative (D56). That was the *side* axis, which moves area and content
//     coverage together; the scale axis, which moves only pixels, says the same
//     and slightly more. Halving the pixel ratio costs **1.04** of full price
//     and quartering it **1.06** — mean over four cells, sd 0.04, exponent
//     **-0.05 ± 0.06** where Adreno's is 0.9. `C_pass` is the same at all three
//     scales to 1.9% (0.934 / 0.931 / 0.949 ms).
//
//     **And reading that as "the divisor is not a lever on Metal" was wrong, by
//     40% on the platform it was said about (D128).** The whole route measured
//     end to end on an iPad — the `glass` step of the M7 ladder against its own
//     floor, two blocks either side of a reboot — costs **0.604** of its full
//     price at a divisor of 4, and it is the largest lever the route has there.
//     No contradiction with D119: the capture is one term of the route, and
//     everything else the route does with the proxy pays by area — the residual
//     blur over the atlas, the texture's own bandwidth, the sampling in the
//     shader. A capture cost model answers a question about the capture, and a
//     policy that reads it as a question about the route forbids itself the
//     only large saving that platform has. [routeCostFactor] is the table that
//     is actually about the route; [captureCostFactor] stays because the merge
//     criterion is a capture question and reads it.
//  3. **What it costs in quality belongs to the finish, not to the glass.** The
//     ladder is 4.6x wider across finishes than across three steps of divisor —
//     `clear` pays 1.279 ΔE at a quarter where `regular` pays 0.222 — because
//     tolerance is bought by how little of the backdrop reaches the eye, not by
//     how blurred it is (D70). Against S4's scale of 34.8 ΔE between two of
//     Apple's own materials, `regular` at a quarter is 0.64% of the distance
//     between two shipping materials. ⚠️ Both columns are the ladder's own
//     recipe and the ladder runs at a device pixel ratio of 2 — which is a fact
//     about the *rung*, not about the run: see the fourth point below, where
//     that turned out to be the table's real key.
//
// **And the divisor is not independent of the blur, which the budget assumed.**
// Recording at 1/k is itself a low-pass: the detail above the texel grid is
// never rasterized and the magnification back is a reconstruction filter.
// Measured by MTF on a square-wave grating (D117): the pair is worth
// **0.30 logical px of Gaussian-equivalent sigma per unit of divisor**, and it
// composes with the finish's own blur in quadrature. Two consequences, and both
// are about numbers rather than taste:
//
//  - Blurring a 1/k recording by the finish's *whole* sigma over-blurs it —
//    12% at a quarter for `Glass.regular` on a dpr-1 view — so the residual the
//    blur pass should ask for is [residualSigmaFor], not the finish's own sigma.
//  - A divisor puts a **floor** under the finish. On a dpr-1 view `regular` at
//    sigma 2.6 is within 8% of its floor at an eighth and past it at a
//    sixteenth: at that point the proxy is blurrier than the material, and the
//    material cannot be rendered at all. [maxDivisorFor] is that ceiling.
//
// Both are stated per *texel*, not per divisor — the texel is the filter's only
// length, so the same divisor on a denser screen delivers proportionally less.
//
// **And so is the damage, which the table's own key did not say (D120).** The
// ladder runs at a device pixel ratio of 2, so its `res4` rung is a rung at half
// a texel per logical pixel; read on another screen as "a quarter" it is wrong
// by up to a factor of three. Run at densities 1, 2 and 4 — 84 arms per
// density, and the dpr-2 run reproduces the recorded ladder's 84 arms *exactly*,
// which is what licenses comparing them — the two rival keys separate cleanly:
//
//  - matched **texel scale**, three densities: median spread 12.9%, 0.045 ΔE;
//  - matched **divisor**, the same arms: median 115.5%, 0.488 ΔE, worst 2.44.
//
// The residual is content, and it splits along a line worth knowing. Scenes
// drawn entirely in logical units transport almost exactly (ratios 1.03/1.04,
// 1.04/1.00, 1.03/1.02 at dpr 1 and 4 against dpr 2) — that is the known-answer
// arm. Text does not: `over_text` reads 0.82 at dpr 1 and 1.21 at dpr 4, because
// glyph antialiasing puts energy up at the *device* grid, so a denser screen has
// more detail for a fixed texel scale to lose. **A denser screen is therefore
// slightly worse than the table says, never better**, and that is the direction
// a caller has to carry. The third group was the rig rather than the material:
// the corpus's photo is baked at the view's own device size and its finest layer
// is drawn one *pixel* wide, so `over_photo` and `many_cluster` swung 1.79/0.79
// — and pinning the bake to one density, which is the control, collapsed them to
// 1.13/1.01 and 1.05/1.01 while moving no other scene by a thousandth.
//
// Consequence, and it is the reason [damageAtTexelScale] exists beside
// [meanDamage]: **the two halves of this knob are indexed differently.** The
// price follows the divisor — it is a ratio of linear sizes and knows nothing
// about the screen (D28) — and the quality follows the texel. A policy that
// reads either table with the other's key is wrong by a factor, not by a
// percent.
//
// Consequence for the API, and it is the reason this file holds tables instead
// of a formula: **the right divisor is a function of the finish and of the
// backend**, and both of those are numbers somebody measured rather than
// constants anybody can derive. A bare `0.25` in a constructor carries neither.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// How the hardware charges for a capture — which decides whether resolution is
/// a lever at all.
enum ProxyCostModel {
  /// `C_pass·n + k·area`, fitted on Adreno 830 (M2, M10). The only model in
  /// which lowering the resolution saves anything.
  areaCharged,

  /// `C_frame + C_pass·n`, with no area term — Metal (D56). A capture costs
  /// about one more frame, once, whatever its size.
  frameCharged,

  /// Neither model has been fitted on this hardware. Every price below refuses
  /// rather than guessing; the Xclipse numbers are in a different unit again and
  /// the vendor GPUs have no counter at all.
  ///
  /// What it does **not** refuse any more is the divisor. For one release the
  /// chooser returned full resolution here, on the argument that a measured
  /// quality loss against an unmeasured saving is not a trade (D121, D130) —
  /// and the one unmeasured device anybody then ran got the worst hand
  /// available: 37 fps at full resolution against 115 at a quarter, where the
  /// stock Material holds 120 (D134). The saving's *size* is still unpriced
  /// here; its *sign* is now measured on every family that has been run —
  /// Adreno's capture (D28), Metal's route (D128) and Xclipse's route (D136,
  /// [ProxyResolution.xclipseRouteSources]) — and a policy that waits for a
  /// fourth family to disagree is waiting for a device nobody has.
  unmeasured,
}

/// A damage figure, and whether it is a reading or a bound.
///
/// [measured] is false when the texel scale asked for is off the table's own
/// rungs: interpolated between two of them, or coarser than the top one, where
/// monotonicity says "at most this" and nothing says more. A caller that needs
/// a value and is handed a bound is being told to measure, not to round.
typedef ProxyDamage = ({double deltaE, bool measured});

/// What the whole route costs at a divisor, relative to the same route at full
/// resolution — and whether that point was measured or interpolated between two
/// that were.
///
/// [measured] is false at the divisor the decomposition predicts and nobody has
/// run. Two points define a two-parameter model exactly, so its middle point has
/// no residual to be judged by: it is arithmetic, and it is labelled as such.
typedef ProxyRouteCost = ({double factor, bool measured});

/// The proxy's recording resolution, as an integer divisor of the device pixel
/// ratio.
///
/// An integer because that is what the ladder measured (1/2/4/8) and because it
/// keeps the ratio comparable between devices; on a device whose own ratio is
/// integral it also keeps one texel a whole number of device pixels, so the
/// source grid and the texel grid share a phase.
@immutable
class ProxyResolution {
  const ProxyResolution.divisor(this.divisor) : assert(divisor >= 1, 'the proxy is never larger than the screen');

  /// Recording at the screen's own resolution. What every capture measured
  /// before M10 was taken at.
  const ProxyResolution.full() : divisor = 1;

  const ProxyResolution.half() : divisor = 2;
  const ProxyResolution.quarter() : divisor = 4;

  final int divisor;

  /// Texels per logical pixel.
  double ratioFor(double devicePixelRatio) => devicePixelRatio / divisor;

  /// Capture price relative to [ProxyResolution.full] on the same hardware, or
  /// null when this point was never measured.
  ///
  /// Null rather than `pow(1 / divisor, 0.9)`: the exponent is itself a fit over
  /// three points, the eighth was never priced, and the roadmap's own rule is
  /// that a report's numbers are quoted where they were taken. A caller that
  /// wants the extrapolation can write it and own it.
  double? captureCostFactor(ProxyCostModel model) {
    switch (model) {
      case ProxyCostModel.areaCharged:
        return const <int, double>{1: 1.00, 2: 0.53, 4: 0.27}[divisor];
      case ProxyCostModel.frameCharged:
        // Not a saving that rounds to one: the model has no area term at all, so
        // the divisor is not on the price — and measured on the scale axis it is
        // slightly the wrong way round (D119). Same refusal as above past the
        // divisors that were run.
        return const <int, double>{1: 1.00, 2: 1.04, 4: 1.06}[divisor];
      case ProxyCostModel.unmeasured:
        return null;
    }
  }

  /// What the **whole route** costs at this divisor, relative to the same route
  /// at full resolution — or null where nobody has measured it.
  ///
  /// Stated over the *addition over the floor* rather than over the frame: the
  /// floor is the application's own UI and the package neither pays it nor
  /// changes it, so a frame-relative figure would be a statement about the
  /// scene as much as about the proxy. On the scene it was measured — two
  /// surfaces, 224 440 logical px² of glass over a photographic backdrop — the
  /// frame-relative figure is 0.604 at a divisor of 4.
  ///
  /// **Measured on Metal and nowhere else (D128).** Two blocks of the M7
  /// ladder, one either side of a reboot, differing in one input: the divisor
  /// the policy chose. Five of the six steps reproduced between the blocks to
  /// 0.5…1.7% and only `glass` moved, which is what makes the pair a comparison
  /// rather than two runs. The split it gives is
  ///
  /// ```
  /// addition = A + C,  A follows the proxy's area, C does not
  /// A = 1.618 ms   C = 1.163 ms = 1.10 of the floor frame
  /// ```
  ///
  /// and `C` landing on D56's own `C_frame`/baseline of 0.73…1.01 — measured on
  /// a different family, on the capture grid rather than on our route — is the
  /// one thing here that is a check rather than a fit.
  ///
  /// ⚠️ **Two points define these two parameters exactly**, so there is no
  /// residual and the divisor-2 row is a prediction (`measured: false`), not a
  /// reading. Its frame-relative value on that scene is ×2.48 of the floor, and
  /// taking it is the cheapest open experiment this file has.
  ///
  /// Null on [ProxyCostModel.areaCharged], and since 2026-09-11 for a different
  /// reason than "nobody ran it". The route **was** measured there (D153, D154):
  /// four divisors on two scenes in one binary, and the area family describes
  /// the valid points to a worst residual of 4.3% and 1.1% — where on Metal the
  /// shape itself is refuted. Two things still stop it becoming a column here,
  /// and both are about what this table *is* rather than about the run.
  ///
  /// Metal's column is normalised to divisor 1, and on Adreno that arm is **off
  /// vsync** (36.8 and 54.8 fps of 120) — the harness excludes it from its own
  /// fits, because cycles-per-frame there divides one frame's work by fewer
  /// frames. A column normalised to divisor 2 instead would be a different
  /// quantity wearing the same name, which is the defect D128 is named for.
  ///
  /// And the two scenes disagree: the divisor-4 row is 0.194 of the addition on
  /// `bank_home` and 0.271 on `over_photo`, 40% apart, while Metal's column came
  /// from one scene and was never shown to travel. A table quoted per divisor
  /// that is really per scene is D120's rule with the key wrong again.
  ProxyRouteCost? routeCostFactor(ProxyCostModel model) {
    switch (model) {
      case ProxyCostModel.frameCharged:
        if (divisor < 1 || divisor > 8) {
          // Same refusal as the capture table's: past the divisors that were
          // run there is no curve to read off, and D139 is why the refusal is a
          // refusal rather than an extrapolation — every family fitted to the
          // first three points predicted the fourth wrongly, by -10% (area) to
          // +20% (D28's exponent), in both directions.
          return null;
        }
        // Four readings, not a formula over any of them.
        //
        // This used to be `(1 - share) + share / divisor²`, with the middle row
        // labelled a prediction. D138 took that row and it came back **18.6%**
        // above what the formula said, against a run whose two anchors
        // reproduced the blocks the formula was fitted on to 0.10% and 0.48%.
        // So the area family is not what the route follows here, and a formula
        // built on it is wrong in the one place it was never checked.
        //
        // D139 then took the fourth divisor and refuted the *shape*, not just
        // one family of it: no `A·k^-p + C` at any exponent predicts a held-out
        // interior point to better than 1.5x what the repeats moved. The curve
        // has a knee — 0.94, 0.65 and **0.05** ms across the three intervals,
        // where a power law's drops fall by a constant ratio. The rows are
        // measurements and nothing here interpolates between them.
        //
        // And D140 said why there was no shape to find: what a divisor buys is
        // the residual blur pass and nothing else (115% of the fall — without
        // the pass a smaller proxy is *dearer*), so this column is one term that
        // follows the divisor steeply on top of one that does not follow it at
        // all. See [metalBlurSplitSource]. The practical half is that the lever
        // named here is really a blur knob, and a finish with no sigma gets
        // nothing from it but damage.
        //
        // All four come from one run under one shuffle (`metalRouteCostSource`).
        // The three D138 also measured reproduce to 0.75% and 1.11% *as ratios*,
        // across a reboot and a different seed — better than the absolutes
        // agree (0.7...2.0%), because a run-wide offset cancels out of a ratio.
        const Map<int, double> measured = <int, double>{
          1: 1.0,
          2: 0.6713,
          4: 0.4439,
          // Not a saving. 4.1% of the addition and 1.3% of the full-resolution
          // frame, against a between-run reproducibility of about 1% — this row
          // exists to record that the lever has run out, which is a thing the
          // table can say and a formula cannot.
          8: 0.4258,
        };
        final double? factor = measured[divisor];
        if (factor == null) {
          // Includes 3: an integer inside the span is still a divisor nobody
          // ran, and interpolating between families that disagree by 4x is not
          // a reading.
          return null;
        }
        return (factor: factor, measured: true);
      case ProxyCostModel.areaCharged:
      case ProxyCostModel.unmeasured:
        // See the doc comment: measured on Adreno since D154 and still not a
        // column, because divisor 1 there is not a frame price and the two
        // scenes disagree by 40% at divisor 4.
        return null;
    }
  }

  /// The share of our route's addition over the floor that a divisor can buy
  /// back on Metal, and it is **not resolved** — the three points that exist
  /// disagree by family.
  ///
  /// 0.5818 is what a two-point fit of `A·f + C` over divisors 1 and 4 returned
  /// with `f = 1/k²`, and it was quoted as "a divisor can never buy back more
  /// than 58.2%". D138 measured the middle point and refuted the family that
  /// number belongs to: re-fitted over all three, `f = 1/k²` leaves a worst
  /// residual of 6.4% while `f = 1/k` leaves 2.2% and `f = (1/k)^0.9` — D28's
  /// exponent, measured on Adreno's *capture* in a different experiment — leaves
  /// **1.6%**. Under the last of those the area-following share is 76.6%, not
  /// 58.2%, so the ceiling on the lever is higher than this constant says rather
  /// than lower.
  ///
  /// It is kept, with its old value, for one job: it is what
  /// `test/glass/proxy_resolution_test.dart` re-derives from the two blocks, so
  /// that the arithmetic which produced the refuted prediction stays checkable.
  /// **Do not price anything with it.** [routeCostFactor] no longer does.
  ///
  /// What three points cannot do is choose the family: each candidate has two
  /// parameters, so each is exact on two points and judged by one residual. A
  /// factor of four between families is evidence that area is the wrong one; it
  /// is not a measurement of the exponent.
  ///
  /// D139 took the fourth divisor, and it did not settle the exponent — it
  /// removed the question. Fitted on the same three points, every family
  /// predicted the fourth and every one missed: area by -10.1%, `f^0.75` by
  /// -1.5%, linear by +14.9% and D28's 0.9 by +19.9%. So the family that fitted
  /// the three points *best* predicted the fourth *worst*, which is what an
  /// in-sample residual over three points is worth. No exponent anywhere on the
  /// grid describes all four: the drops across the intervals are 0.94, 0.65 and
  /// 0.05 ms, and a power law's drops fall by a constant ratio. There is no
  /// share of the addition that follows area, because nothing here follows a
  /// power of the proxy's size at all.
  static const double metalAdditionAreaShare = 0.5818;

  /// The pair of runs [routeCostFactor] is read from, digested to their cells.
  ///
  /// Tracked in the repository for the same reason the damage tables' reports
  /// are: a constant baked into `lib/` that a fresh clone cannot check is a
  /// number somebody remembered. Re-derived by
  /// `test/glass/proxy_resolution_test.dart`, together with the control that
  /// makes them one measurement — the five steps that did *not* move.
  static const Map<int, String> metalRouteSources = <int, String>{
    1: 'provenance/digest/ipad-m7glass-a.json',
    4: 'provenance/digest/ipad-m7glass-q4.json',
  };

  /// The run that first put three divisors in one binary under one shuffle.
  ///
  /// Separate from [metalRouteSources] rather than replacing it, because the two
  /// are used for different things: those two blocks are what the *prediction*
  /// was built on and what this run had to reproduce before its third point
  /// meant anything, and it did — `plain` 0.50%, `material` 0.56%, `backdrop`
  /// 1.71%, and the two glass anchors 0.10% and 0.48% across two reboots.
  static const String metalThreePointSource = 'provenance/digest/ipad-m7glass-3pt.json';

  /// The run [routeCostFactor]'s four factors are read from — one binary, one
  /// shuffle, one floor, all four divisors as an axis of the family.
  ///
  /// It supersedes [metalThreePointSource] as the *table's* source and does not
  /// replace it as a record: three of these four arms were measured twice, under
  /// two seeds and either side of a reboot, and the agreement between the two
  /// runs is what says the fourth point belongs on the same curve rather than to
  /// a different afternoon.
  static const String metalRouteCostSource = 'provenance/digest/ipad-m7glass-4pt.json';

  /// The run that says what a divisor actually buys, by turning the residual
  /// blur pass off and measuring the same two divisors again (D140).
  ///
  /// The answer is that it buys that pass and nothing else. With the blur on,
  /// an eighth is 1.69 ms cheaper than full resolution; with it off, an eighth
  /// is 0.25 ms **dearer** — so the pass's own fall is 115% of the route's. What
  /// is left when it is gone costs 0.731 of the floor frame at a divisor of 1
  /// and 0.967 at 8, which is inside D56's measured band for what a capture
  /// costs (0.73…1.01) with no fit involved at all.
  ///
  /// Consequence for reading everything above: a two-term form was the wrong
  /// shape for the *route*, because the route is a pass that follows the divisor
  /// steeply plus a capture that on Metal does not follow it at all (D119). The
  /// fitted `C` of D128 was trying to be the capture's constant and was
  /// absorbing part of a blur that does not follow area, which is why it came
  /// out 8.8% above the band.
  static const String metalBlurSplitSource = 'provenance/digest/ipad-m7glass-blur.json';

  /// The middle of that curve, which says the knee belongs to the blur pass
  /// itself rather than to the route around it (D141).
  ///
  /// The discriminating cell was a divisor of 2 and the two candidate answers
  /// were written down before the run: a power law through D140's two points
  /// predicts 0.814 ms for the pass there, and the knee hypothesis needs about
  /// 1.06 to reconstruct D139's total. The device returned **1.108** — the power
  /// law missed by 36%, the knee by 4.5%.
  ///
  /// So the pass's own price is not a power of the proxy's size either: 1.964 /
  /// 1.108 / 0.288 ms at divisors 1, 2 and 4, whose pairwise exponents are 0.83,
  /// 1.94 and 1.27, with the *middle* interval the steepest. And Impeller is not
  /// the explanation: `CalculateScale` returns 1.0 below a sigma of 4 texels and
  /// rounds `4/sigma` to a power of two above it
  /// (`gaussian_blur_filter_contents.cc:751-765`), so at our largest texel sigma
  /// of 5.20 the engine's own downsample never engages on any arm here. It would
  /// at 5.66, which is `regular` at full resolution on a dpr-3 screen.
  ///
  /// The number to carry into a budget is not D140's headline. At the divisor
  /// the policy actually picks on a dpr-2 screen, the addition splits **77% not
  /// the blur / 23% the blur**; 73% was the full-resolution figure.
  static const String metalBlurCurveSource = 'provenance/digest/ipad-m7glass-blur2.json';

  /// The two runs that licence [ProxyResolutionPolicy.choose] walking the
  /// divisor ladder on [ProxyCostModel.unmeasured] at all, digested to their
  /// cells and keyed by the shuffle seed they ran under.
  ///
  /// Xclipse 920 is the one device this package has run on that no cost model
  /// fits, and it is therefore the only evidence about what `unmeasured`
  /// actually gets. Both seeds put the `bank_home` glass step at divisors 1 and
  /// 4 in one binary under one shuffle, beside the floor: **37 fps against 115**,
  /// with the proxy recorded every frame on both arms (D133, D134). The metric
  /// is wall clock and not cycles, because on this device `busy × frequency`
  /// reads an added submission up to 25% cheaper (Д3) and the full-resolution
  /// arm is off vsync, where cycles per frame are not a frame price.
  ///
  /// What they do **not** give is a number for [routeCostFactor]: the two-term
  /// decomposition returns a negative `C` there (the quarter arm sits 4% over
  /// the floor and vsync pins it from below), so the route's price on this
  /// family has a measured *sign* and no coefficient. That is exactly the
  /// difference between choosing a divisor on quality — which this licences —
  /// and pricing one, which it does not.
  static const Map<int, String> xclipseRouteSources = <int, String>{
    20260908: 'provenance/digest/s22u-m7glass-bank-wall.json',
    20260909: 'provenance/digest/s22u-holdpair-bank-wall.json',
  };

  /// The run that measured the default *after* D136, on a third seed: the
  /// silent host's arm (`glass`, `glass_pinned_divisor: policy`,
  /// `glass_hardware: detect`) beside the two ends it could have landed on,
  /// pinned 1 and pinned 4, in one binary under one shuffle.
  ///
  /// It landed on the quarter: 8.339 ms against the pinned quarter's 8.341 and
  /// the floor's 8.354, at 119.9 fps, with the proxy recorded every frame —
  /// and the pinned full resolution at 25.5 ms and 39 fps in the same run. Not
  /// in [xclipseRouteSources], because it is not the same measurement: those
  /// two are the *before*, with the quarter arm unmerged and off vsync (the
  /// merge gate fell in the same change), and this one has both refusals
  /// gone, which puts every glass arm but the pinned full resolution on the
  /// display's period where the wall clock is a floor and not a price.
  static const String xclipseDefaultSource = 'provenance/digest/s22u-d136-bank-wall.json';

  /// Mean ΔE against the *same finish* at full resolution, over the seven corpus
  /// scenes of the M11 ladder, or null for a divisor the ladder never ran.
  ///
  /// Read it as damage relative to that finish, never as an absolute: a more
  /// opaque finish is more forgiving by construction. The number that makes it
  /// comparable across finishes is [kMaterialScaleDeltaE].
  ///
  /// [blurCorrected] picks the recipe. Off is what every recorded M11 number was
  /// taken with — the proxy blurred by the finish's whole sigma on top of the
  /// low-pass the divisor already applied — and is the column comparable with
  /// D29 and D70. On is what a shipping surface should do, and it is **not
  /// uniformly better**: it removes the over-blur, which was partly cancelling
  /// the lost detail, so smooth scenes gain up to 34% and text-heavy ones lose
  /// up to 7% (D118).
  double? meanDamage(String finish, {bool blurCorrected = false}) =>
      (blurCorrected ? _damageCorrected : _damage)[finish]?[divisor];

  /// Gaussian-equivalent sigma the recording delivers on its own, **in texels**
  /// — the rasterization at the texel grid plus the bilinear reconstruction
  /// back (D117).
  ///
  /// Per texel rather than per divisor, because the texel is the filter's only
  /// length: at a device pixel ratio of 2 the same divisor covers half as many
  /// logical pixels and delivers half the sigma. Measured both ways — 0.356 /
  /// 0.308 / 0.294 per unit of divisor at dpr 1 for divisors 2 / 4 / 8, each
  /// from three periods agreeing to better than 1%, and the dpr-2 arm returning
  /// half of the dpr-1 one. The value taken is what the two well-sampled
  /// divisors agree on: at a divisor of 2 the attenuation is only readable near
  /// the texel scale, where a Gaussian equivalent is at its weakest, so that arm
  /// reads high.
  static const double sigmaPerTexel = 0.30;

  /// What this divisor low-passes the proxy by, in logical pixels, before any
  /// blur pass runs — **relative to a full-resolution recording**, which is the
  /// frame every comparison here is made in.
  ///
  /// Zero at [ProxyResolution.full] by construction, not by physics: recording
  /// at 1:1 has a filter of its own, and the measurement divided it out by using
  /// that recording as its reference. The proportional model is fitted on
  /// divisors 2, 4 and 8 and does not extend to 1.
  double deliveredSigmaLogical(double devicePixelRatio) =>
      divisor == 1 ? 0 : sigmaPerTexel * divisor / devicePixelRatio;

  /// The sigma a blur pass should ask for so the finish lands at
  /// [finishSigmaLogical] rather than past it — or null when this divisor has
  /// already exceeded the finish and no blur can undo it.
  ///
  /// In logical pixels, and it needs the device pixel ratio for the same reason
  /// [deliveredSigmaLogical] does.
  ///
  /// Quadrature, because that is what the arms measured: total sigma comes back
  /// as `sqrt(delivered^2 + asked^2)` to within 15% over four combinations of
  /// divisor and finish. ⚠️ The residual of that check is one-sided — the
  /// measured total runs 2…15% *above* the prediction, more at the larger finish
  /// sigma — and nothing explains it yet, so a caller reaching for the last few
  /// percent of a blur budget should measure rather than trust this.
  double? residualSigmaFor(double finishSigmaLogical, double devicePixelRatio) {
    final double delivered = deliveredSigmaLogical(devicePixelRatio);
    final double residual = finishSigmaLogical * finishSigmaLogical - delivered * delivered;
    return residual <= 0 ? null : math.sqrt(residual);
  }

  /// Mean ΔE at a **texel scale** — texels per logical pixel, which is what
  /// [ratioFor] returns and what the damage actually indexes on (D120).
  ///
  /// The table's rungs are the dpr-2 ladder's `res2`, `res4` and `res8`, which
  /// sit at 1.0, 0.5 and 0.25 texels per logical pixel. Between them this
  /// interpolates in log-log, which is a choice with no measurement behind it
  /// beyond the curve being smooth and monotone — but the alternative is
  /// refusing every screen whose density is not 2, and a real phone at dpr 3
  /// lands on none of the rungs at any integer divisor.
  ///
  /// Three refusals, and the last is the one that matters:
  ///
  ///  - an unknown finish, or a texel scale finer than the deepest rung (0.25):
  ///    null. Past the measured end the curve is still rising and nothing says
  ///    how fast.
  ///  - a texel scale coarser than the top rung (1.0): the top rung's damage
  ///    with `measured: false`. That is a **bound**, not a reading — damage
  ///    falls with the texel scale everywhere the ladder ran, so a coarser
  ///    recording cannot cost more. The value at the top of the curve cannot be
  ///    read off the dpr-2 ladder at all, because its divisor-1 rung is the
  ///    reference and scores 0.000 by construction at every density — at dpr 4
  ///    the same texel scale of 2.0 costs 0.314 ΔE on `clear`, which is the
  ///    measurement that shows the zero is a definition rather than a point.
  ///  - anything at all when the finish transmits nothing that a texel could
  ///    cost it: not modelled here, because no such finish is measured.
  static ProxyDamage? damageAtTexelScale(
    String finish,
    double texelsPerLogicalPixel, {
    bool blurCorrected = false,
  }) {
    final Map<int, double>? table = (blurCorrected ? _damageCorrected : _damage)[finish];
    if (table == null) {
      return null;
    }
    // Descending in texel scale, which is ascending in divisor.
    final List<int> divisors = measuredDivisors;
    final List<double> scales = <double>[
      for (final int divisor in divisors) damageTableDevicePixelRatio / divisor,
    ];
    final List<double> values = <double>[
      for (final int divisor in divisors) table[divisor]!,
    ];
    if (texelsPerLogicalPixel >= scales.first) {
      return (deltaE: values.first, measured: texelsPerLogicalPixel == scales.first);
    }
    if (texelsPerLogicalPixel < scales.last) {
      return null;
    }
    for (var i = 0; i < scales.length; i++) {
      // A rung returns the table's own number rather than the interpolation's
      // value at t = 0, which is `exp(log(y))` and differs in the last bit.
      if (texelsPerLogicalPixel == scales[i]) {
        return (deltaE: values[i], measured: true);
      }
    }
    for (var i = 0; i < scales.length - 1; i++) {
      if (texelsPerLogicalPixel <= scales[i] && texelsPerLogicalPixel >= scales[i + 1]) {
        final double t =
            (math.log(texelsPerLogicalPixel) - math.log(scales[i + 1])) /
            (math.log(scales[i]) - math.log(scales[i + 1]));
        final double deltaE = math.exp(
          math.log(values[i + 1]) + t * (math.log(values[i]) - math.log(values[i + 1])),
        );
        return (deltaE: deltaE, measured: false);
      }
    }
    return null;
  }

  /// The largest divisor at which a finish of [finishSigmaLogical] is still
  /// reachable — a ceiling from the optics, not a recommendation.
  ///
  /// Above it the proxy is blurrier than the material, and no amount of tint or
  /// rim work makes that back: the surface would be showing a blur nobody asked
  /// for. `Glass.regular` (2.6) caps at 8 on a dpr-1 view and at 17 on a phone
  /// at dpr 2; `Glass.frosted` (8.0) is never threatened by any divisor this
  /// project would use.
  ///
  /// **It reads 1 at sigma 0 and the policy stopped consulting it there (D164).**
  /// The floor is arithmetic — every divisor out-blurs a material that asked for
  /// no blur — so for `clear` and `identity` this was a ceiling of 1 on every
  /// screen at every budget, which is a refusal rather than a ceiling. Where the
  /// material does have blur the policy still gates on this, because the damage
  /// tables are keyed by the finish's name and cannot see a thin sigma.
  static int maxDivisorFor(double finishSigmaLogical, double devicePixelRatio) {
    final int cap = (finishSigmaLogical * devicePixelRatio / sigmaPerTexel).floor();
    return cap < 1 ? 1 : cap;
  }

  /// The reports `test/glass/proxy_recorder_test.dart` re-derives the two tables
  /// from. Tracked rather than ignored like every other report, because a
  /// constant baked into the package needs its source in the repository.
  ///
  /// **Not `d70-split`, which is where these numbers first came from and which
  /// was taken on the pre-M13 optics** (strength 14.0, edge power 3.0 against
  /// today's -58.2, 1.9 and a shoulder). It described a surface this package no
  /// longer renders, and 260 of its 308 graded arms move; the first version of
  /// this table quoted it and was wrong for that reason rather than for any
  /// arithmetic one.
  /// ⚠️ Labelled `d186-*` rather than `d187-*`: the three runs were taken before
  /// the session's two findings were split into a number each, and a report is
  /// kept as it came off the rig rather than renamed to match the prose.
  static const String damageSource = 'provenance/quality/d186-uncorrected-2026-09-14T20-16-32.json';
  static const String damageSourceCorrected = 'provenance/quality/d186-corrected-2026-09-14T20-18-05.json';

  /// Where `regularLight`'s rows came from (D230): the same ladder, both
  /// recipes, over `regular` and `regularLight` — and the `regular` arms are
  /// the control, reproducing [damageSource] and [damageSourceCorrected] to
  /// 0.0006 ΔE, which is what lets a row from another run sit in this table.
  static const String lightDamageSource = 'provenance/quality/d230-light-uncorrected-2026-10-03T00-39-20.json';
  static const String lightDamageSourceCorrected = 'provenance/quality/d230-light-corrected-2026-10-03T00-40-09.json';

  /// The run that says the table's key survives a magnification that is not a
  /// power of two (D187), and the reason the 3 and 6 rungs can be read the same
  /// way as the others.
  ///
  /// D120 established that damage follows the texel scale rather than the
  /// divisor, and every arm it compared happened to magnify by a power of two:
  /// texel 0.5 is divisor 2 at dpr 1, 4 at dpr 2 and 8 at dpr 4. A texel is
  /// `divisor` device pixels wide, so a rung at divisor 3 or 6 reconstructs
  /// through a filter with three sub-texel phases instead of two or four — one
  /// of them exactly on a texel centre — and the obvious guess was that this
  /// costs something the texel scale cannot see.
  ///
  /// It does not. At dpr 3 with the backdrop pinned to one density, texel 1.0
  /// (magnification 3) lands at 0.93…1.02 of the same texel scale at dpr 2
  /// (magnification 2), and texel 0.5 (magnification 6) at 1.02…1.06 of
  /// magnification 4 — inside [transportSpreadMedian] on every finish. The
  /// prediction that discriminates was written before the run.
  static const String magnificationSource = 'provenance/quality/d186-dpr3-pin2-2026-09-14T20-23-47.json';

  /// The same ladder at three screen densities — the run that says which key
  /// the damage table has (D120). Keyed by the device pixel ratio.
  ///
  /// Tracked for the same reason as the two above, and read by
  /// `test/glass/proxy_resolution_test.dart`, which re-derives the transport
  /// claim from them rather than restating it: matched texel scales agree,
  /// matched divisors do not, and the middle one reproduces
  /// [damageSource] arm for arm.
  static const Map<int, String> transportSources = <int, String>{
    1: 'provenance/quality/d120-dpr1-2026-09-08T07-53-35.json',
    2: 'provenance/quality/d120-dpr2-2026-09-08T07-53-58.json',
    4: 'provenance/quality/d120-dpr4-2026-09-08T07-55-09.json',
  };

  /// The control for the same run: the corpus's photographic backdrop pinned to
  /// one density instead of following the view, at dpr 1 and 4.
  ///
  /// It exists because two of the seven scenes disagreed with the transport
  /// claim by a factor of two and the explanation — that their content is drawn
  /// in *device* pixels, so it is not the same picture on a denser screen —
  /// would otherwise have been a story. With the bake pinned they fall into
  /// line and nothing else moves.
  static const Map<int, String> transportControlSources = <int, String>{
    1: 'provenance/quality/d120-pin1-2026-09-08T07-51-51.json',
    4: 'provenance/quality/d120-pin4-2026-09-08T07-52-47.json',
  };

  /// The density the damage table was taken at — which is what makes its rungs
  /// texel scales of 1.0, 0.5 and 0.25 rather than divisors of 2, 4 and 8.
  static const double damageTableDevicePixelRatio = 2;

  /// How far apart two arms at the same texel scale and different densities
  /// landed, over densities 1…4: the accuracy of every number
  /// [damageAtTexelScale] returns away from its own rung.
  ///
  /// Median rather than worst, and stated with its own worst case in the file
  /// header, because the tail belongs to one scene and one mechanism (text)
  /// rather than to the reading.
  static const double transportSpreadMedian = 0.129;

  /// ΔE between `Glass.regular` and `Glass.clear` on one backdrop (S4).
  ///
  /// The only external unit this project has. A damage figure divided by it is
  /// "this fraction of the distance between two of Apple's own materials".
  static const double kMaterialScaleDeltaE = 34.8;

  /// Finishes the ladder has run, in the order of how much backdrop they let
  /// through — which is also the order of how much a lost texel costs them.
  static const List<String> measuredFinishes = <String>[
    'clear',
    'thinLight',
    'frosted',
    'regularDark',
    'regularLight',
  ];

  /// Keyed by the ladder's divisor, which at [damageTableDevicePixelRatio] is a
  /// texel scale of `2 / divisor` — 1.0, 0.667, 0.5, 0.333 and 0.25.
  ///
  /// The 3 and 6 rungs arrived with D187 and the run that took them reproduced
  /// every one of the other three **to 0.00%**, which is what says they belong
  /// to the same measurement rather than to a second afternoon.
  static const Map<String, Map<int, double>> _damage = <String, Map<int, double>>{
    'clear': <int, double>{1: 0.0, 2: 0.646, 3: 1.168, 4: 1.279, 6: 1.790, 8: 1.999},
    'thinLight': <int, double>{1: 0.0, 2: 0.264, 3: 0.459, 4: 0.449, 6: 0.779, 8: 0.760},
    'frosted': <int, double>{1: 0.0, 2: 0.281, 3: 0.398, 4: 0.500, 6: 0.623, 8: 0.652},
    // The ladder's `regular` until D230.
    'regularDark': <int, double>{1: 0.0, 2: 0.143, 3: 0.235, 4: 0.222, 6: 0.379, 8: 0.372},
    // [lightDamageSource]: its own run, whose `regular` arms reproduce
    // [damageSource]'s to 0.0006 — the same ladder on another afternoon.
    'regularLight': <int, double>{1: 0.0, 2: 0.108, 3: 0.174, 4: 0.167, 6: 0.285, 8: 0.282},
  };

  static const Map<String, Map<int, double>> _damageCorrected = <String, Map<int, double>>{
    'clear': <int, double>{1: 0.0, 2: 0.646, 3: 1.168, 4: 1.279, 6: 1.790, 8: 1.999},
    'thinLight': <int, double>{1: 0.0, 2: 0.264, 3: 0.462, 4: 0.443, 6: 0.774, 8: 0.757},
    'frosted': <int, double>{1: 0.0, 2: 0.281, 3: 0.398, 4: 0.484, 6: 0.623, 8: 0.565},
    'regularDark': <int, double>{1: 0.0, 2: 0.143, 3: 0.235, 4: 0.221, 6: 0.380, 8: 0.374},
    'regularLight': <int, double>{1: 0.0, 2: 0.108, 3: 0.173, 4: 0.164, 6: 0.281, 8: 0.282},
  };

  /// The divisors the tables above have rows for, deepest last.
  ///
  /// Read off the table rather than written down, so that adding a rung is one
  /// edit: [damageAtTexelScale] interpolates between consecutive entries and
  /// [ProxyResolutionPolicy.candidateDivisors] is exactly this list.
  ///
  /// `static final` rather than a getter: [damageAtTexelScale] reads it on every
  /// lookup and the chooser makes five of those per capture, so a getter that
  /// built and sorted a list would allocate six of them per recorded frame for
  /// an answer that cannot change.
  static final List<int> measuredDivisors = List<int>.unmodifiable(
    _damage['regularDark']!.keys.where((int d) => d > 1).toList()..sort(),
  );

  @override
  bool operator ==(Object other) => other is ProxyResolution && other.divisor == divisor;

  @override
  int get hashCode => divisor.hashCode;

  @override
  String toString() => divisor == 1 ? 'ProxyResolution.full' : 'ProxyResolution.divisor($divisor)';
}

/// Why the chooser stopped where it did.
///
/// Carried in the result rather than logged, because every one of these is a
/// different conversation with whoever asked: "your hardware has no lever",
/// "your finish cannot take one" and "the next step was never priced" all look
/// identical from the divisor alone.
enum ProxyDivisorReason {
  // Two reasons have been deleted from here, and both were the hardware
  // stopping the walk.
  //
  // `noLever` was Metal: the capture is frame-charged there (D56, D119), so
  // the chooser returned full resolution and said there was nothing to trade.
  // The device then measured the route at **0.604** of full price at a divisor
  // of 4 (D128) — the capture is one term of it, and the rest pays by area.
  //
  // `hardwareUnmeasured` was everything else, which on Android is every
  // device: no cost model fitted, so "a measured loss against an unmeasured
  // gain is not a trade" and the chooser returned full resolution. The one
  // unmeasured device anybody ran then got 37 fps where a quarter gets 115
  // (D134) — the same shape as `noLever`, on the platform the package will
  // mostly run on. Both are gone rather than renamed, because nothing measured
  // stops the walk on the hardware side any more: the divisor's saving has the
  // same sign on all three families run (D28, D128, D136), and only its size
  // is unknown on the third. What the hardware still decides is the *price*
  // ([ProxyResolutionChoice.routeCostFactor] is null on `unmeasured`), not the
  // choice.

  /// The next divisor up would cost more quality than the budget allows, or
  /// would land off the measured end of the damage curve, which is the same
  /// answer arrived at by refusing to extrapolate.
  damageBudget,

  /// The next divisor up would low-pass the proxy past the finish's own blur
  /// ([ProxyResolution.maxDivisorFor]). Past that the surface shows a blur
  /// nobody asked for, and no tint makes it back.
  ///
  /// Only ever returned for a finish that *has* blur. A blurless one is refused
  /// by the budget instead (D164), because there the ceiling is 1 by arithmetic
  /// and says nothing the damage table has not measured directly.
  opticsCeiling,

  /// Nothing stopped it: budget and optics both allow more, and the ladder has
  /// no deeper rung to say what more would cost.
  ///
  /// It was called `unpricedSaving` until D187 and meant the other half of the
  /// trade — both devices priced divisors 2 and 4 and neither priced 8, so
  /// going deeper was a measured loss against an imagined gain. That stopped
  /// being what the walk does when D135 took the cost model out of the choice;
  /// what actually ends the walk here is the **damage** table running out of
  /// measurements, and the difference is not cosmetic. D187 measured two rungs
  /// between the old ones and found the log-log interpolation low by 3…29% at
  /// every one of eight points, never high — so a walk that carried on past the
  /// deepest rung would be spending its budget against a number that is biased
  /// in the direction that overspends it.
  ///
  /// A caller seeing this is being told the honest thing: the budget has room,
  /// and buying it needs a ladder run, not a bolder policy.
  offTheLadder,

  /// The divisor the quality walk returned would have packed an atlas larger
  /// than the GPU can hold, so it was deepened until the atlas fits (D186).
  ///
  /// The one reason here that is not a statement about quality, and the only
  /// one that can **overrule** the budget: the alternative is not a worse
  /// picture but a wrong one, because the engine rescales an oversized snapshot
  /// without telling anybody ([AtlasLayout.fitsTexture]). The damage reported
  /// beside it is the real damage at the divisor that was forced, which may be
  /// past the budget and may be null — off the measured end of the table
  /// entirely. A host seeing this is being told to expect a visibly softer
  /// proxy, and that the fix is a smaller surface or a larger declared
  /// [GlassHardware.maxTextureSide], not a larger budget.
  textureCeiling,

  /// Nothing was chosen: the host named the divisor and the policy was not
  /// asked.
  ///
  /// It exists because the tables above are not a law yet and cannot become one
  /// without it. The route's price against its own floor is known at exactly two
  /// divisors on one platform (1 and 4, D128), and two points fit a
  /// two-parameter model exactly — so the residual that would turn the
  /// decomposition into a law can only come from a *third* divisor, which the
  /// policy will never return because its job is to pick the best one rather
  /// than an interesting one. A pin is how a divisor gets priced at all; the
  /// alternative was reaching it sideways through [damageBudgetDeltaE], which
  /// moves the retake ceiling in the same breath (D131) and would have made the
  /// third point differ from the first two along two axes instead of one.
  ///
  /// It does not check the optics ceiling. Refusing there would forbid pricing
  /// the very rungs whose price is missing, and the consequence of overshooting
  /// is visible rather than silent: the surface shows a blur nobody asked for.
  pinnedByHost,
}

/// What the chooser decided, and enough to argue with it.
@immutable
class ProxyResolutionChoice {
  const ProxyResolutionChoice({
    required this.resolution,
    required this.reason,
    required this.damage,
    required this.captureCostFactor,
    required this.routeCostFactor,
  });

  final ProxyResolution resolution;

  /// What stopped it going deeper.
  final ProxyDivisorReason reason;

  /// Expected mean ΔE against the same finish at full resolution — null at
  /// [ProxyResolution.full], where the arm *is* the reference.
  ///
  /// Damage relative to that finish, never an absolute: a more opaque finish is
  /// more forgiving by construction. Divide by
  /// [ProxyResolution.kMaterialScaleDeltaE] to compare across finishes.
  final ProxyDamage? damage;

  /// Capture price relative to full resolution under the cost model asked for.
  ///
  /// Not what the divisor is chosen on — the capture is one term of the route,
  /// and on Metal it is the term that does *not* move (D119 against D128). It
  /// is here because it is what the merge criterion reads, and because a caller
  /// comparing the two columns is looking at the mistake this chooser used to
  /// make.
  final double? captureCostFactor;

  /// Price of the **whole route** at this divisor, relative to full resolution,
  /// as a fraction of its own addition over the floor — or null where nobody
  /// measured it ([ProxyResolution.routeCostFactor]).
  final ProxyRouteCost? routeCostFactor;

  @override
  String toString() =>
      'ProxyResolutionChoice(1/${resolution.divisor}, ${reason.name}, '
      'dE ${damage == null ? '—' : damage!.deltaE.toStringAsFixed(3)}, '
      'capture ${captureCostFactor?.toStringAsFixed(2) ?? '—'}, '
      'route ${routeCostFactor == null ? '—' : routeCostFactor!.factor.toStringAsFixed(2)})';
}

/// Chooses the divisor.
///
/// The roadmap's third item for phase A is "the one who chooses the divisor,
/// because the choice is a function of the finish, of the platform and of the
/// screen's density". All three are inputs here and not one of them is a
/// preference: each is a table somebody measured, and this class is the
/// arithmetic that puts them together plus the three places it refuses.
///
/// What it deliberately does not do is detect the platform. [ProxyCostModel]
/// separates Adreno from Metal, and **nothing in Dart tells those apart on
/// Android**: the same grid on Xclipse 920 returned `usable: false` on every
/// fit, so "Android" is not an answer, and the one detector that would work —
/// kgsl's own sysfs nodes, which the benchmark harness reads from inside the
/// app — is a probe this package has not measured. So the host declares it, the
/// same way it declares occlusion (D42), reduced transparency (D59) and proxy
/// roles (D115). That is four for four: where the engine does not carry the
/// fact, the application does.
///
/// **And what the declaration decides is narrower than it was.** The cost
/// model used to decide whether there was a trade at all, and a host that
/// declared nothing got full resolution. It now decides only what the chosen
/// divisor is *priced* at — [ProxyResolutionChoice.routeCostFactor] — because
/// the divisor's sign is the same on every family measured and the unmeasured
/// one is the one that shipped at 37 fps (D134, D136). A silent host gets the
/// same quality walk as a declared one and a null where the price would be.
abstract final class ProxyResolutionPolicy {
  /// The default quality budget: **1% of the distance between two of Apple's
  /// own shipping materials** ([ProxyResolution.kMaterialScaleDeltaE]).
  ///
  /// A threshold in bare ΔE would be a taste; written as a fraction of a
  /// measured scale it is at least a statement about something outside this
  /// project (S4's rule). What it buys is a check nobody arranged: on a dpr-2
  /// screen it picks a **quarter**-resolution proxy for the Apple-calibrated
  /// finish, from the quality side alone — and that is the point the device
  /// then measured at ×2.14 Material against ×3.56 at full resolution (D128),
  /// which is the same working point D63's estimate assumed for a reason that
  /// turned out not to hold.
  static const double defaultDamageBudgetDeltaE = 0.01 * ProxyResolution.kMaterialScaleDeltaE;

  /// The divisors the walk may visit.
  ///
  /// Named for the quality table, because that is the only thing it is a table
  /// of: the choice below is made on damage alone, and every divisor here is
  /// one [ProxyResolution.damageAtTexelScale] can answer for at some density.
  /// The price is *reported* on the way out and may be null.
  ///
  /// It used to be called `pricedDivisors` and stop at 4, on the rule that "the
  /// walk only visits divisors with a price, so whatever comes back has both
  /// halves of the trade". That rule contradicted the comment ten lines below
  /// it — the cost model does not enter the choice — and it was **D135 one
  /// storey down**: a refusal on "the saving is unpriced" is a bet that a
  /// lever's sign is unknown, and this lever's sign is measured on every family
  /// that has been run. It cost nothing on a dpr-2 screen, where 4 was the
  /// right answer anyway, and showed up the first time the ladder ran at dpr 4
  /// (D137): the walk ran out at a texel scale of **1.0** while the same finish
  /// and the same budget accept **0.5** — which is a measured rung, not an
  /// extrapolation — and the reason it reported was `unpricedSaving`
  /// ([ProxyDivisorReason.offTheLadder] since D187), the refusal saying its own
  /// name.
  ///
  /// What stops the walk now is what always should have: the budget, the
  /// optics ceiling, and the damage table running out of rungs. Densities move
  /// as follows at the default budget and `regular`, and the first two are
  /// unchanged by construction rather than by luck — 8 is off the budget there,
  /// not off the list:
  ///
  /// | dpr | divisor | texels/logical px | ΔE |
  /// |---|---|---|---|
  /// | 1 | 1/2 | 0.5 | 0.222 (1/4 would be 0.25 px → 0.372, over) |
  /// | 2 | 1/4 | 0.5 | 0.222 (1/8 would be 0.25 px → 0.372, over) |
  /// | 3 | 1/8 | 0.375 | 0.275, **interpolated** |
  /// | 4 | 1/8 | 0.5 | 0.222, measured |
  ///
  /// The dpr-3 row spends the budget against a bound rather than a reading,
  /// which is not new — its previous answer, 0.75 texels, was a bound too — and
  /// the caller can see which it got: `measured` rides along on
  /// [ProxyResolutionChoice.damage].
  static final List<int> candidateDivisors = List<int>.unmodifiable(<int>[
    1,
    ...ProxyResolution.measuredDivisors,
  ]);

  /// The deepest divisor whose quality *and* price are both known, given the
  /// finish, the screen and the hardware.
  ///
  /// [finish] is a key into the measured damage table
  /// ([ProxyResolution.measuredFinishes]); an unknown one refuses the same way
  /// an unmeasured texel scale does, which is to say it comes back at full
  /// resolution rather than at a guess.
  /// The choice a host makes for itself, with the tables read at that divisor
  /// rather than used to pick it.
  ///
  /// Everything but the divisor is the same lookup [choose] does, deliberately:
  /// a pinned arm still reports what the damage table says about it, so a run
  /// that pins a divisor off the measured end reports a null damage rather than
  /// a number nobody measured. See [ProxyDivisorReason.pinnedByHost] for why
  /// this exists at all.
  static ProxyResolutionChoice pin(
    ProxyResolution resolution, {
    required String finish,
    required double devicePixelRatio,
    required ProxyCostModel costModel,
    bool blurCorrected = true,
  }) => read(
    resolution,
    ProxyDivisorReason.pinnedByHost,
    finish: finish,
    devicePixelRatio: devicePixelRatio,
    costModel: costModel,
    blurCorrected: blurCorrected,
  );

  /// A divisor arrived at somewhere other than the quality walk, with the
  /// tables read at it rather than used to pick it.
  ///
  /// [pin] is this with [ProxyDivisorReason.pinnedByHost]; the texture ceiling
  /// is this with [ProxyDivisorReason.textureCeiling]. Kept as one body because
  /// the whole point of both is that the *reporting* does not depend on how the
  /// divisor was reached — a forced arm still says what the damage table says
  /// about it, including saying nothing when the table has nothing.
  static ProxyResolutionChoice read(
    ProxyResolution resolution,
    ProxyDivisorReason reason, {
    required String finish,
    required double devicePixelRatio,
    required ProxyCostModel costModel,
    bool blurCorrected = true,
  }) => ProxyResolutionChoice(
    resolution: resolution,
    reason: reason,
    damage: resolution.divisor == 1
        ? null
        : ProxyResolution.damageAtTexelScale(
            finish,
            resolution.ratioFor(devicePixelRatio),
            blurCorrected: blurCorrected,
          ),
    captureCostFactor: resolution.captureCostFactor(costModel),
    routeCostFactor: resolution.routeCostFactor(costModel),
  );

  static ProxyResolutionChoice choose({
    required String finish,
    required double finishSigmaLogical,
    required double devicePixelRatio,
    required ProxyCostModel costModel,
    double damageBudgetDeltaE = defaultDamageBudgetDeltaE,
    bool blurCorrected = true,
  }) {
    ProxyResolutionChoice at(int divisor, ProxyDivisorReason reason, ProxyDamage? damage) {
      final resolution = ProxyResolution.divisor(divisor);
      return ProxyResolutionChoice(
        resolution: resolution,
        reason: reason,
        damage: damage,
        captureCostFactor: resolution.captureCostFactor(costModel),
        routeCostFactor: resolution.routeCostFactor(costModel),
      );
    }

    // The cost model does not enter the choice. Every family that has been run
    // has the lever, each for its own reason — on `areaCharged` the capture
    // itself is charged by area (D28), on `frameCharged` the capture is not
    // and the rest of the route is (D128), and on the one device no model fits
    // the recording is charged by area end to end (D134) — and the size of the
    // saving never entered here anyway: only quality does. There used to be an
    // early return to full resolution on `unmeasured` at this point; it handed
    // the default Android host the worst arm the ladder had (D136).

    final int opticsCeiling = ProxyResolution.maxDivisorFor(finishSigmaLogical, devicePixelRatio);
    // **The ceiling applies only where the material has blur of its own**, and
    // that exemption is B13's answer (D164). At sigma 0 the ceiling is 1 on
    // every screen — not a statement about optics but the arithmetic
    // degenerating, because *any* divisor delivers more blur than zero — so it
    // was a refusal to let the policy divide a transparent finish at any budget
    // whatsoever. What prices that excess instead is the damage table, and for a
    // blurless finish it prices exactly the rung the pipeline builds: the blur
    // pass returns null residual at sigma 0 (`proxy_pipeline.dart`), so the
    // ladder measured `clear`'s rungs with no correction either, and 0.646 ΔE at
    // a divisor of 2 *is* the price of the blur nobody asked for.
    //
    // At the default budget this changes no divisor at all — 0.646 against
    // 0.348 refuses on its own — and it changes the *reason*, which is the part
    // a host reads. Above zero the ceiling keeps its work, and it is not
    // redundant there: the damage table is keyed by the finish's **name** and
    // cannot see that a finish declared a thin sigma, so for a thin material the
    // two criteria are about different quantities rather than the same one twice.
    final bool ceilingApplies = finishSigmaLogical > 0;
    var chosen = 1;
    ProxyDamage? chosenDamage;
    var reason = ProxyDivisorReason.offTheLadder;

    for (final int divisor in candidateDivisors.skip(1)) {
      if (ceilingApplies && divisor > opticsCeiling) {
        reason = ProxyDivisorReason.opticsCeiling;
        break;
      }
      final ProxyDamage? damage = ProxyResolution.damageAtTexelScale(
        finish,
        ProxyResolution.divisor(divisor).ratioFor(devicePixelRatio),
        blurCorrected: blurCorrected,
      );
      // Null is off the measured end of the curve, which is a refusal to
      // extrapolate rather than a verdict about the picture — but it stops the
      // walk for the same reason the optics ceiling does: every deeper divisor
      // is further off the same end, so there is nothing behind it to find.
      if (damage == null) {
        reason = ProxyDivisorReason.damageBudget;
        break;
      }
      // **A rung over the budget does not stop the walk, and this used to be a
      // `break` (D187).** That break was sound while the damage curve was taken
      // to be monotone in the texel scale, and the two rungs measured between
      // the old ones show it is not: `regular` costs 0.235 at 0.667 texels and
      // 0.221 at 0.5, `frosted` 0.623 at 0.333 and 0.565 at 0.25. The
      // inversions are small — under 10% between rungs — and the consequence is
      // not: at a budget of 0.443 the walk used to stop `thinLight` at a half
      // because 0.667 texels costs 0.462, while the half-again deeper rung it
      // never looked at costs 0.443 and fits. Scanning the whole list and
      // keeping the deepest that fits costs five table lookups and cannot make
      // that mistake.
      if (damage.deltaE > damageBudgetDeltaE) {
        reason = ProxyDivisorReason.damageBudget;
        continue;
      }
      chosen = divisor;
      chosenDamage = damage;
      reason = ProxyDivisorReason.offTheLadder;
    }
    return at(chosen, reason, chosenDamage);
  }
}
