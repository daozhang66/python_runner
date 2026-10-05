// The atlas: N glass surfaces, one recording, one texture, one snapshot (D24).
//
// This is why the walk was built. `OffsetLayer.toImageSync` hands back one
// rectangle per call, so N surfaces are either N passes at `C_pass` each or one
// bounding box carrying dead area. A pass we drive ourselves is neither: one
// recording of the scene, N clipped `drawPicture` calls placing it into one
// texture, one `toImageSync`. Arrived here from `spikes/13_own_walk/` with the
// surface register (D121) as its input, which is what the roadmap means by
// "the capture's area and layout are a function of the glass surfaces and of
// nothing else" — Impeller's render target pool is keyed by size
// (`render_target_cache.cc:69-74`), so a region that moved with the content
// would miss the pool on every frame the content moved.
//
// Four things this file has to get right, and each is a separate failure:
//
//  - **Layout.** Slots must not overlap, must be aligned, and must be placed
//    deterministically — a packer whose answer depends on iteration order would
//    re-map every surface's texture coordinates on a frame where nothing moved.
//  - **Mapping.** The shader samples the proxy by screen coordinate, so the
//    screen -> atlas map has to be exact. Off by one device pixel and the glass
//    refracts the wrong pixels, which looks like a quality setting rather than
//    like a bug.
//  - **Bleed.** A blur reads outside the surface, and whatever it reads has to
//    be real content rather than the neighbouring slot — which is one texel
//    away by construction. How much context that takes is [bleedFor], and it is
//    measured rather than assumed.
//  - **Merging**, which is a lever wherever atlas area is charged — and that
//    is every family measured. See [pack], and the gate it used to have.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'proxy_resolution.dart';

/// One surface's place in the atlas.
@immutable
class AtlasSlot {
  const AtlasSlot({
    required this.index,
    required this.members,
    required this.source,
    required this.rect,
    required this.pixelRatio,
  });

  /// Position in the slot list. Stable for a given input, and what a shader's
  /// uniform block is indexed by.
  final int index;

  /// Which input surfaces sample from this slot.
  ///
  /// More than one when merging is on. That is not a detail: on the corpus's
  /// clustered scenes an atlas of one slot per surface pays for the overlap
  /// between neighbours as many times as they overlap, and a merged slot pays
  /// once.
  final List<int> members;

  /// What is captured for it: [surface] inflated by the blur's support and
  /// snapped outward to the atlas's texel grid ([snapToTexels]).
  final Rect source;

  /// Where it lands in the atlas texture, in device pixels. Origin and size are
  /// both aligned; see [AtlasLayout.align].
  final Rect rect;

  final double pixelRatio;

  /// Screen (logical) point to atlas texel. The map a shader needs, and the one
  /// the pixel test checks by comparing against a separate capture.
  Offset toAtlas(Offset screenPoint) => (screenPoint - source.topLeft) * pixelRatio + rect.topLeft;

  /// The three numbers a fragment shader needs to sample this slot: where its
  /// source starts on screen, where its slot starts in the texture, and the
  /// scale between them. Kept as a record rather than a uniform block because
  /// this spike has no shader — the point is that the map is three numbers and
  /// not a per-pixel search.
  ({Offset srcOrigin, Offset atlasOrigin, double scale}) get uniforms =>
      (srcOrigin: source.topLeft, atlasOrigin: rect.topLeft, scale: pixelRatio);
}

/// N surfaces packed into one texture.
@immutable
class AtlasLayout {
  const AtlasLayout({
    required this.slots,
    required this.size,
    required this.pixelRatio,
    required this.bleed,
    required this.align,
  });

  final List<AtlasSlot> slots;

  /// Texture size in device pixels.
  final Size size;

  final double pixelRatio;

  /// Logical pixels of context captured beyond each surface, for the blur.
  ///
  /// [bleedFor] turns a finish's sigma into this number.
  final double bleed;

