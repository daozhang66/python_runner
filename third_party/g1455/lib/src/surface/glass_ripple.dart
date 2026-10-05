// A viscous wave from where the glass was touched (D229). Not Apple's: iOS 26
// answers a touch with light and a springy scale, and never deforms the
// material. Opt-in, and off under the platform's reduce-motion switch.
//
// **What it costs is the draw and nothing upstream of it.** A wave changes how
// the captured backdrop is sampled and changes neither the backdrop nor the
// surface's content, so it takes no capture and repaints nothing: the glass's
// draw is already recorded at composite time (`glass_draw_layer.dart`), and a
// frame of a wave only invalidates that picture. And it is a separate binary
// (`glass_surface_ripple.frag`) rather than a mode of the surface's, because
// B5 measured a path a program carries and does not take at 52-62% of the
// modes that do not take it: the ripple program is drawn on exactly the frames
// a wave is alive, and a still panel runs the program it always ran.
//
// **The model is linear and closed-form, so the state is a list of events and
// not a simulation.** A touch is two impulses — the press and the release —
// and each launches a front that travels, broadens and decays; the press also
// holds a dimple under the finger, which on release springs back through a
// damped oscillator. Viscosity is one knob over all of it, because in a
// viscous liquid it is one mechanism: damping grows as the square of the
// wavenumber, so a thick liquid loses its ripples (the front is one bump),
// broadens faster, decays sooner and stops overshooting (the dimple settles
// critically damped). Thin, it rings.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// The most waves one draw evaluates; `kMaxWaves` in the shader.
const int kMaxRippleWaves = 4;

/// The bound of the front's profile `exp(-u^2) * 2u` over u, `sqrt(2 / e)`.
/// Shared by the dimple's, which is the same function of `r / sigma`.
const double _kProfileBound = 0.8577638849607068;

/// A wave narrower than this, in displacement px, is gone.
const double _kGone = 0.02;

/// How a glass surface answers a touch with a wave.
///
/// The defaults are chosen by eye, not measured — there is no reference to
/// measure against, since the platform has no such effect.
@immutable
class GlassRipple {
  const GlassRipple({
    this.amplitude = 6,
    this.speed = 360,
    this.width = 12,
    this.viscosity = 0.6,
    this.press = 0.8,
    this.pressRadius = 26,
    this.light = 0.08,
  }) : assert(amplitude >= 0),
       assert(speed > 0),
       assert(width > 0),
       assert(viscosity >= 0 && viscosity <= 1),
       assert(press >= 0),
       assert(pressRadius > 0);

  /// Peak sample displacement of a front at birth, logical px. Every term is
  /// normalised so that this is a bound and not a scale: no fragment moves
  /// further than the sum of the amplitudes alive.
  final double amplitude;

  /// How fast a front travels, logical px per second.
  final double speed;

  /// The front's half-width at birth, logical px.
  final double width;

  /// 0 is thin — the front rings, the dimple overshoots — and 1 is honey: one
  /// bump that broadens and settles without overshooting.
  final double viscosity;

  /// Depth of the dimple held under the finger, as a fraction of [amplitude].
  /// 0 for a ripple with no dimple and no spring-back.
  final double press;

  /// The dimple's radius, logical px.
  final double pressRadius;

  /// How much a slope lit from above brightens (and one facing down darkens),
  /// as a fraction of full scale at the steepest slope. 0 for a wave that only
  /// refracts.
  final double light;

  double _mix(double thin, double thick) => thin + (thick - thin) * viscosity;

  /// Seconds for a front's amplitude to fall by e.
  double get decay => _mix(1.2, 0.45);

  /// px² per second the front's half-width squared grows by.
  double get spread => _mix(150, 1800);

  /// Oscillation inside a front, radians per half-width.
  double get ringing => _mix(3, 0);

  /// The dimple's spring: natural frequency, rad/s, and damping ratio.
  double get springOmega => _mix(26, 16);
  double get springZeta => _mix(0.22, 1);

  /// Seconds for the dimple to sink under a held finger.
  static const double sink = 0.07;

  /// Seconds for a front to rise at birth, so a press does not pop.
  static const double rise = 0.025;

  GlassRipple copyWith({
    double? amplitude,
    double? speed,
    double? width,
    double? viscosity,
    double? press,
    double? pressRadius,
    double? light,
  }) => GlassRipple(
    amplitude: amplitude ?? this.amplitude,
    speed: speed ?? this.speed,
    width: width ?? this.width,
    viscosity: viscosity ?? this.viscosity,
    press: press ?? this.press,
    pressRadius: pressRadius ?? this.pressRadius,
    light: light ?? this.light,
  );

  @override
  bool operator ==(Object other) =>
      other is GlassRipple &&
      other.amplitude == amplitude &&
      other.speed == speed &&
      other.width == width &&
      other.viscosity == viscosity &&
      other.press == press &&
      other.pressRadius == pressRadius &&
      other.light == light;

