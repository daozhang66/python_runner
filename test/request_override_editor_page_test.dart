import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/l10n/app_localizations.dart';
import 'package:python_runner/pages/request_override_editor_page.dart';
import 'package:python_runner/services/network_debug_config.dart';
import 'package:python_runner/services/request_override_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    await RequestOverrideConfig.instance.load();
    await NetworkDebugConfig.instance.load();
  });

  Widget buildPage() => MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const RequestOverrideEditorPage(),
      );

  testWidgets('shows full override editor and disables unavailable debug proxy',
      (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.text('全局覆盖'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('域名规则'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('域名规则'), findsOneWidget);
    expect(find.text('有效覆盖预览'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('保存覆盖配置'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('保存覆盖配置'), findsOneWidget);

    final proxyToggle = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, '脚本未指定代理时使用调试代理'),
    );
    expect(proxyToggle.onChanged, isNull);
  });

  testWidgets('shows field feedback for an invalid domain rule',
      (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('添加域名规则'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('添加域名规则'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'https://invalid');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('请求覆盖配置无效'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