  /// Device-pixel grid every slot origin and size is a multiple of.
  ///
  /// Not padding, and not a gutter: it is the *downscale factor* of the blur.
  /// D11 chose an explicit reduction pass over `textureLod` (which does not
  /// select a level on Vulkan at all), and a reduction by 2^k that lands on
  /// aligned boundaries reads each output texel from exactly one slot. A gutter
  /// would cost area and still bleed; alignment costs at most `align - 1` texels
  /// per side and cannot bleed. Measured in `atlas_test.dart`.
  final int align;

  /// Whether this atlas can be rasterized on a GPU whose textures stop at
  /// [maxTextureSide] device pixels a side (D186).
  ///
  /// **Asked because the engine does not refuse, it rescales — silently, and
  /// then lies about it.** `Picture.toImageSync` on Impeller reaches
  /// `DoMakeRasterSnapshot`, which computes
  /// `scale = min(1, max_side / width, max_side / height)` and multiplies the
  /// render target by it when it is below 1
  /// (`shell/common/snapshot_controller_impeller.cc:32-50`, with the comment
  /// "Exceeding the max would otherwise cause a null result"). The image that
  /// comes back reports the size that was *asked for* —
  /// `DlDeferredImageGPUImpeller::GetSize()` returns the wrapper's own
  /// `size_`, not the texture's
  /// (`lib/ui/painting/display_list_deferred_image_gpu_impeller.cc:88`) — so
  /// nothing downstream can notice. [AtlasSlot.uniforms] would keep handing the
  /// shader a map into an atlas that no longer exists at that scale, and every
  /// surface would sample the wrong part of the screen: not a black frame and
  /// not an exception, but a plausible-looking refraction of the wrong
  /// backdrop.
  ///
  /// Shell Skia fails the other way and is no better: `toImageSync` there
  /// cannot allocate the texture and leaves an error on the image
  /// (`shell/common/rasterizer.cc:405-413`), which `drawImage` turns into an
  /// exception but a shader sampler never reads (`fragment_shader.cc:63-93`) —
  /// so the glass samples nothing (D195). One backend loses the map, the other
  /// loses the frame; neither says so to the code that would notice.
  ///
  /// So the size of the atlas is a quantity the pipeline has to keep inside a
  /// bound itself. It has exactly one lever for that — the texel scale — and
  /// [GlassProxyPipeline] is where it gets pulled, because this class has no
  /// lever at all: refusing here would drop a surface, which is the one outcome
  /// [pack] must not have.
  bool fitsTexture(int maxTextureSide) => size.width <= maxTextureSide && size.height <= maxTextureSide;

  /// How much context beyond a surface a blur of [sigmaLogical] needs, in
  /// logical pixels — **measured**, not taken from the usual "three sigma".
  ///
  /// The instrument is the question itself: crop a region inflated by `b`,
  /// blur it, and compare the result *inside the surface* against the blur of
  /// the whole screen, which is the ideal the proxy is standing in for. The
  /// worst case is a full-contrast step just outside the surface's edge, and
  /// the corpus for it is one: 0 → 255 at four logical pixels out, with bars
  /// elsewhere so no crop has a uniform neighbourhood.
  ///
  /// What it says, in worst code values inside the surface, at `TileMode.clamp`
  /// (which is what the rig uses — a `decal` proxy darkens its own border, and
  /// the border of a proxy is the screen edge, where half the corpus puts its
  /// surfaces):
  ///
  /// | bleed | sigma 2.6 | sigma 8 |
  /// |---|---|---|
  /// | 0 | 29 | 86 |
  /// | 1.0σ | 6 | 9 |
  /// | 1.5σ | 6 | 3 |
  /// | 2.0σ | 0 | 1 |
  /// | 2.5σ | 0 | 0 |
  ///
  /// So **2.5σ** is where a full-contrast step stops showing at all, and the
  /// zero at the top of the table is the arm that says this is not a nicety: a
  /// frosted surface with no bleed is wrong by a third of the range at its own
  /// edge. `decal` needs half a sigma more for the same error.
  ///
  /// ⚠️ **That measurement is Skia's kernel**, because it was taken under
  /// `flutter_tester`. Impeller truncates its own at
  /// `(ScaleSigma(sigma) - 0.5) · sqrt(3)` — `kKernelRadiusPerSigma` is exactly
  /// `sqrt(3)` (`impeller/geometry/sigma.h:24`, `sigma.cc:12`) — which is 1.6σ
  /// at sigma 8 and *narrower* than what is measured here. So this constant
  /// covers both backends, and it covers them from the wider side.
  static double bleedFor(double sigmaLogical) => 2.5 * sigmaLogical;

