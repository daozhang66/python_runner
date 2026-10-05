// The proxy pass: our own paint over the live render tree, recorded into a
// picture the glass surfaces read as their backdrop.
//
// Arrived here from `spikes/13_own_walk/` when phase A opened; M12 is what
// licenses it. Spike #1 had shown that a custom `PaintingContext` does not
// propagate by itself inside the normal pipeline — the wall is exactly
// `isRepaintBoundary` — and that Clarity's active walk goes straight through
// that wall while silently dropping transparency (Spike #1, Q5). M12 answered
// the two questions that made the technique usable: a pass that draws
// *everything* reproduces `toImageSync` byte for byte on 16 constructs of 18
// and 65 corpus combinations of 91, and it leaves the live render tree exactly
// as it found it.
//
// Everything built on top of it — the atlas (D24), stopping the descent on an
// opaque cover, substituting platform views, the roles the app declares through
// `GlassProxy` — is a *subtraction* from that pass. A pass that already lost
// content silently would make every later number a measurement of the loss
// rather than of the optimisation.
//
// Deliberately observable: every subtraction and every construct this pass
// cannot reproduce is counted in [WalkLog] rather than assumed away.

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'proxy_role.dart';
import 'shadow_filter.dart';

/// What a node is allowed to become in the pass.
///
/// M11 removed the middle step this enum was going to have. Simplifying content
/// saves 24…28% (D28) and costs 0.95…9.6 ΔE (D29), while lowering the proxy
/// resolution saves 47…73% and costs 0.47 — so "simplify" loses to a knob that
/// already exists, on both axes. What survives is binary, plus the substitution
/// the engine forces on us for content we cannot read.
enum WalkAction {
  /// Run the node's own `paint`.
  paint,

  /// Draw nothing and do not descend. Our own glass surfaces (self-capture) and
  /// shadows (D31, 0.00 ΔE) are the two mandatory members.
  skip,

  /// Draw a placeholder rectangle and do not descend. Platform views and
  /// `Texture` are unreadable by construction — `PlatformViewLayer::Paint`
  /// without an embedder draws nothing and logs an error
  /// (`platform_view_layer.cc:36-41`), so the stock capture leaves a hole there
  /// too.
  substitute,
}

typedef WalkPolicy = WalkAction Function(RenderObject child);

/// The control policy: draw everything, subtract nothing.
///
/// This is the variant the pixel comparison is run against. Any policy that
/// skips or substitutes is only meaningful once this one is known to be exact.
WalkAction paintEverything(RenderObject child) => WalkAction.paint;

/// Everything one pass observed. A fresh instance per pass on purpose: two
/// passes over the same tree are two measurements, not one accumulated.
class WalkLog {
  int visited = 0;
  int boundariesCrossed = 0;

  /// Effects recovered from `updateCompositedLayer` — the ones a direct
  /// `paint()` call cannot see. Zero here on a tree containing an `Opacity`
  /// means the pass has Clarity's bug.
  int compositedEffectsApplied = 0;

  /// Layers this pass had to create because a `push*` return type is
  /// non-nullable and the caller had none to reuse. Each one is parked in
  /// somebody else's field, which is a mutation of the live tree even though
  /// nothing is lost. The invariant is that this stays at zero.
  int layersMinted = 0;

  /// Layer types with no canvas equivalent, so their effect is missing from the
  /// recording. Named rather than counted: which type it is *is* the finding.
  final List<String> unhandledLayers = <String>[];

  /// Reached through `addLayer`, i.e. content that never goes through a canvas.
  final List<String> addedLayers = <String>[];

  final List<String> substituted = <String>[];
  final List<String> skipped = <String>[];

  /// [GlassProxy] markers the pass actually reached, by role.
  ///
  /// Half a counter on its own: compare it against
  /// `RenderGlassProxy.countIn(root)` to tell a marker that fired from one an
  /// ancestor cut off before the pass ever saw it.
  final Map<GlassProxyRole, int> proxyRoles = <GlassProxyRole, int>{};