  @override
  int get hashCode => Object.hash(amplitude, speed, width, viscosity, press, pressRadius, light);

  @override
  String toString() =>
      'GlassRipple(amplitude $amplitude, speed $speed, width $width, viscosity $viscosity, '
      'press $press, pressRadius $pressRadius, light $light)';
}

/// One wave as the shader takes it: two `vec4`s, in the order of the uniform
/// block. Amplitudes are signed heights in displacement px — positive
/// magnifies — and [uniforms] normalises them.
@immutable
class GlassRippleWave {
  const GlassRippleWave({
    required this.centre,
    required this.radius,
    required this.halfWidth,
    required this.front,
    required this.ringing,
    required this.dimple,
    required this.sigma,
  });

  /// The touch, relative to the surface's centre.
  final Offset centre;
  final double radius;
  final double halfWidth;
  final double front;
  final double ringing;
  final double dimple;
  final double sigma;

  /// The most any fragment is displaced by this wave.
  double get bound => front.abs() + dimple.abs();

  /// `uWave[i]` then `uWaveAmp[i]`.
  List<double> uniforms() => <double>[
    centre.dx,
    centre.dy,
    radius,
    halfWidth,
    front / (_kProfileBound + ringing),
    ringing,
    -2 * dimple / (_kProfileBound * sigma),
    1 / (sigma * sigma),
  ];

  /// The displacement this wave puts on a fragment at [rel] from the
  /// surface's centre, before the rim's damping — the shader's loop body,
  /// transliterated, so the bound can be checked without a GPU.
  Offset displacementAt(Offset rel) {
    final List<double> w = uniforms();
    final Offset q = rel - centre;
    final double r2 = q.distanceSquared;
    final double r = math.sqrt(r2 + w[3] * w[3]);
    final double u = (r - w[2]) / w[3];
    final double ku = w[5] * u;
    final double front = w[4] * math.exp(-u * u) * (-2 * u * math.cos(ku) - w[5] * math.sin(ku));
    return q * (front / r + w[6] * math.exp(-r2 * w[7]));
  }
}

class _Touch {
  _Touch(this.pointer, this.at) : position = at;

  final int pointer;

  /// Where the finger landed: the press front's centre, for its whole life.
  final Offset at;

  /// Where the finger is, or left: the dimple's centre and the release
  /// front's. A finger that drags carries its dimple and lets go where it is.
  Offset position;
  double? down;
  double? up;
  bool released = false;

  /// How far the dimple had sunk when the finger left, 0 to 1.
  double sunkAtRelease = 0;
}

/// The waves on one surface: touches in, uniforms out.
///
/// Time is whatever [advance] is given — the frame's timestamp — and an event
/// takes the time of the first frame after it, so every quantity is a function
/// of one clock. Pointer events carry the platform's own, which is another.
class GlassRippleField {
  GlassRippleField(this.ripple);

  GlassRipple ripple;

  final List<_Touch> _touches = <_Touch>[];

  /// The most touches tracked at once; a fifth drops the oldest.
  static const int maxTouches = 4;

  double _now = 0;
  List<GlassRippleWave> _waves = const <GlassRippleWave>[];

  /// The waves to draw, strongest first, at most [kMaxRippleWaves].
  List<GlassRippleWave> get waves => _waves;

  /// Whether anything is drawn.
  bool get isEmpty => _touches.isEmpty;

  /// The bound on the displacement this frame: the sum of the waves' own.
  double get reach => _waves.fold(0, (double s, GlassRippleWave w) => s + w.bound);

  /// Waves that were alive and did not fit in the draw, over the field's life.
  int dropped = 0;

  void down(int pointer, Offset relative) {
    _touches.removeWhere((_Touch t) => t.pointer == pointer && !t.released);
    if (_touches.length >= maxTouches) {
      _touches.removeAt(0);
    }
    _touches.add(_Touch(pointer, relative));
  }

  /// Moves a held finger, and returns whether that moved anything drawn.
  bool move(int pointer, Offset relative) {
    var moved = false;
    for (final _Touch t in _touches) {
      if (t.pointer == pointer && !t.released && t.position != relative) {
        t.position = relative;
        moved = true;
      }
    }
    return moved;
  }

  /// Lets a finger go, at [relative] if given — the release front starts
  /// there, and not where the finger landed.
  void up(int pointer, [Offset? relative]) {
    for (final _Touch t in _touches) {
      if (t.pointer == pointer && !t.released) {
        t.released = true;
        if (relative != null) {
          t.position = relative;
        }
      }
    }
  }

  void clear() {
    _touches.clear();
    _waves = const <GlassRippleWave>[];
  }

