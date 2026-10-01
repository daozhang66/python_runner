import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/l10n/app_localizations.dart';
import 'package:python_runner/ui/app_bottom_navigation.dart';
import 'package:python_runner/ui/app_navigation_pages.dart';

void main() {
  testWidgets('only releasing navigation starts the page transition',
      (tester) async {
    final selected = ValueNotifier(0);
    final commits = <int>[];
    addTearDown(selected.dispose);
    await _pumpPages(tester, selected, commits: commits);
    final controller =
        tester.widget<PageView>(find.byType(PageView)).controller!;
    final pointer = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('navigation-item-0'))));
    await tester.pump();
    await pointer.moveTo(
        tester.getCenter(find.byKey(const ValueKey('navigation-item-1'))));
    await tester.pump(const Duration(milliseconds: 160));
    await pointer.moveTo(
        tester.getCenter(find.byKey(const ValueKey('navigation-item-2'))));
    await tester.pump(const Duration(milliseconds: 160));
    expect(commits, isEmpty);
    expect(controller.page, 0);
    await pointer.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.page, greaterThan(0));
    expect(controller.page, lessThan(2));
    await tester.pumpAndSettle();
    expect(controller.page, closeTo(2, 0.001));
    expect(commits, [2]);
  });

  testWidgets('committed navigation slides and preserves visited page state',
      (tester) async {
    final selected = ValueNotifier(0);
    addTearDown(selected.dispose);
    await _pumpPages(tester, selected);
    await tester.tap(find.text('count 0: 0'));
    await tester.pump();
    expect(find.text('count 0: 1'), findsOneWidget);
    final list = find.byKey(const ValueKey('list-0'));
    await tester.drag(list, const Offset(0, -200));
    await tester.pumpAndSettle();
    final offset = _scrollOffset(tester, list);
    expect(offset, greaterThan(0));

    selected.value = 1;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final controller =
        tester.widget<PageView>(find.byType(PageView)).controller!;
    expect(controller.page, greaterThan(0));
    expect(controller.page, lessThan(1));
    await tester.pumpAndSettle();
    selected.value = 0;
    await tester.pumpAndSettle();
    expect(_scrollOffset(tester, list), closeTo(offset, 0.1));
    await tester.drag(list, const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(find.text('count 0: 1'), findsOneWidget);
  });

  testWidgets('rapid reverse selection finishes on the latest destination',
      (tester) async {
    final selected = ValueNotifier(0);
    addTearDown(selected.dispose);
    await _pumpPages(tester, selected);
    selected.value = 2;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    selected.value = 1;
    await tester.pumpAndSettle();
    final view = tester.widget<PageView>(find.byType(PageView));
    expect(view.controller!.page, closeTo(1, 0.001));
    expect(find.text('count 1: 0'), findsOneWidget);
  });

  testWidgets('content swipes do not hijack the pages', (tester) async {
    final selected = ValueNotifier(0);
    addTearDown(selected.dispose);
    await _pumpPages(tester, selected);
    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<PageView>(find.byType(PageView)).controller!.page, 0);
  });

  for (final animate in [false, true]) {
    testWidgets('reduced motion and disabled transitions jump: $animate',
        (tester) async {
      final selected = ValueNotifier(0);
      addTearDown(selected.dispose);
      await _pumpPages(tester, selected, animate: animate, reduceMotion: true);
      selected.value = 2;
      await tester.pump();
      expect(
          tester.widget<PageView>(find.byType(PageView)).controller!.page, 2);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  }
}

double _scrollOffset(WidgetTester tester, Finder list) => tester
    .state<ScrollableState>(find.descendant(
      of: list,
      matching: find.byType(Scrollable),
    ))
    .position
    .pixels;

Future<void> _pumpPages(WidgetTester tester, ValueNotifier<int> selected,
    {bool animate = true,
    bool reduceMotion = false,
    List<int>? commits}) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: child!,
    ),
    home: ValueListenableBuilder<int>(
      valueListenable: selected,
      builder: (context, index, _) => Scaffold(
        body: AppNavigationPages(
            index: index,
            animate: animate,
            children: const [_ProbePage(0), _ProbePage(1), _ProbePage(2)]),
        bottomNavigationBar: commits == null
            ? null
            : AppBottomNavigation(
                selectedIndex: index,
                onDestinationSelected: (index) {
                  commits.add(index);
                  selected.value = index;
                },
              ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

class _ProbePage extends StatefulWidget {
  const _ProbePage(this.index);
  final int index;
  @override
  State<_ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<_ProbePage> {
  int count = 0;
  @override
  Widget build(BuildContext context) => ListView(
        key: ValueKey('list-${widget.index}'),
        children: [
          TextButton(
            onPressed: () => setState(() => count++),
            child: Text('count ${widget.index}: $count'),
          ),
          for (var i = 0; i < 50; i++)
            SizedBox(height: 48, child: Text('row $i')),
        ],
      );
}