  /// Colour filters flattened while an alpha layer was open above them.
  ///
  /// The engine folds the alpha into the filter's own `saveLayer`, and the fold
  /// changes that layer's bounds from the cull rect to the content — so a
  /// filter that paints transparent black stops covering the empty area.
  /// Measured: at opacity 1.0 the region is opaque cyan and at 254/255 it is
  /// gone, in the engine's own rendering. This pass keeps it, so a subtree with
  /// a non-zero count here belongs on the `toImageSync` fallback.
  int opacityFoldedIntoFilter = 0;

  /// Nodes whose `paint` threw. We run foreign code; this is the budget for it.
  final List<String> errors = <String>[];

  /// `createChildContext` calls, which should be none: every branch that would
  /// have asked for one is overridden to stay on this context's canvas.
  final List<String> childContextsRequested = <String>[];

  Map<String, Object> summary() => <String, Object>{
    'visited': visited,
    'boundaries_crossed': boundariesCrossed,
    'composited_effects_applied': compositedEffectsApplied,
    'layers_minted': layersMinted,
    'opacity_folded_into_filter': opacityFoldedIntoFilter,
    'unhandled_layers': unhandledLayers,
    'added_layers': addedLayers,
    'substituted': substituted,
    'skipped': skipped,
    'proxy_roles': <String, int>{
      for (final MapEntry<GlassProxyRole, int> e in proxyRoles.entries) e.key.name: e.value,
    },
    'errors': errors,
    'child_contexts_requested': childContextsRequested,
  };
}

/// A `PaintingContext` that walks *through* repaint boundaries instead of
/// compositing them, and flattens every layer effect onto its own canvas.
///
/// Three hazards, all named in `FINDINGS.md` ("Свой обход дерева") and all
/// handled here rather than hoped about:
///
/// - **`push*` with `oldLayer` writes back into somebody else's field.**
///   `RenderClipRect.paint` does `layer = context.pushClipRect(..., oldLayer:
///   layer as ClipRectLayer?)`, and `LayerHandle`'s setter disposes whatever it
///   held when a *different* layer arrives (`layer.dart:800-812`). Returning a
///   fresh layer from any of these would dispose a layer that is still in the
///   live layer tree. So every override returns the `oldLayer` it was given,
///   and assigning the identical object back is a no-op in the handle.
/// - **`addLayer` bypasses the canvas entirely** — platform views, `Texture`.
///   The method is public and overridden here.
/// - **A direct `paint()` call misses `_paintWithContext`** (`object.dart:3484`):
///   `_needsPaint` is left set, which is correct — the pipeline must not be
///   lied to — and the reentrancy assert is skipped, which is why this belongs
///   in a post-frame callback rather than inside our own `paint`.
class ProxyWalkContext extends PaintingContext {
  ProxyWalkContext(
    super.containerLayer,
    super.estimatedBounds, {
    WalkLog? log,
    this.policy = paintEverything,
    this.placeholderColor = const ui.Color(0xFF808080),
    this.shadowFilter,
  }) : log = log ?? WalkLog();

  final WalkLog log;
  final WalkPolicy policy;
  final ui.Color placeholderColor;

  /// The one policy step M11 left alive, and it does not fit [WalkPolicy].
  ///
  /// A shadow is not a node: it is a `drawShadow` inside a physical model's
  /// `paint`, or a blurred `drawRRect` inside a `BoxDecoration`'s. Skipping the
  /// node that owns it would take the card with it. So the filter sits on the
  /// canvas instead — which is possible because `PaintingContext.canvas` is a
  /// plain getter and `ClipContext` reads the same one.
  final ShadowFilter? shadowFilter;

  FilteringCanvas? _filtered;

