// How much glass is on the screen — the second of phase A's two large levers,
// and the one that has to be *visible* rather than clever.
//
// The budget says why it is a lever at all. Over the floor the addition splits
// tax 34% / capture 40% / blur 17% / shader 9% (D63), and the tax is the item
// with no implementation trick behind it: it follows the **area of the glass**,
// 1.1101 cycles per logical px² measured directly on three areas 3x apart at
// fixed content and fixed surface count, R² = 0.99917 (D21, Adreno 830). M9
// tried the one implementation lever anybody proposed — an opaque backing under
// the surface, so the engine's depth pass could cull what it covers — and it
// returned nothing in five scenes and two seeds. So the amount of glass is
// decided when the screen is designed, which makes it an API question rather
// than an engine one, and the API's whole job here is to make the number
// sayable.
//
// **And there is a second term, which is the reason "lots of small chips" is
// the wrong instinct.** At the *same* total glass area twelve surfaces cost
// 1.41x the tax of two, and the excess over `k·area` is 0.7 / 5.8 / 26.8
// thousand cycles at n = 2 / 6 / 12 — growing faster than the count, exponent
// ≈ 2.0 on three points (D26). A constant per surface is refuted (it would
// predict +524% at n = 2), and so is perimeter (+1429%). What is *not* punished
// is smallness on its own: at n = 2 the panel side varies 1.7x with no excess
// at all, sign changing and modulus at the noise floor. So the rule is "merge
// the glass, do not enlarge it", and one big panel beats many chips at equal
// area.
//
// **The two platforms measured do not agree on the shape of any of this, and
// the disagreement is not a constant.** On Adreno there is a law and it was
// measured over 0.10…0.30 screens of glass — a tenth of a screen to a third —
// and nowhere further. On Metal there is no law at all: throughput was measured
// out to 25.6 screens and it is flat and cheap until it falls off a cliff
// between 12.8 and 19.2 screens (0.17 → 2.98 ms of raster on the same shape,
// 0.42 → 8.41 on another), while the surface *count* is nearly free — 0.29 →
// 0.59 ms going from 64 to 256 tiled panels at constant area, about 0.0016 ms
// each (D71, S4, one M2 iPad, one run per arm). Neither platform's numbers say
// anything about the other's, and neither range covers the other's, so this
// file carries two tables and refuses outside both rather than interpolating a
// third.
//
// The contrast that makes the shape of our own route legible is Apple's, on the
// same device in the same run: `.glassEffect` is bound by surface **count** —
// 192 panels drop it to ~90 fps whether they cover 0.8 screens or 19.2 — and is
// untroubled by 64 overlapping panels covering 25.6. One backdrop read per
// surface there against one capture for all of them here (D38). So the two
// routes fail in opposite directions, and an app that would break SwiftUI with
// two hundred chips is comfortable here.

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'glass_finish.dart';
import 'glass_tier.dart';

/// One glass surface, read at the moment it was asked.
///
/// The rect is the axis-aligned bounding box the surface occupies, mapped up
/// through every transform between it and the root — so a panel inside a scaled
/// or scrolled subtree reports where it actually is, and a *rotated* one
/// reports its bounding box, which is larger than the glass. The rotation case
/// is named rather than handled: no measurement covers it.
@immutable
class GlassSurfaceRecord {
  const GlassSurfaceRecord({
    required this.rect,
    required this.shapeArea,
    this.tier = GlassTier.full,
    this.travel,
    this.finish,
    this.presence = 1,
    this.materialize = 1,
  });

  /// How far the surface has materialized (`RenderGlassSurface.materialize`).
  /// At zero it draws nothing and is captured for nothing, like [presence].
  final double materialize;

  /// How much of the surface is there (`RenderGlassSurface.presence`). At
  /// zero it draws nothing, and the host captures nothing for it — so a drop
  /// that exists only while a control is held costs the atlas nothing, and
  /// its finish nothing, the rest of the time.
  final double presence;

  /// The finish this surface is drawn in — its own, or its blend group's — or
  /// null for "the host's". What the capture blurs its slot by.
  final GlassFinish? finish;

