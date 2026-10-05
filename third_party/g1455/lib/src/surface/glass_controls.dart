// Controls whose knob turns into a glass drop while it is held: a switch and a
// slider.
//
// What the drop is was read off Apple's own controls rather than chosen
// (spike 27). A held `NSSwitch` / `NSSlider` on macOS 27 is a **clear** drop —
// no tint, no blur — that bends the backdrop in a band at its rim and leaves the
// middle exactly where it was: the grid lines through the centre of the drop
// sat on the undisplaced grid to the half pixel, so there is no magnification
// and nothing here needs an optics axis the finish does not have. It is
// 1.4–1.6x the resting knob. At rest the knob is an opaque white capsule and
// not glass at all. On iOS, pressed by a finger (D217), both drops are 1.57x;
// the slider's does not magnify either, but the **switch's minifies** — ×0.85
// across and ×0.79 down, which is one margin of 5 pt drawn into the drop
// rather than one zoom (D218), and is `GlassOptics.widen` on its finish.
//
// Three mechanisms carry it, each built and tested on its own:
//
//  - the drop is a [GlassSurface] at `presence` 0 at rest — drawing nothing and
//    **captured for nothing**, so a screen full of switches costs the atlas
//    nothing, and the clear finish's divisor nothing, until one is held;
//  - it grows and fades in through `presence`, which is a field offset and
//    costs no capture;
//  - it moves inside a [GlassTravel] region behind its own repaint boundary, so
//    a drag is drawn from the proxy already held.
//
// What is *not* free is content that changes under the drop. The switch's track
// changes colour only when the value commits, so a drag costs one capture when
// the drop appears and none while it moves. The slider's fill ends under the
// drop and follows it, so every frame of a slider drag is a real change under
// glass and is retaken — the honest price, stated rather than hidden.

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

import 'glass_components.dart' show kGlassMinTapTarget;
import 'glass_finish.dart';
import 'glass_surface.dart';
import 'glass_travel.dart';

/// How much larger a held drop is than the resting knob, by default.
///
/// iOS 26: 1.57x for both the switch and the slider, read off the device's own
/// screenshots under a finger (D217). macOS 27 differs per control — 1.4x the
/// slider, 1.6x the switch (D210) — which is why the controls take it as
/// `dropScale`.
const double kGlassDropScale = 1.57;

/// How far past its own box the held switch's drop shows, logical px — the
/// iOS switch's drop minifies what is under it (×0.85 across, ×0.79 down on a
/// 58 × 38 pt drop), which is this one margin rather than one zoom (D218). The
/// slider's drop, read the same way, does not minify, and its default is 0.
/// See [GlassOptics.widen].
const double kGlassSwitchDropWiden = 5;

/// The optics of a held drop, which are not the material's.
///
/// Read off iOS's slider drop under a finger (D217's frames, D218): the grid
/// moves 2.1–2.5 device px — 1.15 pt — at 2.7–3 pt in from the rim and not
/// at all from 10 pt in. The material's optics move it ~28 pt at 3 pt in,
/// which on a drop 38 pt tall is the whole drop folded: a tab bar's label
/// under it came out as an hourglass. So: a reach of 10, and the amplitude
/// that puts 1.15 pt at 3 pt in on the material's own curve shape (whose
/// exponents two readings cannot identify, and are borrowed).
const GlassOptics kGlassDropOptics = GlassOptics(thickness: 10, strength: -4.1);

/// How long the drop takes to lift or settle.
const Duration kGlassDropDuration = Duration(milliseconds: 180);

/// How opaque a disabled switch or slider is, drawn as one group.
///
/// iOS 26 draws a disabled `UISwitch` and `UISlider` whole at alpha 0.502 —
/// knob, track and fill alike, in both appearances, their colours unchanged
/// (D221). One group, not each part at a half: the knob reads pure white at
/// that alpha, so the track under it does not show through. macOS does
/// something else per part (the switch's accent ×0.69, the slider's fill
/// gone); these controls are iOS's, as their sizes are.
const double kGlassDisabledOpacity = 0.5;

/// The iOS 26 switch's track and knob, logical px.
const Size kGlassSwitchSize = Size(64, 28);
const Size _kSwitchKnob = Size(38, 24);

