import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'app_navigation_destinations.dart';

/// Gesture preview is independent of the page's committed selection.
class NavigationMotion extends ChangeNotifier {
  NavigationMotion({required TickerProvider vsync, required int index})
      : _position = AnimationController.unbounded(
            vsync: vsync, value: index.toDouble()),
        _press = AnimationController.unbounded(vsync: vsync),
        _speed = AnimationController.unbounded(vsync: vsync) {
    for (final animation in [_position, _press, _speed]) {
      animation.addListener(notifyListeners);
    }
  }

  static const _positionSpring =
      SpringDescription(mass: 1, stiffness: 500, damping: 40);
  static const _pressSpring =
      SpringDescription(mass: 1, stiffness: 300, damping: 25);
  final AnimationController _position;
  final AnimationController _press;
  final AnimationController _speed;
  double? _preview;
  Duration? _lastTime;
  double _lastTarget = 0;
  double _origin = 0;
  double _releaseStretch = 0;
  double _releasePress = 1;
  double _releaseOffset = 0;
  bool _reduced = false;
  int _transition = 0;
  int? _targetIndex;
  bool _disposed = false;

  bool settlingTo(int index) => _preview == null && _targetIndex == index;

  double get position => _position.value;
  double get press => _reduced ? 0 : _press.value.clamp(0.0, 1.08);
  double get progress => press.clamp(0.0, 1.0);
  double? get preview => _preview;
  double get speed => _reduced ? 0 : _speed.value.abs().clamp(0.0, 1.0);
  double get stretch => _reduced
      ? 0
      : _preview == null
          ? _releaseStretch * (progress / _releasePress).clamp(0, 1)
          : 0;
  double get panelOffset => _reduced
      ? 0
      : _preview == null
          ? _releaseOffset * (progress / _releasePress).clamp(0, 1)
          : ((_preview! - _origin) / (AppNavigationDestinations.count - 1))
                  .clamp(-1.0, 1.0) *
              2 *
              progress;

  void setReducedMotion(bool value, int selectedIndex) {
    if (_reduced == value) return;
    _reduced = value;
    if (value) {
      _transition++;
      _position.value = _preview ?? selectedIndex.toDouble();
      _press.value = 0;
      _speed.value = 0;
      _releaseStretch = 0;
      _releaseOffset = 0;
    }
  }

  /// A new press travels from the visible capsule; only an actual drag snaps
  /// to the pointer. This also lets a tap interrupt a settling spring smoothly.
  void pressAt(double target, {Duration? time}) {
    _transition++;
    _targetIndex = null;
    target =
        target.clamp(0.0, (AppNavigationDestinations.count - 1).toDouble());
    _origin = position;
    _preview = target;
    _lastTime = time;
    _lastTarget = target;
    _releaseStretch = 0;
    _speed.value = 0;
    if (_reduced) {
      _position.value = target;
    } else {
      _position.animateWith(SpringSimulation(
          _positionSpring, position, target, _position.velocity));
      _press.animateWith(
          SpringSimulation(_pressSpring, _press.value, 1, _press.velocity));
    }
    notifyListeners();
  }

  void follow(double target, {Duration? time}) {
    _transition++;
    _targetIndex = null;
    target =
        target.clamp(0.0, (AppNavigationDestinations.count - 1).toDouble());
    final starting = _preview == null;
    if (starting) {
      _origin = position;
      _lastTime = null;
    }
    if (!_reduced && time != null && _lastTime != null) {
      final seconds = (time - _lastTime!).inMicroseconds / 1000000;
      if (seconds > 0) {
        final velocity =
            ((target - _lastTarget) / seconds / 12).clamp(-1.0, 1.0);
        _speed.animateTo(velocity,
            duration: const Duration(milliseconds: 70), curve: Curves.easeOut);
      }
    }
    _lastTime = time;
    _lastTarget = target;
    _preview = target;
    _releaseStretch = 0;
    if (_reduced) {
      _position.value = target;
    } else {
      if (starting) {
        _press.animateWith(SpringSimulation(_pressSpring, _press.value, 1, 0));
      }
      // Track the finger directly. Restarting an ease-out on every event
      // makes the trailing edge catch up after the finger has stopped.
      _position.value = target;
    }
    notifyListeners();
  }

  void settle(int index, {bool pulse = false}) {
    final transition = ++_transition;
    _targetIndex = index;
    final visible = position;
    final velocity = _position.velocity;
    _releaseStretch = stretch;
    _releaseOffset = panelOffset;
    _releasePress = math.max(progress, 0.001);
    _preview = null;
    _lastTime = null;
    _position.value = visible;
    if (_reduced) {
      _position.value = index.toDouble();
      _press.value = 0;
      _speed.value = 0;
    } else {
      _position.animateWith(SpringSimulation(
          _positionSpring, visible, index.toDouble(), velocity));
      if (pulse && progress < 0.7) {
        _press
            .animateTo(1,
                duration: const Duration(milliseconds: 100),
                curve: Curves.easeOutCubic)
            .whenCompleteOrCancel(() {
          if (!_disposed && transition == _transition) {
            _press.animateWith(
                SpringSimulation(_pressSpring, _press.value, 0, 0));
          }
        });
      } else {
        _press.animateWith(SpringSimulation(_pressSpring, _press.value, 0, 0));
      }
      _speed.animateTo(0,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _transition++;
    for (final animation in [_position, _press, _speed]) {
      animation.removeListener(notifyListeners);
      animation.dispose();
    }
    super.dispose();
  }
}
