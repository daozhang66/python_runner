// A glass surface, as far as phase A has one: a declared shape in a declared
// place, and the register it belongs to.
//
// **It does not draw glass yet, and that is the schedule rather than an
// oversight.** The budget puts the shader at 9% of the addition over the floor
// and everything upstream of it at 91% (D63), so the shader is deliberately
// last; what has to exist first is the thing that says *where* the glass is,
// because two separate machines need that answer and neither can derive it:
//
//  - the ledger, because the translucency tax follows glass area (D21) with an
//    excess for fragmentation (D26), and those are the only two large levers
//    left — and both are decided when a screen is designed, not when it is
//    rendered;
//  - the proxy, because its capture region has to be a function of the
//    surfaces and of nothing else. Impeller's render target pool is keyed by
//    size (`render_target_cache.cc:69-74`), so a region that changed with the
//    content would miss the pool every time the content moved (D115).
//
// So this registers a rectangle, draws the proxy inside its own shape once a
// [GlassHost] is above it, and paints its child on top of that — in that order,
// because the subtree is not in the proxy and therefore belongs above the
// glass rather than under it.
//
// **What it draws is an identity glass, and that is a control rather than a
// placeholder.** Sample the captured backdrop at the fragment's own place in it
// and output that: if the register's coordinate space, the policy's scale, the
// atlas's map and the recording's clip all line up, the frame with the surface
// is the frame without it, byte for byte. One number for four mechanisms, and
// it is the check the roadmap asks for by name. The optics go on top of it
// later and change only what is sampled where.

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'dart:ui' as ui;

import '../proxy/proxy_atlas.dart';
import '../proxy/proxy_pipeline.dart';
import '../proxy/proxy_walk.dart';
import 'glass_draw_layer.dart';
import 'glass_finish.dart';
import 'glass_group.dart';
import 'glass_host.dart';
import 'glass_ledger.dart';
import 'glass_ripple.dart';
import 'glass_theme.dart';
import 'glass_tier.dart';
import 'glass_travel.dart';

/// Where the flat rungs' fade gradient has its stops.
const List<double> _kFadeStops = <double>[0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1];

/// Outlines every registered surface and prints nothing.
///
/// The register is otherwise invisible — a surface that failed to register and
/// one that registered in the wrong coordinate system look identical on screen,
/// which is the shape of defect that survives longest. Debug builds only,
/// wired the way `debugPaintSizeEnabled` is.
bool debugPaintGlassSurfaces = false;

/// Whether a glass draw asks the engine for antialiasing — `Paint.isAntiAlias`
/// on the single surface's quad and on a group's unsplit quad.
///
/// **Not an antialiasing switch, and that is the point of the arm.** The
/// shader writes its own coverage off the shape's distance, and it is zero half
/// a device pixel outside the shape, so both quads are drawn a device pixel
/// larger than any pixel that coverage can reach (the group's always was, by
/// its blend radius): no edge pixel is decided by the rasterizer, on any
/// backend, with the flag either way. What the flag does on Impeller is choose
/// the draw: `isAntiAlias` is read only by `IsCompatibleWithSDFRendering`
/// (`canvas.cc:2635`), and a compatible paint with a colour source — a
/// `FragmentShader` is one — is drawn as a white SDF mask and the shader
/// separately, joined by `MakeBlend(kSrcIn)` through offscreen snapshots
/// (`canvas.cc:2185-2209`, flutter/flutter#192994). SDFs are always on for
/// macOS and on by default on Windows and Linux, opt-in on iOS, absent on
/// Android.
///
/// **False, because the SDF draw is both dearer and wrong (D200).** On an M3
/// Max twelve surfaces cost 1.355 ms of GPU a frame through it and 0.522 ms
/// directly, and the offscreen shifts the whole interior on a fractional
/// layout: the identity finish differs from the bare backdrop by up to 136
/// code values through the SDF draw and by nothing directly. D191 and D199
/// saw no difference because the `false` never arrived — see
/// [primeAliasedDraw] — so their "the flag changes nothing" compared the SDF
/// draw with itself. A global for the reason [debugGlassFusedSplit] is one;
/// set it before the tree mounts, and read which arm ran off
/// [RenderGlassSurface.opticsDrawsAliased] and
/// [RenderGlassGroup.fusedDrawsAliased], never off the label.
bool debugGlassShaderAntiAlias = debugGlassShaderAntiAliasDefault;

/// What [debugGlassShaderAntiAlias] ships as, for a harness that has to name
/// the arm it did not override — a host that wrote its own constant here would
/// report the old default after the package moved, which is the trap D190 and
/// D199 each fell into once with the split.
const bool debugGlassShaderAntiAliasDefault = false;

/// Makes an `isAntiAlias = false` draw that follows it on [canvas] reach
/// Impeller as `false`.
///
/// Without it the flag is lost wherever it opens a picture, which is where
/// every glass draw is: `DisplayListBuilder` records `SetAntiAlias` only when
/// the value changes (`dl_builder.h:277-281`) and starts from `DlPaint`'s
/// `false`, while Impeller's dispatcher starts every display list, nested ones
/// included, from `impeller::Paint()`, whose `anti_alias` is `true`
/// (`dl_dispatcher.cc:801`, `paint.h:88`). So the draw arrives antialiased and,
/// on an SDF backend, as three offscreen passes (#192994) — D199's "the flag
/// changes nothing" was this.
///
/// The primer must be a draw the builder sees and discards. An empty rect is
/// neither: `Canvas.drawRect` drops an empty fill in Dart before the builder is
/// called (`painting.dart:7929`), which is why D199's `Rect.zero` primer
/// refuted a hypothesis that was true. `BlendMode.dst` over a non-empty rect is
/// recorded as attributes and culled as `kNoEffect` (`dl_builder.cc:2140`), so
/// it costs two attribute ops and draws nothing on any backend (D200).
void primeAliasedDraw(Canvas canvas) => canvas.drawRect(const Rect.fromLTWH(0, 0, 1, 1), _aliasPrimer);

final Paint _aliasPrimer = Paint()..blendMode = BlendMode.dst;

/// A radius larger than any box, which is how a **capsule** is declared.
///
/// The engine scales radii that do not fit — `_RRectLike.scaleRadii`, Skia's own
/// rule — so a uniform radius past the box comes out at half the shorter side,
/// which is a stadium at every size. That is what [GlassButton] and [GlassBar]
/// want and what SS5.3's "almost always a capsule" is about: Apple uses a pill
/// for controls, never a squircle.
///
/// It has to be **declared** rather than derived because a `BorderRadius` is a
/// value with no size in it, and the size only exists after layout. The
/// alternative — a `LayoutBuilder` around every control — puts a build inside
/// the layout phase to learn something the engine already knows.
///
/// ⚠️ Read back through [RenderGlassSurface.shape], which scales it, and not
/// raw: `RSuperellipse.contains` uses the radii **as given**, so an unscaled
/// capsule reads as an *ellipse* — 9425 px² against the 11 214 the engine draws
/// on a 200x60 box, 16% low (D183).
const BorderRadius kGlassCapsule = BorderRadius.all(Radius.circular(1e9));