  @override
  Canvas get canvas {
    final Canvas inner = super.canvas;
    final ShadowFilter? filter = shadowFilter;
    // `GlassProxy.verbatim` is a subtree-sized hole in the canvas policy, so it
    // has to be applied here rather than at the node: the draws it protects are
    // several frames down somebody else's `paint`, which is the same reason the
    // filter itself does not live on a node.
    if (filter == null || _verbatimDepth > 0) {
      return inner;
    }
    // `PaintingContext` starts a new recording after every layer it pushes, so
    // the wrapper is rebuilt whenever the canvas underneath changes rather than
    // cached once.
    final FilteringCanvas? wrapper = _filtered;
    if (wrapper == null || !identical(wrapper.inner, inner)) {
      return _filtered = FilteringCanvas(inner, filter);
    }
    return wrapper;
  }

  /// Alpha-carrying `saveLayer`s currently open above the cursor.
  ///
  /// The one construct this pass does not reproduce needs both halves: an
  /// opacity below 1.0 *and* a colour filter under it. The engine folds the
  /// first into the second (`ColorFilterLayer::Preroll` advertises
  /// `kCallerCanApplyOpacity`) and the fold changes the filter's bounds from the
  /// cull rect to the content, which deletes everything the filter painted
  /// outside the content. A flattened pass keeps two layers and keeps that
  /// region. Counted rather than fixed: reproducing the fold means knowing
  /// bottom-up what the child will do, and this pass is top-down.
  int _opacityDepth = 0;

  /// Open [GlassProxyRole.verbatim] subtrees above the cursor.
  int _verbatimDepth = 0;

  /// `stopRecordingIfNeeded` is `@protected`, and whoever seeded this context
  /// has to close the recording before the container layer holds a picture.
  void finish() => stopRecordingIfNeeded();

  // ---------------------------------------------------------------------
  // Descent.
  // ---------------------------------------------------------------------

  @override
  void paintChild(RenderObject child, Offset offset) {
    log.visited++;
    if (child.isRepaintBoundary) {
      log.boundariesCrossed++;
    }

    // The policy is consulted for *every* child, before the marker and whatever
    // the marker says, because `OcclusionPolicy` reads paint order out of this
    // call sequence: a short circuit here would make its order check blind
    // exactly where a `GlassProxy` sits.
    WalkAction action = policy(child);

    final RenderGlassProxy? marker = child is RenderGlassProxy ? child : null;
    if (marker != null) {
      log.proxyRoles.update(marker.role, (int n) => n + 1, ifAbsent: () => 1);
    }
    // A node the policy already cut needs no stub: it is invisible either way,
    // and drawing one would cost area for nothing.
    if (marker != null && action == WalkAction.paint) {
      switch (marker.role) {
        case GlassProxyRole.hidden:
          action = WalkAction.skip;
        case GlassProxyRole.replace:
          log.substituted.add('GlassProxy.replace');
          marker.paintProxy(canvas, offset);
          return;
        case GlassProxyRole.opaque:
        case GlassProxyRole.verbatim:
          break;
      }
    }

    switch (action) {
      case WalkAction.skip:
        log.skipped.add(child.runtimeType.toString());
        return;
      case WalkAction.substitute:
        log.substituted.add(child.runtimeType.toString());
        canvas.drawRect(child.paintBounds.shift(offset), ui.Paint()..color = placeholderColor);
        return;
      case WalkAction.paint:
        break;
    }

    final _CanvasEffect? composited = child.isRepaintBoundary ? _compositedEffect(child) : null;

    // A throwing `paint` leaves the save stack unbalanced, and the next node
    // would then draw under somebody else's clip. Recorded, not hidden.
    final int savesBefore = canvas.getSaveCount();
    if (composited != null && composited.carriesAlpha) {
      _opacityDepth++;
    }
    final bool verbatim = marker != null && marker.role == GlassProxyRole.verbatim;
    final _LiveOffsets? live = _LiveOffsets.of(child);
    composited?.begin(canvas);
    // After `begin` and before `end`, so the effect's own save/restore pair is
    // issued through the same canvas at both ends.
    if (verbatim) {
      _verbatimDepth++;
    }
    try {
      // The whole mechanism: `PaintingContext.paintChild`'s `isRepaintBoundary`
      // branch (`object.dart:255`) is never reached, so nothing is composited
      // and nothing is recorded into the child's own layer. `paint` is
      // `@protected`, which is a lint and not a runtime guard.
      // ignore: invalid_use_of_protected_member
      child.paint(this, offset);
    } catch (error) {
      log.errors.add('${child.runtimeType}: $error');
    } finally {
      live?.restore();
      if (verbatim) {
        _verbatimDepth--;
      }
      composited?.end(canvas);
      if (composited != null && composited.carriesAlpha) {
        _opacityDepth--;
      }
      while (canvas.getSaveCount() > savesBefore) {
        canvas.restore();
      }
    }
  }

