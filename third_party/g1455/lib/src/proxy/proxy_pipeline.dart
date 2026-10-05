// The proxy pipeline, assembled: register -> resolution -> atlas -> one walk ->
// one texture.
//
// Every piece of this has existed and been measured on its own since M12, and
// none of them had ever run in the same frame. That is what phase A is for —
// the roadmap's words are "expose the integration problems the spikes cannot
// reach" — and the assembly is where the pieces stop being independent:
//
//  - the **register** (D121) decides the geometry, because Impeller's render
//    target pool is keyed by size and a region that follows the content misses
//    it on every frame the content moves (D115);
//  - the **resolution policy** (D120) decides the texel scale, from the finish,
//    the screen's density and the hardware — and on Metal it decides not to
//    lower it at all (D119);
//  - the **atlas** (D24) decides the layout, and its bleed is a function of the
//    finish's blur *and* of the divisor, because a divisor is itself a blur
//    (D117, D122);
//  - the **walk** (M12) does the drawing, subtracting what the roles and the
//    occlusion plan say to subtract;
//  - **retention** (D41) is what keeps the previous four from being recomputed
//    every frame, which would cost more than the pass they serve.
//
// What is deliberately *not* here is the finish and the shader. The pipeline
// produces the proxy and the map into it; blurring it and refracting through it
// is the surface's job, and the budget puts that last at 9% (D63). The sigma is
// an input all the same, because the bleed has to be sized for a blur that has
// not happened yet.
//
// **The one structural assumption, and it is checked rather than trusted:** the
// atlas replays *one picture* N times, so the walk has to produce exactly one.
// It does, by construction — `ProxyWalkContext` overrides every route that
// would append a layer and puts the effect on the canvas instead — but "by
// construction" is how a defect survives a refactor, so the assembly counts the
// picture layers and refuses rather than taking the first.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../hardware.dart';
import '../surface/glass_finish.dart';
import '../surface/glass_group.dart';
import '../surface/glass_surface.dart';
import 'occlusion.dart';
import 'proxy_atlas.dart';
import 'proxy_layer_watch.dart';
import 'proxy_resolution.dart';
import 'proxy_retake.dart';
import 'proxy_retention.dart';
import 'proxy_walk.dart';
import 'shadow_filter.dart';

/// The pass's own policy: never draw a glass surface into the proxy.
///
/// Mandatory rather than an optimisation — it is the self-capture rule, and
/// `WalkAction.skip` names it in its own documentation. A surface draws the
/// proxy, so a surface inside the proxy is last frame's proxy inside this
/// frame's, and the feedback compounds. The whole subtree goes, not just the
/// surface: what sits *on* a nav bar is on top of the glass, not behind it.
///
/// **A blend group draws glass too, and it took a failing arm to notice.** The
/// rule is about the *draw*, not about the type that used to be the only one
/// making it: a `RenderGlassGroup` paints the fused shape itself, so a group
/// left in the walk puts last frame's glass into this frame's proxy. It showed
/// up as a group of one disagreeing with a lone surface by up to 39 code
/// values, which reads exactly like a shader that drifted — and the two
/// programs were byte-identical all along.
///
/// **And the rule stays about the draw when the ladder turns the draw off.** A
/// surface below [GlassTier.full] paints a flat fill and reads nothing, so it
/// is not capturing itself — it is ordinary content, and a neighbour's glass
/// has to show it. `excludedFromProxy` is that predicate, said once and read by
/// both machines that need it: this walk, and the layer watch that decides
/// whether the proxy is stale. Two copies of it would be two copies that drift.
WalkAction skipGlassSurfaces(RenderObject child) {
  if (child is RenderGlassSurface) {
    return child.excludedFromProxy ? WalkAction.skip : WalkAction.paint;
  }
  if (child is RenderGlassGroup) {
    return child.group.excludedFromProxy ? WalkAction.skip : WalkAction.paint;
  }
  return WalkAction.paint;
}

/// One frame of proxy: the texture, and the map from the screen into it.
class GlassProxyFrame {
  GlassProxyFrame._({
    required this.image,
    required this.layout,
    required this.resolution,
    required this.log,
    required this.retention,
    required this.keys,
  });

  /// The atlas texture. Owned by the caller: dispose it or leak it.
  final ui.Image image;

  final AtlasLayout layout;

  /// What the resolution policy chose, and why.
  final ProxyResolutionChoice resolution;

  /// What the pass observed. The counters that say whether a marker fired, a
  /// layer went unhandled, or a foreign construct was substituted.
  final WalkLog log;

  /// Whether this frame repacked, and on account of what.
  final RetentionOutcome retention;

  /// What the surfaces were, in the order this frame indexed them.
  ///
  /// Identity rather than position, and the difference is not academic: the
  /// register is a set, a surface that mounts between two captures shifts every
  /// index after it, and a frame is by construction one frame old. Without this
  /// a newly arrived panel would sample the slot belonging to whoever used to
  /// be at its index — a backdrop from somewhere else on the screen, which
  /// looks like a plausible refraction rather than like a bug.
  final List<Object> keys;