/// A fade across a glass surface: whole at [begin], gone at [end], a
/// smoothstep between — in the surface's own logical coordinates.
///
/// What a scroll edge is made of (spike 31): Apple's soft edge blurs the
/// content under a bar and lets it go over a few dozen points, so the glass is
/// drawn at a fraction and the content shows through the rest. One `dot`, one
/// clamp and three multiplies per fragment, and an exact `1.0` without it.
///
/// Not drawn by a fused group, whose one draw carries one set of optics: a
/// faded member of a fusing group is drawn whole.
@immutable
class GlassFade {
  const GlassFade({required this.begin, required this.end});

  /// A vertical fade over [extent] logical px: whole at [from], gone [extent]
  /// further down — or further up, for a negative extent.
  factory GlassFade.vertical({required double from, required double extent}) =>
      GlassFade(begin: Offset(0, from), end: Offset(0, from + extent));

  final Offset begin;
  final Offset end;

  /// `(x, y, z)` with `clamp(dot(rel, (x, y)) + z)` the fade's argument, for a
  /// surface of [size] whose centre `rel` is measured from.
  (double, double, double) uniforms(Size size) {
    final Offset axis = end - begin;
    final double length2 = axis.distanceSquared;
    if (length2 <= 0) {
      return (0, 0, 0);
    }
    final Offset dir = axis / length2;
    final Offset centre = size.center(Offset.zero);
    // dot(p_local - begin, dir) with p_local = rel + centre.
    final double z = (centre.dx - begin.dx) * dir.dx + (centre.dy - begin.dy) * dir.dy;
    return (dir.dx, dir.dy, z);
  }

  @override
  bool operator ==(Object other) => other is GlassFade && other.begin == begin && other.end == end;

  @override
  int get hashCode => Object.hash(begin, end);
}

/// Declares a region of the screen as glass.
///
/// Phase A: it declares geometry and paints its child. See the file comment for
/// why that is the order.
///
/// The shape is the engine's own round superellipse — `RSuperellipse`, the
/// shape a Flutter `RoundedRectangleBorder` already lowers to — rather than a
/// rounded rectangle, because that is what the reference material is and
/// because the two differ where it shows: the curvature at the join of the two
/// arcs jumps by 1.6…4.7x on a plain rounded rect and by less on this one
/// (D79), and a bevel's shading carries that jump.
class GlassSurface extends SingleChildRenderObjectWidget {
  const GlassSurface({
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.finish,
    this.presence = 1,
    this.materialize = 1,
    this.labelled = true,
    this.fade,
    this.ripple,
    super.child,
    super.key,
  });

  /// The wave this glass makes when touched, or null to take the theme's
  /// ([GlassThemeData.ripple]), which is none by default. Not drawn while the
  /// platform asks for reduced motion (`MediaQuery.disableAnimationsOf`), nor
  /// by a member of a fusing group, nor on a rung below [GlassTier.full].
  final GlassRipple? ripple;

  /// A fade across the glass, or null for glass that is whole everywhere. See
  /// [GlassFade].
  final GlassFade? fade;

  /// Whether a label is drawn over this glass, so the theme's label floor
  /// ([GlassThemeData.minLabelContrast]) applies to it.
  ///
  /// False for glass that carries no text — a control's drop, a lens — which
  /// then keeps its finish as named. The floor dims the glass for the label's
  /// sake; a clear drop dimmed for a label it does not have turned grey over
  /// the bar it is meant to show, its margins above and below the bar dark
  /// instead of the backdrop behind them.
  final bool labelled;

  /// How far the glass has materialized, 0 to 1: the finish arriving rather
  /// than the shape — blur first, tint last, as Apple's `.materialize` does.
  /// See [GlassFinish.materializing]. Animate it, or [presence], or both.
  final double materialize;

  /// How much of the surface is there, 0 to 1. Animate it to make glass
  /// appear or leave; see [RenderGlassSurface.presence] for why it is not a
  /// size.
  final double presence;

  /// The corner radii, in logical pixels.
  ///
  /// A default rather than a required argument because every measured panel in
  /// this project has one uniform radius and 24 is the middle of the range the
  /// reference was read at.
  final BorderRadius borderRadius;

  /// The optics. Null takes the host's, which is what a screen with one look
  /// wants; naming one here is for the surface that differs from its
  /// neighbours.
  final GlassFinish? finish;

  @override
  RenderGlassSurface createRenderObject(BuildContext context) =>
      RenderGlassSurface(borderRadius, GlassScope.maybeOf(context))
        ..proxy = GlassProxyScope.maybeOf(context)
        ..group = GlassGroupScope.maybeOf(context)
        ..travel = GlassTravelScope.maybeOf(context)
        ..theme = GlassTheme.of(context)
        ..finish = finish
        ..presence = presence
        ..materialize = materialize
        ..labelled = labelled
        ..fade = fade
        ..ripple = ripple
        ..reduceMotion = _reduceMotionOf(context)
        ..devicePixelRatio = _dprOf(context);

  static bool _reduceMotionOf(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static double _dprOf(BuildContext context) =>
      MediaQuery.maybeDevicePixelRatioOf(context) ?? View.maybeOf(context)?.devicePixelRatio ?? 1;

  @override
  void updateRenderObject(BuildContext context, RenderGlassSurface renderObject) {
    renderObject
      ..ledger = GlassScope.maybeOf(context)
      ..proxy = GlassProxyScope.maybeOf(context)
      ..group = GlassGroupScope.maybeOf(context)
      ..travel = GlassTravelScope.maybeOf(context)
      ..theme = GlassTheme.of(context)
      ..finish = finish
      ..presence = presence
      ..materialize = materialize
      ..labelled = labelled
      ..fade = fade
      ..ripple = ripple
      ..reduceMotion = _reduceMotionOf(context)
      ..devicePixelRatio = _dprOf(context)
      ..borderRadius = borderRadius;
  }
}

/// The render object behind [GlassSurface].
class RenderGlassSurface extends RenderProxyBox implements GlassSurfaceGeometry {
  RenderGlassSurface(this._borderRadius, this._ledger);

  /// A surface repaints on every published proxy, and nothing else should.
  ///
  /// [proxy] is listened to with `markNeedsPaint`, and `markNeedsPaint` walks
  /// up to the nearest repaint boundary — which, without this, is the **host's**
  /// own. The default declaration publishes a proxy every frame, so every frame
  /// repainted the whole screen under the glass: measured at 8 framework paints
  /// of a static sibling over 7 frames, where a screen that changes nothing
  /// should paint once.
  ///
  /// D145 read the same shape off the device counters and wrote it up as a fact
  /// about this class ("a `GlassSurface` is a repaint boundary, so an unchanging
  /// proxy does not dirty it"). The counters were right and the mechanism was
  /// not: a held arm records nothing, so there is no publish to dirty anything,
  /// and the two explanations are indistinguishable from that report. They part
  /// company on the arm that *does* publish, which is every shipping frame of
  /// the default declaration.
  ///
  /// It is also what makes the host's repaint observation possible at all: an
  /// observer above a surface that dirties its ancestors would be watching its
  /// own pipeline publish.
  @override
  bool get isRepaintBoundary => true;

  // Reachable because this is the class that owns it: `RenderObject.layer` is
  // `@protected`, and `debugLayer` returns null in profile, which is where the
  // package runs.
  @override
  Layer? get compositedLayer => layer;