/// The slider's resting knob and track thickness, logical px.
const Size _kSliderKnob = Size(38, 24);
const double _kSliderTrack = 6;

/// A knob that becomes a drop: an opaque white capsule at rest, and a clear
/// glass drop [scale] times its size while [lift] is 1.
///
/// Laid out at its resting size and drawn past it, so what places it — a
/// `Positioned`, an `Align` — places the knob's centre and not the drop's box.
class _Drop extends StatelessWidget {
  const _Drop({required this.rest, required this.lift, required this.scale, this.widen = 0});

  final Size rest;

  /// [GlassOptics.widen] of the held drop.
  final double widen;

  /// The held drop against [rest].
  final double scale;

  /// 0 at rest, 1 held.
  final double lift;

  @override
  Widget build(BuildContext context) {
    final double now = 1 + (scale - 1) * lift;
    final Size held = rest * scale;
    return SizedBox.fromSize(
      size: rest,
      child: OverflowBox(
        maxWidth: held.width,
        maxHeight: held.height,
        child: SizedBox.fromSize(
          size: rest * now,
          child: GlassSurface(
            borderRadius: kGlassCapsule,
            finish: GlassFinish.clear.copyWith(optics: kGlassDropOptics.copyWith(widen: widen)),
            // Arrives by its optics, not its shape: `presence` would erode
            // the capsule to its medial axis, a bright stripe (spike 30).
            materialize: lift,
            labelled: false,
            // The white knob is the surface's content, so it is drawn over the
            // glass and kept out of every capture — nothing under a drop is ever
            // the knob it replaced.
            child: lift >= 1 ? null : Opacity(opacity: 1 - lift, child: const _Knob()),
          ),
        ),
      ),
    );
  }
}

/// The resting knob: an opaque white capsule.
class _Knob extends StatelessWidget {
  const _Knob();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: ShapeDecoration(
      color: Color(0xFFFFFFFF),
      shape: StadiumBorder(),
      shadows: <BoxShadow>[
        BoxShadow(color: Color(0x26000000), blurRadius: 4, offset: Offset(0, 1)),
      ],
    ),
  );
}

/// A disabled control's body: drawn whole at [kGlassDisabledOpacity].
///
/// The `saveLayer` an [Opacity] opens is what makes it one group, and it is
/// safe here only because nothing under it is glass: a disabled control cannot
/// be held, so its knob is the plain [_Knob] and no drop is in the tree.
Widget _disabled(Widget child) => Opacity(opacity: kGlassDisabledOpacity, child: child);

/// The region a drop may move and grow in, and the boundary it moves behind.
///
/// [margin] past the control's own box on every side, because a held drop is
/// larger than the track it sits on and a drop that grew out of its region
/// would be retaken on every frame of the growth.
class _DropStage extends StatelessWidget {
  const _DropStage({required this.margin, required this.child});

  final double margin;
  final Widget child;

  @override
  Widget build(BuildContext context) => Positioned(
    left: -margin,
    top: -margin,
    right: -margin,
    bottom: -margin,
    child: GlassTravel(
      // A boundary of its own, so moving the drop repaints a layer that holds
      // nothing but the drop — no picture under the glass is re-minted, and the
      // layer watch has no change to report.
      child: RepaintBoundary(
        child: Stack(clipBehavior: Clip.none, children: <Widget>[child]),
      ),
    ),
  );
}

/// A switch whose knob becomes a clear glass drop while it is held.
class GlassSwitch extends StatefulWidget {
  const GlassSwitch({
    required this.value,
    required this.onChanged,
    this.activeColor = const Color(0xFF34C759),
    this.trackColor = const Color(0x29787880),
    this.dropScale = kGlassDropScale,
    this.dropWiden = kGlassSwitchDropWiden,
    this.semanticLabel,
    super.key,
  }) : assert(dropScale >= 1);

  /// How much larger the held drop is than the resting knob. See
  /// [kGlassDropScale]; macOS's own switch is 1.6.
  final double dropScale;

  /// How much of the backdrop past its box the held drop shows, which
  /// minifies it. See [kGlassSwitchDropWiden]; 0 is a drop that does not.
  final double dropWiden;

  final bool value;

