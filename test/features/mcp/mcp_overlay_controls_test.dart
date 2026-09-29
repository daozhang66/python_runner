import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:python_runner/providers/theme_provider.dart';
import 'package:python_runner/features/mcp/application/mcp_server_controller.dart';
import 'package:python_runner/features/mcp/presentation/pages/mcp_settings_page.dart';
import 'package:python_runner/l10n/app_localizations.dart';

class OverlayController extends McpServerController {
  int shown = 0;
  int hidden = 0;

  @override
  McpServerState build() => const McpServerState(
      status: McpServerStatus.running, port: 37891, requireToken: false);

  @override
  Future<List<String>> get lanUrls async => ['http://192.168.1.2:37891/mcp'];

  @override
  Future<void> refreshKeepAlive(
      {bool requestPermission = false, bool showOverlay = false}) async {
    if (showOverlay && requestPermission) shown++;
  }

  @override
  Future<void> hideOverlay() async {
    hidden++;
  }
}

void main() {
  testWidgets('settings can show and hide the ball without stopping MCP',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = OverlayController();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        mcpServerControllerProvider.overrideWith(() => controller),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const McpSettingsPage(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('AI / MCP Service'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    final show = find.text('Show keep-alive overlay');
    final hide = find.text('Hide overlay');
    expect(show, findsOneWidget);
    expect(hide, findsOneWidget);
    await tester.ensureVisible(hide);
    await tester.tap(hide);
    await tester.pumpAndSettle();
    expect(controller.hidden, 1);
    expect(controller.isRunning, isTrue);
    await tester.tap(show);
    await tester.pumpAndSettle();
    expect(controller.shown, 1);
    expect(controller.isRunning, isTrue);
  });
}