  /// The bleed a proxy recorded at a divisor needs, which is not the finish's
  /// own sigma.
  ///
  /// Recording at 1/k is itself a low-pass worth `0.30` logical px of sigma per
  /// texel (D117), and it composes with the finish's blur in quadrature — so
  /// the total sigma the proxy will carry is larger than the finish asked for
  /// and the context it needs is larger with it. Both halves are measured; this
  /// is the one line that puts them together.
  static double bleedForResolution(
    double finishSigmaLogical,
    ProxyResolution resolution,
    double devicePixelRatio,
  ) {
    final double delivered = resolution.deliveredSigmaLogical(devicePixelRatio);
    return bleedFor(math.sqrt(finishSigmaLogical * finishSigmaLogical + delivered * delivered));
  }

  /// Shelf packing, deterministic by construction.
  ///
  /// Tallest first, then widest, then input order — the tie-breakers exist so
  /// that two frames with the same surfaces produce the same atlas. They do
  /// *not* make the layout stable when a surface resizes: that reshuffles
  /// everything below it on the shelf, and it is left open on purpose (see the
  /// finding).
  /// [merge] is a *request*: a candidate merge is taken only when the packed
  /// atlas gets strictly smaller ([_mergeGreedy]).
  ///
  /// **There used to be a `ProxyCostModel` gate here, and it guarded a budget
  /// the criterion never spends.** The merge was honoured under `areaCharged`
  /// alone, on the reading that its budget was the capture's dead area,
  /// `C_pass / k` (D20), and that neither constant exists for Metal or for
  /// unknown hardware. But the criterion prices every candidate by packing it
  /// with `passes: 1` — one `toImageSync` for the whole atlas, whatever the
  /// grouping — so `C_pass` is the same on both sides of every comparison and
  /// `k` scales both sides alike: the decision is "did the packed area fall",
  /// and the constants cancel out of it exactly. Checked by inverting the
  /// price (`proxy_atlas_test.dart`). A gate on "we do not know `C_pass / k`"
  /// was therefore a gate on a number the code did not read.
  ///
  /// What the gate actually decided was whether area is charged at all, and on
  /// every family measured it is: the capture on Adreno (D28), 58% of the
  /// route on Metal (D128), the recording end to end on Xclipse (D134). So a
  /// merge that shrinks the atlas is a saving everywhere, and it was being
  /// declined precisely on the family that cannot declare itself — an
  /// `unmeasured` host got two slots where one fits, which is 38% of the atlas
  /// on `over_photo` (D135) — on top of a full-resolution proxy from the other
  /// refusal. The two multiplied (D136).
  ///
  /// What a merge does change everywhere is the number of clipped replays
  /// inside the one recording, and nobody has priced those; it changes it
  /// downward, which is the safe direction.
  ///
  /// [fused] is the one thing here that is not an optimisation. Surfaces whose
  /// silhouettes are blended into one shape have to be sampled in one
  /// coordinate system, so a blend group is *required* to share a slot — the
  /// one-way invariant of §4.4, and the reason the two kinds of grouping are
  /// named apart. [merge] still runs over the result and may put a blend group
  /// together with anything else; what it may not do is take one apart.
  ///
  /// [classes] is the other constraint on the merge, in the opposite
  /// direction: one entry per surface, and surfaces of different classes never
  /// share a slot. A class is a blur — the pass blurs each slot by its own
  /// surfaces' sigma — so a merged slot would have to be blurred twice at once.
  static AtlasLayout pack(
    List<Rect> surfaces, {
    double pixelRatio = 1.0,
    double bleed = 0,
    int align = 1,
    int shelfWidth = 2048,
    int? maxTextureSide,
    bool merge = false,
    List<List<int>>? grouping,
    List<List<int>>? fused,
    List<int>? classes,
  }) {
    assert(align >= 1);
    assert(pixelRatio > 0);
    assert(classes == null || classes.length == surfaces.length);
    assert(grouping == null || !merge, 'a fixed grouping is the answer merging would compute');
    assert(
      grouping == null || fused == null,
      'a held grouping already contains whatever the blend groups forced into it',
    );
    assert(_disjoint(fused, surfaces.length));

    var groups = fused == null
        ? <_Group>[
            for (var i = 0; i < surfaces.length; i++)
              _Group(<int>[i], snapToTexels(surfaces[i].inflate(bleed), pixelRatio)),
          ]
        : _seed(fused, surfaces, bleed, pixelRatio);
    if (grouping != null) {
      // Membership decided elsewhere and held — the retained case. Recomputing
      // the merge every frame costs more than the pass it serves (D41), so the
      // grouping outlives the rectangles it was computed from.
      groups = <_Group>[
        for (final List<int> members in grouping)
          _Group(
            members,
            members
                .map((int i) => snapToTexels(surfaces[i].inflate(bleed), pixelRatio))
                .reduce((Rect a, Rect b) => a.expandToInclude(b)),
          ),
      ];
    } else if (merge) {
      groups = _mergeGreedy(groups, pixelRatio, align, shelfWidth, maxTextureSide, classes);
    }

    final _Placement placement = _place(groups, pixelRatio, align, shelfWidth);
    return AtlasLayout(
      slots: <AtlasSlot>[
        for (var i = 0; i < groups.length; i++)
          AtlasSlot(
            index: i,
            members: groups[i].members,
            source: groups[i].source,
            rect: placement.rects[i],
            pixelRatio: pixelRatio,
          ),
      ],
      size: placement.size,
      pixelRatio: pixelRatio,
      bleed: bleed,
      align: align,
    );
  }

