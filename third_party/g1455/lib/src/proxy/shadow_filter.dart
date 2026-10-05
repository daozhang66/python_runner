// The one content policy M11 left alive: shadows are not drawn into the proxy.
//
// D31 measured it at **0.00 ΔE** behind a blur — the only degradation on the
// whole quality ladder that costs nothing — and the ladder was re-taken with
// `debugDisableShadows = false` afterwards, so the number describes a shadow
// that actually had a blur in it.
//
// **A per-node policy cannot express it.** A shadow is not a node. It is a
// `drawShadow` call inside `RenderPhysicalModel.paint`, or a `drawRRect` with a
// blur `MaskFilter` inside whatever `BoxDecoration.boxShadow` lowers to. Both
// happen inside foreign `paint()`, several frames down somebody else's call
// stack, and [WalkAction.skip] would take the node they belong to with them.
//
// So the policy sits one level lower, on the canvas — and it can, because
// `PaintingContext.canvas` is a plain getter (`object.dart:351-357`) and
// `ClipContext` reads the same getter (`painting/clip.dart:13`). A subclass
// returning a filtering canvas intercepts every draw the subtree makes, with
// nothing private involved. `GlassProxy.verbatim` is the subtree-sized way out
// of it, which exists because [ShadowFilter.dropMaskFiltered] is a heuristic.
//
// The price of the technique is this file's shape: `ui.Canvas` has 38 methods
// and Dart cannot forward them generically (`noSuchMethod` has nothing to
// forward *to*), so every one is written out. A method added to `Canvas`
// upstream is a compile error here rather than a silently dropped draw, which
// is the right way round.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

/// What a draw has to look like to be dropped.
///
/// Two switches rather than one, because they catch different things and it
/// matters which fired: `drawShadow` is the physical-model route (`Material`
/// elevation), a blur `MaskFilter` is the `BoxShadow` route.
class ShadowFilter {
  ShadowFilter({this.dropShadowCalls = true, this.dropMaskFiltered = true});

  final bool dropShadowCalls;

  /// Anything painted through a `MaskFilter`.
  ///
  /// Heuristic, and it has to be named as one: a blurred draw is *usually* a
  /// shadow, and a design that blurs a highlight on purpose would lose it. The
  /// two counters below are what makes the difference visible in a report
  /// instead of in a screenshot.
  final bool dropMaskFiltered;

  int shadowCalls = 0;
  int maskFilteredDraws = 0;

  int get dropped => shadowCalls + maskFilteredDraws;

  bool _dropPaint(ui.Paint paint) {
    if (dropMaskFiltered && paint.maskFilter != null) {
      maskFilteredDraws++;
      return true;
    }
    return false;
  }
}

/// A `Canvas` that forwards everything and refuses the draws a [ShadowFilter]
/// names.
class FilteringCanvas implements Canvas {
  FilteringCanvas(this.inner, this.filter);

  /// The canvas being wrapped. Exposed so a caller can tell whether its
  /// wrapper is still the right one after the context started a new recording.
  final Canvas inner;

  final ShadowFilter filter;

  @override
  void drawShadow(Path path, Color color, double elevation, bool transparentOccluder) {
    if (filter.dropShadowCalls) {
      filter.shadowCalls++;
      return;
    }
    inner.drawShadow(path, color, elevation, transparentOccluder);
  }