  /// Where the surface is, in global logical pixels.
  final Rect rect;

  /// The region the surface declared it may move within (`GlassTravel`), in
  /// the same space, or null for a surface that declared none.
  final Rect? travel;

  /// What the host captures for this surface: [rect], or the declared region
  /// grown to include it.
  ///
  /// Grown rather than replaced, so a surface that has left its region changes
  /// the capture input — and is retaken — instead of sampling a slot that no
  /// longer holds it.
  Rect get captureRect => travel?.expandToInclude(rect) ?? rect;

  /// What the shape covers inside [rect], in logical px² — the rect minus what
  /// the four corners cut away. See [GlassLedger.cornerCutCoefficient].
  final double shapeArea;

  /// Which rung of the ladder this surface draws.
  ///
  /// Here rather than left to the host, because the register is read by two
  /// machines that need **different** subsets of it and neither can work the
  /// other's out. The capture wants the surfaces that read a proxy; the tally
  /// wants every surface there is, because the translucency tax and its
  /// fragmentation excess follow any translucent fill and have nothing to do
  /// with the capture (D21, D26, and phase D says so of the ladder in as many
  /// words).
  final GlassTier tier;

  /// The rect's own area, which is the denominator every measured constant here
  /// was fitted against.
  double get rectArea => rect.width * rect.height;

  @override
  String toString() => 'GlassSurfaceRecord($rect, shape ${shapeArea.toStringAsFixed(0)} px², ${tier.name})';
}

/// Something in the render tree that can say where it is.
///
/// The register holds these rather than the rects they last reported, and asks
/// them at the moment somebody reads it. That is not a refinement — it is the
/// only version that works. **A scroll moves a surface without repainting it:**
/// a sliver's children are repaint boundaries by default, so the viewport
/// re-adds an existing layer at a new offset and the child's `paint` is never
/// called. A register written from `paint` therefore holds the place the
/// surface was before the list moved, for as long as nothing else dirties it —
/// measured, in `glass_surface_test.dart`, where a jump of 60 logical pixels
/// left the cached rect exactly where it started.
abstract interface class GlassSurfaceGeometry {
  /// Where this surface is now, or null if it cannot say — not attached to a
  /// tree, or attached and not yet laid out. Null is a surface that is not on
  /// the screen, which is exactly what should not be counted.
  GlassSurfaceRecord? readGeometry();

  /// The layer this surface composites into, or null before it has painted.
  ///
  /// Read by [ProxyLayerWatch], which has to skip it: a published proxy
  /// repaints every surface by construction, so a watch that looked at them
  /// would see the pipeline's own output and record for ever. Where the surface
  /// *is* stays this register's business, which is why the watch skips the
  /// subtree rather than reading its offset.
  Layer? get compositedLayer;

  /// Whether this surface's subtree is kept out of the proxy — by the walk that
  /// records it, and by the watch that decides whether it is stale.
  ///
  /// The two have to agree, and until the ladder existed they agreed by both
  /// saying "it is a glass surface". The predicate they actually meant is "it
  /// draws the proxy".
  bool get excludedFromProxy;

  /// The layer this surface's own glass is drawn into, or null if it draws
  /// none. Narrower than [compositedLayer]: when glass stands on this surface
  /// its subtree is in the upper level's proxy and has to be watched, and only
  /// the draw — replaced by every publish — is skipped.
  Layer? get drawLayer;
}

/// A set of surfaces whose silhouettes are one shape.
///
/// The picture-side grouping of §4.4, and the register holds it for one reason:
/// the atlas has to know. Members of a blend group share a coordinate system by
/// construction, so they are **required** to share an atlas slot — the one-way
/// invariant, and the only thing about grouping that is not an optimisation.
/// The reverse does not hold and must not be assumed: a tab bar and a floating
/// button can share a texture without ever fusing.
abstract interface class GlassSurfaceCluster {
  /// The surfaces this cluster draws as one shape, in a stable order.
  ///
  /// Stable because the fold that builds the fused field is a smooth minimum,
  /// which is not associative: two orders differ by about a code value in the
  /// saddle, and "a little, differently every frame" is a shimmer.
  Iterable<GlassSurfaceGeometry> get members;

