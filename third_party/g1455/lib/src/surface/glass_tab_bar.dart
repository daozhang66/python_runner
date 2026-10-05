// A tab bar whose selection lifts into a glass drop while a finger is on it —
// a drop over another glass, which is what level capture is for (D214).
//
// What it does was read off Apple's own `UITabBar` on iOS 26.5, pressed by
// XCUITest on an iPhone 17 Pro and an iPad Pro simulator (spike 30, D218):
//
//  - at rest the selected item sits on a grey capsule, its icon and label in
//    the accent colour; nothing about it is glass;
//  - pressed, the capsule becomes a clear drop **10.5 pt larger on every
//    side** (73 x 53 -> 94 x 72 on the phone, 85 x 36 -> 110 x 56.5 on the
//    iPad), standing out of the bar above and below, and the bar itself grows
//    by about 8.5 pt across and 2.5 pt down;
//  - the drop **magnifies** what it is over — the bar and its items — 1.17x on
//    both devices once the bar's own growth is taken out;
//  - dragged, it follows the finger, and the item under it takes the accent
//    colour while the one it left gives it up; let go, it settles on the item
//    and that is the selection.
//
// Not taken: Apple's drop disperses at its rim and ours does not (D103 found
// none in the material; the drop is another material), and the bar's items
// grow with it by ~1.05 where ours stay put.
//
// What it costs, by construction rather than by hope:
//
//  - at rest: the bar, one surface; the drop is at materialize 0 and captured
//    for nothing;
//  - held: the drop is glass on glass, so the frames that record take a second
//    snapshot (D214) — while it lifts and the bar grows, every frame; while it
//    moves, **only the frames where the highlighted item changes**, because the
//    highlight is an item, not a blend, and the drop moves inside its own
//    `GlassTravel` behind its own boundary;
//  - the bar's growth is inside a `GlassTravel` of the grown box, so the bar's
//    own capture is not retaken for it.

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import 'glass_components.dart';
import 'glass_controls.dart' show kGlassDropOptics;
import 'glass_finish.dart';
import 'glass_surface.dart';
import 'glass_travel.dart';

/// One item of a [GlassTabBar].
@immutable
class GlassTabItem {
  const GlassTabItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// How much the held drop magnifies the bar under it (D218).
const double kGlassTabDropZoom = 1.17;

/// How much larger than the resting capsule the held drop is, on every side,
/// logical px (D218).
const double kGlassTabDropGrow = 10.5;

/// How much the bar grows while held, logical px per side (D218).
const Size _kBarGrow = Size(8.5, 2.5);

/// The resting capsule: iOS's fill on a light material.
const Color _kPill = Color(0x33787880);

/// Below this much bar per item the items stack icon over label, as an
/// iPhone's do; above it they sit side by side, as an iPad's do.
const double _kInlinePitch = 80;

/// The bar's layout at one width: where the items are and how large the
/// capsule and the drop are. Pure, so the gesture code and the paint agree.
@immutable
class _TabGeometry {
  factory _TabGeometry(double width, int count) {
    final bool inline = (width - 16) / count >= _kInlinePitch;
    // Read off the simulators (D218): the phone's bar is 60 tall with items
    // 66 apart and 7 in from its ends, the capsule 3.5 in from the bar all
    // round; the iPad's is 44 tall, 8 in, the capsule 3 narrower than the
    // pitch. Layout taste where a device had nothing to say.
    final double height = inline ? 44 : 60;
    final double pad = inline ? 8 : 7;
    final double pitch = (width - 2 * pad) / count;
    final Size pill = inline ? Size(pitch - 3, height - 8) : Size(pitch + 7, height - 7);
    return _TabGeometry._(inline, height, pad, pitch, pill);
  }

  const _TabGeometry._(this.inline, this.height, this.pad, this.pitch, this.pill);

  final bool inline;
  final double height;
  final double pad;
  final double pitch;
  final Size pill;

  Size get drop => pill + const Offset(2 * kGlassTabDropGrow, 2 * kGlassTabDropGrow);

  /// The centre of item [i] — fractional while the drop is between two.
  double centre(double i) => pad + pitch * (i + 0.5);

  /// The item index under [x], fractional, clamped to the items.
  double indexAt(double x, int count) => ((x - pad) / pitch - 0.5).clamp(0.0, count - 1.0);