  /// The size [pack] would return for these arguments, without building the
  /// layout.
  ///
  /// Exists because the ceiling search in [GlassProxyPipeline] runs on every
  /// captured frame and needs one number out of a packing, not a layout: the
  /// slots it would allocate are thrown away, and a per-frame allocation of
  /// N groups and N slots for a question answered by two integers is the kind
  /// of cost that does not show up in any single profile and is there in all of
  /// them. Deliberately **unmerged** — the search needs an upper bound on what
  /// the retained atlas will pack, and a merge only ever lowers it
  /// ([_mergeGreedy] refuses the candidates that would not).
  static Size probeSize(
    List<Rect> surfaces, {
    double pixelRatio = 1.0,
    double bleed = 0,
    int align = 1,
    int shelfWidth = 2048,
    List<List<int>>? fused,
  }) {
    assert(align >= 1);
    assert(pixelRatio > 0);
    assert(_disjoint(fused, surfaces.length));
    final List<_Group> groups = fused == null
        ? <_Group>[
            for (var i = 0; i < surfaces.length; i++)
              _Group(<int>[i], snapToTexels(surfaces[i].inflate(bleed), pixelRatio)),
          ]
        : _seed(fused, surfaces, bleed, pixelRatio);
    return _place(groups, pixelRatio, align, shelfWidth).size;
  }

  /// The groups a blend grouping starts the packer from: one per blend group,
  /// one per surface nobody claimed.
  ///
  /// Ordered by first member so that the packer's tie-breaker — which reads
  /// `members.first` — sees the same list for the same input whatever order the
  /// groups registered in.
  static List<_Group> _seed(
    List<List<int>> fused,
    List<Rect> surfaces,
    double bleed,
    double pixelRatio,
  ) {
    final claimed = <int>{for (final List<int> group in fused) ...group};
    final groups = <_Group>[
      for (final List<int> group in fused)
        _Group(
          List<int>.of(group)..sort(),
          group
              .map((int i) => snapToTexels(surfaces[i].inflate(bleed), pixelRatio))
              .reduce((Rect a, Rect b) => a.expandToInclude(b)),
        ),
      for (var i = 0; i < surfaces.length; i++)
        if (!claimed.contains(i)) _Group(<int>[i], snapToTexels(surfaces[i].inflate(bleed), pixelRatio)),
    ];
    return groups..sort((_Group a, _Group b) => a.members.first.compareTo(b.members.first));
  }