  /// The slot a surface samples from, by its index in the register's order.
  AtlasSlot slotFor(int surface) => layout.slots.firstWhere((AtlasSlot slot) => slot.members.contains(surface));

  /// The slot for the surface itself, or null when this frame does not know it.
  ///
  /// Null is the honest answer for a surface that arrived after the capture,
  /// and the caller's job is to draw nothing rather than to draw a neighbour's
  /// backdrop.
  AtlasSlot? slotForKey(Object key) {
    final int index = keys.indexOf(key);
    if (index < 0) {
      return null;
    }
    for (final AtlasSlot slot in layout.slots) {
      if (slot.members.contains(index)) {
        return slot;
      }
    }
    return null;
  }

  /// The three numbers a fragment shader needs for a surface: where its source
  /// starts on screen, where its slot starts in the texture, and the scale
  /// between them.
  ({Offset srcOrigin, Offset atlasOrigin, double scale}) uniformsFor(int surface) => slotFor(surface).uniforms;

  void dispose() => image.dispose();
}

/// How the residual blur reaches the atlas.
///
/// One axis rather than two booleans, because the three values are three
/// spellings of one decision and the fourth combination ("no blur, folded")
/// does not exist. [none] is here for the same reason [split] is: it is an arm
/// of a measurement, not a mode a surface may ship in.
enum ProxyBlurPass {
  /// Two snapshots: rasterize the packed atlas, then draw that image back
  /// through `ImageFilter.blur` into a second one. What D140 and D141 measured,
  /// and what every recorded number about the pass is a number about.
  split,

  /// One snapshot: the filter rides on a `saveLayer` inside the atlas picture,
  /// so the rasterization that packs the slots also blurs them.
  ///
  /// The reason to want it is in the engine rather than in the kernel:
  /// `DisplayListToTexture` builds a **fresh** `RenderTargetAllocator` per call
  /// and says why — "Do not use the render target cache as the lifecycle of
  /// this texture will outlive a particular frame"
  /// (`dl_dispatcher.cc:1228-1233`) — so the second snapshot is an atlas-sized
  /// MSAA target allocated outside the pool on every frame, and the Gaussian is
  /// only part of what it costs. Measured pixel for pixel against [split] on
  /// Skia (spike #21): worst 1 code value on all four divisors, mean 0.041 at
  /// the largest sigma and 0.134 at the smallest, which is the round trip
  /// through eight bits that [split] takes and this does not.
  ///
  /// **Its price is now measured on both families, and they disagree in sign**,
  /// which is why the default is [defaultFor] rather than a constant. On Metal
  /// the fold is 17.4% *dearer* (D145) and the engine says why: a `SaveLayer`
  /// carrying an image filter cannot take the collapse peephole and allocates
  /// its own MSAA target (`display_list/canvas.cc:1902,147-193`), so what the
  /// fold removes is one `toImageSync` *call* and not one render pass. On
  /// Adreno it is **cheaper** — 9.1% and 17.1% of the addition at the divisor
  /// the policy picks, and worth 57% and 70% more frames at full resolution,
  /// where the split arm sits off vsync. The mechanism offered for the flip
  /// beforehand (a tiler pays less for MSAA) does **not** survive: Apple
  /// silicon is tile-based too. What the data shows beside the sign is that at
  /// full resolution the fold raises the GPU's busy fraction from 0.424 to
  /// 0.621 while producing 57% more frames, so it is removing a stall and not
  /// only work — but no mechanism is claimed.
  folded,

  /// No blur at all. Draws a wrong picture by construction, and exists so the
  /// pass can be subtracted from the route's price (D140).
  ///
  /// **Except at a finish of sigma zero**, where there is no residual to blur
  /// and this is what the pipeline does anyway — so a `clear` finish already
  /// takes the single-snapshot path and gets nothing from [folded].
  none;

  /// The pass a host of [hardware] gets when it does not name one.
  ///
  /// Keyed on the declaration rather than fixed, because the sign is measured
  /// on both families and differs: Metal is 17.4% better on [split] (D145),
  /// Adreno 9.1…17.1% of the addition better on [folded]. The two spellings
  /// draw the same picture to within a code value (spike #21), so a wrong guess
  /// here costs cycles and never pixels — which is what makes it safe to key on
  /// a declaration at all, and is exactly the property the resolution policy
  /// lacked when the same shape of gate cost it D135.
  ///
  /// Everything that is not Apple gets Adreno's answer, and that is an
  /// extrapolation from one GPU: Xclipse has never run this axis, and neither
  /// has a desktop Impeller target. It is the *pulled* end of a lever whose
  /// sign is measured on the family that matters most for this package (D136),
  /// and its worst case is the 17.4% Metal measured in the other direction.
  static ProxyBlurPass defaultFor(GlassHardware hardware) => hardware == GlassHardware.appleMetal ? split : folded;
}