  /// Null disables the switch, which is also what the semantics say; it is
  /// then drawn at [kGlassDisabledOpacity].
  final ValueChanged<bool>? onChanged;

  /// The track when on. iOS's green by default.
  final Color activeColor;

  /// The track when off.
  final Color trackColor;

  /// What a screen reader says the switch is for. Null leaves it to a
  /// `MergeSemantics` around the switch and its row's label.
  final String? semanticLabel;

  @override
  State<GlassSwitch> createState() => _GlassSwitchState();
}

class _GlassSwitchState extends State<GlassSwitch> with TickerProviderStateMixin {
  late final AnimationController _lift = AnimationController(
    vsync: this,
    duration: kGlassDropDuration,
  );
  late final AnimationController _position = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: widget.value ? 1 : 0,
  );
  late final AnimationController _colour = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    value: widget.value ? 1 : 0,
  );
  bool _dragging = false;

  static const double _inset = (28 - 24) / 2;
  static double get _from => _inset + _kSwitchKnob.width / 2;
  static double get _to => kGlassSwitchSize.width - _inset - _kSwitchKnob.width / 2;

  @override
  void didUpdateWidget(GlassSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled && _lift.value > 0) {
      // Disabled mid-drag: the drag's end will never arrive. A finger held
      // still needs none of this — the disposed tap recognizer calls the
      // `onTapCancel` it was built with — but a drag has already won its arena
      // and is dropped without a word (D221).
      _dragging = false;
      _lift.value = 0;
      _position.animateTo(widget.value ? 1 : 0, curve: Curves.easeOutCubic);
    }
    if (widget.value != oldWidget.value) {
      if (!_dragging) {
        _position.animateTo(widget.value ? 1 : 0, curve: Curves.easeOutCubic);
      }
      _colour.animateTo(widget.value ? 1 : 0);
    }
  }

  @override
  void dispose() {
    _lift.dispose();
    _position.dispose();
    _colour.dispose();
    super.dispose();
  }

  bool get _enabled => widget.onChanged != null;

  void _commit(bool value) {
    if (value != widget.value) {
      widget.onChanged?.call(value);
    } else {
      _position.animateTo(value ? 1 : 0, curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double margin = (widget.dropScale - 1) * _kSwitchKnob.width / 2 + _inset + 4;
    return Semantics(
      label: widget.semanticLabel,
      toggled: widget.value,
      enabled: _enabled,
      onTap: _enabled ? () => _commit(!widget.value) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => _lift.forward() : null,
        onTapCancel: _enabled ? () => _dragging ? null : _lift.reverse() : null,
        onTap: _enabled
            ? () {
                _lift.reverse();
                _commit(!widget.value);
              }
            : null,
        onHorizontalDragStart: _enabled
            ? (_) {
                _dragging = true;
                _lift.forward();
              }
            : null,
        onHorizontalDragUpdate: _enabled
            ? (DragUpdateDetails d) {
                _position.value += d.delta.dx / (_to - _from);
              }
            : null,
        onHorizontalDragEnd: _enabled
            ? (_) {
                _dragging = false;
                _lift.reverse();
                _commit(_position.value >= 0.5);
              }
            : null,
        child: SizedBox(
          width: kGlassSwitchSize.width,
          height: math.max(kGlassSwitchSize.height, kGlassMinTapTarget.height),
          child: Center(
            child: SizedBox.fromSize(size: kGlassSwitchSize, child: _switchBody(margin)),
          ),
        ),
      ),
    );
  }

  Widget _switchBody(double margin) {
    final Widget body = Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _colour,
              builder: (BuildContext context, Widget? _) => DecoratedBox(
                decoration: ShapeDecoration(
                  shape: const StadiumBorder(),
                  color: Color.lerp(widget.trackColor, widget.activeColor, _colour.value),
                ),
              ),
            ),
          ),
        ),
        if (!_enabled)
          AnimatedBuilder(
            animation: _position,
            builder: (BuildContext context, Widget? _) => Positioned.fromRect(
              rect: Rect.fromCenter(
                center: Offset(
                  lerpDouble(_from, _to, _position.value)!,
                  kGlassSwitchSize.height / 2,
                ),
                width: _kSwitchKnob.width,
                height: _kSwitchKnob.height,
              ),
              child: const _Knob(),
            ),
          )
        else
          _DropStage(
            margin: margin,
            child: AnimatedBuilder(
              animation: Listenable.merge(<Listenable>[_lift, _position]),
              builder: (BuildContext context, Widget? _) => Positioned.fromRect(
                rect: Rect.fromCenter(
                  center: Offset(
                    margin + lerpDouble(_from, _to, _position.value)!,
                    margin + kGlassSwitchSize.height / 2,
                  ),
                  width: _kSwitchKnob.width,
                  height: _kSwitchKnob.height,
                ),
                child: _Drop(
                  rest: _kSwitchKnob,
                  scale: widget.dropScale,
                  widen: widget.dropWiden,
                  lift: Curves.easeOut.transform(_lift.value),
                ),
              ),
            ),
          ),
      ],
    );
    return _enabled ? body : _disabled(body);
  }
}