  /// Whether a blend grouping names each surface at most once and names nothing
  /// that is not there.
  ///
  /// A surface in two blend groups is not a layout that got worse, it is a
  /// question with no answer — its fragments belong to two silhouettes — so
  /// this refuses rather than picking one.
  static bool _disjoint(List<List<int>>? fused, int count) {
    if (fused == null) {
      return true;
    }
    final seen = <int>{};
    for (final List<int> group in fused) {
      for (final int i in group) {
        if (i < 0 || i >= count || !seen.add(i)) {
          return false;
        }
      }
    }
    return true;
  }

  /// Shelf packing, deterministic by construction.
  ///
  /// Tallest first, then widest, then input order — the tie-breakers exist so
  /// that two frames with the same surfaces produce the same atlas. They do
  /// *not* make the layout stable when a surface resizes: that reshuffles
  /// everything below it on the shelf, and it is left open on purpose.
  static _Placement _place(List<_Group> groups, double pixelRatio, int align, int shelfWidth) {
    final sizes = <({int w, int h})>[
      for (final _Group g in groups)
        (
          w: _alignUp(texelSpan(g.source.width, pixelRatio), align),
          h: _alignUp(texelSpan(g.source.height, pixelRatio), align),
        ),
    ];
    final order = List<int>.generate(groups.length, (int i) => i)
      ..sort((int a, int b) {
        final int byHeight = sizes[b].h.compareTo(sizes[a].h);
        if (byHeight != 0) {
          return byHeight;
        }
        final int byWidth = sizes[b].w.compareTo(sizes[a].w);
        if (byWidth != 0) {
          return byWidth;
        }
        return groups[a].members.first.compareTo(groups[b].members.first);
      });

    // A slot wider than the shelf gets its own shelf and widens the atlas
    // rather than being dropped: losing a surface silently is the one outcome
    // this must not have. That is right for a *packing preference* and it is
    // what [shelfWidth] is; it would be catastrophic for a hardware limit,
    // which is why the two are different parameters now (see [fitsTexture]).
    final int effectiveWidth = sizes.isEmpty
        ? shelfWidth
        : math.max(shelfWidth, sizes.map((s) => s.w).reduce(math.max));

    final rects = List<Rect>.filled(groups.length, Rect.zero);
    var cursorX = 0;
    var shelfY = 0;
    var shelfHeight = 0;
    var usedWidth = 0;
    for (final int i in order) {
      final s = sizes[i];
      if (cursorX + s.w > effectiveWidth && cursorX > 0) {
        shelfY += shelfHeight;
        cursorX = 0;
        shelfHeight = 0;
      }
      rects[i] = Rect.fromLTWH(
        cursorX.toDouble(),
        shelfY.toDouble(),
        s.w.toDouble(),
        s.h.toDouble(),
      );
      cursorX += s.w;
      usedWidth = math.max(usedWidth, cursorX);
      shelfHeight = math.max(shelfHeight, s.h);
    }
    return _Placement(
      rects,
      Size(usedWidth.toDouble(), (shelfY + shelfHeight).toDouble()),
    );
  }