  GlassLedger? _ledger;
  set ledger(GlassLedger? value) {
    if (identical(value, _ledger)) {
      return;
    }
    _ledger?.unregister(this);
    _ledger = value;
    if (attached) {
      _ledger?.register(this);
    }
  }

  BorderRadius _borderRadius;
  set borderRadius(BorderRadius value) {
    if (value == _borderRadius) {
      return;
    }
    _borderRadius = value;
    markNeedsPaint();
  }

  BorderRadius get borderRadius => _borderRadius;

  GlassFinish? _finish;
  set finish(GlassFinish? value) {
    if (value == _finish) {
      return;
    }
    _finish = value;
    _legibilityMemo = null;
    markNeedsPaint();
  }

  /// Needed by the shader and unavailable to a `RenderObject`: the outline is
  /// 0.79 logical px wide, which is **narrower than a device pixel** on every
  /// real screen, so what it draws is a coverage fraction — and a coverage
  /// fraction has to know how big a pixel is. `fwidth` would do it and is not
  /// available: SkSL has no derivatives at all and refuses at load time, on the
  /// user's device (B11, D60).
  double _devicePixelRatio = 1;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) {
      return;
    }
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  GlassThemeData _theme = const GlassThemeData();
  set theme(GlassThemeData value) {
    if (value == _theme) {
      return;
    }
    _theme = value;
    _legibilityMemo = null;
    _rippleChanged();
    markNeedsPaint();
  }

  /// The finish in force: this surface's, else the theme's — after the dim the
  /// theme's label floor asks for, if any ([GlassThemeData.minLabelContrast]).
  GlassFinish get effectiveFinish => _materialize >= 1 ? _legible.finish : _legible.finish.materializing(_materialize);

  /// How far this glass has materialized; see [GlassSurface.materialize].
  ///
  /// Applied after the theme's legibility dim, so a materializing glass
  /// arrives at exactly the finish it will settle in. A member of a fusing
  /// group draws the group's finish and does not materialize on its own.
  double get materialize => _materialize;
  double _materialize = 1;
  set materialize(double value) {
    final double clamped = value.clamp(0.0, 1.0);
    if (clamped == _materialize) {
      return;
    }
    _materialize = clamped;
    markNeedsPaint();
  }

  /// The opaque outline the increase-contrast switch asks for, or null for the
  /// calibrated additive one.
  Color? get effectiveHighContrastRim => _theme.highContrast ? _legible.rim : null;

  /// [GlassThemeData.legibility] for this theme and finish, kept until either
  /// changes: it runs in `paint`, and with a label floor it bisects.
  GlassLegibility get _legible => _legibilityMemo ??= _theme.legibility(_finish, _labelled);
  GlassLegibility? _legibilityMemo;

  /// See [GlassSurface.fade].
  GlassFade? get fade => _fade;
  GlassFade? _fade;
  set fade(GlassFade? value) {
    if (value == _fade) {
      return;
    }
    _fade = value;
    markNeedsPaint();
  }

  /// See [GlassSurface.ripple]: this surface's own declaration.
  GlassRipple? get ripple => _ripple;
  GlassRipple? _ripple;
  set ripple(GlassRipple? value) {
    if (value == _ripple) {
      return;
    }
    _ripple = value;
    _rippleChanged();
  }

  /// Whether the platform asked for reduced motion; no wave while it does.
  bool get reduceMotion => _reduceMotion;
  bool _reduceMotion = false;
  set reduceMotion(bool value) {
    if (value == _reduceMotion) {
      return;
    }
    _reduceMotion = value;
    _rippleChanged();
  }

  /// The wave in force: this surface's, else the theme's, and none under
  /// reduced motion.
  GlassRipple? get effectiveRipple => _reduceMotion ? null : (_ripple ?? _theme.ripple);

  /// The waves alive on this surface, or null when it makes none.
  GlassRippleField? get rippleField => _rippleField;
  GlassRippleField? _rippleField;
  int? _rippleCallback;

  void _rippleChanged() {
    final GlassRipple? ripple = effectiveRipple;
    if (ripple == null) {
      if (_rippleField != null) {
        _rippleField = null;
        _stopRipple();
        _drawLayer.layer?.invalidate();
      }
      return;
    }
    (_rippleField ??= GlassRippleField(ripple)).ripple = ripple;
    if (attached) {
      _proxy?.wantRippleProgram();
    }
  }