/// A slider whose knob becomes a clear glass drop while it is held.
///
/// Every frame of a drag changes the fill under the drop, so every frame of a
/// drag is a capture — see the file comment. The knob moving is not.
class GlassSlider extends StatefulWidget {
  const GlassSlider({
    required this.value,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.activeColor = const Color(0xFF0A84FF),
    this.trackColor = const Color(0x29787880),
    this.dropScale = kGlassDropScale,
    this.dropWiden = 0,
    this.semanticLabel,
    this.semanticStep = 0.1,
    super.key,
  }) : assert(dropScale >= 1),
       assert(semanticStep > 0 && semanticStep <= 1);

  /// How much larger the held drop is than the resting knob. See
  /// [kGlassDropScale]; macOS's own slider is 1.4.
  final double dropScale;

  /// See [GlassSwitch.dropWiden]. 0, because iOS's slider drop does not
  /// minify (D218).
  final double dropWiden;

  /// Between 0 and 1.
  final double value;

  /// Null disables the slider; it is then drawn at [kGlassDisabledOpacity].
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final Color activeColor;
  final Color trackColor;

  /// What a screen reader says the slider is for. Null leaves it to a
  /// `MergeSemantics` around the slider and its row's label.
  final String? semanticLabel;

  /// How far a screen reader's increase or decrease moves the value: a tenth,
  /// as Flutter's own continuous slider does.
  final double semanticStep;

  @override
  State<GlassSlider> createState() => _GlassSliderState();
}

class _GlassSliderState extends State<GlassSlider> with SingleTickerProviderStateMixin {
  late final AnimationController _lift = AnimationController(
    vsync: this,
    duration: kGlassDropDuration,
  );