  /// The layer the cluster's own glass composites into, or null before it has
  /// painted.
  ///
  /// Read by [ProxyLayerWatch] for the same reason a surface's is: a cluster
  /// *draws* glass, so a watch that looked at its layer would see the pipeline's
  /// own output and record for ever. The members' layers are inside this one and
  /// are excluded with it, which is right rather than convenient — the walk
  /// skips the whole group subtree, so nothing in it is in the proxy and nothing
  /// in it can invalidate the proxy.
  Layer? get compositedLayer;

  /// Whether this cluster's subtree is kept out of the proxy. See
  /// [GlassSurfaceGeometry.excludedFromProxy].
  bool get excludedFromProxy;

  /// The layer the cluster's fused glass is drawn into, or null. See
  /// [GlassSurfaceGeometry.drawLayer].
  Layer? get drawLayer;

  /// How far past its members' own boxes the cluster's silhouette can reach,
  /// in logical pixels, or zero for a cluster that draws no fused shape.
  ///
  /// The host captures that much more around every member. A bridge between
  /// two surfaces bulges past both of their boxes, and a shader sampling there
  /// from a slot that stopped at the boxes reads the slot's clamped edge row:
  /// up to 132 code values off the identity over the rows just outside a
  /// fused pair, on every backend (D201).
  double get bridgeReach;
}

/// The register of glass surfaces on one screen.
///
/// A [Listenable] rather than an inherited value, because geometry moves every
/// frame and a surface changing position must not rebuild anybody's subtree —
/// the same reason the roadmap gives for phase C's API. [GlassScope] carries
/// one of these down the tree; its identity never changes, so the inherited
/// widget never notifies.
///
/// Entries are keyed by the render object that owns them, so a surface which
/// stops repainting keeps its last known place instead of vanishing from the
/// tally on a frame where nothing moved. It leaves the register when its render
/// object detaches, which is what a disposed list cell does.
class GlassLedger extends ChangeNotifier {
  final Set<GlassSurfaceGeometry> _surfaces = <GlassSurfaceGeometry>{};

  /// Every surface that can say where it is, read now.
  ///
  /// Reading is `getTransformTo` per surface, which walks to the root — O(depth)
  /// each, and cheap enough that nobody has measured it. What it is not is
  /// free per frame, so a consumer that wants it every frame should read once
  /// and pass it down rather than call this from several places.
  Iterable<GlassSurfaceRecord> get surfaces sync* {
    for (final GlassSurfaceGeometry surface in _surfaces) {
      final GlassSurfaceRecord? record = surface.readGeometry();
      if (record != null) {
        yield record;
      }
    }
  }

  /// How many surfaces are registered — including any that cannot currently say
  /// where they are, which is why this is not `surfaces.length`.
  int get registeredCount => _surfaces.length;

  /// The surfaces themselves, in registration order.
  ///
  /// The host needs these rather than their rects: a frame indexes its slots by
  /// *identity*, so that a surface which mounts between two captures cannot end
  /// up sampling the slot of whoever used to be at its index.
  Iterable<GlassSurfaceGeometry> get registered => _surfaces;

  /// Adds a surface. Notifies, because the *set* changed: geometry does not
  /// notify at all, since it is read rather than stored.
  void register(GlassSurfaceGeometry surface) {
    if (_surfaces.add(surface)) {
      notifyListeners();
    }
  }

  void unregister(GlassSurfaceGeometry surface) {
    if (_surfaces.remove(surface)) {
      notifyListeners();
    }
  }

  /// The blend groups on this screen, in registration order.
  Iterable<GlassSurfaceCluster> get clusters => _clusters;

  final Set<GlassSurfaceCluster> _clusters = <GlassSurfaceCluster>{};

  /// Adds a blend group. Notifies for the same reason [register] does: the
  /// atlas's slots are a function of this, so the grouping changing is the set
  /// changing.
  void registerCluster(GlassSurfaceCluster cluster) {
    if (_clusters.add(cluster)) {
      notifyListeners();
    }
  }

