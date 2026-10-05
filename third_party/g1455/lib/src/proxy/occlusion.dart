// Stopping the descent at an opaque cover: the one culling the engine does not
// do for us.
//
// `Overlay` skips entries below an opaque route (`overlay.dart:892-913`) and
// nothing else does: a modal sheet is not marked opaque, so the page under it is
// painted in full — into the real frame, and into any proxy we record. M9
// measured that the hardware does not save us either: an opaque backing over a
// translucent surface costs its own area and returns nothing on Adreno 830, in
// five scenes and two seeds. So work under an opaque cover is paid for twice and
// culled by nobody.
//
// Three things have to be true for a walk to cut it, and each is a separate
// failure:
//
//  - **The cover has to be recognisable.** Opacity is not a property a
//    `RenderObject` publishes. What can be read is named below, and what cannot
//    is the more interesting half — it is why `GlassProxy.opaque` exists.
//  - **The cut has to be in paint order, and a top-down walk learns paint order
//    too late.** So the plan is built from `visitChildren` order and the walk
//    *checks* it: every child arrives at `paintChild` whether it is skipped or
//    not, so the true order is fully observable, and a pass whose order did not
//    match is invalid rather than wrong.
//  - **The cut has to be invisible.** A culled pass that differs from the
//    uncut one by a single code value is not an optimisation.

import 'package:flutter/rendering.dart';

import 'proxy_role.dart';
import 'proxy_walk.dart';

/// The escape hatch that stands in for a declaration.
///
/// `Overlay.opaque` is the framework's own version of this: the widget says it
/// covers, because nothing downstream can tell. A package needs the same, and
/// the reason is in [opaqueLocalRect] below.
typedef CoverDeclaration = bool Function(RenderObject node);

/// The node's own opaque rectangle, in its local coordinates, or null when
/// nothing public says it has one.
///
/// A [declared] node contributes its `paintBounds` and **still goes through the
/// geometry**: a declaration says "this paints opaquely over itself", not "this
/// covers the region". Letting it skip the geometry was a real defect here —
/// every `ColoredBox` in a tree would have become a full-screen cover.
///
/// **Two types, and that is the whole list.** `RenderDecoratedBox.decoration`
/// and `_RenderPhysicalModelBase.color` are public getters on public classes.
/// The commonest opaque widget in Flutter is not on the list: `ColoredBox` —
/// which is what `Container(color:)` and every plain background lower to —
/// paints through `_RenderColoredBox` (`widgets/basic.dart:8430`), a **private**
/// class, so its colour is unreadable from outside `widgets`. That is not an
/// oversight to work around; it is why the declaration above exists.
Rect? opaqueLocalRect(RenderObject node, {CoverDeclaration? declared}) {
  if (declared != null && declared(node)) {
    return node.paintBounds;
  }
  // The same declaration with a widget in front of it. [declared] is a callback
  // that has to recognise a node from the outside; `GlassProxy.opaque` is the
  // app saying it where the widget is, which is the only place that knows.
  if (node is RenderGlassProxy) {
    switch (node.role) {
      case GlassProxyRole.opaque:
        return node.paintBounds;
      case GlassProxyRole.replace:
        // A stub that claims opacity covers exactly its own box: `paintProxy`
        // clips it there, so the claim cannot reach further than the geometry.
        return (node.painter?.isOpaque ?? false) ? node.paintBounds : null;
      case GlassProxyRole.hidden:
      case GlassProxyRole.verbatim:
        return null;
    }
  }
  if (node is RenderDecoratedBox) {
    if (node.position != DecorationPosition.background) {
      return null;
    }
    final Decoration decoration = node.decoration;
    if (decoration is! BoxDecoration) {
      return null;
    }
    final Color? color = decoration.color;
    // Anything that can let light through disqualifies it, and so does a shape
    // that does not fill its own rectangle: a border radius takes the corners
    // out, and the corners are exactly where a covered pixel would survive.
    if (color == null ||
        color.a < 1.0 ||
        decoration.image != null ||
        decoration.gradient != null ||
        decoration.shape != BoxShape.rectangle ||
        (decoration.borderRadius != null && decoration.borderRadius != BorderRadius.zero) ||
        decoration.backgroundBlendMode != null) {
      return null;
    }
    return node.paintBounds;
  }
  if (node is RenderPhysicalModel) {
    if (node.color.a < 1.0 ||
        node.shape != BoxShape.rectangle ||
        (node.borderRadius != null && node.borderRadius != BorderRadius.zero)) {
      return null;
    }
    return node.paintBounds;
  }
  return null;
}