/// Runs the proxy pipeline for one screen.
///
/// Not a widget and not a render object: it is driven by whoever owns the
/// frame, which for now is a test and later is the surface host. Holding it
/// across frames is the point — [RetainedAtlas] is inside it, and a pipeline
/// rebuilt every frame would repack every frame, which D41 measured as the
/// dominant cost of the whole route.
class GlassProxyPipeline {
  GlassProxyPipeline({
    required this.finishSigmaLogical,
    this.hardware = GlassHardware.unmeasured,
    this.finish = 'regularDark',
    this.align = 1,
    this.slack = 0,
    this.shelfWidth = 2048,
    int? maxTextureSide,
    this.shadowFilter,
    this.occlusion,
    ProxyBlurPass? blurPass,
    this.damageBudgetDeltaE = ProxyResolutionPolicy.defaultDamageBudgetDeltaE,
    this.pinnedResolution,
  }) : blurPass = blurPass ?? ProxyBlurPass.defaultFor(hardware),
       maxTextureSide = maxTextureSide ?? hardware.maxTextureSide;

  /// The divisor the host named, or null to let the policy pick one.
  ///
  /// See [ProxyDivisorReason.pinnedByHost]: the route's price is known at two
  /// divisors on one platform, and a third point cannot come from a chooser
  /// whose job is to return the best divisor rather than an unpriced one.
  final ProxyResolution? pinnedResolution;

  /// The blur the finish will apply, in logical pixels. Decides the bleed and,
  /// with it, how much of the screen each slot holds.
  final double finishSigmaLogical;

  /// The whole quality allowance, in ΔE against the same finish at full
  /// quality — the one the divisor is chosen against.
  ///
  /// The same number the retake oracle is given, and it has to be: D124
  /// measured that damage on two axes composes rather than adds, so the two are
  /// drawing on one allowance. For one release this was not passed at all and
  /// the policy used its own default, which meant a host that raised or lowered
  /// its budget moved the staleness ceiling and not the resolution — half an
  /// effect, and silent.
  final double damageBudgetDeltaE;

  /// Whose measurements apply. Decides what the chosen divisor is *priced* at
  /// ([ProxyResolutionChoice.routeCostFactor]) and nothing about the choice
  /// itself: for one release it also decided whether the divisor and the merge
  /// were levers at all, and a host that declared nothing got a full-resolution,
  /// unmerged atlas larger than its screen (D135, D136).
  final GlassHardware hardware;

  /// Key into the measured damage table, for the resolution policy.
  final String finish;

  /// Device-pixel grid every slot is aligned to.
  ///
  /// 1 is right for a blur applied to the atlas in one pass: the bleed is
  /// already at least the blur's support, so a pixel a surface samples cannot
  /// reach its neighbour's slot. It stops being right when the blur becomes a
  /// **reduction** pass (D11), because a reduction block straddling two slots
  /// mixes them at the reduced resolution and no amount of bleed prevents that;
  /// there the alignment has to be the reduction factor (D39).
  final int align;

  /// Logical pixels of headroom given to each slot on top of the bleed, so a
  /// surface that grows a little does not force a repack.
  final double slack;

  /// The packer's preferred shelf width — a layout preference, exceeded rather
  /// than enforced ([AtlasLayout.pack]).
  final int shelfWidth;

  /// The largest texture the GPU will actually give us, in device pixels a
  /// side. Not a preference: past it the engine rescales the snapshot and says
  /// nothing ([AtlasLayout.fitsTexture]).
  ///
  /// Defaults to [GlassHardware.maxTextureSide], which is a specification floor
  /// rather than a reading of the device. Raising it is how a host that knows
  /// its GPU buys back the quality the ceiling would otherwise spend.
  final int maxTextureSide;

  /// Frames on which the ceiling moved the divisor, and how many steps deep it
  /// had to go in total.
  ///
  /// Counted rather than logged because the alternative to counting is
  /// believing: the ceiling fires on a geometry nobody set up on purpose — one
  /// oversized sheet on a desktop-sized window — so a test that asserts it
  /// never fires is worth as much as the counter that says it did not.
  int get ceilingDeepenings => _ceilingDeepenings;
  int _ceilingDeepenings = 0;
  int get ceilingSteps => _ceilingSteps;
  int _ceilingSteps = 0;

  /// Frames on which even [_maxCeilingSteps] of deepening did not fit, and no
  /// proxy was produced at all.
  ///
  /// Refusing is the last resort and it is loud by construction — every surface
  /// shows no glass rather than the wrong backdrop — but it is still a refusal,
  /// so it is counted separately from the deepenings that worked.
  int get ceilingRefusals => _ceilingRefusals;
  int _ceilingRefusals = 0;

  /// Frames the *search* passed and the packed atlas failed anyway — which is
  /// to say, frames on which the lemma the search rests on was wrong.
  ///
  /// **Expected to be zero for the life of this package**, and counted for
  /// exactly that reason. Two mechanisms can drop an oversized frame: the
  /// search, which fixes it, and the check after the pack, which only refuses.
  /// An arm that asserts "an impossible ceiling produces no frame" is satisfied
  /// by either of them and therefore distinguishes neither — the rule this
  /// project keeps is that a mechanism subsuming another has to be visible as
  /// such. This counter is how: it stays at zero while the search is right, and
  /// deliberately breaking the search (swap the comparison in [_fitToTexture]
  /// for `false && ...`) moves it, which is what says the backstop is a
  /// backstop rather than dead code.
  int get ceilingOverruns => _ceilingOverruns;
  int _ceilingOverruns = 0;

