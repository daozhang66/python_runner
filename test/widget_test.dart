import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:python_runner/pages/settings_page.dart';

void main() {
  testWidgets('settings page shows update controls',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(const {});

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          currentThemeMode: ThemeMode.system,
        ),
      ),
    );
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

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          currentThemeMode: ThemeMode.system,
        ),
      ),
    );
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
}