  /// How far the drop reaches past the bar's resting box, per side.
  Size margin(int count) => Size(
    math.max(drop.width / 2 - centre(0), _kBarGrow.width) + 2,
    math.max((drop.height - height) / 2, _kBarGrow.height) + 2,
  );
}

/// A bottom bar of tabs whose selection becomes a glass drop under a finger.
///
/// The bar is a [GlassBar] — the theme's finish, the theme's label colour —
/// and the drop is a clear glass that magnifies it. See the file comment for
/// what each part costs.
class GlassTabBar extends StatefulWidget {
  const GlassTabBar({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.activeColor = const Color(0xFF007AFF),
    this.dropZoom = kGlassTabDropZoom,
    super.key,
  }) : assert(items.length >= 2),
       assert(dropZoom > 0);

  final List<GlassTabItem> items;
  final int selectedIndex;

  /// Null disables the bar.
  final ValueChanged<int>? onSelected;

  /// The selected item's icon and label, and the one under a held drop.
  final Color activeColor;

  /// See [kGlassTabDropZoom]; 1 is a drop that does not magnify.
  final double dropZoom;

  @override
  State<GlassTabBar> createState() => _GlassTabBarState();
}

class _GlassTabBarState extends State<GlassTabBar> with TickerProviderStateMixin {
  /// 0 at rest, 1 held — and past 1 for a moment, because it is a spring.
  late final AnimationController _lift = AnimationController.unbounded(vsync: this);

  /// Where the drop (or the capsule) is, in item units.
  late final AnimationController _at = AnimationController.unbounded(
    vsync: this,
    value: widget.selectedIndex.toDouble(),
  );

  /// The item the drop is over while held; drives the highlight, which is
  /// binary so a drag repaints the items only when it crosses into another.
  final ValueNotifier<int> _over = ValueNotifier<int>(0);

  _TabGeometry? _geometry;
  bool _down = false;
  bool _moved = false;
  double _downX = 0;
  int _pressed = 0;
  VelocityTracker? _tracker;

  // Read off nothing — a feel, like the switch's 180 ms. Critically damped
  // would be no overshoot; this lifts a few percent past and settles.
  static const SpringDescription _liftSpring = SpringDescription(mass: 1, stiffness: 520, damping: 34);
  static const SpringDescription _slideSpring = SpringDescription(mass: 1, stiffness: 380, damping: 36);

  @override
  void initState() {
    super.initState();
    _over.value = widget.selectedIndex;
    _at.addListener(_noteOver);
  }

  @override
  void didUpdateWidget(GlassTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != oldWidget.selectedIndex && !_down) {
      _slideTo(widget.selectedIndex, 0);
    }
  }

  @override
  void dispose() {
    _lift.dispose();
    _at.dispose();
    _over.dispose();
    super.dispose();
  }

  void _noteOver() {
    final int i = _at.value.round().clamp(0, widget.items.length - 1);
    if (i != _over.value) {
      _over.value = i;
    }
  }

  bool get _enabled => widget.onSelected != null;

  // Ends the springs where the motion is under a device pixel, rather than at
  // the default thousandth: every frame of a spring's tail is a frame the bar
  // under the drop changed size, which is a capture.
  static const Tolerance _tolerance = Tolerance(distance: 0.004, velocity: 0.05);

  // And lands exactly on the target once inside it, so a held drop is at
  // materialize 1 and a settled one at 0 — not a spring's last residue of either.
  void _liftTo(double target) {
    _lift
        .animateWith(
          SpringSimulation(_liftSpring, _lift.value, target, _lift.velocity, tolerance: _tolerance),
        )
        .then((_) => _lift.value = target);
  }

  void _slideTo(int index, double velocity) {
    _at
        .animateWith(
          SpringSimulation(_slideSpring, _at.value, index.toDouble(), velocity, tolerance: _tolerance),
        )
        .then((_) => _at.value = index.toDouble());
  }

