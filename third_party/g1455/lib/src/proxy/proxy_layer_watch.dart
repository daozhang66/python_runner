// Whether anything under the host changed, read off the composited layer tree.
//
// This is D2's dirty oracle, finally built — and built smaller. The original
// plan was a layer walk comparing `PictureLayer.picture` by identity, chosen
// because our own `PaintingContext` cannot pass a repaint boundary and the
// render tree therefore cannot be watched from above. Phase A never built it:
// the oracle got the cheap inputs instead (a surface moving, a marker changing)
// and, since D147–D151, three observations the host makes for itself. The
// census that produced those also measured what they are worth, and the answer
// was uncomfortable: a realistic screen crosses 8–15 nested repaint boundaries
// (`bank_home` 8, `scroll_under_bar` 10, the same under Material 13 and 15), and
// every one of them is a place where a declared hold freezes over content that
// really moved. Not a rare shape — the commonest one.
//
// A repaint cannot hide from the *layer* tree, because a repaint mints new
// `PictureLayer`s and a new `ui.Picture` inside whichever boundary owns it. Nor
// can the one class that repaints nothing at all (D151): an opacity or a filter
// that changed without painting changed a property of a retained layer, and the
// property is right here to be read.
//
// The cost is a walk over composited layers — tens, against the hundreds of
// render objects the capture pass itself visits — on frames that were going to
// be produced anyway. It buys the whole of D146's 97.8%.
//
// **The rule that makes it safe is that the table is a whitelist.** A layer type
// this file does not understand reports a change on every frame, for ever: a
// `TextureLayer` whose pixels arrive from outside Dart, a platform view, a
// follower whose geometry belongs to a leader somewhere else, and — the one that
// matters for the next SDK — anything added to `layer.dart` after this was
// written. The failure mode of not knowing is then "expensive", never "wrong".
//
// The rule is only as good as the reading of the SDK behind it, and the audit
// that reading finally got (D162) found the table one property short and the
// whitelist one word too generous. What it reads now is checked against
// `layer.dart` itself, in `test/glass/proxy_layer_watch_test.dart`: every
// concrete layer class is named there, and every property a class hands to the
// `SceneBuilder` is either read here or listed there with the reason it is not.
// That test fails on the next SDK that adds either.

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// One frame's description of a composited subtree.
///
/// Deliberately a flat `List<Object?>` and not a hash: every element is either a
/// value with real equality (an offset, a rect, an alpha, an `ImageFilter`) or
/// an object none of whose classes override `==`, so a plain element-wise
/// comparison is exact identity where identity is what matters. A hash would
/// have made a collision — two different frames reading as one — into a silently
/// stale picture, which is the one failure this whole mechanism exists to
/// prevent.
typedef LayerSignature = List<Object?>;

/// What the watch saw: whether the subtree composites differently, and where.
///
/// The "where" is the half D174 added, and it is not a refinement of the bit —
/// it is what §4.2 of the research document needs before it can ask its
/// question at all. A shared proxy is a shared dirty flag, so the cost of the
/// route is `P(anything changed) x cost(capture)`, and every term of that is
/// about *regions*: a spinner that turns in a corner invalidates a proxy of the
/// opposite corner only because nobody asked where it turned.
///
/// **The bound is never tighter than the nearest enclosing repaint boundary**,
/// because a repaint mints a `ui.Picture` inside the boundary that owns it and
/// the layer carries that boundary's bounds, not the picture's. That is the
/// mechanism's applicability statement rather than a caveat: it pays exactly
/// where the change sits in a nested boundary that misses the glass, and the
/// census behind D147-D151 already measured how common that is — 8 to 15 nested
/// boundaries on a realistic screen.
@immutable
class LayerChange {
  const LayerChange._({required this.changed, required this.region, required this.bounded});

  /// Nothing the watch can see is different.
  static const LayerChange none = LayerChange._(changed: false, region: null, bounded: true);

  /// Something is different and the watch cannot say where.
  ///
  /// What a layer type the table does not read produces, and what a subtree
  /// under an `ImageFilterLayer` with no clip above it produces: a filter moves
  /// pixels outward by an amount no Dart API will say.
  static const LayerChange everywhere = LayerChange._(
    changed: true,
    region: null,
    bounded: false,
  );

  /// A change confined to [region], in the watched root's coordinate space.
  ///
  /// Public because the pipeline's side of the question is worth testing
  /// without a layer tree: what `capturedAreaTouchedBy` does with a rect is
  /// arithmetic about the atlas, and mounting a subtree to produce that rect
  /// would test the walk twice and the arithmetic never.
  const LayerChange.within(Rect this.region) : changed = true, bounded = true;