  void unregisterCluster(GlassSurfaceCluster cluster) {
    if (_clusters.remove(cluster)) {
      notifyListeners();
    }
  }

  /// What one capture covering every surface would have to span.
  Rect? get bounds {
    Rect? out;
    for (final GlassSurfaceRecord r in surfaces) {
      out = out == null ? r.rect : out.expandToInclude(r.rect);
    }
    return out;
  }

  /// What one corner of a round superellipse cuts away, as a fraction of
  /// `rx·ry` — **measured against the engine's own `RSuperellipse.contains`**,
  /// not derived.
  ///
  /// A circular corner cuts exactly `1 - pi/4 = 0.21460·rx·ry`. The engine's
  /// round superellipse cuts **more**, 0.2270, which is the opposite of the
  /// intuition that a squircle is the fuller shape: its curvature is spread
  /// over a longer stretch of the side, so it leaves the straight edge earlier
  /// and the area it gains near the diagonal does not pay that back.
  ///
  /// Measured by sampling each corner's own box at 2000², which puts the
  /// discretization error near 0.1%. What the sampling says, and every line of
  /// it is checked in `glass_ledger_test.dart`:
  ///
  ///  - the coefficient belongs to the **corner**, not to the box: radii 2, 24
  ///    and 48 give 0.2287 / 0.2268 / 0.2270, an *elliptical* corner 40x16
  ///    gives 0.2269 either way round, and a box with one rounded corner gives
  ///    0.2271. So `cut = c · Σ rx·ry` generalizes, which is what lets this be
  ///    a closed form at all;
  ///  - and it stops being constant as the radius approaches half the shorter
  ///    side, where the engine degenerates to a **circle**: 0.2237 at
  ///    `r = 0.8·h/2` and 0.2171 at exactly `h/2`. Left as a constant rather
  ///    than fitted — four points and no mechanism — so a stadium's shape area
  ///    comes out about 0.8% of its box too small, which is stated instead of
  ///    corrected.
  static const double cornerCutCoefficient = 0.2270;

  /// Area of the engine's round superellipse, in logical px².
  ///
  /// Closed form rather than a sample: `contains` is a native call per point
  /// and this runs per surface per frame. It is checked against the engine over
  /// a corpus of shapes in the tests, with the residual asserted rather than
  /// assumed — which is how the two things below were found.
  ///
  /// **Radii that overflow the box are clamped per axis, and `scaleRadii()` is
  /// the wrong answer here.** The inherited helper divides every radius by one
  /// factor, the smallest any edge needs — the rule an `RRect` follows — and the
  /// engine does not do that for this shape: a 240x200 box asked for a radius of
  /// 400 comes back as a full **ellipse** of 120 by 100, area `pi·rx·ry`
  /// = 37699, where `scaleRadii()` would say 100 by 100. Measured by sampling,
  /// which matched the ellipse to five digits.
  ///
  /// **And a corner filling both half-extents is a quarter ellipse, exactly.**
  /// Its cut is the circular `1 - pi/4` rather than [cornerCutCoefficient], and
  /// using the superellipse constant there costs 1.2% of the box. The two rules
  /// meet in the middle without being joined: a stadium, whose corner fills one
  /// half-extent and not the other, sits between them at 0.2206 and is left to
  /// the constant, which over-cuts it by about 0.4% of its box. That gap is
  /// four measured points with no mechanism behind them, so it is recorded and
  /// not fitted.
  static double shapeAreaOf(RSuperellipse shape) {
    final double w = shape.width;
    final double h = shape.height;
    double cut(double rx, double ry) {
      final double cx = math.min(rx, w / 2);
      final double cy = math.min(ry, h / 2);
      final bool degenerate = cx >= w / 2 && cy >= h / 2;
      return (degenerate ? 1 - math.pi / 4 : cornerCutCoefficient) * cx * cy;
    }

    return math.max(
      0,
      w * h -
          cut(shape.tlRadiusX, shape.tlRadiusY) -
          cut(shape.trRadiusX, shape.trRadiusY) -
          cut(shape.brRadiusX, shape.brRadiusY) -
          cut(shape.blRadiusX, shape.blRadiusY),
    );
  }

