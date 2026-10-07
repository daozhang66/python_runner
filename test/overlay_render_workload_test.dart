import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g1455/g1455.dart' as glass;
import 'package:g1455/glass_diagnostics.dart' as diagnostics;
import 'package:python_runner/ui/app_liquid_host.dart';
import 'package:python_runner/ui/app_materials.dart';
import 'package:python_runner/ui/app_popup_menu.dart';
import 'package:python_runner/ui/app_theme.dart';
import 'package:python_runner/ui/app_visual_style.dart';
import 'package:python_runner/utils/app_page_transitions.dart';
import 'package:python_runner/widgets/app_dialogs.dart';

void main() {
  for (final kind in [
    'menu',
    'dialog',
    'sheet',
    'custom page',
    'material page',
  ]) {
    testWidgets(
      '$kind bounds glass captures without changing finish during opening',
      (tester) async {
        late BuildContext pageContext;
        Widget destination() => Scaffold(
          body: Center(
            child: AppGlassSurface(
              child: TextButton(
                onPressed: () => Navigator.pop(pageContext),
                child: const Text('Done'),
              ),
            ),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(
              ColorScheme.fromSeed(seedColor: Colors.blue),
              visualStyle: AppVisualStyle.liquid,
            ),
            builder: (_, child) => AppLiquidHost(child: child!),
            home: Builder(
              builder: (context) {
                pageContext = context;
                return Scaffold(
                  body: Center(
                    child: AppGlassSurface(
                      key: const ValueKey('background-glass'),
                      child: kind == 'menu'
                          ? AppPopupMenuButton<int>(
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 1, child: Text('Done')),
                              ],
                              child: const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text('Open'),
                              ),
                            )
                          : TextButton(
                              onPressed: () {
                                switch (kind) {
                                  case 'dialog':
                                    showDialog<void>(
                                      context: context,
                                      builder: (_) => AppAlertDialog(
                                        title: const Text('Confirm'),
                                        content: const Text('Dialog content'),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text('Done'),
                                          ),
                                        ],
                                      ),
                                    );
                                  case 'sheet':
                                    showAppModalBottomSheet<void>(
                                      context: context,
                                      builder: (_) => SizedBox(
                                        height: 180,
                                        child: TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: const Text('Done'),
                                        ),
                                      ),
                                    );
                                  case 'custom page':
                                    Navigator.push(
                                      context,
                                      AppPageTransitions.sharedAxisLeftRight(
                                        destination(),
                                      ),
                                    );
                                  case 'material page':
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder: (_) => destination(),
                                      ),
                                    );
                                }
                              },
                              child: const Text('Open'),
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final handle = diagnostics.GlassProxyScope.maybeOf(
          tester.element(find.byKey(const ValueKey('background-glass'))),
        )!;
        final before = handle.snapshots;
        await tester.tap(find.text('Open'));
        await tester.pump();
        glass.GlassTier? panelTier;
        for (var i = 0; i < 42; i++) {
          await tester.pump(const Duration(microseconds: 8333));
          if (!kind.endsWith('page')) {
            final panels = find.byWidgetPredicate(
              (w) => w is AppGlassSurface && w.overlay,
            );
            final surfaces = find.descendant(
              of: panels,
              matching: find.byType(glass.GlassSurface),
            );
            if (surfaces.evaluate().isNotEmpty) {
              final tier = tester
                  .renderObject<glass.RenderGlassSurface>(surfaces.first)
                  .effectiveTier;
              panelTier ??= tier;
              expect(
                tier,
                panelTier,
                reason: 'The panel finish must not flip at the end of its animation',
              );
            }
          }
        }
        final captures = handle.snapshots - before;
        tester.printToConsole('$kind opening snapshots=$captures');
        // Overlays retain their short entrance animation. Their static page
        // backdrop may update, but the near-opaque panel adds no second capture.
        // Full pages navigate directly and only need a fresh destination frame.
        expect(captures, lessThanOrEqualTo(kind.endsWith('page') ? 4 : 24));
        expect(find.text('Done'), findsOneWidget);
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(find.text('Open'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('classic pages retain their existing transition and result', (
    tester,
  ) async {
    Route<int>? route;
    int? returned;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(ColorScheme.fromSeed(seedColor: Colors.blue)),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                route = AppPageTransitions.fadeThrough<int>(
                  Scaffold(
                    body: TextButton(
                      onPressed: () => Navigator.pop(context, 7),
                      child: const Text('Return'),
                    ),
                  ),
                );
                returned = await Navigator.push(context, route!);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect((route! as PageRoute<int>).animation!.value, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Return'));
    await tester.pumpAndSettle();
    expect(returned, 7);
  });
}
