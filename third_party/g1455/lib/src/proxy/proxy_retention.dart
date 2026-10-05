// Holding the atlas layout still between frames.
//
// The atlas leaves this as a question about *quality*: shelf packing is
// deterministic for a given input, but one surface changing size reshuffles
// everything below it, and a proxy whose texture coordinates move on a frame
// where nothing else did is a rewrite of the whole atlas.
//
// The measurement turned it into a question about *price*, which is a different
// and sharper thing (D41). The merge criterion evaluates a candidate by packing it,
// so twelve surfaces cost 173…187 us of greedy search — twice the walk the
// atlas serves and seven times the rest of the route put together. Recomputing
// it per frame is not an inefficiency, it is the dominant cost.
//
// So retention has two halves, and they fail differently:
//
//  - **Membership is held.** The grouping outlives the rectangles it was
//    computed from. Cheap, and wrong only slowly: surfaces drift apart and a
//    merge that made sense stops making sense.
//  - **Placement is held.** A slot keeps its rectangle while the content still
//    fits in it. A surface that only *moves* fits by construction — the map is
//    `source.topLeft -> rect.topLeft`, so translation is free. Only growth
//    forces a repack.
//
// Arrived from `spikes/13_own_walk/` with the atlas it retains.

import 'package:flutter/rendering.dart';

import 'proxy_atlas.dart';

/// Why an update did or did not repack. Named rather than counted: "how often"
/// is useless without "on account of what".
enum RetentionOutcome {
  /// Nothing to retain yet.
  first,

  /// The set of surfaces changed, so the held grouping no longer describes it.
  membership,

  /// A group outgrew its slot.
  grew,

  /// The blend grouping changed, so the held slots no longer cover it.
  blend,

  /// The surfaces' blur classes changed, so a held slot may now mix two.
  blur,

  /// Slots kept, sources re-pointed.
  kept,
}

/// An atlas layout that survives frames.
class RetainedAtlas {
  RetainedAtlas({
    required this.pixelRatio,
    required this.bleed,
    required this.align,
    this.slack = 0,
    this.shelfWidth = 2048,
    this.maxTextureSide,
  });

  final double pixelRatio;
  final double bleed;
  final int align;

  /// Logical pixels of headroom given to every slot when it is packed, on top
  /// of [bleed].
  ///
  /// Bought area against repacks. Not the same thing as bleed even though it is
  /// added the same way: bleed is captured content the blur needs, slack is
  /// slot the content does not use yet. The slot is sized with it and the
  /// source is not, which is what leaves room to grow into.
  final double slack;

  /// The packer's preferred shelf width. A slot wider than this widens the
  /// atlas rather than being dropped — it is a preference, not a limit.
  final int shelfWidth;

  /// The hardware's own limit, which is not a preference
  /// ([AtlasLayout.fitsTexture]). Held only so a repack cannot merge its way
  /// over it; the layout that comes back is still the caller's to check,
  /// because retention has no lever on the texel scale either.
  final int? maxTextureSide;

  // There was a `ProxyCostModel model` here, held so that a repack merged
  // under the same model as the first pack. The gate it fed is gone from
  // [AtlasLayout.pack] — the merge criterion never read the model's constants
  // (D136) — and with it the only thing this retained.

  AtlasLayout? _layout;
  List<List<int>>? _grouping;

  /// The blend grouping the held layout was packed under.
  ///
  /// Held for the same reason the membership is, and compared for a different
  /// one: a merge that stops paying is wrong slowly, but a blend group that
  /// changed and kept the old slots is wrong on the next frame — its members
  /// would be sampling a slot that no longer covers all of them.
  List<List<int>>? _fused;

  /// The blur classes the held layout was packed under. A changed class is
  /// wrong on the next frame for the reason a changed blend group is.
  List<int>? _classes;

  int updates = 0;
  int repacks = 0;

  /// Slots whose rectangle moved between one update and the next.
  ///
  /// The quantity that matters to a shader: a moved slot invalidates its
  /// uniforms and its texels, and a repack usually moves all of them.
  int slotsMoved = 0;

  AtlasLayout? get layout => _layout;