  /// How far the search may deepen before it gives up.
  ///
  /// Termination does not rest on this: a slot's texel size falls as
  /// `w * dpr / k` while its bleed contributes `2.5 * 0.30 * k / dpr * dpr / k`,
  /// a constant 0.75 texels a side, so the atlas shrinks monotonically towards
  /// a floor of about `align + 2` texels per slot. The bound is here so that a
  /// wrong ceiling — a host declaring 64, say — fails as a refusal in bounded
  /// time instead of as a loop.
  static const int _maxCeilingSteps = 32;

  final ShadowFilter? shadowFilter;

  /// How the proxy is blurred before the surfaces sample it.
  ///
  /// One blur over the whole atlas rather than one per slot, and the bleed is
  /// what makes that correct: every pixel a surface samples has at least the
  /// blur's own support of real content inside its own slot (D122), so no
  /// slot's blur can reach its neighbour's.
  ///
  /// The sigma asked for is the **residual**, not the finish's own: recording
  /// at 1/k is itself a low-pass worth 0.30 logical px of sigma per texel and
  /// the two compose in quadrature (D117), so blurring by the whole sigma
  /// over-blurs. ⚠️ D118 measured that correcting it is not uniformly an
  /// improvement — it wins up to 34% on smooth scenes and loses up to 7% on
  /// text — and the package corrects anyway, on the argument that a finish
  /// calibrated at 2.6 should render 2.6.
  final ProxyBlurPass blurPass;

  /// Where the descent may stop. Computed by the caller, because it is a
  /// property of the tree rather than of the pipeline.
  final OcclusionPolicy? occlusion;

  RetainedAtlas? _retained;
  double? _retainedScale;
  double? _retainedBleed;

  /// The layout the last frame used, or null before the first.
  AtlasLayout? get layout => _retained?.layout;

  /// How many times the layout has been repacked, and how many slots that
  /// moved. The two numbers retention exists to keep small.
  int get repacks => _retained?.repacks ?? 0;
  int get slotsMoved => _retained?.slotsMoved ?? 0;

  /// Whether [change] can have altered a pixel that is actually in the proxy.
  ///
  /// The exact question, and it is exact rather than heuristic: `AtlasLayout.record`
  /// replays the one recorded picture into each slot under that slot's own
  /// clip, so a pixel of the atlas comes from inside some slot's [AtlasSlot.source]
  /// and from nowhere else. A change that misses every source misses every
  /// texel, whatever else it did to the screen.
  ///
  /// Refuses in every direction it cannot answer in: an unbounded change, and a
  /// pipeline that has not packed a layout yet.
  ///
  /// **What it does not decide is whether the surfaces moved.** That is the
  /// oracle's own input (`noteSurfaces`), it runs whatever this returns, and it
  /// is why comparing against the *retained* layout is sound rather than a
  /// frame behind: a layout that no longer describes the surfaces is a layout
  /// whose frame is being re-recorded anyway.
  bool capturedAreaTouchedBy(LayerChange change) {
    final AtlasLayout? packed = _retained?.layout;
    if (packed == null) {
      return true;
    }
    // One atlas device pixel of slack, and it is not caution. `record` clips in
    // *destination* space to `slot.rect`, whose size is
    // `ceil(source.size * pixelRatio)` — so the source range that actually
    // reaches the texture runs up to `1 / pixelRatio` logical pixels past
    // `source.right` and `source.bottom`. At the divisor the policy picks on a
    // dpr-3 screen that is 2.7 logical pixels, which is a strip wide enough for
    // a change to hide in and a picture to go stale over.
    final double slack = packed.pixelRatio > 0 ? 1 / packed.pixelRatio : 0;
    for (final AtlasSlot slot in packed.slots) {
      if (change.touches(slot.source.inflate(slack))) {
        return true;
      }
    }
    return false;
  }

  GlassProxyFrame? _current;

  /// The frame [captureIfNeeded] is holding, if any.
  ///
  /// Owned by the pipeline, unlike the one [capture] hands back. The two are
  /// not to be mixed on one pipeline: whichever of them made a frame is the one
  /// that has to dispose it.
  GlassProxyFrame? get current => _current;