/// The clip a parent imposes on a child, and — separately — whether that answer
/// is exact.
///
/// **`describeApproximatePaintClip` is a superset by contract, which is the
/// unsafe direction here, and it cost a fixture.** Its documentation says
/// "approximate bounding box of the clip rect" and names its purpose: the
/// semantics phase, which wants to *avoid dropping* a visible child
/// (`object.dart:3749-3757`). Over-reporting a clip is free there and fatal
/// here — intersecting a cover with a superset over-states coverage, and
/// over-stating coverage is how a cull deletes content. Measured: a
/// `CustomClipper<Rect>` that clips to half the screen reports the whole box,
/// because `getApproximateClipRect` defaults to `Offset.zero & size`
/// (`proxy_box.dart:1426,1567`), and the first version of this file read that
/// half-screen clipper as a full-screen cover.
///
/// So the value is used only where it is provably the true clip:
///
///  - `RenderClipRect` is asked exactly, through the clipper's own `getClip`.
///  - The rest of the `_RenderCustomClip` family — `RenderClipRRect`,
///    `RenderClipOval`, `RenderClipPath`, and both physical models, which
///    extend it (`proxy_box.dart:2062`) — is refused: there is no public way to
///    ask a rounded or arbitrary shape for the largest rectangle inside it.
///  - Anything else reporting exactly its own paint bounds is taken at its
///    word. That is the framework's "I clip to myself" idiom — `RenderStack`
///    (`stack.dart:748`), `RenderFlex` (`flex.dart:1476`), the overlay's own
///    theatre (`overlay.dart:1583`) — and `RenderViewport` returns that or
///    *less* (`viewport.dart:902-930`), which is the safe direction.
///
/// **The residual risk, named rather than papered over:** a render object
/// outside that family that clips to less than its own box while reporting the
/// box violates nothing in the documented contract, and this would over-cull
/// under it. The backstop is the pixel comparison, which is run on every
/// fixture and every scene of the corpus.
({bool known, Rect? clip}) paintClipOf(RenderObject parent, RenderObject child) {
  final Rect? approximate = parent.describeApproximatePaintClip(child);
  if (approximate == null) {
    return (known: true, clip: null);
  }
  if (parent is RenderClipRect) {
    if (parent.clipBehavior == Clip.none) {
      return (known: true, clip: null);
    }
    return (
      known: true,
      clip: parent.clipper?.getClip(parent.size) ?? Offset.zero & parent.size,
    );
  }
  if (parent is RenderClipRRect ||
      parent is RenderClipOval ||
      parent is RenderClipPath ||
      parent is RenderPhysicalModel ||
      parent is RenderPhysicalShape) {
    return (known: false, clip: null);
  }
  if (approximate == parent.paintBounds) {
    return (known: true, clip: approximate);
  }
  return (known: false, clip: null);
}

/// Where a node's opaque rectangle lands in [root]'s coordinates, after every
/// clip between them, or null when the question cannot be answered safely.
///
/// Refuses on anything but a pure translation. A rotated or scaled cover is
/// still a cover, but `MatrixUtils.transformRect` would hand back a *bounding
/// box*, which over-states coverage. Refusing costs a missed optimisation;
/// guessing costs pixels.
Rect? coverInRoot(RenderObject node, RenderObject root, {CoverDeclaration? declared}) {
  Rect? rect = opaqueLocalRect(node, declared: declared);
  if (rect == null) {
    return null;
  }
  RenderObject current = node;
  while (!identical(current, root)) {
    final RenderObject? parent = current.parent;
    if (parent == null) {
      return null;
    }
    final transform = Matrix4.identity();
    parent.applyPaintTransform(current, transform);
    final Offset? translation = MatrixUtils.getAsTranslation(transform);
    if (translation == null) {
      return null;
    }
    rect = rect!.shift(translation);
    final ({bool known, Rect? clip}) clip = paintClipOf(parent, current);
    if (!clip.known) {
      return null;
    }
    if (clip.clip != null) {
      rect = rect.intersect(clip.clip!);
      if (rect.isEmpty) {
        return null;
      }
    }
    current = parent;
  }
  return rect;
}

/// Which subtrees are painted before the last opaque cover of a region, and
/// therefore invisible in a capture of it.
class OcclusionPlan {
  OcclusionPlan._(
    this._enter,
    this._exit,
    this.cover,
    this.coverIndex,
    this.nodes,
    this.opaqueNodes,
    this.largestOpaque,
  );

