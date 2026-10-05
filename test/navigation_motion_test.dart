import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/ui/navigation_motion.dart';

void main() {
  testWidgets('a new press travels from the visible position before tracking',
      (tester) async {
    final motion = NavigationMotion(vsync: tester, index: 0);
    addTearDown(motion.dispose);
    motion.pressAt(3);
    expect(motion.position, 0,
        reason: 'Pointer down must not teleport the lens');
    expect(motion.preview, 3);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(motion.position, inExclusiveRange(0, 3));
    final visible = motion.position;
    motion.settle(3, pulse: true);
    expect(motion.position, visible);
    await tester.pump(const Duration(milliseconds: 16));
    motion.follow(1.3);
    expect(motion.position, 1.3);
    motion.settle(1);
    await tester.pumpAndSettle();
    expect(motion.position, closeTo(1, 0.001));
    expect(motion.press, closeTo(0, 0.001));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('pointer tracking has no delayed position or trailing stretch',
      (tester) async {
    final motion = NavigationMotion(vsync: tester, index: 0);
    addTearDown(motion.dispose);
    motion.follow(0);
    await tester.pumpAndSettle();
    for (final target in [0.2, 0.7, 1.3, 0.8, 1.6]) {
      motion.follow(target);
      expect(motion.position, target);
      expect(motion.stretch, 0);
      await tester.pump(const Duration(milliseconds: 16));
      expect(motion.position, target);
    }
    await tester.pump(const Duration(milliseconds: 150));
    expect(motion.position, 1.6);
    motion.settle(2);
    expect(motion.position, 1.6);
    await tester.pumpAndSettle();
    expect(motion.position, closeTo(2, 0.001));
  });
  testWidgets('velocity changes deformation, and settle returns to rest',
      (tester) async {
    final fast = NavigationMotion(vsync: tester, index: 0);
    final slow = NavigationMotion(vsync: tester, index: 0);
    addTearDown(fast.dispose);
    addTearDown(slow.dispose);
    fast.follow(0, time: Duration.zero);
    slow.follow(0, time: Duration.zero);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    fast.follow(1, time: const Duration(milliseconds: 16));
    slow.follow(1, time: const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(fast.speed, greaterThan(slow.speed));
    expect(fast.panelOffset.abs(), lessThanOrEqualTo(4));
    expect(fast.press, greaterThan(0));
    fast.settle(1);
    slow.settle(1);
    await tester.pumpAndSettle();
    expect(fast.position, closeTo(1, 0.001));
    expect(fast.press, closeTo(0, 0.001));
    expect(fast.speed, 0);
    expect(fast.panelOffset, closeTo(0, 0.001));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets(
      'reduced motion can interrupt a press without residual animations',
      (tester) async {
    final motion = NavigationMotion(vsync: tester, index: 0);
    addTearDown(motion.dispose);
    motion.follow(2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    motion.setReducedMotion(true, 0);
    await tester.pump();
    expect(motion.position, 2);
    expect(motion.press, 0);
    expect(motion.stretch, 0);
    expect(motion.panelOffset, 0);
    motion.settle(0);
    await tester.pumpAndSettle();
    expect(motion.position, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