  /// The effect a repaint boundary carries in `updateCompositedLayer`, which is
  /// invisible to a direct `paint()` call.
  ///
  /// `RenderOpacity.paint` is literally `super.paint` (`proxy_box.dart:947-953`);
  /// all of the alpha lives in `updateCompositedLayer` (`:941`), and that method
  /// is only ever called by `repaintCompositedChild`. Clarity walks past it and
  /// the transparency simply disappears — measured, `wouldDirty` was 0.
  ///
  /// The method is public API, so asking the child for a *throwaway* layer and
  /// reading the effect off it needs nothing private, and it covers all three
  /// framework implementations (`RenderOpacity`, `RenderAnimatedOpacityMixin`,
  /// `_RenderImageFiltered`) plus any future one, which a `case RenderOpacity`
  /// would not. The price is one layer allocated and disposed per boundary per
  /// pass; that is a real entry in M12's CPU budget.
  _CanvasEffect? _compositedEffect(RenderObject child) {
    final handle = LayerHandle<OffsetLayer>();
    try {
      handle.layer = child.updateCompositedLayer(oldLayer: null);
      final OffsetLayer probe = handle.layer!;
      if (probe is OpacityLayer) {
        final int? alpha = probe.alpha;
        if (alpha == null || alpha == 255) {
          return null;
        }
        log.compositedEffectsApplied++;
        return _SaveLayer(ui.Paint()..color = ui.Color.fromARGB(alpha, 0, 0, 0), carriesAlpha: true);
      }
      if (probe is ImageFilterLayer) {
        final ui.ImageFilter? filter = probe.imageFilter;
        if (filter == null) {
          return null;
        }
        log.compositedEffectsApplied++;
        return _SaveLayer(ui.Paint()..imageFilter = filter);
      }
      return null;
    } finally {
      // The public way to dispose a layer: `Layer.dispose` is @protected and
      // @visibleForTesting, `LayerHandle` is neither.
      handle.layer = null;
    }
  }

  // ---------------------------------------------------------------------
  // Layer effects, flattened.
  //
  // The clip and transform families already have a non-compositing branch in
  // the framework that does exactly what we want, so these delegate to it with
  // `needsCompositing: false` rather than re-deriving the canvas calls. That is
  // not laziness: `Clip.antiAliasWithSaveLayer` is a `clipRRect` *plus* a
  // `saveLayer` (`painting/clip.dart:29-33`), and a reimplementation that
  // missed it would differ from `toImageSync` only on antialiased edges.
  // ---------------------------------------------------------------------

  @override
  ClipRectLayer? pushClipRect(
    bool needsCompositing,
    Offset offset,
    Rect clipRect,
    PaintingContextCallback painter, {
    Clip clipBehavior = Clip.hardEdge,
    ClipRectLayer? oldLayer,
  }) {
    super.pushClipRect(false, offset, clipRect, painter, clipBehavior: clipBehavior);
    return oldLayer;
  }

