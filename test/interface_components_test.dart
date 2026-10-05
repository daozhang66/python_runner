import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/l10n/app_localizations.dart';
import 'package:python_runner/ui/app_card.dart';
import 'package:python_runner/ui/app_surfaces.dart';
import 'package:python_runner/ui/app_theme.dart';
import 'package:python_runner/ui/app_visual_style.dart';
import 'package:python_runner/ui/app_liquid_host.dart';
import 'package:g1455/g1455.dart' as glass;

void main() {
  setUpAll(() async {
    for (final font in {
      'MiSans': 'assets/fonts/MiSansVF.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  for (final visual in AppVisualStyle.values) {
    for (final reduced in [false, true]) {
      testWidgets(
        'buttons preserve semantics and motion $visual reduced=$reduced',
        (tester) async {
          var taps = 0;
          await tester.pumpWidget(
            _app(
              visual,
              Brightness.light,
              MediaQuery(
                data: MediaQueryData(disableAnimations: reduced),
                child: Scaffold(
                  body: Column(
                    children: [
                      FilledButton(
                        onPressed: () => taps++,
                        child: const Text('Run'),
                      ),
                      FilledButton.tonal(
                        onPressed: () => taps++,
                        child: const Text('Tonal'),
                      ),
                      const FilledButton(
                        onPressed: null,
                        child: Text('Disabled'),
                      ),
                      OutlinedButton(
                        onPressed: () => taps++,
                        child: const Text('Open'),
                      ),
                      IconButton(
                        onPressed: () => taps++,
                        icon: const Icon(Icons.save),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          final colors = Theme.of(tester.element(find.byType(Scaffold)))
              .colorScheme;
          Color? fill(String label) {
            if (visual == AppVisualStyle.liquid) {
              return tester
                  .widget<glass.GlassSurface>(
                    find
                        .descendant(
                          of: find.widgetWithText(FilledButton, label),
                          matching: find.byType(glass.GlassSurface),
                        )
                        .first,
                  )
                  .finish!
                  .tint;
            }
            return tester
                .widget<Material>(
                  find
                      .descendant(
                        of: find.widgetWithText(FilledButton, label),
                        matching: find.byType(Material),
                      )
                      .first,
                )
                .color;
          }

          expect(fill('Run')!.withValues(alpha: 1), colors.primary);
          expect(
            fill('Tonal')!.withValues(alpha: 1),
            colors.secondaryContainer,
          );
          expect(
            fill('Disabled')!.toARGB32(),
            colors.onSurface.withValues(alpha: 0.12).toARGB32(),
          );
          final button = find.widgetWithText(FilledButton, 'Run');
          final gesture = await tester.startGesture(tester.getCenter(button));
          await tester.pumpAndSettle();
          final scales = tester.widgetList<AnimatedScale>(
            find.descendant(of: button, matching: find.byType(AnimatedScale)),
          );
          expect(
            scales.any((s) => s.scale < 1),
            visual == AppVisualStyle.liquid && !reduced,
          );
          await gesture.up();
          await tester.pumpAndSettle();
          expect(taps, 1);
          await tester.tap(find.text('Disabled'));
          expect(taps, 1);
          await tester.tap(find.text('Open'));
          await tester.tap(find.byIcon(Icons.save));
          await tester.pumpAndSettle();
          expect(taps, 3);
          expect(tester.takeException(), isNull);
          expect(tester.binding.hasScheduledFrame, isFalse);
        },
      );
    }
    for (final brightness in Brightness.values) {
      testWidgets('components appearance ${visual.name} ${brightness.name}', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 620);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          _app(
            visual,
            brightness,
            Scaffold(
              appBar: AppBar(
                title: Text(
                  visual == AppVisualStyle.classic ? '经典 Material' : '液体玻璃',
                ),
              ),
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  AppCard(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '运行脚本',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text('选择脚本并管理运行任务。'),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 12,
                            children: [
                              FilledButton.icon(
                                onPressed: () {},
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('运行'),
                              ),
                              FilledButton.tonal(
                                onPressed: () {},
                                child: const Text('保存'),
                              ),
                            ],
                          ),
                          Wrap(
                            spacing: 12,
                            children: [
                              OutlinedButton(
                                onPressed: () {},
                                child: const Text('打开文件'),
                              ),
                              TextButton(
                                onPressed: () {},
                                child: const Text('取消'),
                              ),
                              IconButton(
                                onPressed: () {},
                                icon: const Icon(Icons.more_horiz),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  AppSurface(
                    margin: EdgeInsets.zero,
                    onTap: () {},
                    child: const ListTile(
                      leading: Icon(Icons.code),
                      title: Text('daily_report.py'),
                      subtitle: Text('今天更新 · 已运行 3 次'),
                      trailing: Icon(Icons.chevron_right),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const TextField(
                    decoration: InputDecoration(hintText: '搜索脚本'),
                  ),
                  const SizedBox(height: 20),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('列表')),
                      ButtonSegment(value: 1, label: Text('宫格')),
                    ],
                    selected: const {0},
                    onSelectionChanged: (_) {},
                  ),
                  const SizedBox(height: 12),
                  const FilledButton(onPressed: null, child: Text('暂无任务')),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/interface_components_${visual.name}_${brightness.name}.png',
          ),
        );
      }, tags: ['golden']);
    }
  }
}

Widget _app(AppVisualStyle visual, Brightness brightness, Widget home) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, child) => AppLiquidHost(child: child!),
      theme: AppTheme.build(
        ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: brightness),
        visualStyle: visual,
        fontFamily: 'MiSans',
      ),
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );
