import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/ui/navigation_indicator_geometry.dart';

void main() {
  for (final width in [288.0, 358.0, 440.0]) {
    for (final position in [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0]) {
      test('independent expansion preserves center: $width $position', () {
        final rest = NavigationIndicatorGeometry.resolve(
            width: width, position: position, press: 0, speed: 0);
        final pressed = NavigationIndicatorGeometry.resolve(
            width: width, position: position, press: 1, speed: 0);
        expect((pressed.center - rest.center).distance, lessThan(0.0001));
        expect(pressed.width - rest.width, closeTo(24, 0.0001));
        expect(pressed.height - rest.height, 20);
        final fast = NavigationIndicatorGeometry.resolve(
            width: width, position: position, press: 1.08, speed: 1);
        expect((fast.center - rest.center).distance, lessThan(0.0001));
        // The bar has 16px horizontal margin and 12px vertical margin.
        expect(fast.left, greaterThanOrEqualTo(-12));
        expect(fast.right, lessThanOrEqualTo(width + 12));
        expect(fast.top, greaterThanOrEqualTo(-12));
        expect(fast.bottom, lessThanOrEqualTo(76));
      });
    }
  }
}
