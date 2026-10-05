// Recording one proxy: a region of the live tree, at a chosen resolution, into
// a texture the glass samples — plus the map back, which is the half that is
// easy to get silently wrong.
//
// Two routes, on purpose. [ProxyRecorder.walk] runs our own pass, which is what
// makes the capture selective (roles, occlusion, the shadow filter);
// [ProxyRecorder.stock] goes through `OffsetLayer.toImageSync` and subtracts
// nothing. The second is not a leftover — it is the structural fallback the
// roadmap requires to exist from the first commit rather than to be added after
// the first divergence, and having both produce the *same* value type is what
// lets a caller swap them per subtree.
//
// **The map is the part that costs pixels when it is wrong.** The engine's own
// arithmetic is `texel = (logical - bounds.topLeft - layer.offset) * pixelRatio`
// with the image sized `ceil(pixelRatio * bounds.width)` by
// `ceil(pixelRatio * bounds.height)` (`layer.dart:1519-1524,1580-1593`). Both
// halves are reproduced here rather than assumed, because an error in either is
// a shift of the whole backdrop by a fraction of a pixel — visible as a smear on
// the rim and on nothing else.
//
// **And the region is snapped before anything else happens.** `Rect.fromLTWH`
// stores `bottom = top + height`, so the height it gives back is
// `(top + h) - top`, which differs by an ULP when `top` is an awkward fraction —
// and `ceil` turns that ULP into a whole extra row of texels. Measured on the
// harness: at `passes = 8, side = 64` on a 360x772 source, pass 5 sits at
// `top = 505.7142857142857` and the capture comes back 128x129. Snapping outward
// to whole logical pixels costs at most one pixel per side and cannot do that.

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'proxy_resolution.dart';
import 'proxy_walk.dart';
import 'shadow_filter.dart';

/// One recorded proxy, and the map from the screen into it.
class ProxyRecording {
  ProxyRecording._(this._handle, this.image, this.region, this.scale, this.log);

  final LayerHandle<OffsetLayer>? _handle;

  /// The texture the glass samples.
  final ui.Image image;

  /// The part of the screen it holds, in logical pixels, after snapping.
  final Rect region;

  /// Texels per logical pixel.
  final double scale;

  /// What the pass observed. Null for [ProxyRecorder.stock], which runs no pass
  /// — and that null is the difference between the two routes made visible
  /// rather than described.
  final WalkLog? log;

  /// Where a point on the screen lands in [image].
  ///
  /// The three numbers a shader needs are [region].topLeft and [scale]; this is
  /// the same map written out, so a test can check the shader's arithmetic
  /// against something other than itself. The atlas adds a third term for the
  /// slot's own origin; here it is zero.
  Offset toTexel(Offset logical) => (logical - region.topLeft) * scale;

  /// The inverse, for reading a texel back as a place on screen.
  Offset toLogical(Offset texel) => texel / scale + region.topLeft;

  /// What [image] should be, from the engine's own rule. Checked rather than
  /// trusted: a mismatch means the snapping above did not hold.
  ({int width, int height}) get expectedSize =>
      (width: (scale * region.width).ceil(), height: (scale * region.height).ceil());

  void dispose() {
    image.dispose();
    _handle?.layer = null;
  }
}

/// Records a proxy off the live render tree.
abstract final class ProxyRecorder {
  /// Snaps a region outward to whole logical pixels.
  ///
  /// Outward, so the snapped region is never smaller than what was asked for:
  /// a proxy short of the surface that samples it is a transparent edge, and a
  /// proxy one pixel wider is a pixel nobody reads.
  static Rect snap(Rect region) => Rect.fromLTRB(
    region.left.floorToDouble(),
    region.top.floorToDouble(),
    region.right.ceilToDouble(),
    region.bottom.ceilToDouble(),
  );

  /// Our own pass: roles, occlusion and the canvas policy all apply.
  static ProxyRecording walk(
    RenderObject root, {
    required Rect region,
    required ProxyResolution resolution,
    required double devicePixelRatio,
    WalkPolicy policy = paintEverything,
    ShadowFilter? shadowFilter,
    Offset rootOffset = Offset.zero,
  }) {
    final Rect bounds = snap(region);
    final double scale = resolution.ratioFor(devicePixelRatio);
    final log = WalkLog();
    final handle = LayerHandle<OffsetLayer>()..layer = OffsetLayer();
    final context = ProxyWalkContext(
      handle.layer!,
      bounds,
      log: log,
      policy: policy,
      shadowFilter: shadowFilter,
    )..paintChild(root, rootOffset);
    context.finish();
    return ProxyRecording._(
      handle,
      handle.layer!.toImageSync(bounds, pixelRatio: scale),
      bounds,
      scale,
      log,
    );
  }

  /// The fallback: the engine's own capture of the retained layer, subtracting
  /// nothing.
  ///
  /// The route every number in M2 and M10 was measured through, and the one a
  /// subtree falls back to when the pass reports a construct it cannot
  /// reproduce — `BackdropFilter`, or an opacity folded into a colour filter.
  static ProxyRecording stock(
    RenderRepaintBoundary boundary, {
    required Rect region,
    required ProxyResolution resolution,
    required double devicePixelRatio,
  }) {
    final Rect bounds = snap(region);
    final double scale = resolution.ratioFor(devicePixelRatio);
    // `layer`, not `debugLayer`: the second is wrapped in an `assert` and
    // returns **null in profile** (`object.dart:3184-3191`), which is where this
    // runs. `layer` is `@protected`, which is a lint rather than a guard.
    // ignore: invalid_use_of_protected_member
    final OffsetLayer? layer = boundary.layer as OffsetLayer?;
    if (layer == null) {
      throw StateError('the boundary has no layer: it has not painted yet');
    }
    // `toImageSync` off the layer rather than `RenderRepaintBoundary.toImage`,
    // which asserts `!debugNeedsPaint` (`proxy_box.dart:3553`) — and a tree that
    // captures in a post-frame callback is dirty by construction, because
    // publishing the proxy marks the glass for repaint.
    return ProxyRecording._(null, layer.toImageSync(bounds, pixelRatio: scale), bounds, scale, null);
  }
}