  void _onDown(PointerDownEvent e) {
    final _TabGeometry? g = _geometry;
    if (!_enabled || g == null || _down) {
      return;
    }
    _down = true;
    _moved = false;
    _downX = e.localPosition.dx;
    _tracker = VelocityTracker.withKind(e.kind)..addPosition(e.timeStamp, e.localPosition);
    _liftTo(1);
    // A press on another item takes the drop there; a press on the selected
    // one lifts it where it is.
    final int i = _pressed = g.indexAt(e.localPosition.dx, widget.items.length).round();
    _slideTo(i, 0);
  }

  void _onMove(PointerMoveEvent e) {
    final _TabGeometry? g = _geometry;
    if (!_down || g == null) {
      return;
    }
    _tracker?.addPosition(e.timeStamp, e.localPosition);
    if (!_moved && (e.localPosition.dx - _downX).abs() < 4) {
      return;
    }
    _moved = true;
    _at.value = g.indexAt(e.localPosition.dx, widget.items.length);
  }

  void _onUp(PointerUpEvent e) {
    final _TabGeometry? g = _geometry;
    if (!_down || g == null) {
      return;
    }
    _down = false;
    // The drop keeps the finger's speed into the settle, in item units, and a
    // flick carries it on to the item it was heading for.
    final double velocity = _moved ? (_tracker?.getVelocity().pixelsPerSecond.dx ?? 0) / g.pitch : 0;
    // A tap is the item pressed, wherever the drop has got to on its way.
    final int i = _moved ? (_at.value + velocity * 0.08).round().clamp(0, widget.items.length - 1) : _pressed;
    _slideTo(i, velocity);
    _liftTo(0);
    if (i != widget.selectedIndex) {
      widget.onSelected?.call(i);
    }
  }

  void _onCancel(PointerCancelEvent e) {
    if (!_down) {
      return;
    }
    _down = false;
    _slideTo(widget.selectedIndex, 0);
    _liftTo(0);
  }