  /// Records only when [oracle] says the proxy is worth re-recording, and holds
  /// the previous frame otherwise.
  ///
  /// This is the whole loop: the oracle sees the surfaces move, the markers
  /// fire and the ceiling arrive; everything it cannot see the application
  /// declares with `noteChange`. The reason comes back with the frame because
  /// "it held" and "it re-recorded" are different events for whoever is
  /// counting, and a policy that quietly re-records every frame looks exactly
  /// like one that works.
  ({GlassProxyFrame? frame, RetakeReason reason}) captureIfNeeded(
    RenderObject root,
    List<Rect> surfaces, {
    required double devicePixelRatio,
    required RetakeOracle oracle,
    List<Object>? keys,
    List<List<int>>? fused,
    List<GlassFinish>? finishes,
    Offset rootOffset = Offset.zero,
    Rect? sceneBounds,
    List<Rect>? watched,
  }) {
    // [watched] when glass stands on glass: the levels above are recorded on
    // this decision, so the oracle has to see their surfaces move too.
    oracle.noteSurfaces(watched ?? surfaces);
    final RetakeReason reason = oracle.decide();
    if (reason.holds) {
      oracle.noteFrame();
      return (frame: _current, reason: reason);
    }
    final GlassProxyFrame? frame = capture(
      root,
      surfaces,
      devicePixelRatio: devicePixelRatio,
      keys: keys,
      fused: fused,
      finishes: finishes,
      rootOffset: rootOffset,
      sceneBounds: sceneBounds,
    );
    if (frame == null) {
      oracle.noteFrame();
      return (frame: _current, reason: reason);
    }
    _current?.dispose();
    _current = frame;
    // What the divisor cost comes out of the same allowance staleness draws on
    // (D124), and it is only knowable here: the density arrives with the frame.
    oracle.noteResolutionDamage(frame.resolution.damage?.deltaE ?? 0);
    oracle.noteCapture(watched ?? surfaces);
    return (frame: frame, reason: reason);
  }

  /// Drops the held frame. Nothing else here owns anything.
  void dispose() {
    _current?.dispose();
    _current = null;
  }

  /// Records one frame of proxy for [surfaces], or null when there is nothing
  /// to record.
  ///
  /// [surfaces] is the register's own list — `ledger.surfaces.map((r) => r.rect)`
  /// — and the surface indices in [GlassProxyFrame] are indices into it.
  GlassProxyFrame? capture(
    RenderObject root,
    List<Rect> surfaces, {
    required double devicePixelRatio,
    List<Object>? keys,
    List<List<int>>? fused,
    List<GlassFinish>? finishes,
    Offset rootOffset = Offset.zero,
    Rect? sceneBounds,
    WalkPolicy glass = skipGlassSurfaces,
  }) {
    assert(keys == null || keys.length == surfaces.length);
    assert(finishes == null || finishes.length == surfaces.length);
    if (surfaces.isEmpty) {
      return null;
    }
    final _Blurs blurs = _Blurs.of(finishes, finish, finishSigmaLogical);
    final ProxyResolution? pinned = pinnedResolution;
    final ProxyResolutionChoice asked = pinned != null
        ? ProxyResolutionPolicy.pin(
            pinned,
            finish: finish,
            devicePixelRatio: devicePixelRatio,
            costModel: hardware.captureCostModel,
          )
        : _strictest(blurs, devicePixelRatio);
    final ProxyResolutionChoice? fitted = _fitToTexture(
      asked,
      surfaces,
      fused,
      devicePixelRatio,
      blurs.maxSigma,
    );
    if (fitted == null) {
      return null;
    }
    final ProxyResolutionChoice resolution = fitted;
    final double scale = resolution.resolution.ratioFor(devicePixelRatio);
    // Sized for the blurriest finish present: a slot of a sharper one holds
    // more context than it needs, which costs area and never a pixel.
    final double bleed = AtlasLayout.bleedForResolution(
      blurs.maxSigma,
      resolution.resolution,
      devicePixelRatio,
    );

    // A change of scale is a change of every slot's size, so the retained
    // layout cannot survive it. Rebuilt rather than repacked: `RetainedAtlas`
    // holds its pixel ratio as a constant, and pretending otherwise would keep
    // slots sized for a texel that no longer exists. The bleed likewise, which
    // moves when the blurriest finish on the screen does.
    if (_retained == null || _retainedScale != scale || _retainedBleed != bleed) {
      _retained = RetainedAtlas(
        pixelRatio: scale,
        bleed: bleed,
        align: align,
        slack: slack,
        shelfWidth: shelfWidth,
        maxTextureSide: maxTextureSide,
      );
      _retainedScale = scale;
      _retainedBleed = bleed;
    }
    final ({AtlasLayout layout, RetentionOutcome outcome}) update = _retained!.update(
      surfaces,
      fused: fused,
      classes: blurs.classes,
    );
    // The search above reasons about the layout this one will be; this asks it.
    // The reasoning is sound — an unmerged pack that fits bounds the merged one
    // (`AtlasLayout._mergeGreedy`), and a retained slot was packed under the
    // same bound — but the cost of it being wrong is not a slow frame, it is
    // every surface sampling the wrong backdrop with nothing anywhere saying
    // so. A dropped frame is the loud version of the same failure, and this is
    // the one place that can still choose which one happens.
    if (!update.layout.fitsTexture(maxTextureSide)) {
      _ceilingOverruns++;
      return null;
    }
    final handle = LayerHandle<OffsetLayer>()..layer = OffsetLayer();
    final log = WalkLog();
    try {
      final context = ProxyWalkContext(
        handle.layer!,
        sceneBounds ?? _boundsOf(root),
        log: log,
        policy: (RenderObject child) {
          // The two policies compose in the safe direction: whatever either of
          // them subtracts is subtracted. The occlusion plan is about geometry
          // and this one is about identity, and neither can be expressed in
          // the other's terms.
          final WalkAction occluded = occlusion?.call(child) ?? WalkAction.paint;
          return occluded == WalkAction.paint ? glass(child) : occluded;
        },
        shadowFilter: shadowFilter,
      )..paintChild(root, rootOffset);
      context.finish();

      final ui.Picture scene = _singlePictureOf(handle.layer!);
      final ui.Picture packed = update.layout.record(scene);
      // The folded arm draws the packed atlas once more, inside a layer that
      // carries the filter. One extra `Picture` object and no extra
      // rasterization — `drawPicture` splices the ops in — against one whole
      // snapshot saved.
      final ui.Picture atlas = _folded(
        packed,
        update.layout,
        scale,
        resolution.resolution,
        devicePixelRatio,
        blurs,
      );
      try {
        return GlassProxyFrame._(
          image: _blurred(
            _snapshot(
              atlas,
              update.layout.size.width.ceil(),
              update.layout.size.height.ceil(),
            ),
            scale,
            resolution.resolution,
            devicePixelRatio,
            update.layout,
            blurs,
          ),
          layout: update.layout,
          resolution: resolution,
          log: log,
          retention: update.outcome,
          keys: keys == null ? List<Object>.generate(surfaces.length, (int i) => i) : List<Object>.of(keys),
        );
      } finally {
        if (!identical(atlas, packed)) {
          atlas.dispose();
        }
        packed.dispose();
      }
    } finally {
      handle.layer = null;
    }
  }

