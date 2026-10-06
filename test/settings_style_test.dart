import 'package:python_runner/ui/app_liquid_host.dart';
import 'package:g1455/g1455.dart' as glass;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/l10n/app_localizations.dart';
import 'package:python_runner/pages/settings_page.dart';
import 'package:python_runner/pages/app_logs_page.dart';
import 'package:python_runner/runtime/runtime_manager.dart';
import 'package:python_runner/runtime/linux_like_backend.dart';
import 'package:python_runner/providers/theme_provider.dart';
import 'package:python_runner/ui/app_theme.dart';
import 'package:python_runner/ui/app_settings_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in {
      'MiSans': 'assets/fonts/MiSansVF.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final loader = FontLoader(font.key);
      loader.addFont(rootBundle.load(font.value));
      await loader.load();
    }
  });

  test(
    'Debian display names preserve the installed runtime backend identity',
    () {
      expect(RuntimeManager.backendDisplayName('linux_like'), 'Debian');
      expect(LinuxLikeBackend().name, 'Debian');
      expect(LinuxLikeBackend().id, 'linux_like');
      expect(
        RuntimeManager.normalizePreferredBackendId('linux_like'),
        'linux_like',
      );
    },
  );

  testWidgets(
    'settings group related controls and keep export inside app logs',
    (tester) async {
      await _pumpSettings(tester, height: 6000);
      final sections = tester
          .widgetList<AppSettingsSection>(find.byType(AppSettingsSection))
          .toList();
      expect(sections.map((section) => section.title), [
        '外观与语言',
        '脚本与存储',
        '运行引擎',
        '网络与连接',
        '诊断与日志',
        '关于与更新',
      ]);
      Finder section(String title) => find.byWidgetPredicate(
        (widget) => widget is AppSettingsSection && widget.title == title,
      );
      expect(
        find.descendant(of: section('脚本与存储'), matching: find.text('备份与恢复')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: section('网络与连接'),
          matching: find.text('AI / MCP 服务'),
        ),
        findsOneWidget,
      );
      expect(find.text('导出完整日志'), findsNothing);
      expect(find.text('Debian（实验）'), findsOneWidget);
      await tester.tap(find.text('应用日志'));
      await tester.pumpAndSettle();
      expect(find.byType(AppLogsPage), findsOneWidget);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('导出日志'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('liquid settings ${brightness.name} appearance', (
      tester,
    ) async {
      await _pumpSettings(
        tester,
        brightness: brightness,
        visualStyle: AppVisualStyle.liquid,
      );
      final dynamic host = tester.state(find.byType(glass.GlassHost));
      final captured = host.recorded as int;
      await tester.pump(const Duration(seconds: 1));
      expect(
        host.recorded as int,
        captured,
        reason: 'An idle page with closed dropdowns must retain its atlas',
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/global_liquid_settings_${brightness.name}.png',
        ),
      );
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -260));
      await tester.pumpAndSettle();
      expect(find.text('设置'), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/settings_header_backup_scrolled_${brightness.name}.png',
        ),
      );
      expect(tester.takeException(), isNull);
    }, tags: const ['golden']);
    testWidgets('settings ${brightness.name} appearance', (tester) async {
      await _pumpSettings(tester, brightness: brightness);
      expect(find.byType(Card), findsWidgets);
      for (final section in tester.widgetList<AppSettingsSection>(
        find.byType(AppSettingsSection),
      )) {
        expect(section.framed, isTrue);
      }
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/settings_soft_${brightness.name}.png'),
      );
    }, tags: const ['golden']);
  }

  for (final locale in ['zh', 'en']) {
    testWidgets('settings stay usable at 320 width and 2x text: $locale', (
      tester,
    ) async {
      await _pumpSettings(
        tester,
        width: 320,
        textScale: 2,
        locale: Locale(locale),
      );
      expect(tester.takeException(), isNull);
      for (var step = 0; step < 28; step++) {
        await tester.drag(
          find.byType(CustomScrollView).first,
          const Offset(0, -400),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      expect(position.pixels, closeTo(position.maxScrollExtent, 1));
    });
  }

  testWidgets('wide settings constrain forms without moving their sections', (
    tester,
  ) async {
    await _pumpSettings(tester, width: 1024);
    expect(
      tester.getSize(find.byType(AppSettingsSection).first).width,
      lessThanOrEqualTo(760),
    );
    expect(find.text('语言'), findsOneWidget);
    expect(find.text('主题与配色'), findsOneWidget);
  });

  testWidgets('proxy fields use readable rows on narrow screens', (
    tester,
  ) async {
    await _pumpSettings(
      tester,
      width: 320,
      textScale: 2,
      initialPreferences: const {'net_debug_mode': true},
    );
    final host = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.hintText == '192.168.1.100',
    );
    await tester.scrollUntilVisible(
      host,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(host).width, greaterThan(230));
    final port = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.hintText == '8888',
    );
    expect(
      tester.getTopLeft(port).dy,
      greaterThan(tester.getBottomLeft(host).dy),
    );
    expect(tester.getSize(port).width, greaterThan(180));
  });
}

Future<void> _pumpSettings(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  double width = 390,
  double height = 844,
  double textScale = 1,
  Locale locale = const Locale('zh'),
  Map<String, Object> initialPreferences = const {},
  AppVisualStyle visualStyle = AppVisualStyle.classic,
}) async {
  SharedPreferences.setMockInitialValues(initialPreferences);
  final preferences = await SharedPreferences.getInstance();
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(
          ColorScheme.fromSeed(seedColor: Colors.blue, brightness: brightness),
          fontFamily: 'MiSans',
          visualStyle: visualStyle,
        ),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: AppLiquidHost(child: child!),
        ),
        home: const SettingsPage(currentThemeMode: ThemeMode.system),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