  @override
  ClipRRectLayer? pushClipRRect(
    bool needsCompositing,
    Offset offset,
    Rect bounds,
    RRect clipRRect,
    PaintingContextCallback painter, {
    Clip clipBehavior = Clip.antiAlias,
    ClipRRectLayer? oldLayer,
  }) {
    super.pushClipRRect(false, offset, bounds, clipRRect, painter, clipBehavior: clipBehavior);
    return oldLayer;
  }

  @override
  ClipRSuperellipseLayer? pushClipRSuperellipse(
    bool needsCompositing,
    Offset offset,
    Rect bounds,
    RSuperellipse clipRSuperellipse,
    PaintingContextCallback painter, {
    Clip clipBehavior = Clip.antiAlias,
    ClipRSuperellipseLayer? oldLayer,
  }) {
    super.pushClipRSuperellipse(
      false,
      offset,
      bounds,
      clipRSuperellipse,
      painter,
      clipBehavior: clipBehavior,
    );
    return oldLayer;
  }

  @override
  ClipPathLayer? pushClipPath(
    bool needsCompositing,
    Offset offset,
    Rect bounds,
    Path clipPath,
    PaintingContextCallback painter, {
    Clip clipBehavior = Clip.antiAlias,
    ClipPathLayer? oldLayer,
  }) {
    super.pushClipPath(false, offset, bounds, clipPath, painter, clipBehavior: clipBehavior);
    return oldLayer;
  }

  @override
  TransformLayer? pushTransform(
    bool needsCompositing,
    Offset offset,
    Matrix4 transform,
    PaintingContextCallback painter, {
    TransformLayer? oldLayer,
  }) {
    super.pushTransform(false, offset, transform, painter);
    return oldLayer;
  }

  // Opacity and colour filter have no non-compositing branch to borrow: the
  // framework always builds a layer for them. Both are a `saveLayer` at the
  // engine level anyway (`OpacityLayer.addToScene` → `builder.pushOpacity`),
  // so the flattening is exact rather than approximate.

  @override
  OpacityLayer pushOpacity(
    Offset offset,
    int alpha,
    PaintingContextCallback painter, {
    OpacityLayer? oldLayer,
  }) {
    // `PaintingContext.pushOpacity` puts `offset` on the layer and paints the
    // children at zero, so the translate has to happen here.
    _opacityDepth++;
    canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..saveLayer(null, ui.Paint()..color = ui.Color.fromARGB(alpha, 0, 0, 0));
    painter(this, Offset.zero);
    canvas
      ..restore()
      ..restore();
    _opacityDepth--;
    return oldLayer ?? _mint(OpacityLayer());
  }

  @override
  ColorFilterLayer pushColorFilter(
    Offset offset,
    ColorFilter colorFilter,
    PaintingContextCallback painter, {
    ColorFilterLayer? oldLayer,
  }) {
    _noteColorFilter();
    canvas.saveLayer(null, ui.Paint()..colorFilter = colorFilter);
    painter(this, offset);
    canvas.restore();
    return oldLayer ?? _mint(ColorFilterLayer());
  }

  /// Non-nullable return types force a layer into existence when the caller had
  /// none to reuse. Returning `oldLayer` unchanged is what keeps the live tree
  /// intact; this is the one case where that is not an option, so it is counted
  /// and the count is an invariant rather than a detail.
  T _mint<T extends ContainerLayer>(T layer) {
    log.layersMinted++;
    return layer;
  }

  // ---------------------------------------------------------------------
  // The general routes. Anything that did not come through a typed `push*`
  // arrives here carrying its effect in the layer object itself.
  // ---------------------------------------------------------------------