  /// Every rasterization the route asks the engine for, counted.
  ///
  /// The trace [ProxyBlurPass] would otherwise not have: `split` and `folded`
  /// draw the same picture at the same divisor with the same sigma, so a run
  /// that recorded only the label would be saying "we asked for the fold". Two
  /// per published proxy on `split`, one on `folded` and on `none`.
  /// The divisor the quality walk asked for, deepened until the atlas it packs
  /// fits in a texture — or null when no divisor does.
  ///
  /// **Re-derived from the policy's own answer on every frame, holding no
  /// state.** The alternative was remembering the deepened divisor so the
  /// search could be skipped, and it buys a defect rather than time: a sheet
  /// that opens and closes would leave the proxy permanently coarser than the
  /// budget allows, because nothing would ever ask to go back. What that
  /// costs instead is one [AtlasLayout.probeSize] per frame — a sort and a
  /// single pass over at most twelve rectangles, against the 173…187 us the
  /// merge costs when retention lets it run (D41) — and the search is exact
  /// rather than hysteretic.
  ///
  /// The probe is unmerged and the real atlas is merged, which is the right
  /// direction: a merge is taken only when the packed area falls and never when
  /// the result would break the ceiling, so a layout that fits unmerged fits
  /// merged. Retention's held layouts inherit the same bound, a kept slot being
  /// by definition one that was packed under it.
  ProxyResolutionChoice? _fitToTexture(
    ProxyResolutionChoice asked,
    List<Rect> surfaces,
    List<List<int>>? fused,
    double devicePixelRatio,
    double sigma,
  ) {
    for (var step = 0; step <= _maxCeilingSteps; step++) {
      final resolution = ProxyResolution.divisor(asked.resolution.divisor + step);
      final Size size = AtlasLayout.probeSize(
        surfaces,
        pixelRatio: resolution.ratioFor(devicePixelRatio),
        bleed: AtlasLayout.bleedForResolution(sigma, resolution, devicePixelRatio) + slack,
        align: align,
        shelfWidth: shelfWidth,
        fused: fused,
      );
      if (size.width > maxTextureSide || size.height > maxTextureSide) {
        continue;
      }
      if (step == 0) {
        return asked;
      }
      _ceilingDeepenings++;
      _ceilingSteps += step;
      return ProxyResolutionPolicy.read(
        resolution,
        ProxyDivisorReason.textureCeiling,
        finish: finish,
        devicePixelRatio: devicePixelRatio,
        costModel: hardware.captureCostModel,
      );
    }
    _ceilingRefusals++;
    return null;
  }

  int get snapshots => _snapshots;
  int _snapshots = 0;

  ui.Image _snapshot(ui.Picture picture, int width, int height) {
    _snapshots++;
    return picture.toImageSync(width, height);
  }

  /// The divisor for the strictest finish on the screen.
  ///
  /// Chosen per finish and the smallest taken, because the divisor is one for
  /// the whole atlas and a coarser one is damage the sharper finish's table
  /// never allowed — a clear drop under a regular bar is read at the divisor
  /// `clear` permits, not the one `regular` would. Ties go to the host's own
  /// finish, so a screen with one finish gets exactly the choice it always did.
  ProxyResolutionChoice _strictest(_Blurs blurs, double devicePixelRatio) {
    ProxyResolutionChoice? best;
    for (final ({String name, double sigma}) material in blurs.materials) {
      final ProxyResolutionChoice choice = ProxyResolutionPolicy.choose(
        finish: material.name,
        finishSigmaLogical: material.sigma,
        devicePixelRatio: devicePixelRatio,
        costModel: hardware.captureCostModel,
        damageBudgetDeltaE: damageBudgetDeltaE,
      );
      if (best == null || choice.resolution.divisor < best.resolution.divisor) {
        best = choice;
      }
    }
    return best!;
  }

