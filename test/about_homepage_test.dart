import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/l10n/app_localizations.dart';
import 'package:python_runner/pages/settings_page.dart';
import 'package:python_runner/providers/theme_provider.dart';
import 'package:python_runner/ui/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.daozhang.py/native_bridge');
  const homepage = 'github.com/daozhang66/python_runner';

  for (final language in ['zh', 'en']) {
    for (final width in [320.0, 390.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('homepage stays on one line: $language, $width, $scale',
            (tester) async {
          String? opened;
          tester.binding.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'getAppInfo':
                return {'version': '1.5.9'};
              case 'getPythonInfo':
                return {'pythonVersion': '3.11.10'};
              case 'getLinuxLikeRuntimeInfo':
                return {'available': 'false'};
              case 'openUrl':
                opened = (call.arguments as Map)['url'] as String;
                return null;
            }
            return null;
          });
          addTearDown(() => tester.binding.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null));
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 844);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          SharedPreferences.setMockInitialValues({});
          final preferences = await SharedPreferences.getInstance();
          await tester.pumpWidget(ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(preferences),
            ],
            child: MaterialApp(
              theme:
                  AppTheme.build(ColorScheme.fromSeed(seedColor: Colors.blue)),
              locale: Locale(language),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const SettingsPage(currentThemeMode: ThemeMode.system),
            ),
          ));
          await tester.pumpAndSettle();
          final about = find.widgetWithText(
              ListTile, language == 'zh' ? '关于应用' : 'About app');
          await tester.scrollUntilVisible(about.hitTestable(), 350,
              scrollable: find.byType(Scrollable).first);
          await tester.pumpAndSettle();
          await tester.tap(about);
          await tester.pumpAndSettle();
          final link = find.text(homepage);
          await tester.ensureVisible(link);
          await tester.pumpAndSettle();
          final label =
              find.text(language == 'zh' ? '项目主页' : 'Project homepage');
          expect(tester.widget<Text>(label).maxLines, 1);
          expect(tester.widget<Text>(link).maxLines, 1);
          expect(tester.widget<Text>(link).overflow, TextOverflow.ellipsis);
          expect(tester.getCenter(label).dy,
              closeTo(tester.getCenter(link).dy, 1));
          expect(find.byTooltip(homepage), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(link);
          await tester.pumpAndSettle();
          expect(opened, 'https://$homepage');
          if (const bool.fromEnvironment('testLocalSponsor')) {
            final sponsor = find.text(language == 'zh' ? '赞助' : 'Sponsor');
            await tester.ensureVisible(sponsor);
            await tester.pumpAndSettle();
            await tester.tap(sponsor);
            await tester.pumpAndSettle();
            final image = tester.widget<Image>(find.byType(Image));
            expect((image.image as AssetImage).assetName,
                'IMG_20260802_014149.png');
            expect(tester.takeException(), isNull);
            await tester.tap(find.widgetWithText(
                TextButton, language == 'zh' ? '关闭' : 'Close'));
            await tester.pumpAndSettle();
          }
        });
      }
    }
  }
}
