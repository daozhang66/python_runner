// A blend group: N glass surfaces drawn as one silhouette.
//
// **The two groupings of §4.4, and the whole point of this file is that they
// are not the same thing.** `CaptureBatch` — surfaces sharing one atlas slot —
// is a runtime decision made by the cost of packing, it changes only the
// price, and it has been in the package since D122. A blend group changes the
// *picture*: two shapes near each other grow a bridge between them, the way
// Apple's `glassEffectUnion` does. The invariant between them runs one way —
// a blend group must share a capture batch, because its members sample one
// coordinate system — and it is enforced where the batch is decided
// (`AtlasLayout.pack`'s `fused`), not asserted afterwards.
//
// **Why the group draws and the members do not.** The bridge belongs to no
// member: there is no fragment of either surface's own box where it lives. So
// a group paints one quad over its own bounds and the members paint only their
// children. The price is the dead area of that quad — fragments outside every
// shape, shaded and then discarded by coverage — and it is the thing a group
// trades against what it saves: at equal total area, twelve surfaces cost 1.41x
// two on the translucency tax alone (D26), and that excess is charged per
// *draw*.
//
// **The shape order is registration order and it is load-bearing.** The fused
// field is a fold of smooth minima, and `smin` is not associative: reordering
// moves the saddle by about a code value. That is invisible once and a shimmer
// every frame, so the member list is append-only within a mount rather than
// sorted by anything that moves.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../proxy/proxy_atlas.dart';
import '../proxy/proxy_pipeline.dart';
import '../proxy/proxy_walk.dart';
import 'glass_draw_layer.dart';
import 'glass_finish.dart';
import 'glass_host.dart';
import 'glass_ledger.dart';
import 'glass_surface.dart';
import 'glass_theme.dart';
import 'glass_tier.dart';

/// Where the group's shader lives. See [kGlassShaderAsset] for why the key has
/// a package prefix.
const String kGlassGroupShaderAsset = 'packages/g1455/shaders/glass_group.frag';

/// Shapes one fused draw can carry.
///
/// Twelve because that is where the measured corpus stops: the fragmentation
/// excess is read at two and at twelve surfaces (D26) and everything past it is
/// an extrapolation of a curve nobody took, so a thirteenth shape would be
/// priced by guess. The shader's array is this long; a larger group is
/// **refused** — its members go back to drawing themselves, which loses the
/// bridges and says so in a counter — rather than truncated, because a
/// truncated group would draw a picture with shapes missing and no sign of it.
const int kMaxFusedShapes = 12;

/// Where `glass_group.frag`'s uniforms resume after `uBox` and `uRadius`.
const int _kTail = 11 + kMaxFusedShapes * 5;

/// The membership of one blend group.
///
/// Owned by [GlassGroup]'s state rather than by its render object, because the
/// surfaces below have to find it while they are being built and a render
/// object is not reachable from its own subtree's `build`.
class GlassBlendGroup implements GlassSurfaceCluster {
  final List<RenderGlassSurface> _members = <RenderGlassSurface>[];

  RenderGlassGroup? _owner;

  @override
  Iterable<GlassSurfaceGeometry> get members => _members;

  @override
  Layer? get compositedLayer => _owner?.compositedLayer;

  @override
  Layer? get drawLayer => _owner?.drawLayer;

  /// Keyed on the rung rather than on [fuses], and the difference matters for
  /// one case: an **over-capacity** group does not fuse and its members draw
  /// their own glass, so its subtree still has to stay out of the proxy. Below
  /// the top rung nothing in it draws a proxy at all, and then it is ordinary
  /// content.
  @override
  bool get excludedFromProxy => _tier.readsBackdrop;

  @override
  double get bridgeReach {
    final RenderGlassGroup? owner = _owner;
    if (owner == null || !fuses || _members.length < 2) {
      return 0;
    }
    // Global boxes rather than the paint space's: the reach depends on the
    // distances between members and on their radii, and both are the same in
    // any translated space.
    final boxes = <Rect>[];
    final radii = <double>[];
    final travel = <Rect?>[];
    for (final RenderGlassSurface member in _members) {
      if (!member.attached || !member.hasSize) {
        continue;
      }
      boxes.add(member.globalRect);
      radii.add(member.effectiveRadius);
      travel.add(member.travel?.globalRect);
    }
    if (boxes.length < 2) {
      return 0;
    }
    // Sized for wherever the members may go, when they say: this is what the
    // capture is inflated by, and a reach that followed them would move the
    // capture input — and retake — on every step of a declared motion.
    return owner._fusedReach(boxes, radii, travel: travel.any((Rect? t) => t != null) ? travel : null).reach;
  }

  /// The finish the fused draw wears, or null before the group has a render
  /// object. Its members are captured in it, whatever they declare.
  GlassFinish? get finish => _owner?.effectiveFinish;

  /// The members, as the surfaces they are.
  List<RenderGlassSurface> get surfaces => List<RenderGlassSurface>.unmodifiable(_members);

  /// The rung the group's own glass would draw, from the theme above it.
  ///
  /// Set by the render object rather than read here, for the reason this class
  /// is owned by the state at all: it is found from inside its members' builds,
  /// where no render object is reachable.
  GlassTier get tier => _tier;
  GlassTier _tier = GlassTier.full;
  set tier(GlassTier value) {
    if (value == _tier) {
      return;
    }
    _tier = value;
    _changed();
  }

  /// Whether this group draws its members, or hands them back to themselves.
  ///
  /// False for an empty group, for one past [kMaxFusedShapes], and **below
  /// [GlassTier.full]**.
  ///
  /// The last of those is a decision with a visible consequence, so it is
  /// stated rather than buried: a group below the full rung stops fusing, its
  /// members draw their own flat panels, and the silhouette **loses its
  /// bridges**. That contradicts half of D58's promise — the fallback is
  /// supposed to keep the same shape — and the alternative would be worse. The
  /// bridge is a fold of two distance fields evaluated in a fragment shader
  /// that samples the atlas; drawing it without reading the backdrop needs a
  /// second fused program whose picture nobody has designed, because a bridge
  /// with no refraction in it is a filled blob rather than glass pulling
  /// towards its neighbour. Phase D designs it; until then the degradation is
  /// the one that already exists for an over-capacity group, which is one
  /// behaviour rather than two.
  bool get fuses => _members.isNotEmpty && _members.length <= kMaxFusedShapes && _tier == GlassTier.full;

  void join(RenderGlassSurface surface) {
    if (_members.contains(surface)) {
      return;
    }
    _members.add(surface);
    _changed();
  }

  void leave(RenderGlassSurface surface) {
    if (_members.remove(surface)) {
      _changed();
    }
  }

  void _changed() {
    _owner?.markNeedsPaint();
    // Every member's own decision about whether to draw depends on `fuses`, and
    // that flips on the member that crosses the ceiling — so the twelfth
    // surface joining has to repaint the other eleven.
    for (final RenderGlassSurface surface in _members) {
      surface.markNeedsPaint();
    }
  }
}

/// Carries the group down to the surfaces inside it.
///
/// An [InheritedWidget] holding an object whose identity never changes, so it
/// never notifies: geometry moves every frame and must not rebuild anybody's
/// subtree, which is the same rule [GlassScope] follows.
class GlassGroupScope extends InheritedWidget {
  const GlassGroupScope({required this.group, required super.child, super.key});

  final GlassBlendGroup group;

  static GlassBlendGroup? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassGroupScope>()?.group;

  @override
  bool updateShouldNotify(GlassGroupScope oldWidget) => !identical(group, oldWidget.group);
}

/// The deepest the sequential `smin` can pull the field below the nearest
/// shape's own distance, in units of `k`, folding [count] shapes.
///
/// `delta_1 = 0`, `delta_{j+1} = delta_j + (k - delta_j)^2 / (4k)`: an upper
/// bound for any arrangement, and tight on the one where every shape is the
/// same distance away. It converges — 0.25 at two shapes, 0.483 at four, 0.758
/// at twelve, never reaching 1 — which is why the naive `(n - 1) / 4` is eleven
/// times too large at twelve and this is not.
///
/// Twelve iterations of three flops once per fused draw, which is nothing next
/// to the pixels it removes.
double _foldDepression(int count) {
  var delta = 0.0;
  for (var i = 1; i < count; i++) {
    final double gap = 1 - delta;
    delta += gap * gap / 4;
  }
  return delta;
}