  /// Greedy merging, decided on the **packed** atlas rather than on the slot
  /// rectangles.
  ///
  /// The obvious rule is pairwise: merge when `C_pass` buys more than the dead
  /// area the union adds, which is M2's dead-area budget (`C_pass / k`, ~102
  /// thousand device pixels on Adreno at heavy content) applied to two
  /// rectangles. It is wrong, and the corpus says so: on `over_animation` it
  /// merges and the atlas gets 5% *dearer*, because the unmerged layout's own
  /// packing waste was already paying part of what the merge would save. So the
  /// candidate is packed and priced, and only a real reduction is taken. At
  /// twelve surfaces that is at most twelve rounds of sixty-six packings of
  /// twelve rectangles, which is nothing.
  ///
  /// The price is the packed area in device pixels and nothing else. It was
  /// written as `CaptureCost(passes: 1, area).cycles()`, which is the same
  /// ordering — one pass on every candidate, so the constant cancels and the
  /// slope is positive — dressed as a cost model it did not depend on. Stated
  /// bare so that nobody gates it on those constants again.
  ///
  /// [maxTextureSide] makes the criterion **lexicographic**: a candidate over
  /// the ceiling is priced at infinity, so fitting comes first and area second.
  /// That is not the same as declining such candidates, and the difference is
  /// visible in both directions — a merge that *costs* area is now taken when
  /// it is what brings the atlas under the limit, and the same merge is still
  /// declined when the unmerged layout already fits.
  ///
  /// It also buys the lemma the divisor search rests on. If the unmerged layout
  /// fits, the starting price is finite; every merge taken is strictly cheaper
  /// than the price before it, so it is finite too, so it fits. **An unmerged
  /// pack that fits is therefore a guarantee about the merged one** — which is
  /// what lets [GlassProxyPipeline] choose a divisor from [probeSize] without
  /// paying for the merge to find out.
  static List<_Group> _mergeGreedy(
    List<_Group> groups,
    double pixelRatio,
    int align,
    int shelfWidth,
    int? maxTextureSide,
    List<int>? classes,
  ) {
    double priceOf(List<_Group> candidate) {
      final Size size = _place(candidate, pixelRatio, align, shelfWidth).size;
      if (maxTextureSide != null && (size.width > maxTextureSide || size.height > maxTextureSide)) {
        return double.infinity;
      }
      return size.width * size.height;
    }

    var current = List<_Group>.of(groups);
    var price = priceOf(current);
    while (current.length > 1) {
      List<_Group>? best;
      var bestPrice = price;
      for (var i = 0; i < current.length; i++) {
        for (var j = i + 1; j < current.length; j++) {
          // A slot is blurred as one, so two surfaces blurred differently can
          // never share one — whatever the merge would save.
          if (classes != null && classes[current[i].members.first] != classes[current[j].members.first]) {
            continue;
          }
          final candidate = <_Group>[
            for (var k = 0; k < current.length; k++)
              if (k != i && k != j) current[k],
            _Group(
              <int>[...current[i].members, ...current[j].members]..sort(),
              current[i].source.expandToInclude(current[j].source),
            ),
          ];
          final double p = priceOf(candidate);
          if (p < bestPrice) {
            bestPrice = p;
            best = candidate;
          }
        }
      }
      if (best == null) {
        break;
      }
      current = best;
      price = bestPrice;
    }
    // Sorted by first member so the result does not depend on merge order.
    current.sort((a, b) => a.members.first.compareTo(b.members.first));
    return current;
  }