  /// Whether anything at all differs from the last frame.
  ///
  /// Kept separate from [touches] on purpose: the debug assertion that the
  /// framework cannot repaint this subtree without the watch noticing is about
  /// *this*, and folding the region into it would turn a hole in the table into
  /// a silent hold the moment the hole happened to sit away from the glass.
  final bool changed;

  /// Where it differs, in the coordinate space of the watched root.
  ///
  /// Null means one of two things and [bounded] separates them: an unbounded
  /// change (anywhere), or a change that composites nothing at all — two
  /// signature entries that differ while neither draws a pixel, which is a hold
  /// and not a record.
  final Rect? region;

  /// Whether [region] is a bound at all.
  final bool bounded;

  /// Whether the change can have altered a pixel inside [area].
  ///
  /// Inclusive on the edges. A dirty rect of zero area is a real answer — an
  /// empty picture has empty bounds — and `Rect.overlaps` reports false for it
  /// against everything, which would be a silent hold.
  bool touches(Rect area) {
    if (!changed) {
      return false;
    }
    if (!bounded) {
      return true;
    }
    final Rect? dirty = region;
    if (dirty == null) {
      return false;
    }
    return dirty.right >= area.left && area.right >= dirty.left && dirty.bottom >= area.top && area.bottom >= dirty.top;
  }

  @override
  String toString() => !changed
      ? 'LayerChange.none'
      : !bounded
      ? 'LayerChange.everywhere'
      : 'LayerChange(${region ?? 'nothing composited'})';
}

/// Watches the composited output of one subtree for change.
class ProxyLayerWatch {
  LayerSignature? _previous;
  List<Rect?>? _previousBounds;

  /// How many entries the last signature had. Diagnostic only.
  int get lastLength => _previous?.length ?? 0;

  /// Whether the subtree under [root] composites differently than it did the
  /// last time this was asked, and where.
  ///
  /// [exclude] is skipped wholesale, subtree and all. It carries the glass
  /// surfaces: a published proxy repaints them by construction (that is what
  /// publishing *is*), so watching them would report our own pipeline back to
  /// itself and record for ever. Their geometry is watched by the ledger
  /// instead, which is where it was always watched.
  ///
  /// The first call is always a change: there is nothing to compare against, and
  /// on that frame the oracle has no proxy either.
  ///
  /// **The region is in [root]'s own space, and that is the same space the
  /// pipeline calls global.** `GlassProxyPipeline.capture` paints the root at
  /// `Offset.zero` and clips the result to slot rects taken from the ledger in
  /// global logical pixels, so the two agree exactly as long as this walk
  /// ignores the root layer's own offset — which it does, and which is the only
  /// place in this file where a layer's property is deliberately not applied.
  LayerChange changeSince(ContainerLayer root, {Set<Layer> exclude = const <Layer>{}}) {
    final walk = _Walk(exclude);
    walk.visit(root, Matrix4.identity(), null, isRoot: true);
    final LayerSignature current = walk.out;
    final List<Rect?> currentBounds = walk.bounds;
    final LayerSignature? previous = _previous;
    final List<Rect?>? previousBounds = _previousBounds;
    _previous = current;
    _previousBounds = currentBounds;
    if (previous == null || previousBounds == null || previous.length != current.length) {
      return LayerChange.everywhere;
    }
    Rect? dirty;
    var changed = false;
    for (var i = 0; i < current.length; i++) {
      if (current[i] == previous[i]) {
        continue;
      }
      changed = true;
      final Rect? before = previousBounds[i];
      final Rect? after = currentBounds[i];
      // The entry that left and the entry that arrived, both: a subtree that
      // moved changed no picture, only the offset above it, and the pixels it
      // vacated are as dirty as the ones it took.
      if (identical(before, _Walk.anywhere) || identical(after, _Walk.anywhere)) {
        return LayerChange.everywhere;
      }
      dirty = _Walk.union(_Walk.union(dirty, before), after);
    }
    if (!changed) {
      return LayerChange.none;
    }
    return LayerChange._(changed: true, region: dirty, bounded: true);
  }

  /// Forget the last frame, so the next call reports a change.
  void reset() {
    _previous = null;
    _previousBounds = null;
  }

  /// Structure marker, so that moving a subtree between parents is visible even
  /// when every layer in it is unchanged.
  static final Object _pop = Object();