  /// Reads the register against the measured limits of one platform.
  ///
  /// [viewSize] is the logical size of the screen the surfaces are on — the
  /// unit both platforms' limits are quoted in is *screens of glass*, which is
  /// the only unit that transfers between a phone and a tablet at all.
  GlassLoad read({required Size viewSize, required GlassSurfaceCostModel model}) {
    final Rect view = Offset.zero & viewSize;
    var rectArea = 0.0;
    var onScreenArea = 0.0;
    var shapeArea = 0.0;
    var count = 0;
    var capturedCount = 0;
    var capturedRectArea = 0.0;
    Rect? bounds;
    for (final GlassSurfaceRecord r in surfaces) {
      count++;
      rectArea += r.rectArea;
      shapeArea += r.shapeArea;
      final Rect visible = r.rect.intersect(view);
      if (!visible.isEmpty) {
        onScreenArea += visible.width * visible.height;
      }
      // The capture side counts only the rungs that read a proxy, and the tally
      // side counts everything: a cheap surface pays the tax and takes no
      // snapshot. Before the ladder existed the two sets were the same set, and
      // `bounds` in particular was documented as spanning "every surface" —
      // which was true and is now the wrong sentence, because a screen with one
      // full panel and eleven cheap ones would have reported a capture eleven
      // panels wide.
      if (!r.tier.readsBackdrop) {
        continue;
      }
      capturedCount++;
      capturedRectArea += r.rectArea;
      bounds = bounds == null ? r.rect : bounds.expandToInclude(r.rect);
    }
    final double screenArea = viewSize.width * viewSize.height;
    return GlassLoad(
      surfaceCount: count,
      capturedSurfaceCount: capturedCount,
      rectAreaLogical: rectArea,
      capturedRectAreaLogical: capturedRectArea,
      onScreenRectAreaLogical: onScreenArea,
      shapeAreaLogical: shapeArea,
      bounds: bounds,
      screensOfGlass: screenArea <= 0 ? 0 : rectArea / screenArea,
      model: model,
    );
  }
}

/// Which platform's measurements to read the register against.
///
/// Not a rendering backend: it is "whose numbers apply", and the two that exist
/// were taken on one device each. The third value is what every other device
/// gets, and it is not a placeholder — most of them have neither a counter nor
/// a run.
enum GlassSurfaceCostModel {
  /// Adreno 830 / Impeller-Vulkan (D21, D26). A linear law in the glass area
  /// plus a superlinear excess in the surface count, measured over 0.10…0.30
  /// screens of glass and 2…12 surfaces.
  adrenoCycles,

  /// Apple M2 / Metal (D71). No law: raster time is flat and cheap out to 12.8
  /// screens of glass and falls off a cliff by 19.2, and the surface count is
  /// nearly free to 256.
  metalThroughput,

  /// Nobody measured this hardware. Every number below refuses.
  unmeasured,
}

/// What the register says, read against one platform's measurements.
@immutable
class GlassLoad {
  const GlassLoad({
    required this.surfaceCount,
    required this.rectAreaLogical,
    required this.onScreenRectAreaLogical,
    required this.shapeAreaLogical,
    required this.bounds,
    required this.screensOfGlass,
    required this.model,
    this.capturedSurfaceCount = 0,
    this.capturedRectAreaLogical = 0,
  });

  final int surfaceCount;

  /// How many of them read a proxy, which is how many the capture is for.
  ///
  /// Equal to [surfaceCount] on a screen that is all [GlassTier.full], and zero
  /// on one that is all cheap — where the whole pipeline goes quiet and the
  /// picture is still a panel.
  final int capturedSurfaceCount;