  // Two `LayoutBuilder`s, and the second is the point. A `LayoutBuilder` is a
  // build scope: every tick of an animation below it schedules it for layout,
  // and one whose constraints are loose — a bar placed with `bottom:` and no
  // height, which is how bars are placed — passes that up to its parent, and
  // the relayout repaints the host's whole screen on every frame of a press.
  // So the outer one only measures the width, and the animated tree lives
  // under an inner one that is given a tight size: a relayout boundary, behind
  // a repaint boundary of its own. And one above the outer one too, for the
  // rebuild a new selection brings.
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    // Tab labels are not text to select, as a button's are not.
    child: SelectionContainer.disabled(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double width = constraints.maxWidth;
          final _TabGeometry g = _geometry = _TabGeometry(width, widget.items.length);
          final Size margin = g.margin(widget.items.length);
          return SizedBox(
            width: width,
            height: math.max(g.height, kGlassMinTapTarget.height),
            child: RepaintBoundary(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints _) => Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _onDown,
                  onPointerMove: _onMove,
                  onPointerUp: _onUp,
                  onPointerCancel: _onCancel,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      // The bar's whole growth is declared, so growing does not retake
                      // the bar's own capture.
                      Positioned(
                        left: -_kBarGrow.width,
                        right: -_kBarGrow.width,
                        top: -_kBarGrow.height,
                        bottom: -_kBarGrow.height,
                        child: GlassTravel(
                          // A boundary of its own, so the bar resizing repaints this
                          // and not the screen it sits on.
                          child: RepaintBoundary(
                            child: Center(
                              child: AnimatedBuilder(
                                animation: _lift,
                                builder: (BuildContext context, Widget? child) {
                                  // In whole device pixels: the drop on the bar shows
                                  // the bar, so a growth under a pixel is a capture that
                                  // changes nothing anybody can see.
                                  final double dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
                                  double px(double v) => (v * dpr).round() / dpr;
                                  final double t = _lift.value.clamp(0.0, 1.2);
                                  final double gx = px(_kBarGrow.width * t);
                                  final double gy = px(_kBarGrow.height * t);
                                  return SizedBox(
                                    width: width + 2 * gx,
                                    height: g.height + 2 * gy,
                                    child: GlassBar(
                                      padding: EdgeInsets.zero,
                                      // Content stays where it was laid out at rest: the
                                      // bar grows around it.
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: <Widget>[
                                          Positioned(
                                            left: gx,
                                            top: gy,
                                            width: width,
                                            height: g.height,
                                            child: child!,
                                          ),
                                          Positioned(
                                            left: gx - margin.width,
                                            top: gy - margin.height,
                                            width: width + 2 * margin.width,
                                            height: g.height + 2 * margin.height,
                                            child: _dropStage(g, margin),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                                child: _content(g),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );

  /// The capsule and the items: everything the drop magnifies.
  Widget _content(_TabGeometry g) => Stack(
    clipBehavior: Clip.none,
    children: <Widget>[
      // The capsule, behind its own boundary: it slides with `_at` at rest and
      // is gone while the drop is up, so a drag repaints nothing here.
      Positioned.fill(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[_lift, _at]),
            builder: (BuildContext context, Widget? _) {
              final double fade = 1 - _lift.value.clamp(0.0, 1.0);
              if (fade <= 0) {
                return const SizedBox.shrink();
              }
              return Stack(
                children: <Widget>[
                  Positioned(
                    left: g.centre(_at.value) - g.pill.width / 2,
                    top: (g.height - g.pill.height) / 2,
                    width: g.pill.width,
                    height: g.pill.height,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        shape: const StadiumBorder(),
                        color: _kPill.withValues(alpha: _kPill.a * fade),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      Positioned.fill(
        child: RepaintBoundary(
          child: ValueListenableBuilder<int>(
            valueListenable: _over,
            builder: (BuildContext context, int over, Widget? _) => Row(
              children: <Widget>[
                SizedBox(width: g.pad),
                for (var i = 0; i < widget.items.length; i++)
                  SizedBox(
                    width: g.pitch,
                    child: _item(g, i, highlighted: i == over),
                  ),
              ],
            ),
          ),
        ),
      ),
    ],
  );

  Widget _item(_TabGeometry g, int i, {required bool highlighted}) {
    final GlassTabItem item = widget.items[i];
    final Color? colour = highlighted ? widget.activeColor : null;
    final Widget icon = Icon(item.icon, size: g.inline ? 20 : 26, color: colour);
    final Widget label = Text(
      item.label,
      maxLines: 1,
      overflow: TextOverflow.fade,
      softWrap: false,
      style: TextStyle(
        fontSize: g.inline ? 12 : 11,
        fontWeight: FontWeight.w600,
        color: colour,
      ),
    );
    return Semantics(
      button: true,
      label: item.label,
      selected: i == widget.selectedIndex,
      enabled: _enabled,
      onTap: _enabled ? () => widget.onSelected?.call(i) : null,
      child: ExcludeSemantics(
        child: g.inline
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  icon,
                  const SizedBox(width: 6),
                  Flexible(child: label),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[icon, const SizedBox(height: 2), label],
              ),
      ),
    );
  }

  /// The drop's region: the bar's resting box plus how far the drop reaches
  /// past it.
  ///
  /// No boundary of its own, unlike the switch's: moving the drop repaints the
  /// bar, whose draw the watch excludes and whose content sits behind its own
  /// boundaries, so nothing the watch reads changes either way — a boundary
  /// here was tried and broke no arm when removed (D218).
  Widget _dropStage(_TabGeometry g, Size margin) => GlassTravel(
    child: AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_lift, _at]),
      builder: (BuildContext context, Widget? _) {
        final double lift = _lift.value;
        final double appear = lift.clamp(0.0, 1.0);
        final Size size = Size(
          lerpDouble(g.pill.width, g.drop.width, lift)!,
          lerpDouble(g.pill.height, g.drop.height, lift)!,
        );
        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned(
              left: margin.width + g.centre(_at.value) - size.width / 2,
              top: margin.height + (g.height - size.height) / 2,
              width: size.width,
              height: size.height,
              child: GlassSurface(
                borderRadius: kGlassCapsule,
                finish: GlassFinish.clear.copyWith(
                  optics: kGlassDropOptics.copyWith(zoom: widget.dropZoom),
                ),
                // The drop arrives by its optics, not its shape: `presence`
                // erodes a lone capsule to its medial axis, which on the
                // way down read as a bright stripe across the item for
                // ~50 ms after the capsule was back. Apple's keeps its
                // outline and fades the bend and the rim in and out.
                materialize: appear,
                labelled: false,
              ),
            ),
          ],
        );
      },
    ),
  );
}