  @override
  void pushLayer(
    ContainerLayer childLayer,
    PaintingContextCallback painter,
    Offset offset, {
    Rect? childPaintBounds,
  }) {
    // Deliberately not `super`: `PaintingContext.pushLayer` starts by calling
    // `childLayer.removeAllChildren()` (`object.dart:554-556`), and this layer
    // belongs to a live render object that is *not* repainting. Stripping its
    // children would gut a retained subtree, and the next real frame — which
    // has no reason to repaint it — would composite nothing.
    final _CanvasEffect? effect = _effectOf(childLayer);
    final int savesBefore = canvas.getSaveCount();
    effect?.begin(canvas);
    painter(this, offset);
    effect?.end(canvas);
    while (canvas.getSaveCount() > savesBefore) {
      canvas.restore();
    }
  }

  @override
  void addLayer(Layer layer) {
    // Content that never reaches a canvas: `TextureLayer`, `PlatformViewLayer`.
    // There is nothing to read, so the choice is a placeholder or a hole — and
    // it is a hole, because the stock capture gives a hole and the base level
    // is recorded that way: a level above it that drew a stub showed something
    // the level below did not. On the web every `SelectionArea` stands on one
    // — the browser's context menu, a transparent `HtmlElementView` under the
    // whole selectable region — and a stub there painted a selectable page
    // grey into the backdrop of every bar over it.
    log.addedLayers.add(layer.runtimeType.toString());
    if (layer is! TextureLayer && layer is! PlatformViewLayer) {
      log.unhandledLayers.add(layer.runtimeType.toString());
    }
  }

  @override
  void appendLayer(Layer layer) {
    // Only reachable from `addLayer`/`pushLayer`, both overridden. If this
    // fires, a route was missed.
    log.unhandledLayers.add('appendLayer:${layer.runtimeType}');
  }

  @override
  PaintingContext createChildContext(ContainerLayer childLayer, Rect bounds) {
    // Same: every caller is overridden. Recorded rather than asserted, because
    // the pass has to survive profile mode where an assert is not there.
    log.childContextsRequested.add(childLayer.runtimeType.toString());
    return this;
  }

  /// The one place this pass is known to diverge from `toImageSync`.
  ///
  /// Conservative on purpose: the engine only folds when the opacity's sole
  /// child advertises that it can absorb one, and this counts every colour
  /// filter under any live alpha. Over-reporting sends a subtree back to a
  /// plain `toImageSync`, which is the direction a fallback should err in.
  void _noteColorFilter() {
    if (_opacityDepth > 0) {
      log.opacityFoldedIntoFilter++;
    }
  }