  /// Records the atlas: one clipped, translated replay of [scene] per slot.
  ///
  /// [scene] is the whole walked subtree, recorded **once**. That is the shape
  /// the CPU cost of this route has: one tree walk regardless of N, and N GPU
  /// replays each clipped to its own slot — which is the cost we wanted to pay,
  /// since the clip is what makes a replay cost its slot's area rather than the
  /// screen's (`canvas.cc:2307`).
  /// [jitter] displaces one slot's *content* without moving its rectangle — the
  /// negative control. Without it the pixel test would pass for any map that is
  /// merely self-consistent, and self-consistency is not what a shader needs.
  ui.Picture record(
    ui.Picture scene, {
    Offset Function(AtlasSlot)? jitter,
    bool clipToSource = false,
  }) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & size);
    for (final AtlasSlot slot in slots) {
      final Offset shift = jitter?.call(slot) ?? Offset.zero;
      final Rect clip = clipToSource
          ? Rect.fromLTWH(
              slot.rect.left,
              slot.rect.top,
              texelSpan(slot.source.width, pixelRatio).toDouble(),
              texelSpan(slot.source.height, pixelRatio).toDouble(),
            )
          : slot.rect;
      canvas
        ..save()
        ..clipRect(clip)
        ..translate(slot.rect.left + shift.dx, slot.rect.top + shift.dy)
        ..scale(pixelRatio)
        ..translate(-slot.source.left, -slot.source.top)
        ..drawPicture(scene)
        ..restore();
    }
    return recorder.endRecording();
  }

  /// Device pixels the slots occupy.
  double get slotArea => slots.fold(0, (double a, AtlasSlot s) => a + s.rect.width * s.rect.height);

  /// Device pixels the texture holds but no slot uses — the atlas's own waste,
  /// which is what has to be compared against a bounding box's dead area rather
  /// than against zero.
  double get waste => size.width * size.height - slotArea;

  /// What one capture of the enclosing rectangle would have cost, in device
  /// pixels, and how much of it no surface needs. The alternative D24 is against.
  ({double area, double dead}) get boundingBoxRoute {
    if (slots.isEmpty) {
      return (area: 0, dead: 0);
    }
    final Rect bounds = slots.map((AtlasSlot s) => s.source).reduce((Rect a, Rect b) => a.expandToInclude(b));
    final double area = texelSpan(bounds.width, pixelRatio) * texelSpan(bounds.height, pixelRatio).toDouble();
    return (area: area, dead: area - slotArea);
  }

  static int _alignUp(int value, int align) => ((value + align - 1) ~/ align) * align;
}

@immutable
class _Group {
  const _Group(this.members, this.source);

  final List<int> members;
  final Rect source;
}

@immutable
class _Placement {
  const _Placement(this.rects, this.size);

  final List<Rect> rects;
  final Size size;
}

/// What the three routes cost, on M2's measured constants.
///
/// Arithmetic, not measurement — and the constants belong to one device
/// (SM-S938B / Adreno 830) and to the sides the fit was taken on. It is here so
/// the corpus's real surface rectangles decide the comparison instead of the
/// two round numbers D24 was written with.
@immutable
class CaptureCost {
  const CaptureCost({required this.passes, required this.areaDevicePx});

  final int passes;
  final double areaDevicePx;

  /// `C_pass` from M2, heavy content, Adreno 830.
  static const double cPass = 27600;

  /// Marginal cycles per device pixel: flat content and heavy content.
  static const double kFlat = 0.198;
  static const double kHeavy = 0.271;

  double cycles({double k = kHeavy}) => passes * cPass + k * areaDevicePx;
}

/// [r] snapped outward to the grid of texels at [pixelRatio] per logical pixel.
///
/// The grid, not whole logical pixels, which is what this was until a phone
/// with a fractional density ran the identity arm: at dpr 1.875 a slot starting
/// at logical 100 starts at device 187.5, so every texel of the slot straddles
/// two screen pixels and the bilinear tap averages them — 9682 px of a still
/// identity glass differing by up to 72 code values on the S908B, where dpr 2
/// and 3 had read zero because a whole logical pixel is a whole device pixel
/// there. On the grid a texel's centre is a screen pixel's centre at divisor 1,
/// and the start of a block of them at any other.
///
/// A millionth of a texel of tolerance each way, because the edges arrive as
/// products of the layout's own floats: a left edge one ULP under a grid line
/// would otherwise take a whole extra texel.
Rect snapToTexels(Rect r, double pixelRatio) {
  const double e = 1e-6;
  return Rect.fromLTRB(
    (r.left * pixelRatio + e).floorToDouble() / pixelRatio,
    (r.top * pixelRatio + e).floorToDouble() / pixelRatio,
    (r.right * pixelRatio - e).ceilToDouble() / pixelRatio,
    (r.bottom * pixelRatio - e).ceilToDouble() / pixelRatio,
  );
}

/// How many texels [logical] spans at [pixelRatio], for a length that
/// [snapToTexels] put on the grid: `(R - L) / p * p` comes back a ULP either
/// side of the integer it was, and a plain `ceil` turns the ULP above into a
/// whole row.
int texelSpan(double logical, double pixelRatio) => (logical * pixelRatio - 1e-6).ceil();