  /// Wraps the packed atlas in the layers that carry the residual blur, or
  /// returns it unchanged when this arm blurs some other way or not at all.
  ///
  /// One layer per blur class, each clipped to its own slots. With one class
  /// that is the single layer over the whole atlas it always was.
  ui.Picture _folded(
    ui.Picture packed,
    AtlasLayout layout,
    double scale,
    ProxyResolution resolution,
    double devicePixelRatio,
    _Blurs blurs,
  ) {
    if (blurPass != ProxyBlurPass.folded) {
      return packed;
    }
    final Rect bounds = Offset.zero & layout.size;
    if (blurs.classes == null) {
      final double? residual = _residualFor(resolution, devicePixelRatio, blurs.maxSigma);
      if (residual == null) {
        return packed;
      }
      final recorder = ui.PictureRecorder();
      Canvas(recorder, bounds)
        ..saveLayer(bounds, Paint()..imageFilter = _blurFilter(residual * scale))
        ..drawPicture(packed)
        ..restore();
      return recorder.endRecording();
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, bounds);
    for (var c = 0; c < blurs.sigmas.length; c++) {
      final Path clip = _classClip(layout, blurs, c);
      final double? residual = _residualFor(resolution, devicePixelRatio, blurs.sigmas[c]);
      // The layer over the class's own slots, not the atlas: see [_classBounds].
      final Rect region = _classBounds(layout, blurs, c);
      canvas
        ..save()
        ..clipPath(clip);
      if (residual == null) {
        canvas.drawPicture(packed);
      } else {
        canvas
          ..saveLayer(region, Paint()..imageFilter = _blurFilter(residual * scale))
          ..clipRect(region)
          ..drawPicture(packed)
          ..restore();
      }
      canvas.restore();
    }
    return recorder.endRecording();
  }

  /// The box around blur class [c]'s slots.
  ///
  /// **What a class is blurred over, and the reason a second finish on a
  /// screen is no longer a second atlas.** Each class used to blur the whole
  /// atlas and keep its own slots — so a scroll edge (σ 1.6) over a screen of
  /// cards (the host's 2.6) blurred every card twice: on the iPad 6.40 ms a
  /// scrolling frame against 3.11 without the edge (D227). Its own slots are
  /// all it is read in, and each slot carries its own context (`bleedFor`,
  /// 2.5 σ), so what lies past them is a neighbour's bleed that no sample of
  /// this class reaches.
  static Rect _classBounds(AtlasLayout layout, _Blurs blurs, int c) {
    Rect? out;
    for (final AtlasSlot slot in layout.slots) {
      if (blurs.classes![slot.members.first] == c) {
        out = out?.expandToInclude(slot.rect) ?? slot.rect;
      }
    }
    return out ?? Rect.zero;
  }

  /// The slots of blur class [c], as one clip.
  static Path _classClip(AtlasLayout layout, _Blurs blurs, int c) {
    final path = Path();
    for (final AtlasSlot slot in layout.slots) {
      if (blurs.classes![slot.members.first] == c) {
        path.addRect(slot.rect);
      }
    }
    return path;
  }

  /// `TileMode.clamp` rather than the default `decal`: the border of the atlas
  /// is the border of a slot, and a decal there darkens it — which is the one
  /// place a surface at the screen's edge samples, and where half the corpus
  /// puts its surfaces.
  static ui.ImageFilter _blurFilter(double sigmaTexels) =>
      ui.ImageFilter.blur(sigmaX: sigmaTexels, sigmaY: sigmaTexels, tileMode: TileMode.clamp);

  /// The sigma the pass still owes for a finish of [sigma], or null when this
  /// arm asks for none.
  ///
  /// Shared by both spellings so they cannot drift apart: a fold that blurred
  /// by a different sigma than the split would be a different material, and the
  /// comparison between them would be measuring that instead.
  double? _residualFor(ProxyResolution resolution, double devicePixelRatio, double sigma) {
    if (blurPass == ProxyBlurPass.none || sigma <= 0) {
      return null;
    }
    final double? residual = resolution.residualSigmaFor(sigma, devicePixelRatio);
    // The divisor has already spent the whole sigma — past this point the proxy
    // is blurrier than the material and no blur can undo it. Refusing to add
    // more is the honest half; the other half used to be
    // [ProxyResolution.maxDivisorFor] stopping the policy from getting here, and
    // since D164 that is true only where the material has blur of its own. A
    // blurless finish reaches this line whenever the host's budget allows a
    // divisor, returns null, and shows the proxy's own softness — which is not a
    // silent overshoot: the damage table's `clear` rungs were measured on this
    // exact path, so the budget that allowed the divisor priced this.
    return residual == null || residual <= 0 ? null : residual;
  }