  @override
  void didUpdateWidget(GlassSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled) {
      // Disabled mid-drag: see the switch's.
      _lift.value = 0;
    }
  }

  @override
  void dispose() {
    _lift.dispose();
    super.dispose();
  }

  bool get _enabled => widget.onChanged != null;

  double _valueAt(Offset local) {
    final double width = (context.findRenderObject()! as RenderBox).size.width;
    final double span = width - _kSliderKnob.width;
    if (span <= 0) {
      return widget.value;
    }
    return ((local.dx - _kSliderKnob.width / 2) / span).clamp(0.0, 1.0);
  }

  void _start(Offset local) {
    _lift.forward();
    final double v = _valueAt(local);
    widget.onChangeStart?.call(widget.value);
    widget.onChanged?.call(v);
  }

  void _end() {
    _lift.reverse();
    widget.onChangeEnd?.call(widget.value);
  }

  /// A screen reader's increase or decrease: a whole change, start to end, with
  /// no drop, since nothing is held.
  void _step(double to) {
    widget.onChangeStart?.call(widget.value);
    widget.onChanged?.call(to);
    widget.onChangeEnd?.call(to);
  }

  static String _percent(double v) => '${(v * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final double margin = (widget.dropScale - 1) * _kSliderKnob.width / 2 + 4;
    final double value = widget.value.clamp(0.0, 1.0);
    final double up = (value + widget.semanticStep).clamp(0.0, 1.0);
    final double down = (value - widget.semanticStep).clamp(0.0, 1.0);
    return Semantics(
      slider: true,
      label: widget.semanticLabel,
      enabled: _enabled,
      value: _percent(value),
      increasedValue: _enabled && up != value ? _percent(up) : null,
      decreasedValue: _enabled && down != value ? _percent(down) : null,
      onIncrease: _enabled && up != value ? () => _step(up) : null,
      onDecrease: _enabled && down != value ? () => _step(down) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _enabled ? (DragStartDetails d) => _start(d.localPosition) : null,
        onHorizontalDragUpdate: _enabled
            ? (DragUpdateDetails d) => widget.onChanged?.call(_valueAt(d.localPosition))
            : null,
        onHorizontalDragEnd: _enabled ? (_) => _end() : null,
        onTapDown: _enabled ? (TapDownDetails d) => _start(d.localPosition) : null,
        onTapUp: _enabled ? (_) => _end() : null,
        onTapCancel: _enabled ? () => _lift.reverse() : null,
        child: SizedBox(height: kGlassMinTapTarget.height, child: _sliderBody(value, margin)),
      ),
    );
  }

  Widget _sliderBody(double value, double margin) {
    final Widget body = Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(painter: _SliderTrack(value, widget.trackColor, widget.activeColor)),
          ),
        ),
        if (!_enabled)
          // The same box the drop's region pads back down to, so the knob sits
          // where the enabled one does.
          Positioned.fill(
            child: Align(
              alignment: Alignment(value * 2 - 1, 0),
              child: SizedBox.fromSize(size: _kSliderKnob, child: const _Knob()),
            ),
          )
        else
          _DropStage(
            margin: margin,
            child: Positioned.fill(
              child: Padding(
                padding: EdgeInsets.all(margin),
                child: AnimatedBuilder(
                  animation: _lift,
                  // `Align` puts the resting knob's centre at
                  // `rest / 2 + value * (width - rest)`, which is where
                  // [SliderGeometry.fillEnd] ends the fill.
                  builder: (BuildContext context, Widget? _) => Align(
                    alignment: Alignment(value * 2 - 1, 0),
                    child: _Drop(
                      rest: _kSliderKnob,
                      scale: widget.dropScale,
                      widen: widget.dropWiden,
                      lift: Curves.easeOut.transform(_lift.value),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    return _enabled ? body : _disabled(body);
  }
}

class _SliderTrack extends CustomPainter {
  _SliderTrack(this.value, this.track, this.active);

  final double value;
  final Color track;
  final Color active;

  @override
  void paint(Canvas canvas, Size size) {
    final double y = size.height / 2;
    final Rect bar = Rect.fromLTRB(
      _kSliderKnob.width / 2 - _kSliderTrack / 2,
      y - _kSliderTrack / 2,
      size.width - _kSliderKnob.width / 2 + _kSliderTrack / 2,
      y + _kSliderTrack / 2,
    );
    final RRect whole = RRect.fromRectAndRadius(bar, const Radius.circular(_kSliderTrack / 2));
    canvas.drawRRect(whole, Paint()..color = track);
    // The fill is a capsule of its own, not the track clipped: a clip cuts
    // its end square, and the lifted drop is clear and magnifies exactly that
    // end (Apple's held slider rounds it, spike 27 `held/`). Shorter than the
    // track is thick, it cannot be a capsule ending at `end`, so it is the
    // track's own cap cut there, which the resting knob covers anyway.
    final double end = SliderGeometry.fillEnd(value, size.width);
    final RRect fill = RRect.fromLTRBR(
      bar.left,
      bar.top,
      math.max(end, bar.left + _kSliderTrack),
      bar.bottom,
      const Radius.circular(_kSliderTrack / 2),
    );
    canvas
      ..save()
      ..clipRect(Rect.fromLTRB(bar.left, bar.top, end, bar.bottom))
      ..drawRRect(fill, Paint()..color = active)
      ..restore();
  }

  @override
  bool shouldRepaint(_SliderTrack oldDelegate) =>
      oldDelegate.value != value || oldDelegate.track != track || oldDelegate.active != active;
}

/// Where the slider's fill ends for a value, on a slider [width] wide.
abstract final class SliderGeometry {
  static double fillEnd(double value, double width) =>
      _kSliderKnob.width / 2 + value * math.max(0, width - _kSliderKnob.width);
}
