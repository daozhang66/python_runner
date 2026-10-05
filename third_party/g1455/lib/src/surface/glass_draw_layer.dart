// The glass's draw, recorded when the frame is composited rather than when it
// is painted.
//
// A glass fragment samples the proxy at its place *on the screen*, and a
// fragment shader only knows its place in the layer it is drawn into — so
// every draw carries the surface's global origin as a uniform. Paint is the
// wrong time to read it: a surface is a repaint boundary, and a boundary that
// moves is not painted, its layer is re-offset (`PaintingContext._compositeChild`).
// So a glass that moved drew the backdrop of the place it had left, for one
// frame until the next publish repainted it — and for ever, once a declared
// travel region stopped the publish from happening (the arm in
// `glass_travel_test.dart` measured 4538 px of it at 37 px of motion).
//
// The framework's own answer to "this layer depends on where it ends up" is a
// layer that reads it at composite time — `FollowerLayer`. This is the same
// thing for a picture: the paint hands the layer everything that does not
// move, and `addToScene` reads where it is, which layout has settled by then,
// and re-records only when that changed.
//
// **The layer also owns the shaders its picture draws with, on the web.**
// CanvasKit hands a `FragmentShader`'s uniforms to Skia by pointer: the floats
// live in a buffer the shader mallocs, and `RuntimeEffect.makeShader` passes it
// as not-owned (`shouldOwnUniforms = !floats._ck`), so the `SkShader` recorded
// into the picture reads that buffer when the picture is *rasterized* — which
// is at the end of the frame, and again on every frame the picture is
// retained. A `dispose()` straight after the draw frees it first: the glass
// then drew from whatever reused the memory — a shape off by hundreds of
// pixels, a solid green or grey slab, a different picture each frame. Every
// Safari, which never gets Skwasm, drew that, and so does Chromium forced onto
// CanvasKit. [releaseGlassShader] is the one call a draw makes instead.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// Releases [shader] once nothing drawn with it can be rasterized again.
///
/// Natively that is now: the engine copies the uniforms into the display list.
/// On the web it is when the picture the draw went into is disposed — the
/// [GlassDrawLayer]'s, when the draw is made while it records — or, for a draw
/// into any other picture (the capture of a level above), two frame ends after
/// this one, by which time that picture has been snapshotted and dropped.
void releaseGlassShader(ui.FragmentShader shader) {
  if (!kIsWeb && !debugReleaseGlassShadersAsOnWeb) {
    shader.dispose();
    return;
  }
  final List<ui.FragmentShader>? recording = GlassDrawLayer._recording;
  if (recording != null) {
    recording.add(shader);
    return;
  }
  // Two frame ends rather than one: the frame that drew is not always
  // rasterized by the time its own post-frame callbacks run. And one more when
  // the draw is made in a post-frame callback, which is where the host
  // captures: the countdown's own callback may still be due in this batch, and
  // would count the end that is already under way.
  final bool ending = SchedulerBinding.instance.schedulerPhase == SchedulerPhase.postFrameCallbacks;
  _releasedAfterFrame.add((shader, _frameEnds + (ending ? 3 : 2)));
  _scheduleRelease();
}

/// Routes [releaseGlassShader] through the web's deferred release on every
/// platform, for a test to watch it: `kIsWeb` is a constant, and the release
/// it guards is otherwise unreachable from `flutter test`.
@visibleForTesting
bool debugReleaseGlassShadersAsOnWeb = false;

/// How many shaders [releaseGlassShader] is holding for a frame to end,
/// outside any [GlassDrawLayer].
@visibleForTesting
int get debugGlassShadersAwaitingRelease => _releasedAfterFrame.length;

/// Each shader with the count of frame ends at which it goes, so one queued
/// while the countdown runs still gets its own two.
final List<(ui.FragmentShader, int)> _releasedAfterFrame = <(ui.FragmentShader, int)>[];

/// Frame ends seen by [_releaseDue] since the process started.
int _frameEnds = 0;

bool _releaseScheduled = false;

// A post-frame callback alone does not ask for a frame, so a scene that went
// idle on the frame that queued a shader would keep it — and, held here, past
// the host that drew it — until something else repainted. The frame asked for
// is otherwise empty: nothing is marked dirty.
void _scheduleRelease() {
  if (_releaseScheduled) {
    return;
  }
  _releaseScheduled = true;
  SchedulerBinding.instance
    ..addPostFrameCallback(_releaseDue, debugLabel: 'releaseGlassShader')
    ..ensureVisualUpdate();
}

void _releaseDue(Duration _) {
  _releaseScheduled = false;
  _frameEnds++;
  _releasedAfterFrame.removeWhere(((ui.FragmentShader, int) entry) {
    final (ui.FragmentShader shader, int at) = entry;
    if (at > _frameEnds) {
      return false;
    }
    shader.dispose();
    return true;
  });
  if (_releasedAfterFrame.isNotEmpty) {
    _scheduleRelease();
  }
}

/// A leaf layer whose picture is a function of where its owner is on screen.
class GlassDrawLayer extends Layer {
  /// Returns what the picture depends on that paint cannot see — the owner's
  /// global geometry — as a list compared element-wise.
  List<Object?> Function()? probe;

  /// Draws the picture for the geometry [probe] just returned.
  void Function(Canvas canvas)? painter;

  ui.Picture? _picture;
  List<Object?>? _pictureAt;

  /// The shaders [_picture] was drawn with, released with it (web only; see
  /// [releaseGlassShader]).
  List<ui.FragmentShader> _shaders = <ui.FragmentShader>[];

  /// Where [releaseGlassShader] puts a shader while a layer records.
  static List<ui.FragmentShader>? _recording;

  /// How many times the picture was recorded, and how many of those were
  /// forced by the owner moving rather than by a paint.
  ///
  /// The trace the mechanism would otherwise not have: an arm that only checks
  /// the pixels passes as well on a surface that happened to be repainted by
  /// something else on the frame it moved.
  int records = 0;
  int recordsOnMove = 0;

  /// The paint changed what is drawn: the next composite records afresh.
  void invalidate() {
    _releasePicture();
    _pictureAt = null;
  }

  void _releasePicture() {
    _picture?.dispose();
    _picture = null;
    final List<ui.FragmentShader> shaders = _shaders;
    if (shaders.isNotEmpty) {
      _shaders = <ui.FragmentShader>[];
      for (final ui.FragmentShader shader in shaders) {
        shader.dispose();
      }
    }
  }

  // Every frame, because what the picture depends on is not a property of
  // this layer or of any layer above it that the framework would mark: a
  // re-offset ancestor re-adds its own layer and retains ours.
  @override
  bool get alwaysNeedsAddToScene => true;

  @override
  void addToScene(ui.SceneBuilder builder) {
    final List<Object?> at = probe?.call() ?? const <Object?>[];
    ui.Picture? picture = _picture;
    if (picture == null || !listEquals(at, _pictureAt)) {
      if (picture != null) {
        recordsOnMove++;
      }
      _releasePicture();
      final recorder = ui.PictureRecorder();
      final List<ui.FragmentShader>? outer = _recording;
      final shaders = <ui.FragmentShader>[];
      _recording = shaders;
      try {
        painter?.call(Canvas(recorder));
      } finally {
        _recording = outer;
      }
      picture = _picture = recorder.endRecording();
      _shaders = shaders;
      _pictureAt = at;
      records++;
    }
    builder.addPicture(Offset.zero, picture);
  }

  @override
  void dispose() {
    invalidate();
    super.dispose();
  }
}