  void _stopRipple() {
    final int? id = _rippleCallback;
    if (id != null) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(id);
      _rippleCallback = null;
    }
  }

  /// Whether a touch here can be drawn as a wave this frame: the surface draws
  /// its own optics.
  bool get _ripples => _rippleField != null && !fusedByGroup && _materialize > 0 && effectiveTier.readsBackdrop;

  /// Frames a wave advanced, and draws made through the ripple program.
  ///
  /// The second is the trace that the wave reached the screen; the first
  /// without it is a surface whose program never arrived. Neither touches
  /// [paintsWithOptics]: a wave's frame paints nothing — it invalidates the
  /// draw, which re-records at composite time.
  int rippleTicks = 0;
  int rippleDraws = 0;

  /// Translucent where it ripples: the glass hears a touch inside its shape
  /// and lets whatever is behind it hear it too, as `Listener` does. With no
  /// ripple declared, hit testing is exactly a proxy box's.
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final bool hit = super.hitTest(result, position: position);
    if (!hit && _rippleField != null && size.contains(position) && shape.contains(position)) {
      result.add(BoxHitTestEntry(this, position));
    }
    return hit;
  }

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    final GlassRippleField? field = _rippleField;
    if (field == null) {
      return;
    }
    // Through the transform as it is now, not `localPosition`: that one is
    // the hit test's, taken at the down, and a glass that moves under the
    // finger — a slider's drop — would place the wave by where it was.
    final Offset relative = globalToLocal(event.position) - size.center(Offset.zero);
    if (event is PointerDownEvent) {
      if (!_ripples) {
        return;
      }
      field.down(event.pointer, relative);
    } else if (event is PointerMoveEvent) {
      if (!field.move(event.pointer, relative)) {
        return;
      }
    } else if (event is PointerUpEvent) {
      field.up(event.pointer, relative);
    } else if (event is PointerCancelEvent) {
      field.up(event.pointer);
    } else {
      return;
    }
    _scheduleRipple();
  }

  void _scheduleRipple() {
    _rippleCallback ??= SchedulerBinding.instance.scheduleFrameCallback(_rippleTick);
  }

  /// Advances the waves to this frame and invalidates the draw — no paint, so
  /// neither the content nor anything the layer watch reads is touched, and
  /// the host captures nothing for it.
  void _rippleTick(Duration now) {
    _rippleCallback = null;
    final GlassRippleField? field = _rippleField;
    if (field == null || !attached || !hasSize) {
      return;
    }
    final bool changing = field.advance(now, extent: size.longestSide);
    rippleTicks++;
    _drawLayer.layer?.invalidate();
    if (changing) {
      _scheduleRipple();
    }
  }

  /// See [GlassSurface.labelled].
  bool get labelled => _labelled;
  bool _labelled = true;
  set labelled(bool value) {
    if (value == _labelled) {
      return;
    }
    _labelled = value;
    _legibilityMemo = null;
    markNeedsPaint();
  }

  /// The rung in force.
  ///
  /// Themed only, with no per-surface override, because scoping configuration
  /// by position is what the inherited level is for — a toolbar that stays
  /// glass over a list that does not is an inner [GlassTheme]. See that class
  /// for why the same argument does not retroactively delete [finish].
  GlassTier get effectiveTier => _theme.tier.tier;

  /// Whether this surface's subtree is kept out of the proxy.
  ///
  /// True exactly when it draws the proxy, and that identity is the rule rather
  /// than a coincidence: the exclusion is the **self-capture** rule, and a
  /// surface inside its own proxy is last frame's proxy inside this frame's.
  /// A surface below the top rung draws no proxy, so it is ordinary content —
  /// it belongs in the backdrop its neighbours read, and a change inside it has
  /// to invalidate theirs.
  ///
  /// Getting this wrong is invisible on a screen where every surface wears the
  /// same rung, which is every screen this package had until the ladder
  /// existed. It shows up on a mixed one, twice: a full panel would read a
  /// backdrop with the cheap panel next to it missing, and the layer watch
  /// would hold that backdrop over a cheap panel that had changed.
  @override
  bool get excludedFromProxy => effectiveTier.readsBackdrop;

  /// Repaints for a new proxy — and only if this surface is going to read it.
  ///
  /// Not `markNeedsPaint` itself, which is what it was until the ladder: a
  /// cheap surface *is* in the proxy now, so a cheap surface that repainted on
  /// every publish would be repainting the content the next capture reads,
  /// which the host's repaint observer reports as a change, which records
  /// another capture. A publish loop with the holding declaration defeated, on
  /// the one screen shape the ladder exists to make cheaper.
  void _onProxyPublished() {
    if (effectiveTier.readsBackdrop) {
      _repaintingForProxy = true;
      markNeedsPaint();
      _repaintingForProxy = false;
    }
  }

  /// Whether what this surface holds has to be painted again — set by every
  /// `markNeedsPaint` except the one a new proxy asks for.
  ///
  /// **A publish repaints the glass, and it must not repaint the content.**
  /// The content of a glass that other glass stands on is in that glass's
  /// capture, and the layer watch reads it there; a publish that re-recorded
  /// a label re-minted its picture, the watch called that a change, the host
  /// recorded and published again — every frame of a still screen, 30 records
  /// in 30 frames with a `Text` in a card under a lifted bar, 0 with the same
  /// `Text` behind a `RepaintBoundary`. It is D177's rule — a node that
  /// repaints on every publish while inside the proxy feeds the next capture
  /// its own repaint — met in the surface itself, and it had been there since
  /// levels (D214): its fixtures put every label behind a boundary.
  bool _contentDirty = true;
  bool _repaintingForProxy = false;

  @override
  void markNeedsPaint() {
    if (!_repaintingForProxy) {
      _contentDirty = true;
    }
    super.markNeedsPaint();
  }

  /// The layer the content was last painted into, re-added untouched when only
  /// the proxy changed.
  final LayerHandle<OffsetLayer> _contentLayer = LayerHandle<OffsetLayer>();
  Offset? _contentOffset;

  /// Paints the child — into the retained [_contentLayer] when it has to be
  /// painted, by re-adding that layer when it does not.
  void _paintContent(PaintingContext context, Offset offset) {
    final RenderBox? child = this.child;
    if (child == null) {
      return;
    }
    // A capture is one picture and takes no layers, and it is painted afresh
    // every time anyway. At presence zero (classic UI), use normal child
    // painting too: Material route snapshots can otherwise leave this extra
    // retained layer holding an ink frame after its animation has completed.
    // There is no glass-only repaint to optimize while the surface is absent.
    if (context is ProxyWalkContext || _presence <= 0) {
      context.paintChild(child, offset);
      return;
    }
    final OffsetLayer? kept = _contentLayer.layer;
    if (kept != null && !_contentDirty && _contentOffset == offset) {
      context.addLayer(kept);
      return;
    }
    final OffsetLayer layer = _contentLayer.layer ??= OffsetLayer();
    context.pushLayer(layer, (PaintingContext context, Offset offset) => context.paintChild(child, offset), offset);
    _contentOffset = offset;
    _contentDirty = false;
  }

  /// The finish this surface named for itself, or null if it took the host's.
  ///
  /// Read by the group above, which cannot honour it: one fused draw carries one
  /// set of optics, so a member with its own finish is a declaration the picture
  /// cannot express.
  GlassFinish? get declaredFinish => _finish;

  /// Where this surface is, in global logical pixels.
  ///
  /// `getTransformTo(null)` rather than the paint offset: the offset is a
  /// position inside whatever layer happens to enclose the surface, so a panel
  /// inside a scrolled viewport, a `Transform`, or any subtree with a layer of
  /// its own would report a place that is not on the screen. The register is
  /// read by the capture, which works in scene coordinates, so this has to be
  /// the same space.
  ///
  /// A rotated surface reports its axis-aligned bounding box, which is larger
  /// than the glass. Named rather than corrected: no cost measurement covers a
  /// rotated surface, so a smaller number here would be a guess dressed as
  /// precision.
  Rect get globalRect => MatrixUtils.transformRect(getTransformTo(null), Offset.zero & size);

  /// The shape this surface would draw, in its own coordinates.
  RSuperellipse get shape => shapeAt(Offset.zero);

  /// The same shape, placed at [offset].
  ///
  /// **`scaleRadii` is the whole of it, and it is the engine's rule rather than
  /// ours** (`_RRectLike.scaleRadii`, which is Skia's). Every draw scales radii
  /// that do not fit, so until something declared one this was invisible — and
  /// `RSuperellipse.contains` does **not** scale, which is why the register's
  /// own control could not see it: `contains` and `drawRSuperellipse` disagree
  /// for an oversized radius, the first reading an ellipse and the second
  /// drawing a stadium. On a 200x60 capsule that is 9425 px² of declared glass
  /// against 11 214 drawn — the area law's denominator 16% light (D183). Scaled
  /// here, once, so that the shader, the canvas, the clip and the register are
  /// all reading the same shape.
  RSuperellipse shapeAt(Offset offset) => _borderRadius.toRSuperellipse(offset & size).scaleRadii();

  /// The corner radius the glass is actually drawn with, logical px.
  ///
  /// One number rather than four, because that is what both shaders take — a
  /// fused group's array carries one radius per shape.
  ///
  /// Read by the group above to fill `uRadius`, and by the union's solver: the
  /// distance between two rounded boxes is not the distance between their
  /// boxes, and the difference is exactly this radius.
  double get effectiveRadius => shape.tlRadiusX;

  /// Where this surface is, read now.
  ///
  /// Null before layout and while detached. `hasSize` rather than a try: a
  /// `RenderBox` that has not been laid out throws from `size`, and a register
  /// read during a build — which is a legitimate thing for a debug overlay to
  /// do — would take the app down.
  @override
  GlassSurfaceRecord? readGeometry() {
    if (!attached || !hasSize) {
      return null;
    }
    final Rect rect = globalRect;
    // Flutter keeps inactive PageView children attached but their sliver
    // transform can be singular. Such a surface has no drawable global box;
    // passing NaN to atlas sizing aborts the capture after a theme switch.
    // It re-enters the atlas naturally as soon as its page is visible again.
    if (!rect.isFinite || rect.isEmpty) {
      return null;
    }
    final Rect? travelRect = travel?.globalRect;
    return GlassSurfaceRecord(
      rect: rect,
      shapeArea: GlassLedger.shapeAreaOf(shape),
      tier: effectiveTier,
      travel: travelRect != null && travelRect.isFinite && !travelRect.isEmpty ? travelRect : null,
      finish: fusedByGroup ? (_group?.finish ?? effectiveFinish) : effectiveFinish,
      presence: _presence,
      materialize: fusedByGroup ? 1 : _materialize,
    );
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
      if (_rippleField != null) {
        _proxy?.wantRippleProgram();
      }
    }
    markNeedsPaint();
  }

  /// The blend group this surface belongs to, if any.
  ///
  /// A surface in a *fusing* group draws no glass of its own: the bridge
  /// between two members belongs to neither of them, so the group draws the
  /// whole silhouette in one pass. It still registers its geometry — the atlas
  /// and the ledger both need it, and the group reads it back to place a shape.
  /// The region this surface declared it may move within, if any. Read by
  /// [readGeometry] only: the paint maps the surface's current place into its
  /// slot whatever was captured, which is what makes the declaration free.
  GlassTravelRegion? travel;

  /// How much of this surface is there, from 0 (none) to 1 (all of it).
  ///
  /// **An offset of the distance field, not a scale of the box**, and the
  /// difference is the whole feature. Growing a box from zero pops inside a
  /// group: a point is already a shape to `smin`, so a member of size zero
  /// pulls a bud of up to `k / 4` out of every neighbour within `k` on the
  /// frame it appears. Offsetting the field by `L` instead —
  /// `sdRoundedBox(p, b − L, r − L)` is `sdRoundedBox(p, b, r) + L` exactly,
  /// because `q` does not move — has a limit at which the member provably
  /// changes nothing: with `L = inradius + 2k` the member is at least `2k`
  /// away wherever the rest of the field is within `k` of the silhouette, so
  /// `h` is exactly zero there. On the way up the member's field reaches the
  /// neighbours before it reaches zero itself, so what appears first is a bud
  /// growing *out of the neighbour towards it* — the morph — and then the
  /// shape. Alone, it erodes towards its own medial axis.
  ///
  /// Read at paint and, in a group, at composite: nothing is captured for it,
  /// and the capture keeps the full box, so animating it costs no retake.
  double get presence => _presence;
  double _presence = 1;
  set presence(double value) {
    final double clamped = value.clamp(0.0, 1.0);
    if (clamped == _presence) {
      return;
    }
    _presence = clamped;
    markNeedsPaint();
  }

  /// How far the field is pushed out at the current [presence], in logical
  /// pixels, for a fold of blend radius [blend] — zero at full presence.
  ///
  /// The extra logical pixel takes a lone surface's coverage, which is
  /// `clamp(0.5 − d / pixel)`, to zero at presence zero on any screen of dpr 1
  /// or more.
  double presenceInset({double blend = 0}) {
    if (_presence >= 1 || !hasSize) {
      return 0;
    }
    final double absent = 1 - _presence;
    return absent * absent * (size.shortestSide / 2 + 2 * blend + 1);
  }

  GlassBlendGroup? _group;
  set group(GlassBlendGroup? value) {
    if (identical(value, _group)) {
      return;
    }
    _group?.leave(this);
    _group = value;
    if (attached) {
      _group?.join(this);
    }
    markNeedsPaint();
  }

  /// Whether the group above is drawing this surface's glass this frame.
  bool get fusedByGroup => _group?.fuses ?? false;

  /// Frames this surface painted with no proxy to sample.
  ///
  /// Never zero on a live screen — the first frame of any host has nothing to
  /// show yet — and it must stop growing. A surface that never gets a proxy and
  /// one that gets a stale proxy look identical on a screenshot, so this is the
  /// counter that separates them.
  ///
  /// **Only ever counted at [GlassTier.full].** A cheap surface has no proxy on
  /// purpose, and letting it land here would make a working screen indexed
  /// against the same counter as a broken one — which is the shape of defect
  /// this file's counters exist to prevent, not to add.
  int paintsWithoutProxy = 0;

  /// Frames this surface painted the proxy.
  int paintsWithProxy = 0;

  /// Frames this surface left its glass to the group above it.
  ///
  /// The counter that separates "the group drew it" from "nobody drew it": on a
  /// still screenshot a fused member and a surface that silently failed to paint
  /// look the same, and one of them is a bug.
  int paintsDeferredToGroup = 0;

  /// Frames it painted the proxy *through the optics*.
  ///
  /// Separate from [paintsWithProxy] because the shader arrives asynchronously
  /// — `FragmentProgram.fromAsset` is a future — and a surface drawing the
  /// unrefracted proxy looks like working glass on a still screenshot. The
  /// difference between the two counters is how many frames shipped without
  /// optics.
  int paintsWithOptics = 0;

  /// Frames it painted the cheap rung, and frames it painted the opaque one.
  ///
  /// Two counters rather than one, because the rung can differ between two
  /// surfaces on the same screen — nested themes are how a screen mixes them —
  /// so "which rung ran" cannot be read off the host's configuration.
  int paintsCheap = 0;
  int paintsOpaque = 0;

  /// Of [paintsWithOptics], the draws made with `isAntiAlias` false.
  ///
  /// What [debugGlassShaderAntiAlias] actually did, counted at the draw: the
  /// two arms differ in no uniform, so a retained layer painted under the other
  /// setting would otherwise be reported as this one.
  int opticsDrawsAliased = 0;

  /// Draws of this glass *into a capture* — the proxy of a glass that stands
  /// on this one — rather than onto the screen. Kept off every counter above,
  /// which count what the screen got.
  int paintsIntoProxy = 0;

  /// Zeroes the counters above.
  ///
  /// For a benchmark that measures the same mounted scene several times: the
  /// harness keeps one rig across repeats and remounts the tree for each, so
  /// without this the paint totals span every repeat while the host's
  /// publish counter, read off a handle that is rebuilt with the tree, spans
  /// one. The ratio between them is the only way to read either.
  void resetCounters() {
    paintsWithoutProxy = 0;
    paintsWithProxy = 0;
    paintsWithOptics = 0;
    paintsDeferredToGroup = 0;
    paintsCheap = 0;
    paintsOpaque = 0;
    opticsDrawsAliased = 0;
    paintsIntoProxy = 0;
    rippleTicks = 0;
    rippleDraws = 0;
  }

  /// Displaces where the proxy is sampled from, without moving the surface.
  ///
  /// **The negative control, and it exists for the same reason the atlas has
  /// one** (`AtlasLayout.record`'s `jitter`): an identity glass is invisible,
  /// and so is a surface that draws nothing at all. Every arm that asserts the
  /// invisibility needs a twin that samples the wrong place and must therefore
  /// be visible, or it is checking that two blank frames agree. Moving the
  /// panel does not do it — the identity is invisible wherever it is — so the
  /// displacement has to be of the *sample*, which nothing else in the package
  /// can express.
  ///
  /// Debug-only, and read through an `assert` so it cannot cost a profile
  /// build a branch.
  Offset debugSampleShift = Offset.zero;

  /// Glass first, then whatever the surface holds.
  ///
  /// The order is the same claim `skipGlassSurfaces` makes when it drops the
  /// **whole** subtree out of the proxy — what sits on a nav bar is on top of
  /// the glass, not behind it — and it was the other way round for two steps,
  /// invisibly: every arm of every earlier test puts an *empty* panel over the
  /// scene, and an empty panel's paint order cannot be observed. A panel with a
  /// title in it drew the proxy over its own title.
  @override
  void paint(PaintingContext context, Offset offset) {
    if (fusedByGroup) {
      if (context is! ProxyWalkContext) {
        paintsDeferredToGroup++;
      }
    } else if (_materialize <= 0) {
      // Not there yet: nothing drawn, and the host captures nothing for it.
    } else if (effectiveTier.readsBackdrop) {
      _paintProxy(context, offset);
    } else {
      _paintFlat(context.canvas, offset);
    }
    _paintContent(context, offset);
    assert(() {
      if (debugPaintGlassSurfaces) {
        context.canvas.drawRSuperellipse(
          shapeAt(offset),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xFF00E5FF),
        );
      }
      return true;
    }());
  }

  /// Hands the draw to a [GlassDrawLayer]: through the optics once the program
  /// has arrived, and as the plain backdrop before that.
  void _paintProxy(PaintingContext context, Offset offset) {
    if (context is ProxyWalkContext) {
      _paintIntoProxy(context.canvas, offset);
      return;
    }
    final GlassProxyFrame? frame = _proxy?.frameFor(this);
    final AtlasSlot? slot = frame?.slotForKey(this);
    if (frame == null || slot == null) {
      paintsWithoutProxy++;
      // A newly visible surface has no atlas slot until the post-frame capture.
      // Keep its tint and outline present on that first frame instead of
      // briefly exposing bare page content through cards and button fills.
      _paintFlat(context.canvas, offset, countPaint: false);
      return;
    }
    paintsWithProxy++;
    final ui.FragmentProgram? program = _proxy?.program;
    if (program != null) {
      paintsWithOptics++;
      if (!debugGlassShaderAntiAlias) {
        opticsDrawsAliased++;
      }
    }
    // Into a layer that records at composite time, because the draw depends on
    // where this surface is on the screen and a moved repaint boundary is not
    // painted (see `glass_draw_layer.dart`). Everything else is read here.
    final GlassDrawLayer layer = _drawLayer.layer ??= GlassDrawLayer();
    layer
      ..invalidate()
      ..probe = _drawProbe
      ..painter = (Canvas canvas) {
        // A frame the pipeline has since replaced is disposed: drawing it
        // would sample a released texture. Only reachable by compositing a
        // moved surface without painting it first, which `drawFrame` never
        // does — it paints the publish before it composites.
        if (!identical(_proxy?.frameFor(this), frame)) {
          return;
        }
        if (program != null) {
          _paintOptics(canvas, offset, frame, slot, program, ripple: true);
        } else {
          _paintImage(canvas, offset, frame, slot);
        }
      };
    context.addLayer(layer);
  }

  final LayerHandle<GlassDrawLayer> _drawLayer = LayerHandle<GlassDrawLayer>();

  /// The layer this surface's own glass is drawn into, or null before it has
  /// drawn any. Read by the host's layer watch when glass stands on this one:
  /// then the surface's *subtree* is in a proxy — the upper level's — and only
  /// the draw, which every publish replaces, is to be ignored.
  @override
  Layer? get drawLayer => _drawLayer.layer;

  /// Draws this glass straight onto the canvas of a capture that is recording
  /// the level above it (glass on glass: a lens on a tab bar, a drop on a
  /// card).
  ///
  /// Straight onto the canvas because a capture is one picture
  /// (`ProxyWalkContext` refuses layers), and synchronously because the walk
  /// is the live tree at the moment of the capture — the composite-time
  /// recording [GlassDrawLayer] exists for is about a boundary that moved
  /// *without* being painted, and the walk paints everything it visits. The
  /// frame is the one this surface reads on screen, already published for this
  /// round: the host records the levels bottom up.
  void _paintIntoProxy(Canvas canvas, Offset offset) {
    final GlassProxyFrame? frame = _proxy?.frameFor(this);
    final AtlasSlot? slot = frame?.slotForKey(this);
    if (frame == null || slot == null) {
      _paintFlat(canvas, offset, countPaint: false);
      return;
    }
    paintsIntoProxy++;
    final ui.FragmentProgram? program = _proxy?.program;
    if (program != null) {
      _paintOptics(canvas, offset, frame, slot, program);
    } else {
      _paintImage(canvas, offset, frame, slot);
    }
  }

  /// Draws recorded at composite time, and how many of those because the glass
  /// had moved since it was painted — the trace of `GlassDrawLayer`, without
  /// which a moving glass that happened to be repainted anyway would pass every
  /// pixel arm.
  int get drawRecords => _drawLayer.layer?.records ?? 0;
  int get drawRecordsOnMove => _drawLayer.layer?.recordsOnMove ?? 0;

  List<Object?> _drawProbe() {
    var shift = Offset.zero;
    assert(() {
      shift = debugSampleShift;
      return true;
    }());
    return <Object?>[if (attached && hasSize) globalRect.topLeft, shift];
  }

  /// Draws the captured backdrop inside this surface's shape, unrefracted — what
  /// a surface draws before its program has arrived.
  ///
  /// `drawImageRect` from the slot's own region rather than a shader, because
  /// there is no shader yet and because this is the identity: the source rect
  /// is exactly where this surface's box lands in the atlas, so a correct
  /// pipeline reproduces the screen and an incorrect one shows a piece of
  /// somewhere else.
  ///
  /// Clipped to the shape rather than filled with it: a rounded panel that drew
  /// its whole rect would differ from the screen in the corners and the
  /// invisibility control would fail there and nowhere else, which is the
  /// hardest place to read a diff.
  void _paintImage(Canvas canvas, Offset offset, GlassProxyFrame frame, AtlasSlot slot) {
    final double inset = presenceInset();
    if (inset >= size.shortestSide / 2) {
      return;
    }
    // The flat finish already supports the fade mask while the shader loads.
    if (_fade != null) {
      _paintFlat(canvas, offset, countPaint: false);
      return;
    }
    final Rect box = offset & size;
    var sampled = globalRect;
    assert(() {
      sampled = sampled.shift(debugSampleShift);
      return true;
    }());
    final Offset topLeft = slot.toAtlas(sampled.topLeft);
    final Offset bottomRight = slot.toAtlas(sampled.bottomRight);
    canvas
      ..save()
      ..clipRSuperellipse(inset > 0 ? shapeAt(offset).deflate(inset) : shapeAt(offset))
      ..drawImageRect(
        frame.image,
        Rect.fromPoints(topLeft, bottomRight),
        box,
        // `low`, and both halves of that are measured. Not the default, which
        // is nearest: at a divisor the proxy is magnified, and nearest there is
        // a different picture rather than a slightly worse one — the defect
        // that killed the precedents' path (D1) and that `setImageSampler`
        // still defaults to. And not `high`, which is **not the identity even
        // at 1:1**: Skia's cubic is Mitchell with B = 1/3, whose kernel at zero
        // phase is (1/18, 8/9, 1/18) rather than a delta, so a proxy drawn back
        // over its own pixels comes out blurred — measured here at 8528 pixels
        // of the surface differing by up to 16 code values, on an arm whose
        // whole point is that the difference is zero.
        Paint()..filterQuality = FilterQuality.low,
      )
      ..restore();
    // The unrefracted atlas alone has no material tint or outline. Preserve
    // both until the shader arrives, including captures for nested controls.
    _paintFlat(canvas, offset, countPaint: false);
  }

  /// Draws a rung that reads nothing: the same shape, the same rim, and the
  /// finish's own tint laid straight over whatever is behind.
  ///
  /// **No new constants, and phase D is why rather than an excuse.** All three
  /// rungs are one affine law, `mix(·, tint, a)`, over three arguments: the
  /// blurred backdrop, the backdrop, and — for [GlassTier.opaque] — the
  /// backdrop's declared mean (D178). So the cheap rung draws the finish the
  /// screen already declared, with the two things the proxy paid for removed,
  /// and its level is the 0.307 `.regular` itself was measured to transmit
  /// (D66, D70).
  ///
  /// That it needs no correction of its own is **measured, not assumed**: the
  /// least-squares cheap rung — the one that trades transmission for the detail
  /// the blur removes — differs from the declared one by 1.7 code values at
  /// sigma 2.6 and scores no better in ΔE (0.31 against 0.24). At sigma 8 the
  /// same correction is worth 16 code values and 12%, which is where the
  /// roadmap's "one pair of constants will not do for both themes" came from:
  /// it was written when `frosted` was the working point, and S4 moved it
  /// (D179).
  ///
  /// The rim is a stroke straddling the edge rather than the shader's inward
  /// coverage ramp, and it is additive because the rim *is* additive: 50.2 code
  /// values of neutral white, fitted across seven rims of two Apple materials,
  /// against a mix toward a colour that is 4.7x worse (D86–D88). At 0.79
  /// logical px it is narrower than a device pixel on every real screen, so
  /// what lands is a coverage fraction either way.
  void _paintFlat(Canvas canvas, Offset offset, {bool countPaint = true}) {
    final GlassTier tier = effectiveTier;
    if (countPaint) {
      if (tier == GlassTier.opaque) {
        paintsOpaque++;
      } else {
        paintsCheap++;
      }
    }
    final GlassFinish finish = effectiveFinish;
    final double inset = presenceInset();
    if (inset >= size.shortestSide / 2) {
      return;
    }
    final RSuperellipse shape = inset > 0 ? shapeAt(offset).deflate(inset) : shapeAt(offset);
    final Color? backdrop = _theme.backdrop;
    final Color fill = tier == GlassTier.opaque
        ? (backdrop == null ? finish.tint.withValues(alpha: 1) : finish.opaqueFillOver(backdrop))
        : finish.tint;
    final ui.Shader? fadeMask = _fadeShader(offset);
    if (fill.a > 0) {
      canvas.drawRSuperellipse(shape, _faded(Paint()..color = fill, fadeMask, fill));
    }
    final Color? contrastRim = effectiveHighContrastRim;
    if (contrastRim != null) {
      // Laid on rather than added, and inside the edge like the shader's band:
      // the switch asks for a line that stands out against the level, and an
      // addition cannot do that over a light one (D203).
      canvas.drawRSuperellipse(
        shape.deflate(kHighContrastRimWidthLogical / 2),
        _faded(
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = kHighContrastRimWidthLogical
            ..color = contrastRim,
          fadeMask,
          contrastRim,
        ),
      );
    } else if (finish.rim.a > 0) {
      canvas.drawRSuperellipse(
        shape.deflate(kRimWidthLogical / 2),
        _faded(
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = kRimWidthLogical
            ..blendMode = BlendMode.plus
            ..color = finish.rim,
          fadeMask,
          finish.rim,
        ),
      );
    }
    // Reported **after** the drawing, and once per surface, both on purpose: an
    // assert thrown from `paint` aborts the rest of it, so a complaint raised
    // where the decision is taken would replace the fallback panel with no panel
    // at all — and a debug build would then disagree with release about what the
    // rung even draws. Once, because paint runs every frame.
    assert(() {
      if (tier == GlassTier.opaque && backdrop == null && !_warnedUndeclaredOpaque) {
        _warnedUndeclaredOpaque = true;
        throw FlutterError(
          'GlassTier.opaque with no GlassThemeData.backdrop declared.\n'
          'The rung transmits none of what is behind it, so the level it stands '
          'in for is the backdrop\'s mean — and a surface that reads no backdrop '
          'has no way to measure one. Without it the fill is the finish tint '
          'itself, which is the colour the material lays on rather than the level '
          'it shows: 29 of 255 for GlassFinish.regularDark, against the 69 the glass '
          'shows over a mid-grey screen. Over a light screen that is 23.3 ΔE, '
          'two thirds of the distance between Apple .regular and .clear (D179).\n'
          'Declare it on GlassHost or GlassTheme — it is the screen background '
          'colour the application already keeps.',
        );
      }
      return true;
    }());
  }

  /// The rungs that read nothing fade the same way the shader does: a linear
  /// gradient whose stops follow `1 - smoothstep`, in [offset]'s space.
  ui.Shader? _fadeShader(Offset offset) {
    final GlassFade? fade = _fade;
    if (fade == null) {
      return null;
    }
    return ui.Gradient.linear(
      offset + fade.begin,
      offset + fade.end,
      <Color>[for (final double t in _kFadeStops) Color.fromRGBO(255, 255, 255, 1 - t * t * (3 - 2 * t))],
      _kFadeStops,
    );
  }

  /// [paint] with its colour carried by [mask]'s alpha instead, when there is
  /// a mask: the gradient is white with the fade in its alpha, and `modulate`
  /// against the paint's colour is that colour faded.
  Paint _faded(Paint paint, ui.Shader? mask, Color color) {
    if (mask == null) {
      return paint;
    }
    // Opaque white under the shader, because a paint's colour alpha still
    // scales a shaded draw: left at the colour's own, the tint came out at
    // its alpha squared (0.36 for 0.6, the first run of the fade's arm).
    return paint
      ..color = const Color(0xFFFFFFFF)
      ..shader = mask
      ..colorFilter = ColorFilter.mode(color, BlendMode.modulate);
  }

  /// See the assert in [_paintFlat]: the complaint is worth making once and not
  /// sixty times a second.
  bool _warnedUndeclaredOpaque = false;

  /// Draws the surface through the measured optics.
  ///
  /// The map into the atlas is folded into two uniforms — `texel = p * scale +
  /// origin` — because a shader that had to reconstruct it would be doing per
  /// pixel what is the same for the whole quad. The clamp is to the **slot**,
  /// which is what keeps a displaced sample out of the neighbouring surface's
  /// backdrop.
  ///
  /// With [ripple], and waves alive, through the ripple program instead — the
  /// same block with the waves appended. Not into a capture: the level above
  /// would hold a wave mid-flight for as long as it holds its proxy.
  void _paintOptics(
    Canvas canvas,
    Offset offset,
    GlassProxyFrame frame,
    AtlasSlot slot,
    ui.FragmentProgram program, {
    bool ripple = false,
  }) {
    final List<GlassRippleWave> waves = ripple && _ripples ? _rippleField!.waves : const <GlassRippleWave>[];
    final ui.FragmentProgram? rippleProgram = waves.isEmpty ? null : _proxy?.rippleProgram;
    if (rippleProgram != null) {
      program = rippleProgram;
      rippleDraws++;
    }
    final GlassFinish finish = effectiveFinish;
    final GlassOptics optics = finish.optics;
    final double radius = effectiveRadius;
    final double inset = presenceInset();
    final Offset walk = optics.walk(size / 2) * _presence;
    final (double, double, double) fade = _fade?.uniforms(size) ?? (0, 0, 0);
    // Draw space to global logical: the surface is painted into whatever layer
    // it is in, and the register works in the root's coordinates.
    final Offset srcOrigin = globalRect.topLeft - offset;
    final double scale = slot.pixelRatio;
    var mapOrigin = (srcOrigin - slot.source.topLeft) * scale + slot.rect.topLeft;
    assert(() {
      // The negative control reaches the shader through the same term the map
      // does, so it displaces the sample and nothing else — see
      // [debugSampleShift].
      mapOrigin += debugSampleShift * scale;
      return true;
    }());
    final Color tint = finish.tint;
    final Color? contrastRim = effectiveHighContrastRim;
    final Color rim = contrastRim ?? finish.rim;
    final double rimWidth = contrastRim != null ? kHighContrastRimWidthLogical : (rim.a <= 0 ? 0 : kRimWidthLogical);
    final ui.FragmentShader shader = program.fragmentShader()
      ..setFloat(0, frame.image.width.toDouble())
      ..setFloat(1, frame.image.height.toDouble())
      ..setFloat(2, mapOrigin.dx)
      ..setFloat(3, mapOrigin.dy)
      ..setFloat(4, scale)
      // Texel **centres**, not the slot's edges. A bilinear tap reaches half a
      // texel each way, so clamping to the rect would let it cross into the
      // neighbouring slot — and clamping a texel short, which is what this said
      // first, throws away half a texel of the surface's own last column: the
      // identity control failed on exactly one column, x = 239 of a box ending
      // at 240, by up to 34 code values.
      ..setFloat(5, slot.rect.left + 0.5)
      ..setFloat(6, slot.rect.top + 0.5)
      ..setFloat(7, slot.rect.right - 0.5)
      ..setFloat(8, slot.rect.bottom - 0.5)
      // Eroded by the presence inset, which is the same field plus a constant
      // (see [presence]); at full presence the subtraction is of zero.
      ..setFloat(9, size.width / 2 - inset)
      ..setFloat(10, size.height / 2 - inset)
      ..setFloat(11, offset.dx + size.width / 2)
      ..setFloat(12, offset.dy + size.height / 2)
      ..setFloat(13, radius - inset)
      ..setFloat(14, optics.thickness)
      ..setFloat(15, optics.strength)
      ..setFloat(16, optics.edgePower)
      ..setFloat(17, optics.shoulder)
      ..setFloat(18, tint.r)
      ..setFloat(19, tint.g)
      ..setFloat(20, tint.b)
      ..setFloat(21, tint.a)
      ..setFloat(22, rimWidth)
      ..setFloat(23, rim.r)
      ..setFloat(24, rim.g)
      ..setFloat(25, rim.b)
      ..setFloat(26, rim.a)
      ..setFloat(27, 1 / _devicePixelRatio)
      ..setFloat(28, contrastRim == null ? 0 : 1)
      // Over the full half-box rather than the eroded one, and scaled by
      // presence: a drop growing in shows its margin growing with it, where
      // over the eroded box the first frames would show the whole margin
      // through a pinhole.
      ..setFloat(29, walk.dx)
      ..setFloat(30, walk.dy)
      ..setFloat(31, fade.$1)
      ..setFloat(32, fade.$2)
      ..setFloat(33, fade.$3)
      // Explicit, always: the default is nearest, which is the defect that
      // killed the precedents' path (D1) and which at a divisor would make the
      // proxy measure aliasing instead of resolution.
      ..setImageSampler(0, frame.image, filterQuality: FilterQuality.low);
    if (rippleProgram != null) {
      _writeWaves(shader, waves);
    }
    if (!debugGlassShaderAntiAlias) {
      primeAliasedDraw(canvas);
    }
    // A device pixel past the box, so the shader's own coverage decides every
    // edge pixel (it is zero half a pixel out) and the rasterizer decides none.
    // On the box itself a pixel whose centre fell just outside was dropped
    // without antialiasing and doubly attenuated with it: 648 pixels of one
    // fractional layout on Skia, up to 31 code values (D200).
    canvas.drawRect(
      (offset & size).inflate(1 / _devicePixelRatio),
      Paint()
        ..shader = shader
        ..isAntiAlias = debugGlassShaderAntiAlias,
    );
    releaseGlassShader(shader);
  }

  /// The ripple program's tail, from index 34: the count, `uWave[4]`,
  /// `uWaveAmp[4]`, the reach and the light. Every slot is written, the unused
  /// ones as zeros, because a short write leaves whatever was there.
  void _writeWaves(ui.FragmentShader shader, List<GlassRippleWave> waves) {
    final GlassRipple ripple = _rippleField!.ripple;
    shader.setFloat(34, waves.length.toDouble());
    for (var i = 0; i < kMaxRippleWaves; i++) {
      final List<double> w = i < waves.length ? waves[i].uniforms() : const <double>[0, 0, 0, 1, 0, 0, 0, 0];
      for (var j = 0; j < 4; j++) {
        shader
          ..setFloat(35 + i * 4 + j, w[j])
          ..setFloat(35 + kMaxRippleWaves * 4 + i * 4 + j, w[4 + j]);
      }
    }
    // Never zero: it divides. A wave at birth is all zeros.
    final double reach = _rippleField!.reach;
    shader
      ..setFloat(35 + kMaxRippleWaves * 8, reach > 1e-3 ? reach : 1e-3)
      ..setFloat(36 + kMaxRippleWaves * 8, ripple.light);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _ledger?.register(this);
    _group?.join(this);
    _proxy?.addListener(_onProxyPublished);
    if (_rippleField != null) {
      _proxy?.wantRippleProgram();
    }
  }

  @override
  void detach() {
    _group?.leave(this);
    // Belt and braces rather than the mechanism: [readGeometry] already refuses
    // while detached, so a surface that skipped this would be missing from
    // every reading anyway. What this keeps honest is [GlassLedger.
    // registeredCount], which counts declarations rather than places.
    _ledger?.unregister(this);
    _proxy?.removeListener(_onProxyPublished);
    _stopRipple();
    _rippleField?.clear();
    super.detach();
  }

  @override
  void dispose() {
    _drawLayer.layer = null;
    _contentLayer.layer = null;
    _ledger?.unregister(this);
    _group?.leave(this);
    _proxy?.removeListener(_onProxyPublished);
    super.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<BorderRadius>('borderRadius', _borderRadius));
    properties.add(FlagProperty('registered', value: _ledger != null, ifFalse: 'no GlassScope above'));
  }
}