  /// Reads a layer's effect and returns the canvas operation that reproduces
  /// it, or null when there is none to reproduce.
  _CanvasEffect? _effectOf(ContainerLayer layer) {
    switch (layer) {
      case ClipRectLayer():
        final Rect? clip = layer.clipRect;
        return clip == null ? null : _ClipRect(clip, layer.clipBehavior);
      case ClipRRectLayer():
        final RRect? clip = layer.clipRRect;
        return clip == null ? null : _ClipRRect(clip, layer.clipBehavior);
      case ClipRSuperellipseLayer():
        final RSuperellipse? clip = layer.clipRSuperellipse;
        return clip == null ? null : _ClipRSuperellipse(clip, layer.clipBehavior);
      case ClipPathLayer():
        final Path? clip = layer.clipPath;
        return clip == null ? null : _ClipPath(clip, layer.clipBehavior);
      case TransformLayer():
        final Matrix4? m = layer.transform;
        return m == null ? null : _Transform(m);
      case OpacityLayer():
        final int alpha = layer.alpha ?? 255;
        log.compositedEffectsApplied++;
        return _OffsetThen(
          layer.offset,
          alpha == 255
              ? null
              : _SaveLayer(
                  ui.Paint()..color = ui.Color.fromARGB(alpha, 0, 0, 0),
                  carriesAlpha: true,
                ),
        );
      case ImageFilterLayer():
        final ui.ImageFilter? filter = layer.imageFilter;
        return filter == null ? null : _OffsetThen(layer.offset, _SaveLayer(ui.Paint()..imageFilter = filter));
      case ColorFilterLayer():
        final ColorFilter? filter = layer.colorFilter;
        if (filter == null) {
          return null;
        }
        _noteColorFilter();
        return _SaveLayer(ui.Paint()..colorFilter = filter);
      case ShaderMaskLayer():
        final Shader? shader = layer.shader;
        final Rect? maskRect = layer.maskRect;
        final BlendMode? blend = layer.blendMode;
        return (shader == null || maskRect == null || blend == null) ? null : _ShaderMask(shader, maskRect, blend);
      case LeaderLayer():
        return _OffsetThen(layer.offset, null);
      case OffsetLayer():
        return _OffsetThen(layer.offset, null);
      case AnnotatedRegionLayer<Object>():
        // Pure metadata for hit testing; painting the children inline is exact.
        return null;
      case ContainerLayer() when layer.runtimeType == ContainerLayer:
        return null;
      default:
        // `BackdropFilterLayer` lands here and cannot land anywhere else: a
        // backdrop filter reads what is already on the destination, and
        // `ui.Canvas.saveLayer` has no backdrop parameter — there is no canvas
        // call that reproduces it. `FollowerLayer` lands here too, because its
        // transform is resolved against a leader at composition time.
        log.unhandledLayers.add(layer.runtimeType.toString());
        return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Canvas effects. Each is a matched save/restore pair so the walk can wrap a
// child in it without knowing what it is.
// ---------------------------------------------------------------------------

/// Where a live layer was before the walk painted the render object that owns
/// it, put back afterwards.
///
/// A render object that keeps its own layer writes its position into it from
/// `paint` and then pushes it: `RenderLeaderLayer` sets `layer.offset`,
/// `RenderFollowerLayer` the follower's offsets. That layer is the one on
/// screen, and the walk calls `paint` with the root's offset rather than the
/// one the layer's parent composites it at — so the write moved the live
/// layer. A `SelectionArea` in a bar (its `CompositedTransformTarget`) put the
/// bar's title one sidebar right and one inset down whenever a level above the
/// bar was captured, a popover's, and left it there until the bar repainted.
final class _LiveOffsets {
  _LiveOffsets._(this._layer, this._offset, this._linked);

  static _LiveOffsets? of(RenderObject owner) {
    // ignore: invalid_use_of_protected_member
    final ContainerLayer? layer = owner.layer;
    return switch (layer) {
      OffsetLayer() => _LiveOffsets._(layer, layer.offset, null),
      LeaderLayer() => _LiveOffsets._(layer, layer.offset, null),
      FollowerLayer() => _LiveOffsets._(layer, layer.unlinkedOffset, layer.linkedOffset),
      _ => null,
    };
  }

  final ContainerLayer _layer;
  final Offset? _offset;
  final Offset? _linked;

  void restore() {
    switch (_layer) {
      case final OffsetLayer layer:
        layer.offset = _offset!;
      case final LeaderLayer layer:
        layer.offset = _offset!;
      case final FollowerLayer layer:
        layer
          ..unlinkedOffset = _offset
          ..linkedOffset = _linked;
    }
  }
}

abstract class _CanvasEffect {
  const _CanvasEffect();

  /// Whether this effect opens a layer whose alpha the engine would be free to
  /// fold into something below it.
  bool get carriesAlpha => false;

  void begin(Canvas canvas);

  void end(Canvas canvas);
}

class _SaveLayer extends _CanvasEffect {
  const _SaveLayer(this.paint, {this.carriesAlpha = false});

  final ui.Paint paint;

  @override
  final bool carriesAlpha;

  /// Null bounds on purpose: the recorder then infers the layer's extent from
  /// what is drawn inside it, which is what makes a flattened effect identical
  /// to the layer it replaces. Explicit bounds were tried and are worse — they
  /// move a blur's edge by one code value over 18 327 pixels instead of 1 383,
  /// and they do not fix the opacity/colour-filter fold, which is not a bounds
  /// problem.
  @override
  void begin(Canvas canvas) => canvas.saveLayer(null, paint);

  @override
  void end(Canvas canvas) => canvas.restore();
}

class _OffsetThen extends _CanvasEffect {
  const _OffsetThen(this.offset, this.inner);

  final Offset offset;
  final _CanvasEffect? inner;

  @override
  void begin(Canvas canvas) {
    canvas
      ..save()
      ..translate(offset.dx, offset.dy);
    inner?.begin(canvas);
  }

  @override
  void end(Canvas canvas) {
    inner?.end(canvas);
    canvas.restore();
  }
}

class _Transform extends _CanvasEffect {
  const _Transform(this.transform);

  final Matrix4 transform;

  @override
  void begin(Canvas canvas) {
    canvas
      ..save()
      ..transform(transform.storage);
  }

  @override
  void end(Canvas canvas) => canvas.restore();
}

/// The clip effects mirror `ClipContext._clipAndPaint` (`painting/clip.dart:15-37`)
/// including the extra `saveLayer` that `Clip.antiAliasWithSaveLayer` adds.
abstract class _Clip extends _CanvasEffect {
  const _Clip(this.behavior, this.bounds);

  final Clip behavior;
  final Rect bounds;

  void applyClip(Canvas canvas, {required bool doAntiAlias});

  @override
  void begin(Canvas canvas) {
    canvas.save();
    switch (behavior) {
      case Clip.none:
        break;
      case Clip.hardEdge:
        applyClip(canvas, doAntiAlias: false);
      case Clip.antiAlias:
        applyClip(canvas, doAntiAlias: true);
      case Clip.antiAliasWithSaveLayer:
        applyClip(canvas, doAntiAlias: true);
        canvas.saveLayer(bounds, ui.Paint());
    }
  }

  @override
  void end(Canvas canvas) {
    if (behavior == Clip.antiAliasWithSaveLayer) {
      canvas.restore();
    }
    canvas.restore();
  }
}

class _ClipRect extends _Clip {
  const _ClipRect(this.rect, Clip behavior) : super(behavior, rect);

  final Rect rect;

  @override
  void applyClip(Canvas canvas, {required bool doAntiAlias}) => canvas.clipRect(rect, doAntiAlias: doAntiAlias);
}

class _ClipRRect extends _Clip {
  _ClipRRect(this.rrect, Clip behavior) : super(behavior, rrect.outerRect);

  final RRect rrect;

  @override
  void applyClip(Canvas canvas, {required bool doAntiAlias}) => canvas.clipRRect(rrect, doAntiAlias: doAntiAlias);
}

class _ClipRSuperellipse extends _Clip {
  _ClipRSuperellipse(this.rse, Clip behavior) : super(behavior, rse.outerRect);

  final RSuperellipse rse;

  @override
  void applyClip(Canvas canvas, {required bool doAntiAlias}) => canvas.clipRSuperellipse(rse, doAntiAlias: doAntiAlias);
}

class _ClipPath extends _Clip {
  _ClipPath(this.path, Clip behavior) : super(behavior, path.getBounds());

  final Path path;

  @override
  void applyClip(Canvas canvas, {required bool doAntiAlias}) => canvas.clipPath(path, doAntiAlias: doAntiAlias);
}

class _ShaderMask extends _CanvasEffect {
  const _ShaderMask(this.shader, this.maskRect, this.blendMode);

  final Shader shader;
  final Rect maskRect;
  final BlendMode blendMode;

  @override
  void begin(Canvas canvas) => canvas.saveLayer(null, ui.Paint());

  @override
  void end(Canvas canvas) {
    canvas
      ..drawRect(
        maskRect,
        ui.Paint()
          ..shader = shader
          ..blendMode = blendMode,
      )
      ..restore();
  }
}