  /// Summed area of the surfaces' bounding rects, logical px².
  ///
  /// **This is the denominator every constant here was fitted against**, and it
  /// is not the same as the glass the eye sees: a rounded panel covers
  /// [shapeAreaLogical]. On the panels the law was measured on — 118…205 px
  /// square at radius 18 — the two differ by 0.7…2.1%, which is inside the
  /// fit's own worst residual of 2.2%, so **that measurement cannot tell the
  /// two denominators apart**. It matters for shapes the measurement never had:
  /// a stadium or a circle covers 21% less than its rect, and which of the two
  /// the cost follows there is not known.
  final double rectAreaLogical;

  /// The part of [rectAreaLogical] belonging to surfaces that read a proxy.
  ///
  /// The two numbers were one number until the ladder existed, and separating
  /// them is the whole arithmetic of the cheap rung: the tax follows the first
  /// and the capture follows the second, so moving a panel down a rung removes
  /// it from one denominator and not the other.
  final double capturedRectAreaLogical;

  /// The same, clipped to the view.
  ///
  /// Glass scrolled past the edge of the screen is in the register — its render
  /// object is alive and inside a list's cache extent — and does not shade a
  /// pixel. The difference is a bound on how pessimistic [rectAreaLogical] is.
  final double onScreenRectAreaLogical;

  /// What the shapes cover, corners removed.
  final double shapeAreaLogical;

  /// What one capture spanning every surface that reads a proxy would cover —
  /// phase B's dead-area question, in the same units as its measured budget of
  /// ~102 000 device px.
  ///
  /// Null when nothing on the screen reads a proxy, which is a whole screen of
  /// cheap glass and not an empty one.
  final Rect? bounds;

  /// [rectAreaLogical] as a multiple of the screen's own area. The unit both
  /// platforms' limits are quoted in.
  final double screensOfGlass;

  final GlassSurfaceCostModel model;

  /// Dead area one shared capture would pay for, logical px².
  double get deadAreaLogical {
    final Rect? b = bounds;
    if (b == null) {
      return 0;
    }
    return math.max(0, b.width * b.height - capturedRectAreaLogical);
  }

  /// D21's law: cycles of translucency tax per frame, or null off Adreno.
  ///
  /// Excludes the fragmentation excess, which is [fragmentationExcessCycles].
  double? get areaTaxCycles => model == GlassSurfaceCostModel.adrenoCycles ? kTaxPerLogicalPx2 * rectAreaLogical : null;

  /// D26's second term, in the same cycles, or null off Adreno.
  ///
  /// The quadratic is the only simple form the three points leave standing, and
  /// it is written as what the data showed rather than as a law: three points
  /// on one decade, no mechanism proposed, and the exponent between successive
  /// pairs is 1.90 / 2.02 / 2.21. Calibrated at n = 12 and stated for the
  /// measured range; past 12 surfaces it is an extrapolation of a curve nobody
  /// has a reason for, which is why [verdict] says so rather than quoting this.
  double? get fragmentationExcessCycles => model == GlassSurfaceCostModel.adrenoCycles
      ? kFragmentationExcessAt12 * (surfaceCount * surfaceCount) / (12 * 12)
      : null;

  /// The whole tax, or null off Adreno.
  double? get taxCycles {
    final double? area = areaTaxCycles;
    final double? excess = fragmentationExcessCycles;
    return area == null || excess == null ? null : area + excess;
  }

  /// What merging every surface into one would save, as a fraction of the tax.
  ///
  /// The honest form of "merge, do not enlarge": the area term does not move,
  /// so the whole saving is the excess, and quoting it as a ratio keeps the
  /// unit out of a number an app author has no scale for.
  double? get mergingSaves {
    final double? total = taxCycles;
    if (total == null || total <= 0 || surfaceCount <= 1) {
      return null;
    }
    final double merged = kTaxPerLogicalPx2 * rectAreaLogical + kFragmentationExcessAt12 / (12 * 12);
    return 1 - merged / total;
  }