  // Every type the table knows how to read, by exact identity.
  //
  // The guard below is what makes "whitelist" mean the class and not the class
  // and its descendants. A subclass is a type this file has never read: it can
  // override `addToScene` and push state of its own, and `is` would have
  // described it by its parent's properties and then held through whatever it
  // added. The framework's own three subclasses of handled types are the
  // inspector's, they carry nothing and they only exist in debug, so exactness
  // costs nothing here — and it takes the ordering hazard out of the chain,
  // where an unknown descendant of `OffsetLayer` used to land on the first
  // branch that matched it.
  static const Set<Type> _exact = <Type>{
    PictureLayer,
    ContainerLayer,
    OffsetLayer,
    OpacityLayer,
    ImageFilterLayer,
    TransformLayer,
    ClipRectLayer,
    ClipRRectLayer,
    ClipRSuperellipseLayer,
    ClipPathLayer,
    ColorFilterLayer,
    ShaderMaskLayer,
    BackdropFilterLayer,
    LeaderLayer,
  };

  /// Whether the table reads this exact type at all.
  ///
  /// Extracted from [_describeSelf] rather than duplicated, because the bounds
  /// walk has to make the same call and two copies of a whitelist are a
  /// whitelist with a hole in it by the second edit.
  ///
  /// `AnnotatedRegionLayer` is the one type matched by subtype rather than by
  /// identity, and deliberately: it is generic, so its `runtimeType` is an
  /// instantiation [_exact] cannot name, and the alternatives are worse than
  /// the risk. Matching on the name of the type would read as unknown under
  /// `--obfuscate` and cost every `Scaffold` in an obfuscated build its
  /// retention; refusing to hold through it at all would cost every `Scaffold`
  /// its retention outright, because `AnnotatedRegion` is how the framework
  /// carries an overlay style. What it risks instead is a subclass of it that
  /// paints, and it has none: the class does not override `addToScene`, which
  /// the audit test asserts off the SDK source rather than trusting here.
  static bool _readable(Layer layer) => _exact.contains(layer.runtimeType) || layer is AnnotatedRegionLayer;

  // Still ordered subclass-first, because `is` matches subclasses and three of
  // the whitelisted types are themselves `OffsetLayer`s: `OpacityLayer`,
  // `ImageFilterLayer` and `TransformLayer`.
  static void _describeSelf(Layer layer, LayerSignature out) {
    if (!_readable(layer)) {
      // A `TextureLayer` (pixels from outside Dart), a `PlatformViewLayer`, a
      // `PerformanceOverlayLayer`, a `FollowerLayer` whose transform belongs to
      // a leader elsewhere, a subclass of anything above, or something newer
      // than this file. A fresh object never equals the one recorded last frame,
      // so the subtree is reported as changing on every frame it is present.
      out.add(Object());
      return;
    }
    if (layer is PictureLayer) {
      // The identity of the picture, which a repaint always replaces:
      // `PaintingContext._startRecording` mints a fresh `PictureLayer` and
      // `stopRecordingIfNeeded` a fresh `ui.Picture` for it.
      out.add(layer.picture);
    } else if (layer is OpacityLayer) {
      out
        ..add(layer.alpha)
        ..add(layer.offset);
    } else if (layer is ImageFilterLayer) {
      out
        ..add(layer.imageFilter)
        ..add(layer.offset);
    } else if (layer is TransformLayer) {
      out
        ..add(layer.transform)
        ..add(layer.offset);
    } else if (layer is OffsetLayer) {
      out.add(layer.offset);
    } else if (layer is ClipRectLayer) {
      out
        ..add(layer.clipRect)
        ..add(layer.clipBehavior);
    } else if (layer is ClipRRectLayer) {
      out
        ..add(layer.clipRRect)
        ..add(layer.clipBehavior);
    } else if (layer is ClipRSuperellipseLayer) {
      out
        ..add(layer.clipRSuperellipse)
        ..add(layer.clipBehavior);
    } else if (layer is ClipPathLayer) {
      // By identity: `Path` has no equality, and nothing in the framework
      // mutates the path a layer is already holding — a clipper that changes its
      // mind goes through `markNeedsPaint`, which mints new pictures above.
      out
        ..add(layer.clipPath)
        ..add(layer.clipBehavior);
    } else if (layer is ColorFilterLayer) {
      out.add(layer.colorFilter);
    } else if (layer is ShaderMaskLayer) {
      out
        ..add(layer.shader)
        ..add(layer.maskRect)
        ..add(layer.blendMode);
    } else if (layer is BackdropFilterLayer) {
      // `backdropKey` is read for the same reason as the other two: it reaches
      // the engine, as `SceneBuilder.pushBackdropFilter(backdropId:)`. It was
      // missing until the audit of this table against `layer.dart` (D162), and
      // it is the shape D151 already closed for alpha and for filters —
      // `RenderBackdropFilter` reuses its layer (`layer ??= BackdropFilterLayer()`)
      // and only assigns the property, so a group that re-keys mints no picture
      // anywhere. `BackdropGroup` re-keys on every rebuild it is not handed a
      // key for, which means the commonest use of the feature changes this and
      // nothing else. It has no `==`, so this compares identity, which is what
      // grouping is: two filters are in one group when they hold one key object.
      out
        ..add(layer.filter)
        ..add(layer.blendMode)
        ..add(layer.backdropKey);
    } else if (layer is LeaderLayer) {
      out
        ..add(layer.link)
        ..add(layer.offset);
    } else if (layer is AnnotatedRegionLayer) {
      // Nothing it carries reaches a pixel: the annotation is read by hit
      // testing and by the semantics tree.
    } else if (layer is ContainerLayer) {
      // A plain grouping layer: it carries nothing of its own, and the guard
      // above has already established that this is exactly `ContainerLayer` and
      // not a descendant.
    } else {
      // Unreachable unless `_exact` and the chain drift apart — a type named in
      // the set with no branch to read it. Reported as changing for the same
      // reason as everything else this file cannot read, so that the drift costs
      // retention rather than correctness.
      out.add(Object());
    }
  }
}