  /// Builds the plan from `visitChildren`, which is cheap — no foreign `paint`
  /// runs here — and is *not* guaranteed to be paint order. The mismatch is
  /// what [OcclusionPolicy.orderViolations] exists to catch.
  factory OcclusionPlan.of(RenderObject root, Rect region, {CoverDeclaration? declared}) {
    final enter = <RenderObject, int>{};
    final exit = <RenderObject, int>{};
    var index = 0;
    RenderObject? cover;
    var coverIndex = -1;
    var opaqueNodes = 0;
    Rect? largestOpaque;

    void visit(RenderObject node) {
      final int own = index++;
      enter[node] = own;
      final Rect? opaque = coverInRoot(node, root, declared: declared);
      if (opaque != null) {
        // Diagnostics, not mechanism: "no cover" and "no opaque rectangle at
        // all" are different findings about a scene, and without these two the
        // report cannot tell them apart.
        opaqueNodes++;
        final double area = opaque.width * opaque.height;
        if (largestOpaque == null || area > largestOpaque!.width * largestOpaque!.height) {
          largestOpaque = opaque;
        }
        if (opaque.containsRect(region) && own > coverIndex) {
          cover = node;
          coverIndex = own;
        }
      }
      node.visitChildren(visit);
      exit[node] = index - 1;
    }

    visit(root);
    return OcclusionPlan._(enter, exit, cover, coverIndex, index, opaqueNodes, largestOpaque);
  }

  final Map<RenderObject, int> _enter;
  final Map<RenderObject, int> _exit;

  /// The last node in visit order that opaquely covers the region, or null.
  final RenderObject? cover;

  final int coverIndex;

  /// Render objects in the subtree, so a saving can be quoted as a share.
  final int nodes;

  /// Nodes that paint *some* opaque rectangle, whether or not it spans the
  /// region, and the biggest one in root coordinates.
  final int opaqueNodes;
  final Rect? largestOpaque;

  bool get hasCover => cover != null;

  /// A subtree is dead iff all of it is painted before the cover.
  bool isOccluded(RenderObject node) {
    if (coverIndex < 0) {
      return false;
    }
    final int? end = _exit[node];
    return end != null && end < coverIndex;
  }

  int? visitIndexOf(RenderObject node) => _enter[node];

  /// How many nodes the cut removes, if paint order agrees with visit order.
  int get occludedNodes => coverIndex < 0 ? 0 : coverIndex;
}

/// The walk policy that applies a plan, and the check that says whether it was
/// allowed to.
///
/// The check is the point. A plan built from `visitChildren` assumes each
/// parent paints its children in that order, and `RenderViewport` alone is
/// enough to make that false in general (`childrenInPaintOrder`). But the walk
/// sees the truth: `paintChild` is called for every child, skipped or not, so
/// the observed sequence of visit indices must be strictly increasing. It is
/// one integer compare per node, it works in profile — no assert, no
/// `debugLayer` — and a pass that fails it is discarded rather than trusted,
/// which is the structural fallback D37 asks for.
class OcclusionPolicy {
  OcclusionPolicy(this.plan, {this.inner = paintEverything, this.enabled = true});

  final OcclusionPlan plan;

  /// What to do with a node the cull does not remove. The mandatory skips of
  /// step 2 compose here rather than replacing this.
  final WalkPolicy inner;

  /// Off, to measure the same walk without the cut. The negative control lives
  /// here rather than in a second code path.
  final bool enabled;

  int occludedNodes = 0;
  int orderViolations = 0;
  int _lastIndex = -1;

  /// Whether the pass this policy drove may be used.
  bool get valid => orderViolations == 0;

  WalkAction call(RenderObject child) {
    final int? index = plan.visitIndexOf(child);
    if (index == null) {
      // A node the plan never saw. The tree changed between the plan and the
      // pass, which is not something to paper over.
      orderViolations++;
    } else {
      if (index <= _lastIndex) {
        orderViolations++;
      }
      _lastIndex = index;
    }
    if (enabled && index != null && plan.isOccluded(child)) {
      occludedNodes++;
      return WalkAction.skip;
    }
    return inner(child);
  }
}

extension on Rect {
  /// `Rect.contains` takes a point; the cover has to hold the whole region.
  bool containsRect(Rect other) =>
      left <= other.left && top <= other.top && right >= other.right && bottom >= other.bottom;
}