  ({AtlasLayout layout, RetentionOutcome outcome}) update(
    List<Rect> surfaces, {
    List<List<int>>? fused,
    List<int>? classes,
  }) {
    updates++;
    _pendingClasses = classes;
    final AtlasLayout? previous = _layout;
    if (previous == null) {
      return _repackWith(surfaces, fused, previous, RetentionOutcome.first);
    }
    final List<List<int>>? grouping = _grouping;
    if (grouping == null || _memberCount(grouping) != surfaces.length) {
      return _repackWith(surfaces, fused, previous, RetentionOutcome.membership);
    }
    if (!_sameGrouping(_fused, fused)) {
      return _repackWith(surfaces, fused, previous, RetentionOutcome.blend);
    }
    if (!_sameClasses(_classes, classes)) {
      return _repackWith(surfaces, fused, previous, RetentionOutcome.blur);
    }

    final kept = <AtlasSlot>[];
    for (final AtlasSlot slot in previous.slots) {
      final Rect source = _sourceOf(slot.members, surfaces, bleed);
      if (_alignUp(texelSpan(source.width, pixelRatio), align) > slot.rect.width ||
          _alignUp(texelSpan(source.height, pixelRatio), align) > slot.rect.height) {
        return _repackWith(surfaces, fused, previous, RetentionOutcome.grew);
      }
      kept.add(
        AtlasSlot(
          index: slot.index,
          members: slot.members,
          source: source,
          rect: slot.rect,
          pixelRatio: pixelRatio,
        ),
      );
    }
    _layout = AtlasLayout(
      slots: kept,
      size: previous.size,
      pixelRatio: pixelRatio,
      bleed: bleed,
      align: align,
    );
    return (layout: _layout!, outcome: RetentionOutcome.kept);
  }

  ({AtlasLayout layout, RetentionOutcome outcome}) _repackWith(
    List<Rect> surfaces,
    List<List<int>>? fused,
    AtlasLayout? previous,
    RetentionOutcome outcome,
  ) {
    repacks++;
    // Packed with the slack so the slots have room; sources rewritten tight so
    // the room is actually free. Keeping the padded rect as the source would
    // make the slack cancel out — it would be captured content rather than
    // headroom, which is the mistake this pair of lines exists to avoid.
    final AtlasLayout padded = AtlasLayout.pack(
      surfaces,
      pixelRatio: pixelRatio,
      bleed: bleed + slack,
      align: align,
      shelfWidth: shelfWidth,
      maxTextureSide: maxTextureSide,
      merge: true,
      fused: fused,
      classes: _pendingClasses,
    );
    _classes = _pendingClasses == null ? null : List<int>.of(_pendingClasses!);
    _fused = fused == null ? null : <List<int>>[for (final List<int> group in fused) List<int>.of(group)];
    _grouping = <List<int>>[for (final AtlasSlot slot in padded.slots) List<int>.of(slot.members)];
    _layout = AtlasLayout(
      slots: <AtlasSlot>[
        for (final AtlasSlot slot in padded.slots)
          AtlasSlot(
            index: slot.index,
            members: slot.members,
            source: _sourceOf(slot.members, surfaces, bleed),
            rect: slot.rect,
            pixelRatio: pixelRatio,
          ),
      ],
      size: padded.size,
      pixelRatio: pixelRatio,
      bleed: bleed,
      align: align,
    );
    slotsMoved += _movedBetween(previous, _layout!);
    return (layout: _layout!, outcome: outcome);
  }

  /// Whether two blend groupings are the same set of groups.
  ///
  /// Compared as lists rather than by identity: the host builds a fresh one
  /// every frame out of a register, so identity would repack every frame and
  /// the retention would be a counter that never fires.
  static bool _sameGrouping(List<List<int>>? a, List<List<int>>? b) {
    if (a == null || b == null) {
      return a == null && b == null;
    }
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i].length != b[i].length) {
        return false;
      }
      for (var j = 0; j < a[i].length; j++) {
        if (a[i][j] != b[i][j]) {
          return false;
        }
      }
    }
    return true;
  }

  List<int>? _pendingClasses;

  static bool _sameClasses(List<int>? a, List<int>? b) {
    if (a == null || b == null) {
      return a == null && b == null;
    }
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

  static int _memberCount(List<List<int>> grouping) => grouping.fold(0, (int a, List<int> g) => a + g.length);

  Rect _sourceOf(List<int> members, List<Rect> surfaces, double bleed) => members
      .map((int i) => snapToTexels(surfaces[i].inflate(bleed), pixelRatio))
      .reduce((Rect a, Rect b) => a.expandToInclude(b));

  static int _alignUp(int value, int align) => ((value + align - 1) ~/ align) * align;
}

/// Slots that changed rectangle between two layouts, matched by membership.
///
/// A group that disappeared counts as moved, because whatever sampled it has to
/// be told something.
int _movedBetween(AtlasLayout? before, AtlasLayout after) {
  if (before == null) {
    return 0;
  }
  final was = <String, Rect>{
    for (final AtlasSlot slot in before.slots) slot.members.join(','): slot.rect,
  };
  var moved = 0;
  for (final AtlasSlot slot in after.slots) {
    final Rect? old = was[slot.members.join(',')];
    if (old == null || old != slot.rect) {
      moved++;
    }
  }
  return moved;
}

/// Device pixels the slots' *sources* actually need, as against the area the
/// atlas allocates for them.
///
/// The price of retention, and the only one it has: a slot held across frames is
/// as large as the content that was in it when it was packed.
double usefulArea(AtlasLayout layout) => layout.slots.fold(0, (double a, AtlasSlot slot) {
  final int w = texelSpan(slot.source.width, layout.pixelRatio);
  final int h = texelSpan(slot.source.height, layout.pixelRatio);
  return a + w * h;
});
