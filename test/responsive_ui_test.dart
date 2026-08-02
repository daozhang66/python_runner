import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/ui/app_responsive.dart';
import 'package:python_runner/ui/app_state_views.dart';

void main() {
  testWidgets('responsive layout switches at the tablet breakpoint',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(599, 800);

    await tester.pumpWidget(
      const MaterialApp(
        home: AppResponsiveLayout(
          compact: Text('compact'),
          tablet: Text('tablet'),
        ),
      ),
    );
    expect(find.text('compact'), findsOneWidget);
    expect(find.text('tablet'), findsNothing);

    tester.view.physicalSize = const Size(600, 800);
    await tester.pump();
    expect(find.text('compact'), findsNothing);
    expect(find.text('tablet'), findsOneWidget);
  });

  testWidgets('state views expose loading and retry semantics', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            const Expanded(child: AppLoadingState(label: '正在加载脚本')),
            Expanded(
              child: AppErrorState(
                message: '加载失败',
                onRetry: () => retried = true,
              ),
            ),
          ],
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('加载失败'), findsOneWidget);
    await tester.tap(find.text('重试'));
    expect(retried, isTrue);
  });
}