  /// Moves the field to [now] and returns whether it will change after it —
  /// false once it is empty, and while a held dimple has settled with no
  /// front left, so a long press costs no frames.
  ///
  /// [extent] is how far from the centre the surface reaches; a front wholly
  /// past it is gone.
  bool advance(Duration now, {required double extent}) {
    _now = now.inMicroseconds / Duration.microsecondsPerSecond;
    for (final _Touch t in _touches) {
      t.down ??= _now;
      if (t.released && t.up == null) {
        t.up = _now;
        t.sunkAtRelease = _sunk(_now - t.down!);
      }
    }
    final List<GlassRippleWave> all = <GlassRippleWave>[];
    var changing = false;
    _touches.removeWhere((_Touch t) {
      final List<GlassRippleWave> waves = _wavesOf(t, extent);
      if (waves.isEmpty) {
        return true;
      }
      all.addAll(waves);
      // Still while held, once the front has left and the dimple has sunk; a
      // drag asks for its own frames.
      final bool settled =
          !t.released && waves.every((GlassRippleWave w) => w.front == 0) && _sunk(_now - t.down!) > 0.999;
      changing = changing || !settled;
      return false;
    });
    all.sort((GlassRippleWave a, GlassRippleWave b) => b.bound.compareTo(a.bound));
    if (all.length > kMaxRippleWaves) {
      dropped += all.length - kMaxRippleWaves;
    }
    _waves = all.take(kMaxRippleWaves).toList(growable: false);
    return changing;
  }

  static double _sunk(double held) => 1 - math.exp(-held / GlassRipple.sink);

  /// The dimple's height after release, from 1: a damped oscillator let go at
  /// rest.
  double _spring(double t) {
    final double w = ripple.springOmega;
    final double z = ripple.springZeta;
    if (z >= 1) {
      return (1 + w * t) * math.exp(-w * t);
    }
    final double wd = w * math.sqrt(1 - z * z);
    return math.exp(-z * w * t) * (math.cos(wd * t) + z * w / wd * math.sin(wd * t));
  }

  /// A front launched [age] seconds ago at [scale] of the amplitude — signed:
  /// the press pushes a trough out, the release a crest — or null if it is
  /// gone.
  ({double radius, double halfWidth, double amplitude})? _front(double age, double scale, double extent, Offset at) {
    final double w0 = ripple.width;
    final double radius = ripple.speed * age;
    final double halfWidth = math.sqrt(w0 * w0 + ripple.spread * age);
    final double amplitude =
        scale *
        ripple.amplitude *
        (1 - math.exp(-age / GlassRipple.rise)) *
        math.exp(-age / ripple.decay) *
        // Broadening flattens the slope, and a circle's front spreads its
        // energy over its length.
        math.sqrt(w0 / halfWidth) /
        math.sqrt(1 + radius / (4 * w0));
    final bool past = radius - 3 * halfWidth > extent + at.distance;
    // Not judged while it is still rising: at birth it is zero by design.
    final bool faded = age > 4 * GlassRipple.rise && amplitude.abs() < _kGone;
    if (past || faded) {
      return null;
    }
    return (radius: radius, halfWidth: halfWidth, amplitude: amplitude);
  }

  /// A bound on [_spring]'s magnitude from [t] on, which falls monotonically
  /// where the spring itself crosses zero.
  double _envelope(double t) {
    final double w = ripple.springOmega;
    final double z = ripple.springZeta;
    if (z >= 1) {
      return (1 + w * t) * math.exp(-w * t);
    }
    return math.exp(-z * w * t) / math.sqrt(1 - z * z);
  }

  /// A touch's waves: the press front from where it landed, the release
  /// front from where it left, and the dimple under the finger, folded into
  /// whichever of the two shares its centre — so a touch that never moved
  /// takes the slots it took before a finger could drag.
  List<GlassRippleWave> _wavesOf(_Touch t, double extent) {
    final double age = _now - t.down!;
    final pressed = _front(age, -1, extent, t.at);
    final double? up = t.up;
    final released = up == null ? null : _front(_now - up, t.sunkAtRelease, extent, t.position);
    final double scale = ripple.press * ripple.amplitude;
    final double depth = up == null ? _sunk(age) : t.sunkAtRelease * _spring(_now - up);
    // Judged by the envelope after release, not by the value: a ringing
    // dimple passes through zero on its way to the overshoot, and a touch
    // judged there would be dropped mid-swing.
    final bool held = up == null ? scale > 0 : scale * t.sunkAtRelease * _envelope(_now - up) >= _kGone;
    final double dimple = held ? -scale * depth : 0;
    final bool still = t.position == t.at;
    return <GlassRippleWave>[
      if (pressed != null || (held && still)) _wave(t.at, pressed, still ? dimple : 0),
      if (released != null || (held && !still)) _wave(t.position, released, still ? 0 : dimple),
    ];
  }

  GlassRippleWave _wave(Offset centre, ({double radius, double halfWidth, double amplitude})? f, double dimple) =>
      GlassRippleWave(
        centre: centre,
        radius: f?.radius ?? 0,
        halfWidth: f?.halfWidth ?? ripple.width,
        front: f?.amplitude ?? 0,
        ringing: ripple.ringing,
        dimple: dimple,
        sigma: ripple.pressRadius,
      );
}