/// One pass over the composited tree, building the signature and, next to every
/// entry of it, the root-space bounds of what that entry composites.
///
/// Two parallel lists rather than a list of pairs, so that the comparison in
/// [ProxyLayerWatch.changeSince] stays the element-wise identity check it has
/// always been: a record with a `Rect` in it would have needed an `==` that
/// looks at the value and not at the bounds, and that is one refactor away from
/// a collision — the failure this whole mechanism exists to prevent.
///
/// A `null` bound means "composites nothing"; [anywhere] means "could be
/// anywhere". They are not the same answer and the difference decides: the
/// first is a hold, the second is a record.
class _Walk {
  _Walk(this._exclude);

  final Set<Layer> _exclude;

  final LayerSignature out = <Object?>[];
  final List<Rect?> bounds = <Rect?>[];

  /// The bound of a layer whose extent is not knowable from Dart.
  ///
  /// Compared by identity everywhere it is read, so a real rect that happens to
  /// equal `Rect.largest` cannot impersonate it.
  static final Rect anywhere = Rect.fromLTRB(
    -double.maxFinite,
    -double.maxFinite,
    double.maxFinite,
    double.maxFinite,
  );

  static Rect? union(Rect? a, Rect? b) {
    if (a == null) {
      return b;
    }
    if (b == null) {
      return a;
    }
    if (identical(a, anywhere) || identical(b, anywhere)) {
      return anywhere;
    }
    return a.expandToInclude(b);
  }

  /// Maps [rect] out of a layer's own space and through the clips above it.
  ///
  /// Returns null when nothing of it survives. An empty result is the same
  /// answer as no result: a picture with empty bounds draws nothing, and a rect
  /// entirely outside its clip is not on the screen.
  static Rect? _map(Rect rect, Matrix4 toRoot, Rect? clip) {
    final Rect mapped = MatrixUtils.transformRect(toRoot, rect);
    if (clip == null) {
      return mapped.isEmpty ? null : mapped;
    }
    final Rect inside = mapped.intersect(clip);
    return inside.isEmpty ? null : inside;
  }

  /// The clip a child sees, given this layer's clip and everything above it.
  ///
  /// Never returns null, and that is the point: `null` in this walk means
  /// *unclipped*, so handing it to a subtree whose clip fell entirely outside
  /// its parent's would widen the region instead of emptying it — the safe
  /// direction, and silently the wrong answer. `Rect.zero` is an empty clip
  /// that stays empty: nothing intersects it, so every descendant maps to
  /// nothing.
  static Rect _narrow(Rect local, Matrix4 toRoot, Rect? clip) => _map(local, toRoot, clip) ?? Rect.zero;

