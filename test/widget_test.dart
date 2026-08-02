import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:python_runner/l10n/app_localizations.dart';
import 'package:python_runner/pages/settings_page.dart';
import 'package:python_runner/providers/theme_provider.dart';

void main() {
  testWidgets('settings page shows update controls',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(_buildSettings(preferences));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('文本前 10 MB，图片最大 30 MB（增加内存占用）'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('文本前 10 MB，图片最大 30 MB（增加内存占用）'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('检查更新'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('检查更新'), findsOneWidget);
    expect(find.text('更新日志'), findsOneWidget);
    expect(find.text('启动时自动检查更新'), findsOneWidget);
  });
  testWidgets('settings page uses official PyPI source wording',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(_buildSettings(preferences));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('PyPI 源'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('PyPI 源'), findsOneWidget);
    expect(find.text('留空使用官方源'), findsOneWidget);
    expect(find.text('恢复官方源'), findsOneWidget);
    expect(find.text('https://pypi.org/simple'), findsOneWidget);
  });

  testWidgets('language selection is in the general section',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(_buildSettings(preferences));
    await tester.pumpAndSettle();

    expect(find.byType(PopupMenuButton<Locale>), findsNothing);
    expect(find.text('语言'), findsOneWidget);
    expect(find.text('中文'), findsOneWidget);

    await tester.tap(find.text('语言'));
    await tester.pumpAndSettle();
    expect(find.text('English'), findsOneWidget);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(preferences.getString('app_locale'), 'en');
  });
}

Widget _buildSettings(SharedPreferences preferences) => ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettingsPage(currentThemeMode: ThemeMode.system),
      ),
    );
