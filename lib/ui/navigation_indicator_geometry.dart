import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'app_navigation_destinations.dart';

/// Expansion changes the silhouette, never the finger's center or tab layout.
abstract final class NavigationIndicatorGeometry {
  static const inset = 6.0;
  static const expansion = EdgeInsets.symmetric(horizontal: 12, vertical: 10);
  static Rect resolve(
      {required double width,
      required double position,
      required double press,
      required double speed}) {
    final slot =
        math.max(0.0, (width - inset * 2) / AppNavigationDestinations.count);
    final horizontal = expansion.horizontal * press + 4 * speed;
    final vertical = expansion.vertical * press - 2 * speed;
    final indicatorWidth = math.min(
        math.max(0.0, slot - 4) + horizontal, math.max(0.0, width + 8));
    final height = 52 + vertical;
    final center = inset +
        (position.clamp(0.0, (AppNavigationDestinations.count - 1).toDouble()) +
                0.5) *
            slot;
    return Rect.fromCenter(
        center: Offset(center, 32), width: indicatorWidth, height: height);
  }
}