  /// Blurs the atlas by what each finish still owes after the divisor.
  ui.Image _blurred(
    ui.Image atlas,
    double scale,
    ProxyResolution resolution,
    double devicePixelRatio,
    AtlasLayout layout,
    _Blurs blurs,
  ) {
    if (blurPass != ProxyBlurPass.split) {
      return atlas;
    }
    final double? single = blurs.classes == null ? _residualFor(resolution, devicePixelRatio, blurs.maxSigma) : null;
    if (blurs.classes == null && single == null) {
      return atlas;
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (single != null) {
      // In texels, which is what the filter works in.
      canvas.drawImage(atlas, Offset.zero, Paint()..imageFilter = _blurFilter(single * scale));
    } else {
      var any = false;
      for (var c = 0; c < blurs.sigmas.length; c++) {
        final double? residual = _residualFor(resolution, devicePixelRatio, blurs.sigmas[c]);
        any |= residual != null;
        // The class's own region of the atlas, not all of it: see [_classBounds].
        final Rect region = _classBounds(layout, blurs, c);
        canvas
          ..save()
          ..clipPath(_classClip(layout, blurs, c))
          ..drawImageRect(
            atlas,
            region,
            region,
            residual == null ? Paint() : (Paint()..imageFilter = _blurFilter(residual * scale)),
          )
          ..restore();
      }
      if (!any) {
        recorder.endRecording().dispose();
        return atlas;
      }
    }
    final ui.Picture picture = recorder.endRecording();
    try {
      final ui.Image out = _snapshot(picture, atlas.width, atlas.height);
      atlas.dispose();
      return out;
    } finally {
      picture.dispose();
    }
  }

  static Rect _boundsOf(RenderObject root) => root is RenderBox ? Offset.zero & root.size : root.paintBounds;

  /// The one picture the walk produced.
  ///
  /// Refuses rather than taking the first. The walk cannot append a layer —
  /// every `push*`, `addLayer` and `appendLayer` route is overridden and puts
  /// its effect on the canvas — so this is one by construction; the check is
  /// here because the atlas replays this picture N times, and replaying the
  /// first of several would drop the rest silently, on whichever construct
  /// broke the invariant rather than on all of them.
  static ui.Picture _singlePictureOf(ContainerLayer root) {
    ui.Picture? found;
    var pictures = 0;
    var others = 0;
    for (Layer? child = root.firstChild; child != null; child = child.nextSibling) {
      if (child is PictureLayer) {
        pictures++;
        found ??= child.picture;
      } else {
        others++;
      }
    }
    if (pictures != 1 || others != 0) {
      throw StateError(
        'the walk produced $pictures picture layers and $others others; the atlas '
        'replays one picture, so this frame would be missing content',
      );
    }
    return found!;
  }
}

/// The finishes on one screen, as blur classes.
///
/// A finish decides two things the pipeline does rather than the shader: how
/// much the proxy is blurred, and — through its name — which damage table
/// prices the divisor. Until this class the host's finish decided both for
/// every surface, so `GlassSurface(finish: GlassFinish.clear)` under a
/// `regular` host drew a backdrop blurred at σ 2.6 and a `frosted` one was
/// `regular` with a different tint.
class _Blurs {
  _Blurs._(this.materials, this.sigmas, this.classes, this.maxSigma);

  factory _Blurs.of(List<GlassFinish>? finishes, String hostName, double hostSigma) {
    final materials = <({String name, double sigma})>[(name: hostName, sigma: hostSigma)];
    if (finishes == null) {
      return _Blurs._(materials, <double>[hostSigma], null, hostSigma);
    }
    // The host's own finish counts only if a surface wears it: the question is
    // what the atlas holds, and a screen of clear drops under a regular host
    // holds nothing regular.
    final present = <({String name, double sigma})>[];
    for (final GlassFinish f in finishes) {
      final entry = (name: f.name, sigma: f.blurSigmaLogical);
      if (!present.contains(entry)) {
        present.add(entry);
      }
    }
    if (present.isEmpty) {
      return _Blurs._(materials, <double>[hostSigma], null, hostSigma);
    }
    // Host first when present, so ties in [_strictest] keep its choice.
    present.sort((a, b) => (a == materials.first ? 0 : 1).compareTo(b == materials.first ? 0 : 1));
    final sigmas = <double>[];
    for (final ({String name, double sigma}) m in present) {
      if (!sigmas.contains(m.sigma)) {
        sigmas.add(m.sigma);
      }
    }
    final double maxSigma = sigmas.reduce(math.max);
    return _Blurs._(
      present,
      sigmas,
      sigmas.length == 1 ? null : <int>[for (final GlassFinish f in finishes) sigmas.indexOf(f.blurSigmaLogical)],
      maxSigma,
    );
  }

  /// Every distinct finish, the host's first if any surface wears it.
  final List<({String name, double sigma})> materials;

  /// Every distinct sigma; a class is an index into this.
  final List<double> sigmas;

  /// Each surface's class, or null when there is one — which is the path every
  /// screen took before, bit for bit.
  final List<int>? classes;

  final double maxSigma;
}