/// One rectangle of a fused draw, and the shapes that can colour a pixel in it.
///
/// A group is one silhouette; it does not have to be one draw. [rect] is a
/// piece of the area the fold can reach, and [shapes] indexes the boxes handed
/// to [fusedDrawTiles] — every shape left out of a tile is one whose every
/// contribution inside that tile is exactly zero, so the tiles together are the
/// single quad **pixel for pixel** and not merely to the eye.
class GlassFusedTile {
  const GlassFusedTile(this.rect, this.shapes);

  /// The rectangle to draw, in the group's paint space.
  final Rect rect;

  /// Indices into the caller's boxes, ascending.
  ///
  /// Ascending because `smin` is not associative: the fold order is the order
  /// of the uniforms, and a tile that renumbered its members would differ from
  /// the single quad in the saddle — which is where the eye cannot see it and
  /// a byte comparison can.
  final List<int> shapes;

  @override
  String toString() => 'GlassFusedTile($rect, $shapes)';
}

/// How many rectangles a fused draw may become before it gives up and covers
/// everything with one.
///
/// Two per shape. The decomposition below is exact for any arrangement, but a
/// staircase of twelve overlapping boxes falls into two hundred rectangles, and
/// a draw call is not free on any backend here: what tiling buys is fragments,
/// and past some count the draws cost more than the fragments they remove.
/// Where that count is has not been measured, so this is a bound on the damage
/// rather than an optimum — and [RenderGlassGroup.fusedTileRefusals] counts the
/// frames that hit it, because a screen that lives on the wrong side of a
/// number nobody measured should be visible rather than mysteriously slow.
const int kMaxFusedTiles = 24;

/// Splits a fused draw into disjoint rectangles, each carrying only the shapes
/// that can change a pixel inside it.
///
/// Returns null when the split is refused as too fine ([maxTiles]); the caller
/// then draws the one quad it always could. An empty list means there was
/// nothing to draw.
///
/// **Why the area can shrink at all.** The fold is bounded below by
/// `min_i d_i - delta(n) * k` ([_foldDepression]), so the silhouette lies
/// inside the union of the members' own boxes each grown by [reach] — not
/// inside the bounding box of all of them grown by the same. On a clustered
/// layout the two are nearly the same rectangle; on a scattered one the second
/// is the screen and the first is twelve panels' worth of it.
///
/// **Why a shape can be dropped from a tile, exactly.** A shape farther than
/// `(1 + 2 * delta(n)) * k` from the tile — [cullMargin] — cannot change one
/// bit of any fragment in it, and that is arithmetic rather than a tolerance.
/// Run the fold in the order the uniforms are in. Before the first near shape
/// is folded the running `d` is at least `min_far - delta(n) * k`, which that
/// margin puts at `(1 + delta(n)) * k` or more; a near shape sits at
/// `delta(n) * k` or less wherever the draw is not already transparent, so
/// `|d_i - d| >= k`, `h` is exactly zero, and the fold leaves `min(d_i, d)`
/// with `mix(n, n_i, 0)` — the near shape's own distance and its own normal,
/// which is what it would have found had the far ones never been there. After
/// that first near shape `d <= delta(n) * k`, so every later far one is
/// `k` away or more and is skipped for the same reason. The shader's own
/// `uCullK` branch is this same identity spent on speed, which is why the two
/// are independent: dropping a shape here is exact whether or not the branch
/// runs.
///
/// **Why the rectangles must not overlap.** The draw is translucent
/// (`vec4(col, 1) * coverage`), so a pixel covered twice composites twice and
/// the seam is visible. The decomposition below is a partition by construction
/// — vertical slabs at every box edge, disjoint y-intervals inside each — and
/// the draws go out with antialiasing off, so the rasterizer's own rule gives
/// each device pixel to exactly one of two tiles that share an edge.
List<GlassFusedTile>? fusedDrawTiles({
  required List<Rect> boxes,
  required double reach,
  required double cullMargin,
  int maxTiles = kMaxFusedTiles,
}) {
  final int n = boxes.length;
  if (n == 0) {
    return const <GlassFusedTile>[];
  }
  final covers = <Rect>[for (final Rect b in boxes) b.inflate(reach)];

  // One decomposition per connected run of overlapping boxes, and that is the
  // difference between a dozen rectangles and forty. A single sweep over all of
  // them splits every box at every other box's edges — including the edges of
  // one on the far side of the screen, which shares no pixel with it and cannot
  // change what is drawn there. Boxes that do not overlap are already disjoint
  // rectangles, so their decompositions cannot collide and each can be taken on
  // its own. Measured on the corpus: twelve scattered panels fall into 14-21
  // rectangles this way and into 39-55 without it, for the same area.
  final rects = <Rect>[];
  for (final List<int> part in _overlapping(covers)) {
    final slice = <Rect>[for (final int i in part) covers[i]];
    // Every x where the set of boxes in force can change, so a slab between two
    // of them is spanned by the same boxes from top to bottom.
    final xs = <double>{
      for (final Rect r in slice) ...<double>[r.left, r.right],
    }.toList(growable: false)..sort();

    // The run of slabs whose y-intervals are identical, so a single box comes
    // back as a single rectangle rather than as one per edge in the layout.
    List<double>? run;
    double runLeft = 0;
    for (var j = 0; j + 1 < xs.length; j++) {
      final List<double> intervals = _slabIntervals(slice, xs[j], xs[j + 1]);
      if (run != null && _sameSpans(run, intervals)) {
        continue;
      }
      if (run != null) {
        _emitSpans(rects, runLeft, xs[j], run);
      }
      run = intervals.isEmpty ? null : intervals;
      runLeft = xs[j];
    }
    if (run != null) {
      _emitSpans(rects, runLeft, xs.last, run);
    }
    if (rects.length > maxTiles) {
      return null;
    }
  }
  return <GlassFusedTile>[
    for (final Rect rect in rects)
      GlassFusedTile(rect, <int>[
        for (var i = 0; i < n; i++)
          if (_within(boxes[i], cullMargin, rect)) i,
      ]),
  ];
}

/// The boxes grouped into connected runs of overlap, by index.
///
/// Overlap here is positive area: two rectangles that merely share an edge are
/// already disjoint, and putting them in one group would split both on the
/// other's edges for nothing.
List<List<int>> _overlapping(List<Rect> covers) {
  final int n = covers.length;
  final parent = List<int>.generate(n, (int i) => i);
  int find(int i) {
    while (parent[i] != i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  }

  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      if (covers[i].overlaps(covers[j])) {
        parent[find(i)] = find(j);
      }
    }
  }
  final groups = <int, List<int>>{};
  for (var i = 0; i < n; i++) {
    groups.putIfAbsent(find(i), () => <int>[]).add(i);
  }
  return groups.values.toList(growable: false);
}

/// The disjoint y-intervals the boxes spanning `[left, right]` cover, as
/// `[top, bottom, top, bottom, ...]`.
List<double> _slabIntervals(List<Rect> covers, double left, double right) {
  final spans = <Rect>[
    for (final Rect r in covers)
      if (r.left <= left && r.right >= right) r,
  ]..sort((Rect a, Rect b) => a.top.compareTo(b.top));
  final out = <double>[];
  for (final Rect r in spans) {
    // Touching counts as overlapping: two rectangles that share an edge are one
    // rectangle, and emitting them separately would be a seam for nothing.
    if (out.isNotEmpty && r.top <= out.last) {
      if (r.bottom > out.last) {
        out[out.length - 1] = r.bottom;
      }
    } else {
      out
        ..add(r.top)
        ..add(r.bottom);
    }
  }
  return out;
}