  /// Walks [layer], appending its entries, and returns what it composites.
  ///
  /// [toRoot] maps [layer]'s own coordinate space into the watched root's.
  /// [clip] is every clip above it, already in root space and intersected —
  /// null meaning none. [isRoot] suppresses the root's own offset, for the
  /// reason [ProxyLayerWatch.changeSince] documents.
  Rect? visit(Layer layer, Matrix4 toRoot, Rect? clip, {required bool isRoot}) {
    if (_exclude.contains(layer)) {
      return null;
    }
    // An empty stock FollowerLayer paints no pixels. Flutter 3.47 keeps one
    // mounted for a closed Material dropdown; treating it as unknown causes a
    // capture/publish loop on an otherwise idle screen. Only skip the exact
    // empty framework class: a populated follower remains conservative, and
    // its insertion/removal changes the signature on the next frame.
    if (layer.runtimeType == FollowerLayer &&
        (layer as FollowerLayer).firstChild == null) {
      return null;
    }
    final int start = out.length;
    out.add(layer.runtimeType);
    ProxyLayerWatch._describeSelf(layer, out);
    final int selfEnd = out.length;
    while (bounds.length < selfEnd) {
      bounds.add(null);
    }

    Matrix4 childTransform = toRoot;
    Rect? childClip = clip;
    Rect? own;
    // Whether this layer paints outside whatever its children cover. Two kinds
    // of layer do: a filter, which moves pixels by an amount no Dart API
    // reports, and a type the table cannot read at all. Both then answer with
    // the clip above them, which is the only honest bound left.
    var spreads = false;

    if (!ProxyLayerWatch._readable(layer)) {
      spreads = true;
    } else if (layer is PictureLayer) {
      own = _map(layer.canvasBounds, toRoot, clip);
    } else if (layer is TransformLayer) {
      // `translate(offset) * transform`, which is what `TransformLayer.addToScene`
      // hands the engine — not the other order, and it is the one place the two
      // differ visibly.
      childTransform = Matrix4.copy(toRoot)
        ..translateByDouble(layer.offset.dx, layer.offset.dy, 0, 1)
        ..multiply(layer.transform!);
    } else if (layer is ImageFilterLayer) {
      spreads = true;
    } else if (layer is OffsetLayer) {
      // Covers `OpacityLayer` too: it is an `OffsetLayer` and pushes the same
      // offset alongside its alpha.
      if (!isRoot && layer.offset != Offset.zero) {
        childTransform = Matrix4.copy(toRoot)..translateByDouble(layer.offset.dx, layer.offset.dy, 0, 1);
      }
    } else if (layer is ClipRectLayer) {
      childClip = _narrow(layer.clipRect!, toRoot, clip);
    } else if (layer is ClipRRectLayer) {
      childClip = _narrow(layer.clipRRect!.outerRect, toRoot, clip);
    } else if (layer is ClipRSuperellipseLayer) {
      childClip = _narrow(layer.clipRSuperellipse!.outerRect, toRoot, clip);
    } else if (layer is ClipPathLayer) {
      childClip = _narrow(layer.clipPath!.getBounds(), toRoot, clip);
    } else if (layer is BackdropFilterLayer) {
      // It filters what is already behind it and paints the result over the
      // whole of the current clip, so its output is the clip and its input is
      // wider than its output. Reading it as the clip covers both: anything the
      // filter could have pulled in from outside had to change *somewhere*, and
      // that somewhere has its own entry.
      spreads = true;
    } else if (layer is ShaderMaskLayer) {
      // Multiplies its children inside `maskRect` and paints nothing outside
      // them, so the children are the bound.
    } else if (layer is LeaderLayer) {
      if (layer.offset != Offset.zero) {
        childTransform = Matrix4.copy(toRoot)..translateByDouble(layer.offset.dx, layer.offset.dy, 0, 1);
      }
    }

    Rect? subtree = own;
    if (layer is ContainerLayer) {
      for (Layer? child = layer.firstChild; child != null; child = child.nextSibling) {
        subtree = union(subtree, visit(child, childTransform, childClip, isRoot: false));
      }
    }
    if (spreads) {
      // With no clip above it, a filter is dirty everywhere; under an empty one
      // it composites nothing at all, and `Rect.zero` is how [_narrow] spells
      // that. Unioning the empty rect instead would drag the region to the
      // origin, which is a dirty pixel nobody has.
      subtree = childClip == null ? anywhere : (childClip.isEmpty ? null : childClip);
    }
    out.add(ProxyLayerWatch._pop);
    bounds.add(null);
    // Patched only now: a container's own entries answer for its whole subtree,
    // because its offset is what puts the subtree where it is. The `_pop` keeps
    // a null bound — it never differs on its own, and if it does the lengths
    // differ and the walk has already said `everywhere`.
    //
    // **A layer that spreads patches its descendants too, and that took a
    // failing arm.** A blur over a repainting picture changes the picture's
    // entry and nothing else, so patching only this layer's own entries left
    // the region at the picture's tight bounds — a filtered subtree reported as
    // dirty exactly where it would have been dirty unfiltered, which is the one
    // answer that is certainly wrong.
    final int end = spreads ? out.length : selfEnd;
    for (var i = start; i < end; i++) {
      bounds[i] = subtree;
    }
    return subtree;
  }
}