  /// Where this screen sits against what was actually measured.
  GlassLoadVerdict get verdict {
    switch (model) {
      case GlassSurfaceCostModel.unmeasured:
        return GlassLoadVerdict.hardwareUnmeasured;
      case GlassSurfaceCostModel.adrenoCycles:
        // The law is linear and was measured from a tenth of a screen to a
        // third. Past that there is no cliff *and no evidence of one*: the grid
        // simply stopped. Saying "fine" there would be quoting a fit outside
        // its own range, which is what the whole file exists not to do.
        if (screensOfGlass > kAdrenoMeasuredScreens) {
          return GlassLoadVerdict.pastMeasuredRange;
        }
        return GlassLoadVerdict.withinMeasured;
      case GlassSurfaceCostModel.metalThroughput:
        if (screensOfGlass >= kMetalCliffScreens) {
          return GlassLoadVerdict.overMeasuredCliff;
        }
        if (screensOfGlass > kMetalComfortableScreens) {
          return GlassLoadVerdict.betweenMeasuredPoints;
        }
        return GlassLoadVerdict.withinMeasured;
    }
  }

  /// D21, measured directly: cycles of translucency tax per logical px² of
  /// glass (0.1233 per device px), R² = 0.99917 on three areas 3x apart.
  ///
  /// Adreno 830, two seeds, worst median disagreement 1.78%, zero caveats in
  /// either report. Reproduced independently by M7 and M9 across scenes as
  /// unlike as the corpus gets.
  static const double kTaxPerLogicalPx2 = 1.1101;

  /// D26: the excess over `k·area` at twelve surfaces and 56 160 logical px²,
  /// in cycles. 715 at n = 2 and 5 776 at n = 6 on the same area.
  static const double kFragmentationExcessAt12 = 26769;

  /// The deepest the Adreno grid went: 30% of a 360x780 screen.
  static const double kAdrenoMeasuredScreens = 0.30;

  /// The most glass Metal was measured carrying comfortably: 12.8 screens, at
  /// 0.17 ms of raster on 32 stacked panels and 0.42 on 128 half-size ones.
  static const double kMetalComfortableScreens = 12.8;

  /// Where it stopped being comfortable: 19.2 screens, 2.98 and 8.41 ms on the
  /// same two shapes. The step is 18x, not a slope, and its mechanism was not
  /// found.
  static const double kMetalCliffScreens = 19.2;

  /// Apple's own limit on the same device, for contrast: `.glassEffect` falls
  /// to ~90 fps somewhere between 128 and 192 surfaces, **whatever area they
  /// cover** — 0.8 screens and 19.2 give 91.5 and 90.0 fps.
  ///
  /// Not a limit of this package: one backdrop read per surface there, one
  /// capture for all of them here (D38). It is here because it is the number an
  /// app author is most likely to have in mind from the platform, and it points
  /// the other way.
  static const int kAppleSurfaceLimit = 192;

  @override
  String toString() =>
      'GlassLoad($surfaceCount surfaces, ${screensOfGlass.toStringAsFixed(2)} screens, '
      '${verdict.name}${taxCycles == null ? '' : ', ${(taxCycles! / 1000).toStringAsFixed(1)}k cycles'})';
}

/// Where a screen's glass sits against the runs that exist.
enum GlassLoadVerdict {
  /// Inside the range something was measured on.
  withinMeasured,

  /// Past the deepest point of the only grid that fitted a law here. Not "too
  /// much" — unknown, which is a different word.
  pastMeasuredRange,

  /// Between the last comfortable measurement and the first bad one. On Metal
  /// that gap is 12.8 to 19.2 screens and nothing was run inside it.
  betweenMeasuredPoints,

  /// At or past a point measured to fall over: on Metal, 19.2 screens of glass,
  /// where raster time steps by a factor of 18.
  overMeasuredCliff,

  /// No run covers this hardware.
  hardwareUnmeasured,
}

/// Carries one [GlassLedger] down the tree.
///
/// The value is the ledger's *identity*, which never changes, so this never
/// notifies and a surface moving never rebuilds anything. Everything that
/// actually changes travels through the ledger as a [Listenable].
class GlassScope extends InheritedWidget {
  const GlassScope({required this.ledger, required super.child, super.key});

  final GlassLedger ledger;

  static GlassLedger? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<GlassScope>()?.ledger;

  @override
  bool updateShouldNotify(GlassScope oldWidget) => oldWidget.ledger != ledger;
}
