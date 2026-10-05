import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/ui/app_materials.dart';
import 'package:python_runner/ui/app_popup_menu.dart';
import 'package:python_runner/ui/app_theme.dart';
import 'package:python_runner/ui/app_visual_style.dart';

void main() {
  for (final rtl in [false, true]) {
    testWidgets(
        'glass menu expands from its anchor, selects and cancels: rtl=$rtl',
        (tester) async {
      int? selected;
      var canceled = 0;
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.build(ColorScheme.fromSeed(seedColor: Colors.blue),
              visualStyle: AppVisualStyle.liquid),
          home: Directionality(
              textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
              child: Scaffold(
                  appBar: AppBar(actions: [
                AppPopupMenuButton<int>(
                  onSelected: (value) => selected = value,
                  onCanceled: () => canceled++,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 1, child: Text('Run')),
                    PopupMenuItem(value: 2, child: Text('Edit'))
                  ],
                )
              ])))));
      final trigger = find.byType(AppPopupMenuButton<int>);
      final anchor = tester.getRect(trigger);
      await tester.tap(trigger);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final panel = find.byType(AppGlassSurface);
      final early = tester.getRect(panel);
      expect(early.center.dx, closeTo(anchor.center.dx, 160));
      await tester.pumpAndSettle();
      expect(tester.getRect(panel).width, greaterThan(early.width));
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(selected, 2);
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(canceled, 1);
      expect(find.text('Edit'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('rapid reopen and reduced motion keep one menu route',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(ColorScheme.fromSeed(seedColor: Colors.blue),
            visualStyle: AppVisualStyle.liquid),
        home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
                appBar: AppBar(actions: [
              AppPopupMenuButton<int>(
                  itemBuilder: (_) =>
                      const [PopupMenuItem(value: 1, child: Text('Run'))])
            ])))));
    final state = tester
        .state<PopupMenuButtonState<int>>(find.byType(AppPopupMenuButton<int>));
    state.showButtonMenu();
    state.showButtonMenu();
    await tester.pumpAndSettle();
    expect(find.text('Run'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, false);
  });
}