bool _sameSpans(List<double> a, List<double> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

void _emitSpans(List<Rect> out, double left, double right, List<double> spans) {
  for (var i = 0; i + 1 < spans.length; i += 2) {
    out.add(Rect.fromLTRB(left, spans[i], right, spans[i + 1]));
  }
}

/// Whether [box] grown by [margin] reaches [rect] at all, touching included.
bool _within(Rect box, double margin, Rect rect) =>
    box.left - margin <= rect.right &&
    box.right + margin >= rect.left &&
    box.top - margin <= rect.bottom &&
    box.bottom + margin >= rect.top;

/// The smallest blend radius that folds [boxes] into **one** connected
/// silhouette, in logical pixels — what a [GlassUnion] hands the shader instead
/// of a declared spacing.
///
/// Closed form rather than a search, in two steps that are both exact.
///
/// **When two shapes bridge.** At the midpoint of a gap `g` both fields read
/// `g / 2`, and a tie is where `smin` is deepest: `min - k / 4`. So the fused
/// field reaches zero there exactly when `k >= 2 * g`, which is the same
/// arithmetic [GlassGroup.spacing] documents from the other end.
///
/// **Which gaps have to bridge.** Not all of them: a chain of panels is one
/// piece of glass without the ends reaching each other. The set is connected
/// once every edge of *some* spanning tree bridges, and the cheapest such tree
/// is the one whose longest edge is shortest — a minimum bottleneck spanning
/// tree, which any MST is. So `k = 2 * (the MST's longest edge)`, by Prim over
/// at most twelve shapes.
///
/// The fold being sequential rather than tree-shaped does not weaken this:
/// `smin(x, c, k) <= min(x, c) <= x`, so folding in more shapes can only lower
/// the field, and a midpoint that the pair alone would bridge stays bridged.
/// The bound is conservative in the direction that keeps the picture connected.
///
/// Zero when the members overlap or touch, and that is not a special case —
/// they are already connected, so a union of overlapping shapes is a plain
/// union and costs what one costs.
double unionBlendRadius(List<Rect> boxes, List<double> radii) => boxes.length < 2
    ? 0
    : 2 * _bottleneck(boxes.length, (int i, int j) => _shapeGap(boxes[i], radii[i], boxes[j], radii[j]));

/// The most [unionBlendRadius] can come to while every member stays inside its
/// travel region — the box it may move within, or null for one that does not
/// move.
///
/// What the *capture* of a moving union has to be sized for. The solved `k`
/// follows the members, so the bridges' reach does too, and a capture input
/// that moves with every step is a retake on every step: a [GlassTravel] that
/// held a lone surface's proxy still bought nothing for a union. The picture
/// keeps the solved `k`; only the capture is sized for the worst of it.
///
/// An upper bound and not the maximum: the gap between two members is bounded
/// with their offsets on each axis pushed apart independently, and the
/// bottleneck of the bounds' spanning tree bounds the bottleneck of the real
/// one, because every edge of a spanning tree is a path the real one can take.
double unionBlendRadiusBound(List<Rect> boxes, List<double> radii, List<Rect?> travel) => boxes.length < 2
    ? 0
    : 2 *
          _bottleneck(
            boxes.length,
            (int i, int j) => _shapeGapBound(boxes[i], radii[i], travel[i], boxes[j], radii[j], travel[j]),
          );

/// The longest edge of the minimum spanning tree over [n] nodes (Prim).
double _bottleneck(int n, double Function(int i, int j) gap) {
  final reached = List<bool>.filled(n, false);
  final nearest = List<double>.filled(n, double.infinity);
  reached[0] = true;
  for (var i = 1; i < n; i++) {
    nearest[i] = gap(0, i);
  }
  var bottleneck = 0.0;
  for (var step = 1; step < n; step++) {
    var pick = -1;
    for (var i = 0; i < n; i++) {
      if (!reached[i] && (pick < 0 || nearest[i] < nearest[pick])) {
        pick = i;
      }
    }
    bottleneck = math.max(bottleneck, nearest[pick]);
    reached[pick] = true;
    for (var i = 0; i < n; i++) {
      if (!reached[i]) {
        nearest[i] = math.min(nearest[i], gap(pick, i));
      }
    }
  }
  return bottleneck;
}

/// [_shapeGap] at its largest over every place the two boxes can be inside
/// their travel regions ([ta], [tb]; null for a box that stays put).
///
/// The cores' separation on each axis is pushed to its extreme independently,
/// which is at least the true extreme of the Euclidean gap because the gap
/// grows with each.
double _shapeGapBound(Rect a, double ra, Rect? ta, Rect b, double rb, Rect? tb) {
  final double ca = ra.clamp(0, a.shortestSide / 2);
  final double cb = rb.clamp(0, b.shortestSide / 2);
  // A box partly outside its region can still be where it is.
  final Rect ra0 = ta?.expandToInclude(a) ?? a;
  final Rect rb0 = tb?.expandToInclude(b) ?? b;
  // Core A's left edge is at most `ra0.right - a.width + ca`, core B's right
  // edge at least `rb0.left + b.width - cb`; and the same the other way round.
  final double dx = math.max(
    0,
    math.max(
      (ra0.right - a.width + ca) - (rb0.left + b.width - cb),
      (rb0.right - b.width + cb) - (ra0.left + a.width - ca),
    ),
  );
  final double dy = math.max(
    0,
    math.max(
      (ra0.bottom - a.height + ca) - (rb0.top + b.height - cb),
      (rb0.bottom - b.height + cb) - (ra0.top + a.height - ca),
    ),
  );
  return math.max(0, math.sqrt(dx * dx + dy * dy) - ca - cb);
}

/// The distance between two rounded boxes, exactly.
///
/// **Not the distance between their boxes**, and the difference is the whole
/// reason this is a function. A rounded box is its core rect — the box pulled
/// in by the radius on every side — grown by a disc of that radius, so the
/// distance between two of them is the distance between the cores less both
/// radii. On neighbours that share a flat edge the two agree and the radius
/// cancels; on **diagonal** neighbours the nearest points are on the corner
/// arcs and the box gap is short by up to `(sqrt(2) - 1) * (ra + rb)`, which is
/// a union that solves for a `k` too small to connect what it was asked to
/// connect.
double _shapeGap(Rect a, double ra, Rect b, double rb) {
  final double ca = ra.clamp(0, a.shortestSide / 2);
  final double cb = rb.clamp(0, b.shortestSide / 2);
  final Rect coreA = a.deflate(ca);
  final Rect coreB = b.deflate(cb);
  final double dx = math.max(0, math.max(coreA.left - coreB.right, coreB.left - coreA.right));
  final double dy = math.max(0, math.max(coreA.top - coreB.bottom, coreB.top - coreA.bottom));
  return math.max(0, math.sqrt(dx * dx + dy * dy) - ca - cb);
}

/// Far enough that no distance a real screen produces can reach it, so the
/// fold's skip never fires.
const double _kNoCull = 1e9;

/// Whether the fused fold skips a shape farther than `k` from the field so far.
///
/// True everywhere but a measurement. The skip is bit-identical — `h` is
/// exactly zero there, so the fold keeps `d` and `mix(n, ni, 0)` is exactly `n`
/// — which is precisely why turning it off has to be possible: a saving that
/// changes no pixel is invisible in every frame and can only be seen as a
/// price. It bought 25% of a twelve-shape group's whole addition on Adreno 830
/// (D170) and 44% on Xclipse 920 (D171), and a dynamic branch is not free on
/// every GPU, so the arm that says so has to exist on hardware nobody here has
/// run.
///
/// A global rather than a constructor argument, and the same shape
/// [debugPaintGlassSurfaces] has: it is a property of the process under
/// measurement, not of any one group, and an application has no business
/// choosing it.
///
/// Setting it repaints every group that is already mounted. That is not a
/// convenience: the switch changes no pixel, so a group that kept its retained
/// layer would go on culling with the switch off and the run would report the
/// branch as free. The first arm written against this found exactly that.
bool get debugGlassFoldCull => _foldCull;

set debugGlassFoldCull(bool value) {
  if (value == _foldCull) {
    return;
  }
  _foldCull = value;
  for (final RenderGlassGroup group in RenderGlassGroup._live) {
    group.markNeedsPaint();
  }
}

bool _foldCull = true;

/// Whether a fused group is drawn as several rectangles instead of one.
///
/// The split changes no pixel — [fusedDrawTiles] carries the proof — so it can
/// only be seen as a price, and what it trades runs both ways: fewer fragments,
/// each folding fewer shapes, against more draw calls. **On by default except
/// on desktop, because what a draw costs is decided by whether the engine runs
/// SDFs, and Dart can tell that only by the platform.** Where it does not —
/// Android always, iOS unless the app opts in — both GPUs that have been timed
/// charge for the fragments. On Adreno 830 eleven
/// rectangles cost 0.91x the one quad's frame and twenty cost 0.52x it, the
/// glass over its floor 0.83x and 0.35x (D192). On the M2 iPad Pro the same two
/// scenes cost 0.71-0.76x and 0.40-0.42x in GPU time, the glass over its floor
/// 0.61-0.67x and 0.30-0.32x, two seeds (D194).
///
/// For a day the default was keyed on the declared hardware — the quad on
/// Apple, from D190: on an Apple-silicon Mac eleven rectangles cost 3.2x the
/// one quad and fifteen 5.8-6.3x. That run had one instrument, the raster
/// thread's wall time, because a desktop's GPU tracer dies with its uptime; on
/// the iPad, where both instruments read the same arms, the raster thread says
/// +8-25% for the split while the GPU says -24…-60%, and the GPU is where the
/// frame is spent (3-7 ms of 8.3 against 0.5-0.6). So D190 priced the raster
/// thread, and the key answered the same for every declaration once the GPU
/// had been asked — it was removed rather than kept as a switch that switches
/// nothing.
///
/// It came back keyed on the platform for a day (D199): on an M3 Max in Metal
/// System Trace eleven rectangles cost 1.88x the quad's frame and fifteen
/// 1.39x, because every shader rectangle there was three offscreen passes — a
/// white SDF mask, the shader and a `kSrcIn` blend (`canvas.cc:2185-2209`,
/// flutter/flutter#192994). The tiles asked for `isAntiAlias = false`, which
/// keeps a draw off that path, and the flag never arrived: it opened the
/// picture, where the recorder does not write a `false` it already holds and
/// Impeller starts from `true` ([primeAliasedDraw]). Primed, a tile is one
/// draw on macOS as well, and the split costs 0.94-0.95x the quad's frame on
/// the cluster and 0.70-0.75x on the scatter, two seeds (D200). So it ships on
/// every platform again, and nothing keys it.
///
/// Set `null` to return to the default.
///
/// Independent of [debugGlassFoldCull]: dropping a shape from a tile is exact
/// whether or not the shader's own skip runs, so the arm that prices one does
/// not silently price the other.
///
/// Set it before the tree mounts, and restore it afterwards. Setting it
/// repaints every group already mounted, for the reason the cull's setter
/// does: a retained layer would go on drawing the old way and the run would
/// report the split as free.
bool get debugGlassFusedSplit => _fusedSplit ?? debugGlassFusedSplitDefault;

set debugGlassFusedSplit(bool? value) {
  final bool was = debugGlassFusedSplit;
  _fusedSplit = value;
  if (debugGlassFusedSplit == was) {
    return;
  }
  for (final RenderGlassGroup group in RenderGlassGroup._live) {
    group.markNeedsPaint();
  }
}

bool? _fusedSplit;

/// What [debugGlassFusedSplit] reads while nothing is imposed: the split.
///
/// Separate from the flag because a benchmark records what an unnamed arm
/// resolved to, and by then an earlier arm may have imposed a value; and a
/// getter rather than a constant because this default has moved three times
/// (D190, D194, D199, D200), and a harness that copied it was wrong after each.
bool get debugGlassFusedSplitDefault => true;

/// Draws every [GlassSurface] below it as one fused shape.
///
/// The analogue of SwiftUI's `GlassEffectContainer`, and [spacing] means what
/// its does: two surfaces closer than this at their nearest edges grow a bridge
/// between them. Zero is a legitimate declaration and not a disabled feature —
/// it says "share the capture, keep the silhouettes", which is the batch
/// without the blend.
///
/// **A group holds the glass, not the page.** It paints the fused shape and
/// *then* its subtree, so everything inside it lands on top of the glass —
/// which is what a panel's own label wants and what the content behind it does
/// not. Put the background beside the group, not in it.
///
/// ```dart
/// Stack(
///   children: <Widget>[
///     Positioned.fill(child: page),          // behind the glass
///     Positioned.fill(
///       child: GlassGroup(                   // the glass, and only the glass
///         spacing: 12,
///         child: Stack(children: <Widget>[fab, toolbar]),
///       ),
///     ),
///   ],
/// )
/// ```
///
/// The finish is the group's, not each member's: one draw has one set of
/// optics, so a member that names its own finish is declaring something the
/// fused picture cannot express. Reported in debug, once, and then ignored.
///
/// **What a group costs is fragments, on both GPUs it has been timed on.**
///
/// One draw of N shapes evaluates every shape at every fragment, so each
/// declared shape adds about **0.030 cycles per device pixel** to every pixel
/// the group covers — roughly half of what a lone glass fragment costs in
/// total, each — and twelve of them make the fragment about six times a single
/// surface's. Measured on Adreno 830 (D169, D170), reproduced in sign on
/// Xclipse 920 (D171), and re-derived from the tracked digests by
/// `test/glass/glass_group_test.dart`. In screens: twelve panels declared one
/// group came out at 2.25x stock Material where the same twelve ungrouped were
/// 1.19x, and at 3.24x against 1.18x once spread over the screen. There, a
/// group is a way to get a picture and not a way to get a price.
///
/// Those are the one quad's numbers, and the group no longer draws one: since
/// D192 it draws tiles ([debugGlassFusedSplit]), which on Adreno
/// took the clustered twelve from 1.87x Material to 1.70x and the scattered
/// twelve from 3.17x to 1.65x. The layout stopped being the price; the
/// declaration still is.
///
/// *On the M2 iPad Pro (D194), in GPU time,* the sign is the same: the
/// clustered twelve grouped cost 1.60-1.65x the same twelve ungrouped as one
/// quad and 1.18-1.21x as tiles, two seeds.
///
/// *What D190 read on an Apple-silicon Mac is the other sign* — the ungrouped
/// twelve at **5.1-5.4x** the one fused draw, the area not entering — and it
/// was read off the raster thread's wall time, the only instrument a desktop
/// run has. On the iPad that instrument agrees with the Mac's sign on the same
/// arms (the grouped quad 0.86-0.90x the ungrouped) while the GPU reads the
/// opposite, and the GPU is where the frame goes. So the Mac's number is a
/// price of the raster thread, not of the GPU, which on a desktop is still
/// untimed.
///
/// So the guidance is the picture: declare the surfaces that should *look*
/// merged and leave the rest out.
///
/// **And [spacing] zero is not the cheap way to have a group.** It is the other
/// declaration — one draw, one shared capture, every member keeping its own
/// silhouette — and it costs 2.34x an ungrouped screen's addition where a
/// spacing of 8 costs 3.05x (D172). The difference between the two spacings is
/// area and nothing else: the fragment costs the same to within 0.4% either
/// way, and what a non-zero spacing buys is a quad reaching further out. The
/// cheap thing is not grouping.
class GlassGroup extends StatefulWidget {
  const GlassGroup({
    required this.child,
    this.spacing = 0,
    this.finish,
    this.labelled = true,
    super.key,
  });

  /// The edge-to-edge distance at which two members fuse, in logical pixels.
  ///
  /// The blend radius the shader takes is twice this, and the factor is
  /// arithmetic rather than taste: at the midpoint of a gap `g` both fields
  /// read `g/2`, so the smooth minimum reaches zero — which is where a bridge
  /// starts — exactly when `g = k/2`.
  final double spacing;

  /// The optics for the whole group. Null takes the host's.
  final GlassFinish? finish;

  /// Whether labels are drawn over the group's glass; false for blobs and
  /// drops, which then keep their finish. See [GlassSurface.labelled].
  final bool labelled;

  final Widget child;

  @override
  State<GlassGroup> createState() => _GlassGroupState();
}

class _GlassGroupState extends State<GlassGroup> {
  final GlassBlendGroup _group = GlassBlendGroup();

  @override
  Widget build(BuildContext context) => _GlassGroupRenderWidget(
    group: _group,
    spacing: widget.spacing,
    finish: widget.finish,
    labelled: widget.labelled,
    child: GlassGroupScope(group: _group, child: widget.child),
  );
}

/// Draws every [GlassSurface] below it as one piece of glass, **however far
/// apart they are**.
///
/// SwiftUI's `glassEffectUnion`, and the reason it is a type of its own rather
/// than a [GlassGroup] with a large spacing: it takes no spacing at all. The
/// roadmap's standing guess was that a union is `GlassGroup(spacing: infinity)`
/// and therefore not worth a name. It is not — infinity is not a value this
/// machine can take. The quad a fused draw shades is the members' union grown
/// by `delta(n) * k`, so an infinite `k` is an infinite quad; and the fold's
/// skip, which is a quarter of a twelve-shape group's whole addition on Adreno
/// and 44% of it on Xclipse (D170, D171), fires when a shape is farther than
/// `k` than the field so far, so an infinite `k` never skips anything. A union
/// declared that way would ask for every pixel on the screen and pay full price
/// for each.
///
/// So the union **solves** for `k` instead of taking it: the smallest radius
/// that connects the members that are there, which is twice the longest edge of
/// their minimum spanning tree ([unionBlendRadius]). Finite, minimal for the
/// picture asked for, and usually *smaller* than the spacing somebody would
/// have declared to be safe — a spacing costs the quad and nothing else (the
/// fragment is the same to within 0.4% at `spacing` 0 and 8, D172), so the
/// difference between a solved `k` and a guessed one is paid in area.
///
/// **Two consequences, both visible, both named rather than buried.**
///
///  - `k` smooths the *whole* fold, not just the bridges, so a union spread
///    over a distance is a puffier silhouette than the same shapes near each
///    other — the members swell by up to `k / 4` of field. That is what "one
///    piece of glass" looks like at distance, and it is the reason this is a
///    declaration rather than a default.
///  - `k` is a function of where the members are, so moving one member changes
///    the shape of all of them, continuously. A declared spacing is the other
///    trade: a member that drifts out of range breaks its bridge and leaves
///    everything else alone.
///
/// **No `GlassId`.** Apple needs one because `glassEffectUnion(id:namespace:)`
/// is a modifier on each view, with no common ancestor to group by, so the
/// identity has to be written down. Here the ancestor *is* the namespace:
/// membership is position in the tree, the nearest [GlassGroupScope] wins, and
/// a union nested inside a group partitions it — the inner surfaces fuse with
/// each other and the outer ones with each other. Two unions are two widgets.
/// An id would be a second way to say what the tree already says, and the thing
/// Apple's id does that position cannot — carrying a shape's identity *across*
/// an appearance so the glass morphs between them — is still not here. What is
/// here since D209 is the half that needs no identity: a member that appears or
/// leaves inside a group buds out of its neighbours through
/// `GlassSurface.presence`, which is a field offset and exact at zero.
class GlassUnion extends StatefulWidget {
  const GlassUnion({required this.child, this.finish, this.labelled = true, super.key});

  /// The optics for the whole union. Null takes the host's.
  final GlassFinish? finish;

  /// See [GlassGroup.labelled].
  final bool labelled;

  final Widget child;

  @override
  State<GlassUnion> createState() => _GlassUnionState();
}

class _GlassUnionState extends State<GlassUnion> {
  final GlassBlendGroup _group = GlassBlendGroup();

  @override
  Widget build(BuildContext context) => _GlassGroupRenderWidget(
    group: _group,
    spacing: null,
    finish: widget.finish,
    labelled: widget.labelled,
    child: GlassGroupScope(group: _group, child: widget.child),
  );
}

class _GlassGroupRenderWidget extends SingleChildRenderObjectWidget {
  const _GlassGroupRenderWidget({
    required this.group,
    required this.spacing,
    required this.finish,
    required this.labelled,
    required Widget super.child,
  });

  final GlassBlendGroup group;
  final bool labelled;

  /// The declared spacing, or null to solve for it — see [GlassUnion].
  final double? spacing;
  final GlassFinish? finish;

  @override
  RenderGlassGroup createRenderObject(BuildContext context) => RenderGlassGroup(group, GlassScope.maybeOf(context))
    ..proxy = GlassProxyScope.maybeOf(context)
    ..theme = GlassTheme.of(context)
    ..spacing = spacing
    ..finish = finish
    ..labelled = labelled
    ..devicePixelRatio = _dprOf(context);

  @override
  void updateRenderObject(BuildContext context, RenderGlassGroup renderObject) {
    renderObject
      ..ledger = GlassScope.maybeOf(context)
      ..proxy = GlassProxyScope.maybeOf(context)
      ..theme = GlassTheme.of(context)
      ..spacing = spacing
      ..finish = finish
      ..labelled = labelled
      ..devicePixelRatio = _dprOf(context);
  }

  static double _dprOf(BuildContext context) =>
      MediaQuery.maybeDevicePixelRatioOf(context) ?? View.maybeOf(context)?.devicePixelRatio ?? 1;
}

/// The render object behind [GlassGroup].
class RenderGlassGroup extends RenderProxyBox {
  RenderGlassGroup(this._group, this._ledger) {
    _group._owner = this;
  }

  final GlassBlendGroup _group;

  /// A group repaints on every published proxy, and nothing else should — the
  /// same reason [RenderGlassSurface] gives (D149). Without this, a publish
  /// would repaint the whole screen under the glass.
  ///
  /// It is also what gives the layer watch something to exclude: the group's
  /// glass has to be outside what the watch reads, or the watch is looking at
  /// the pipeline's own output.
  @override
  bool get isRepaintBoundary => true;

  // Reachable because this is the class that owns it: `RenderObject.layer` is
  // `@protected`, and `debugLayer` returns null in profile.
  Layer? get compositedLayer => layer;

  GlassLedger? _ledger;
  set ledger(GlassLedger? value) {
    if (identical(value, _ledger)) {
      return;
    }
    _ledger?.unregisterCluster(_group);
    _ledger = value;
    if (attached) {
      _ledger?.registerCluster(_group);
    }
  }

  /// The declared half-gap at which two members fuse, or null when the group
  /// is a [GlassUnion] and the blend radius is solved from where the members
  /// are.
  double? _spacing;
  set spacing(double? value) {
    if (value == _spacing) {
      return;
    }
    _spacing = value;
    markNeedsPaint();
  }

  GlassFinish? _finish;
  set finish(GlassFinish? value) {
    if (value == _finish) {
      return;
    }
    _finish = value;
    _legibilityMemo = null;
    markNeedsPaint();
  }

  double _devicePixelRatio = 1;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) {
      return;
    }
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  GlassProxyHandle? _proxy;
  set proxy(GlassProxyHandle? value) {
    if (identical(value, _proxy)) {
      return;
    }
    _proxy?.removeListener(_onProxyPublished);
    _proxy = value;
    if (attached) {
      _proxy?.addListener(_onProxyPublished);
    }
    markNeedsPaint();
  }

  /// The finish in force: this group's, else the host's.
  GlassFinish get effectiveFinish => _legible.finish;

  /// The opaque outline the increase-contrast switch asks for, or null. Drawn
  /// by the fused shader along the silhouette, so a bridge gets it too.
  Color? get effectiveHighContrastRim => _theme.highContrast ? _legible.rim : null;

  /// [GlassThemeData.legibility] for this theme and finish, kept until either
  /// changes: it runs in `paint`, and with a label floor it bisects.
  GlassLegibility get _legible => _legibilityMemo ??= _theme.legibility(_finish, _labelled);
  GlassLegibility? _legibilityMemo;

  bool _labelled = true;
  set labelled(bool value) {
    if (value == _labelled) {
      return;
    }
    _labelled = value;
    _legibilityMemo = null;
    markNeedsPaint();
  }

  /// Repaints for a new proxy, and only if this group is going to read it. See
  /// `RenderGlassSurface._onProxyPublished`.
  void _onProxyPublished() {
    if (_group.tier.readsBackdrop) {
      markNeedsPaint();
    }
  }

  GlassThemeData _theme = const GlassThemeData();
  set theme(GlassThemeData value) {
    if (value == _theme) {
      return;
    }
    _theme = value;
    _legibilityMemo = null;
    _group.tier = value.tier.tier;
    markNeedsPaint();
  }

  /// The blend radius and how far past the members' boxes the fused
  /// silhouette can reach, for [boxes] in any one translated space.
  ///
  /// One function for the quad and for the capture, because the two have to
  /// agree: a capture smaller than the quad is the clamped band D201 found,
  /// and a quad smaller than the silhouette cuts the bridges off.
  ({double blend, double depression, double slack, double reach}) _fusedReach(
    List<Rect> boxes,
    List<double> radii, {
    List<Rect?>? travel,
  }) {
    final double? declared = _spacing;
    final double blend = declared != null
        ? declared * 2
        : travel != null
        ? unionBlendRadiusBound(boxes, radii, travel)
        : unionBlendRadius(boxes, radii);
    final double depression = _foldDepression(boxes.length);
    // The rasterizer's slack, and both bounds carry it: half a device pixel is
    // where the shader's coverage reaches zero, and the extra logical pixel is
    // against the rasterizer's own rounding rather than against the bound.
    final double slack = 0.5 / _devicePixelRatio + 1;
    return (
      blend: blend,
      depression: depression,
      slack: slack,
      reach: depression * blend + slack,
    );
  }

  /// Where this group is, in global logical pixels. See
  /// [RenderGlassSurface.globalRect] for why it is `getTransformTo(null)`.
  Rect get globalRect => MatrixUtils.transformRect(getTransformTo(null), Offset.zero & size);

  /// Frames this group drew the fused shape.
  int fusedPaints = 0;

  /// Frames it had members and declined to fuse them.
  ///
  /// Non-zero means a group past [kMaxFusedShapes]: its members drew themselves,
  /// so the screen is a correct picture of the wrong declaration. See
  /// [_reportOverflow] for why this is a counter and not a throw.
  int refusedPaints = 0;

  /// Frames it painted with nothing to sample.
  int paintsWithoutProxy = 0;

  /// Frames where the invariant did not hold: members landed in different slots.
  ///
  /// It cannot happen while the host builds `fused` out of this register, which
  /// is exactly why it is counted: the check is on the mechanism rather than on
  /// the arithmetic, so a future caller that packs without the grouping is
  /// caught by the number instead of by the picture.
  int splitSlots = 0;

  /// The rectangle the fused draw last covered, in this group's paint space.
  ///
  /// Null until the group has fused once. Read by an instrument or a report:
  /// dead area is one of the two articles a group moves — the other is D26's
  /// fragmentation tax, which it moves the other way — and a report without the
  /// quad would be describing the widget tree's shape rather than the mechanism.
  Rect? lastFusedQuad;

  /// The blend radius `k` the last fused draw handed the shader, in logical
  /// pixels — twice the declared spacing, or what [unionBlendRadius] solved for.
  ///
  /// Recorded because a [GlassUnion] does not take it as an argument: the one
  /// number that says what picture the union chose is otherwise nowhere, and a
  /// solver that returned a plausible constant would draw a plausible blob.
  double lastBlendRadius = 0;

  /// The cull distance the last fused draw handed the shader, in logical
  /// pixels: `k`, or [_kNoCull] when [debugGlassFoldCull] is off.
  ///
  /// Recorded because the switch it reflects changes no pixel by construction,
  /// and an axis with no observable trace is not an axis — a run of the `off`
  /// arm that silently culled anyway would report as "the branch is free".
  double lastCullDistance = 0;

  /// The rectangles the last fused draw covered, or null when it covered
  /// [lastFusedQuad] with one.
  ///
  /// Kept beside the quad rather than instead of it: the quad is still the
  /// bound the tiles partition a part of, and a debug overlay that drew only
  /// the tiles could not show what they removed.
  List<GlassFusedTile>? lastFusedTiles;

  /// Draws the fused glass took, summed over [fusedPaints].
  ///
  /// The article the split trades against fragments, and the one quantity a
  /// tiled draw adds. Its denominator is [fusedPaints]: a group that split into
  /// eleven rectangles and one that refused to split are the same row otherwise.
  int fusedDraws = 0;

  /// Frames the split was asked for and refused as too fine ([kMaxFusedTiles]).
  ///
  /// Must be zero on every layout the corpus has; non-zero means a screen is
  /// paying the whole quad on a bound nobody measured.
  int fusedTileRefusals = 0;

  /// Of [fusedDraws], those made with `isAntiAlias` false: every tile, and the
  /// unsplit quad when [debugGlassShaderAntiAlias] is off.
  int fusedDrawsAliased = 0;

  /// Those quads and the member boxes inside them, summed over [fusedPaints],
  /// in logical px^2.
  ///
  /// Two totals and not their ratio: a dead-area fraction that moved says
  /// nothing about which of the two moved, and on this axis both do. With the
  /// split on, the first is the tiles' area rather than the quad's — it is what
  /// was shaded either way.
  double fusedQuadArea = 0;
  double fusedShapeArea = 0;

  /// Shaded area weighted by the shapes folded over it, in logical px^2 per
  /// shape, summed over [fusedPaints].
  ///
  /// The third total, and the one D169's model multiplies: the fragment costs
  /// `0.0343 + 0.0441 * n` cycles per device pixel on Adreno 830, so a draw
  /// that halves its area and quarters the shapes in it moves this by eight and
  /// [fusedQuadArea] by two. Area alone would have called those the same run.
  double fusedFoldArea = 0;

  void resetCounters() {
    fusedPaints = 0;
    paintsIntoProxy = 0;
    refusedPaints = 0;
    paintsWithoutProxy = 0;
    splitSlots = 0;
    fusedQuadArea = 0;
    fusedShapeArea = 0;
    fusedFoldArea = 0;
    fusedDraws = 0;
    fusedTileRefusals = 0;
    fusedDrawsAliased = 0;
    lastCullDistance = 0;
    lastBlendRadius = 0;
  }

  /// The group's membership, for a test or a debug overlay.
  GlassBlendGroup get group => _group;

  /// Whether the over-capacity report has already been made for this group.
  ///
  /// Once, not per frame: the condition is a property of the tree, and a report
  /// on every frame of an animation is a report nobody reads.
  bool _reportedOverflow = false;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_group.fuses) {
      _paintFusedLayer(context, offset);
    } else if (_group._members.isNotEmpty && _group.tier == GlassTier.full) {
      // Only over-capacity counts as a refusal. A group below the full rung is
      // not failing to do something it was asked to do, and reporting it as one
      // would put an error in the console of every screen that turned the
      // ladder down.
      refusedPaints++;
      _reportOverflow();
    }
    super.paint(context, offset);
  }

  /// Says out loud, once, that the group is too large to fuse.
  ///
  /// Reported rather than asserted, and the distinction is deliberate. The
  /// number of surfaces on a screen is a property of the application's data, so
  /// a list one item too long must not take the app down — but the degradation
  /// is a *missing bridge*, which on a screenshot looks like a design decision.
  /// So: a counter that ships, and an error in debug that a test can read.
  void _reportOverflow() {
    assert(() {
      if (!_reportedOverflow) {
        _reportedOverflow = true;
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: FlutterError(
              'A GlassGroup holds ${_group._members.length} surfaces; the fused draw '
              'carries $kMaxFusedShapes.\n'
              'Its members are drawing themselves, so the bridges between them are '
              'missing. Twelve is where the measured corpus stops (D26) — past it the '
              'cost of a group is an extrapolation nobody took — so the group is '
              'refused rather than truncated.',
            ),
            library: 'glass',
            context: ErrorDescription('while painting a GlassGroup'),
          ),
        );
      }
      return true;
    }());
  }

  /// Says out loud, once, that a member asked for optics the group cannot give
  /// it.
  bool _reportedFinish = false;

  void _reportMemberFinishes(List<RenderGlassSurface> shapes) {
    assert(() {
      if (_reportedFinish) {
        return true;
      }
      final int named = shapes.where((RenderGlassSurface s) => s.declaredFinish != null).length;
      if (named == 0) {
        return true;
      }
      _reportedFinish = true;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: FlutterError(
            '$named of ${shapes.length} surfaces in a GlassGroup name their own finish.\n'
            'A fused group is one draw and one set of optics, so the group\'s finish is '
            'what ships and theirs is ignored. Put the finish on the GlassGroup, or take '
            'the surface out of it.',
          ),
          library: 'glass',
          context: ErrorDescription('while painting a GlassGroup'),
        ),
      );
      return true;
    }());
  }

  /// The fused draw goes into a layer that records at composite time, for the
  /// reason [RenderGlassSurface]'s does: the silhouette and the map into the
  /// atlas are functions of where the group and its members are on screen, and
  /// neither a member that moved behind its own boundary nor a group re-offset
  /// by a scroll paints this node. Everything the draw needs is read when it is
  /// recorded, so the counters below count recorded draws.
  void _paintFusedLayer(PaintingContext context, Offset offset) {
    final GlassProxyFrame? frame = _frame;
    if (context is ProxyWalkContext) {
      // Into the capture of glass standing on this group; see
      // `RenderGlassSurface._paintIntoProxy`.
      if (frame != null && _proxy?.groupProgram != null) {
        paintsIntoProxy++;
        _paintFused(context.canvas, offset, frame);
      }
      return;
    }
    if (frame == null || _proxy?.groupProgram == null) {
      paintsWithoutProxy++;
      return;
    }
    final GlassDrawLayer layer = _drawLayer.layer ??= GlassDrawLayer();
    layer
      ..invalidate()
      ..probe = _drawProbe
      ..painter = (Canvas canvas) {
        // A replaced frame is a disposed texture; see the surface's painter.
        if (identical(_frame, frame)) {
          _paintFused(canvas, offset, frame);
        }
      };
    context.addLayer(layer);
  }

  /// The frame the members' slot is in: the base one, or the level of glass
  /// this group stands at.
  GlassProxyFrame? get _frame {
    final GlassProxyHandle? proxy = _proxy;
    if (proxy == null) {
      return null;
    }
    return _group._members.isEmpty ? proxy.frame : proxy.frameFor(_group._members.first);
  }

  /// Fused draws made into a capture of the level above rather than onto the
  /// screen.
  int paintsIntoProxy = 0;

  final LayerHandle<GlassDrawLayer> _drawLayer = LayerHandle<GlassDrawLayer>();

  /// See `RenderGlassSurface.drawLayer`.
  Layer? get drawLayer => _drawLayer.layer;

  /// Draws recorded at composite time, and how many of those because the glass
  /// had moved since it was painted — the trace of `GlassDrawLayer`, without
  /// which a moving glass that happened to be repainted anyway would pass every
  /// pixel arm.
  int get drawRecords => _drawLayer.layer?.records ?? 0;
  int get drawRecordsOnMove => _drawLayer.layer?.recordsOnMove ?? 0;

  List<Object?> _drawProbe() => <Object?>[
    if (attached && hasSize) globalRect,
    for (final RenderGlassSurface member in _group._members)
      if (member.attached && member.hasSize) ...<Object?>[member.globalRect, member.presence],
  ];

  void _paintFused(Canvas canvas, Offset offset, GlassProxyFrame frame) {
    final ui.FragmentProgram program = _proxy!.groupProgram!;
    // Every member that is on the screen, and the slot they share. A member the
    // frame has never seen — mounted since the last capture — is left out of
    // this draw rather than drawn against somebody else's slot.
    final shapes = <RenderGlassSurface>[];
    AtlasSlot? slot;
    for (final RenderGlassSurface member in _group._members) {
      final AtlasSlot? found = frame.slotForKey(member);
      if (found == null) {
        continue;
      }
      if (slot == null) {
        slot = found;
      } else if (found.index != slot.index) {
        splitSlots++;
        continue;
      }
      shapes.add(member);
    }
    if (slot == null || shapes.isEmpty) {
      paintsWithoutProxy++;
      return;
    }

    // Draw space: the group's own box, the same space `FlutterFragCoord`
    // reports. A member's place comes through global coordinates because that
    // is the only space both of them can name.
    final Offset toDraw = offset - globalRect.topLeft;
    final boxes = <Rect>[
      for (final RenderGlassSurface member in shapes) member.globalRect.shift(toDraw),
    ];

    // The quad is the members' union, not the group's box. A `GlassGroup` is
    // laid out by whatever holds its children — a `Stack` over the page, a
    // `Row` across the screen — so its box says where the group *is* and not
    // where its glass is, and shading the difference is the largest single
    // article a group adds. Nothing outside this rect can reach the screen:
    // the shader's coverage is `clamp(0.5 - d / uPixel, 0, 1)`, exactly zero
    // half a device pixel outside the fused shape, and every other term is
    // multiplied by it.
    //
    // How far outside the union the bridges can reach, and it is a function of
    // the count rather than a constant. One `smin` step depresses the field by
    // at most `k / 4`, so a naive bound over n shapes would be
    // `(n - 1) * k / 4` — but the steps do not add up, because each one widens
    // the gap the next one is measured against. Write the running depression as
    // `d = min_i - delta`. Folding in a shape that is farther leaves
    // `delta' = g + h^2 k / 4` with `g <= delta` (the gap cannot exceed what is
    // already lost), and that expression grows with `g`, so
    // `delta' <= delta + (k - delta)^2 / (4k)`; folding in a nearer one leaves
    // at most `k / 4`. The same recurrence bounds both, which makes
    // [_foldDepression] an upper bound for *any* arrangement and not just for
    // the equidistant one it is tight on.
    //
    // Why bother, when `k` alone is a valid bound: a spacing costs the quad and
    // nothing else. Measured, at twelve shapes, the fragment costs the same at
    // `spacing = 0` and `spacing = 8` to within 0.4% — the whole price of the
    // bridges is the area this number inflates (D172). At twelve it is 0.758,
    // at two it is 0.25, so the naive `k` overcharges a pair by four times.
    Rect union = boxes.first;
    for (var i = 1; i < boxes.length; i++) {
      union = union.expandToInclude(boxes[i]);
    }
    // `k` is `uBlend`: twice the declared spacing, or — for a [GlassUnion] —
    // whatever it takes to connect the members that are actually there. The
    // half device pixel is where the shader's coverage reaches zero; the extra
    // logical pixel is slack against the rasterizer's own rounding, not against
    // the bound.
    final (:double blend, :double depression, :double slack, :double reach) = _fusedReach(
      boxes,
      <double>[for (final RenderGlassSurface member in shapes) member.effectiveRadius],
    );
    // Not intersected with the group's own box, and that is the same decision
    // as the paragraph above rather than a second one. A group laid out tight
    // around its members has bridges that bulge past them, and clipping to the
    // box would delete exactly those — which would put the layout back into the
    // picture. Painting outside one's box is what a shadow does too.
    final Rect quad = union.inflate(reach);

    // And the same bound applied per member instead of to all of them at once.
    // The silhouette lies inside the union of the members' own boxes grown by
    // `reach`, which on a scattered layout is a small part of the rectangle
    // that contains them; what the tiles cost is draw calls, and what they save
    // is fragments and the shapes each one folds. [fusedDrawTiles] carries why
    // it changes no pixel.
    final bool split = debugGlassFusedSplit;
    final List<GlassFusedTile>? tiles = split
        ? fusedDrawTiles(
            boxes: boxes,
            reach: reach,
            cullMargin: (1 + 2 * depression) * blend + slack,
          )
        : null;
    if (split && tiles == null) {
      fusedTileRefusals++;
    }

    fusedPaints++;
    lastCullDistance = debugGlassFoldCull ? math.max(blend, 1e-4) : _kNoCull;
    lastBlendRadius = blend;
    lastFusedQuad = quad;
    lastFusedTiles = tiles;
    if (tiles == null) {
      fusedDraws++;
      fusedQuadArea += quad.width * quad.height;
      fusedFoldArea += quad.width * quad.height * shapes.length;
    } else {
      fusedDraws += tiles.length;
      for (final GlassFusedTile tile in tiles) {
        final double area = tile.rect.width * tile.rect.height;
        fusedQuadArea += area;
        fusedFoldArea += area * tile.shapes.length;
      }
    }
    fusedShapeArea += boxes.fold<double>(0, (double a, Rect b) => a + b.width * b.height);
    _reportMemberFinishes(shapes);

    final GlassFinish finish = effectiveFinish;
    final GlassOptics optics = finish.optics;
    final Offset srcOrigin = globalRect.topLeft - offset;
    final double scale = slot.pixelRatio;
    final Rect texels = slot.rect;
    final Offset mapOrigin = (srcOrigin - slot.source.topLeft) * scale + texels.topLeft;
    final Color tint = finish.tint;
    final Color? contrastRim = effectiveHighContrastRim;
    final Color rim = contrastRim ?? finish.rim;
    final double rimWidth = contrastRim != null ? kHighContrastRimWidthLogical : (rim.a <= 0 ? 0 : kRimWidthLogical);

    // Everything but the members, which are the tile's.
    ui.FragmentShader shaded() => program.fragmentShader()
      ..setFloat(0, frame.image.width.toDouble())
      ..setFloat(1, frame.image.height.toDouble())
      ..setFloat(2, mapOrigin.dx)
      ..setFloat(3, mapOrigin.dy)
      ..setFloat(4, scale)
      // Texel centres, not the slot's edges: a bilinear tap reaches half a texel
      // each way. See [RenderGlassSurface] for the column this cost.
      ..setFloat(5, texels.left + 0.5)
      ..setFloat(6, texels.top + 0.5)
      ..setFloat(7, texels.right - 0.5)
      ..setFloat(8, texels.bottom - 0.5)
      ..setFloat(10, blend)
      ..setFloat(_kTail, optics.thickness)
      ..setFloat(_kTail + 1, optics.strength)
      ..setFloat(_kTail + 2, optics.edgePower)
      ..setFloat(_kTail + 3, optics.shoulder)
      ..setFloat(_kTail + 4, tint.r)
      ..setFloat(_kTail + 5, tint.g)
      ..setFloat(_kTail + 6, tint.b)
      ..setFloat(_kTail + 7, tint.a)
      ..setFloat(_kTail + 8, rimWidth)
      ..setFloat(_kTail + 9, rim.r)
      ..setFloat(_kTail + 10, rim.g)
      ..setFloat(_kTail + 11, rim.b)
      ..setFloat(_kTail + 12, rim.a)
      ..setFloat(_kTail + 13, 1 / _devicePixelRatio)
      // The fold's cull distance, which is `k` in every draw that ships. It is
      // a uniform so that the skip's bit-identity is checkable from outside the
      // shader — render the same fragment twice with the branch compiled into
      // both and the threshold out of reach in one — and
      // [debugGlassFoldCull] is the same lever reachable from a benchmark.
      ..setFloat(_kTail + 14, lastCullDistance)
      ..setFloat(_kTail + 15, contrastRim == null ? 0 : 1)
      ..setImageSampler(0, frame.image, filterQuality: FilterQuality.low);

    // One shader object for every tile — natively. `ReusableFragmentShader::
    // shader()` copies the uniform buffer on each draw the paint is converted
    // for (`fragment_shader.cc:110-120`), so setting the next tile's members
    // and drawing again is a memcpy in C++ rather than an allocation in Dart.
    //
    // **Not on the web.** Skwasm's runtime-effect shader holds the uniform
    // buffer by reference (`UniformData` is a `shared_ptr`, handed to the
    // `DlColorSource` uncopied), so a draw recorded with it renders whatever
    // the buffer says when the picture is rasterized — the last tile's
    // members, for every tile. Blobs vanished, or showed through the wrong
    // tile as the bare tint. There each tile gets a shader of its own, and
    // CanvasKit does the same with a raw pointer, so each is released only
    // with the picture (`releaseGlassShader`).
    final bool shared = !kIsWeb;
    final ui.FragmentShader? shader = shared ? shaded() : null;

    final Paint paint = Paint()
      // Off for a split draw, and that is the seam rather than a detail. The
      // shader's output is premultiplied and translucent, so a device pixel
      // handed to two tiles composites twice: coverages of 0.37 and 0.63 make
      // 0.77 and not 1, which is a line down the middle of the glass. With
      // antialiasing off the rasterizer's fill rule gives a shared edge to
      // exactly one of the two. The single quad's own edges are where coverage
      // is zero anyway, so there the flag chooses the engine's draw and not the
      // picture — see [debugGlassShaderAntiAlias].
      ..isAntiAlias = tiles == null && debugGlassShaderAntiAlias;

    void draw(Rect rect, List<int> members) {
      final ui.FragmentShader tile = shader ?? shaded();
      paint.shader = tile;
      tile.setFloat(9, members.length.toDouble());
      for (var i = 0; i < members.length; i++) {
        final int m = members[i];
        final Rect box = boxes[m];
        // The member's presence, as the same field plus a constant — which is
        // why neither the quad, the tiles nor the capture reach move with it:
        // an eroded member is inside its box, so every bound drawn from the
        // box still holds.
        final double inset = shapes[m].presenceInset(blend: blend);
        tile
          ..setFloat(11 + i * 4, box.center.dx)
          ..setFloat(12 + i * 4, box.center.dy)
          ..setFloat(13 + i * 4, box.width / 2 - inset)
          ..setFloat(14 + i * 4, box.height / 2 - inset);
        tile.setFloat(11 + kMaxFusedShapes * 4 + i, shapes[m].effectiveRadius - inset);
      }
      // Unused slots are zeroed rather than left at whatever the last frame —
      // or the last tile — put there: `uCount` stops the loop, but a uniform
      // buffer nobody wrote is not a promise this code should be making.
      for (var i = members.length; i < kMaxFusedShapes; i++) {
        tile
          ..setFloat(11 + i * 4, 0)
          ..setFloat(12 + i * 4, 0)
          ..setFloat(13 + i * 4, 0)
          ..setFloat(14 + i * 4, 0)
          ..setFloat(11 + kMaxFusedShapes * 4 + i, 0);
      }
      canvas.drawRect(rect, paint);
      if (!shared) {
        releaseGlassShader(tile);
      }
      if (!paint.isAntiAlias) {
        fusedDrawsAliased++;
      }
    }

    if (!paint.isAntiAlias) {
      primeAliasedDraw(canvas);
    }
    if (tiles == null) {
      draw(quad, List<int>.generate(shapes.length, (int i) => i));
    } else {
      for (final GlassFusedTile tile in tiles) {
        draw(tile.rect, tile.shapes);
      }
    }
    shader?.dispose();
  }

  /// Every group currently attached, so [debugGlassFoldCull] can repaint them.
  ///
  /// Maintained unconditionally rather than behind an assert: profile strips
  /// assertions and the benchmark only runs in profile, so a debug-only
  /// registry would leave the switch working nowhere it is used.
  static final Set<RenderGlassGroup> _live = <RenderGlassGroup>{};

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _live.add(this);
    _ledger?.registerCluster(_group);
    _proxy?.addListener(_onProxyPublished);
  }

  @override
  void detach() {
    _live.remove(this);
    _ledger?.unregisterCluster(_group);
    _proxy?.removeListener(_onProxyPublished);
    super.detach();
  }

  @override
  void dispose() {
    _drawLayer.layer = null;
    _live.remove(this);
    _ledger?.unregisterCluster(_group);
    _proxy?.removeListener(_onProxyPublished);
    _group._owner = null;
    super.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('spacing', _spacing, ifNull: 'union'));
    properties.add(IntProperty('members', _group._members.length));
  }
}