  // --- the draws that carry a paint, and can therefore carry a mask filter ---

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    if (filter._dropPaint(paint)) {
      return;
    }
    inner.drawLine(p1, p2, paint);
  }

  @override
  void drawPaint(Paint paint) {
    if (filter._dropPaint(paint)) {
      return;
    }
    inner.drawPaint(paint);
  }

  @override
  void drawRect(Rect rect, Paint paint) {
    if (filter._dropPaint(paint)) {
      return;
    }
    inner.drawRect(rect, paint);
  }

  @override
  void drawRRect(RRect rrect, Paint paint) {
    if (filter._dropPaint(paint)) {
      return;
    }
    inner.drawRRect(rrect, paint);
  }

  @override
  void drawDRRect(RRect outer, RRect innerRRect, Paint paint) {
    if (filter._dropPaint(paint)) {
      return;
    }
    inner.drawDRRect(outer, innerRRect, paint);
  }

  @override
  void drawRSuperellipse(RSuperellipse rsuperellipse, Paint paint) {
    if (filter._dropPaint(paint)) {
      return;
    }
    inner.drawRSuperellipse(rsuperellipse, paint);
  }

  @override
  void drawOval(Rect rect, Paint paint) {
    if (filter._dropPaint(paint)) {
      return;
    }
    inner.drawOval(rect, paint);
  }

  @override
  void drawCircle(Offset c, double radius, Paint paint) {
    if (filter._dropPaint(paint)) {
      return;
    }
    inner.drawCircle(c, radius, paint);
  }

  @override
  void drawArc(Rect rect, double startAngle, double sweepAngle, bool useCenter, Paint paint) {
    if (filter._dropPaint(paint)) {
      return;
    }
    inner.drawArc(rect, startAngle, sweepAngle, useCenter, paint);
  }

  @override
  void drawPath(Path path, Paint paint) {
    if (filter._dropPaint(paint)) {
      return;
    }
    inner.drawPath(path, paint);
  }

  // --- everything else, forwarded unchanged ---

  @override
  void save() => inner.save();

  @override
  void saveLayer(Rect? bounds, Paint paint) => inner.saveLayer(bounds, paint);

  @override
  void restore() => inner.restore();

  @override
  void restoreToCount(int count) => inner.restoreToCount(count);

  @override
  int getSaveCount() => inner.getSaveCount();

  @override
  void translate(double dx, double dy) => inner.translate(dx, dy);

  @override
  void scale(double sx, [double? sy]) => inner.scale(sx, sy);

  @override
  void rotate(double radians) => inner.rotate(radians);

  @override
  void skew(double sx, double sy) => inner.skew(sx, sy);

  @override
  void transform(Float64List matrix4) => inner.transform(matrix4);

  @override
  Float64List getTransform() => inner.getTransform();

  @override
  void clipRect(Rect rect, {ui.ClipOp clipOp = ui.ClipOp.intersect, bool doAntiAlias = true}) =>
      inner.clipRect(rect, clipOp: clipOp, doAntiAlias: doAntiAlias);

  @override
  void clipRRect(RRect rrect, {bool doAntiAlias = true}) => inner.clipRRect(rrect, doAntiAlias: doAntiAlias);

  @override
  void clipRSuperellipse(RSuperellipse rsuperellipse, {bool doAntiAlias = true}) =>
      inner.clipRSuperellipse(rsuperellipse, doAntiAlias: doAntiAlias);

  @override
  void clipPath(Path path, {bool doAntiAlias = true}) => inner.clipPath(path, doAntiAlias: doAntiAlias);

  @override
  Rect getLocalClipBounds() => inner.getLocalClipBounds();

  @override
  Rect getDestinationClipBounds() => inner.getDestinationClipBounds();

  @override
  void drawColor(Color color, BlendMode blendMode) => inner.drawColor(color, blendMode);

  @override
  void drawImage(ui.Image image, Offset offset, Paint paint) => inner.drawImage(image, offset, paint);

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) => inner.drawImageRect(image, src, dst, paint);

  @override
  void drawImageNine(ui.Image image, Rect center, Rect dst, Paint paint) =>
      inner.drawImageNine(image, center, dst, paint);

  @override
  void drawPicture(ui.Picture picture) => inner.drawPicture(picture);

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) => inner.drawParagraph(paragraph, offset);

  @override
  void drawPoints(ui.PointMode pointMode, List<Offset> points, Paint paint) =>
      inner.drawPoints(pointMode, points, paint);

  @override
  void drawRawPoints(ui.PointMode pointMode, Float32List points, Paint paint) =>
      inner.drawRawPoints(pointMode, points, paint);

  @override
  void drawVertices(ui.Vertices vertices, BlendMode blendMode, Paint paint) =>
      inner.drawVertices(vertices, blendMode, paint);

  @override
  void drawAtlas(
    ui.Image atlas,
    List<RSTransform> transforms,
    List<Rect> rects,
    List<Color>? colors,
    BlendMode? blendMode,
    Rect? cullRect,
    Paint paint,
  ) => inner.drawAtlas(atlas, transforms, rects, colors, blendMode, cullRect, paint);

  @override
  void drawRawAtlas(
    ui.Image atlas,
    Float32List rstTransforms,
    Float32List rects,
    Int32List? colors,
    BlendMode? blendMode,
    Rect? cullRect,
    Paint paint,
  ) => inner.drawRawAtlas(atlas, rstTransforms, rects, colors, blendMode, cullRect, paint);
}
