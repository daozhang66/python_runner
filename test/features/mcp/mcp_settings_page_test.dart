import 'package:python_runner/ui/app_liquid_host.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/mcp/application/mcp_confirmation_service.dart';
import 'package:python_runner/features/mcp/application/mcp_server_controller.dart';
import 'package:python_runner/features/mcp/infrastructure/mcp_server_adapter.dart';
import 'package:python_runner/features/mcp/infrastructure/mcp_token_store.dart';
import 'package:python_runner/features/mcp/infrastructure/mcp_tool_registry.dart';
import 'package:python_runner/features/mcp/presentation/pages/mcp_settings_page.dart';
import 'package:python_runner/l10n/app_localizations.dart';
import 'package:python_runner/providers/theme_provider.dart';
import 'package:python_runner/ui/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/mcp_test_helper.dart';
import '../../support/mcp_token_test_helper.dart';

const _originalKey = 'original-key-for-ui-testing-123456';
Finder get _preview => find.byKey(const ValueKey('mcp-token-value'));
Finder _key(String key) => find.byKey(ValueKey(key));

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

  testWidgets(
      'first authenticated start displays the automatically generated key',
      (tester) async {
    final storage = MemoryTokenStorage();
    final container = (await tester.runAsync(() async {
      final container = await _makeContainer(storage);
      final controller = container.read(mcpServerControllerProvider.notifier);
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      await controller.setPort(port);
      await controller.start();
      return container;
    }))!;
    final controller = container.read(mcpServerControllerProvider.notifier);
    try {
      await _pumpMcp(tester, existing: container);
      expect(container.read(mcpServerControllerProvider).status,
          McpServerStatus.running);
      await _show(tester, _preview);
      final generated = container.read(mcpTokenStoreProvider).token!;
      expect(generated, hasLength(64));
      expect(tester.widget<SelectableText>(_preview).data, generated);
      expect(storage.writes, 1);
      expect(storage.value, generated);
    } finally {
      await tester.runAsync(controller.stop);
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
      'regeneration refreshes the complete preview without switching state',
      (tester) async {
    final container = await _pumpMcp(tester);
    await _show(tester, _preview);
    expect(tester.widget<SelectableText>(_preview).data, _originalKey);
    final prior = container.read(mcpServerControllerProvider);
    for (var i = 0; i < 2; i++) {
      final old = container.read(mcpTokenStoreProvider).token;
      await _show(tester, _key('mcp-regenerate-token'));
      await tester.tap(_key('mcp-regenerate-token'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
      await tester.pumpAndSettle();
      final current = container.read(mcpTokenStoreProvider).token!;
      expect(current, isNot(old));
      expect(tester.widget<SelectableText>(_preview).data, current);
      expect(container.read(mcpServerControllerProvider).requireToken,
          prior.requireToken);
      expect(container.read(mcpServerControllerProvider).status, prior.status);
    }
  });

  testWidgets(
      'custom keys validate, save, copy and immediately invalidate sessions',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final container = await _pumpMcp(tester);
    final sessions = container.read(mcpSessionStoreProvider);
    sessions.create(
        clientName: 'test', clientVersion: '1', protocolVersion: '2025-06-18');
    final confirmations = container.read(mcpConfirmationServiceProvider);
    final decision = confirmations.request(
        toolName: 'test', summary: 'test', clientLabel: 'test');
    await _show(tester, _key('mcp-custom-token'));
    await tester.tap(_key('mcp-custom-token'));
    await tester.pumpAndSettle();
    final field = _key('mcp-custom-token-field');
    expect(tester.widget<TextField>(field).obscureText, isFalse);
    await tester.enterText(field, 'short');
    await tester.tap(_key('mcp-save-custom-token'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).decoration!.errorText, isNotNull);
    expect(container.read(mcpTokenStoreProvider).token, _originalKey);

    const custom = 'my-custom-key-for-mcp-2026';
    await tester.enterText(field, custom);
    await tester.tap(_key('mcp-save-custom-token'));
    await tester.pumpAndSettle();
    expect(tester.widget<SelectableText>(_preview).data, custom);
    expect(container.read(mcpTokenStoreProvider).verify(custom), isTrue);
    expect(container.read(mcpTokenStoreProvider).verify(_originalKey), isFalse);
    expect(sessions.activeCount, 0);
    expect(await decision, McpConfirmationDecision.deny);
    // The existing confirmation service uses Future.delayed for its timeout.
    // Assert immediate denial first, then drain that already-obsolete callback.
    await tester.pump(const Duration(minutes: 1));
    await _show(tester, _key('mcp-copy-token'));
    await tester.tap(_key('mcp-copy-token'));
    await tester.pumpAndSettle();
    expect(copied, custom);
  });

  testWidgets('failed saves keep the prior key and re-enable editing',
      (tester) async {
    final storage = MemoryTokenStorage(value: _originalKey);
    final container = await _pumpMcp(tester, storage: storage);
    storage.failWrites = true;
    await _show(tester, _key('mcp-custom-token'));
    await tester.tap(_key('mcp-custom-token'));
    await tester.pumpAndSettle();
    await tester.enterText(
        _key('mcp-custom-token-field'), 'new-key-that-cannot-save');
    await tester.tap(_key('mcp-save-custom-token'));
    await tester.pumpAndSettle();
    expect(tester.widget<SelectableText>(_preview).data, _originalKey);
    expect(container.read(mcpTokenStoreProvider).verify(_originalKey), isTrue);
    expect(
        find.text(
            'The key could not be saved. The previous key is unchanged. Try again.'),
        findsOneWidget);
    expect(tester.widget<OutlinedButton>(_key('mcp-custom-token')).onPressed,
        isNotNull);
  });

  testWidgets('storage loading errors can be retried without generating a key',
      (tester) async {
    final storage = MemoryTokenStorage(value: _originalKey)..failReads = true;
    await _pumpMcp(tester, storage: storage);
    await _show(tester, find.text('Retry'));
    storage.failReads = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(tester.widget<SelectableText>(_preview).data, _originalKey);
    expect(storage.writes, 0);
  });

  for (final brightness in Brightness.values) {
    testWidgets('liquid MCP settings ${brightness.name}', (tester) async {
      await _pumpMcp(tester,
          brightness: brightness,
          locale: const Locale('zh'),
          visualStyle: AppVisualStyle.liquid);
      await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
              '../../goldens/global_liquid_mcp_${brightness.name}.png'));
    }, tags: const ['golden']);
    testWidgets('MCP settings ${brightness.name} appearance', (tester) async {
      await _pumpMcp(tester,
          brightness: brightness, locale: const Locale('zh'));
      await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
              '../../goldens/mcp_settings_${brightness.name}.png'));
    }, tags: const ['golden']);
  }

  testWidgets('MCP settings and custom editor fit narrow large-text screens',
      (tester) async {
    await _pumpMcp(tester, width: 320, textScale: 2);
    expect(tester.takeException(), isNull);
    await _show(tester, _key('mcp-custom-token'));
    await tester.tap(_key('mcp-custom-token'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 24; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}

Future<void> _show(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 240,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

Future<ProviderContainer> _pumpMcp(
  WidgetTester tester, {
  MemoryTokenStorage? storage,
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('en'),
  double width = 390,
  double textScale = 1,
  ProviderContainer? existing,
  AppVisualStyle visualStyle = AppVisualStyle.classic,
}) async {
  final container = existing ?? await _makeContainer(storage);
  addTearDown(container.dispose);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.build(
        ColorScheme.fromSeed(seedColor: Colors.blue, brightness: brightness),
        fontFamily: 'MiSans',
        visualStyle: visualStyle,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: AppLiquidHost(child: child!),
      ),
      home: const McpSettingsPage(),
    ),
  ));
  await tester.pumpAndSettle();
  return container;
}

Future<ProviderContainer> _makeContainer(MemoryTokenStorage? storage) async {
  SharedPreferences.setMockInitialValues({
    McpServerController.requireTokenPrefsKey: true,
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    mcpTokenStoreProvider.overrideWith((ref) => McpTokenStore(
        preferences: prefs,
        storage: storage ?? MemoryTokenStorage(value: _originalKey))),
    mcpServerAdapterProvider.overrideWith((ref) => McpServerAdapter(
          tools: McpToolRegistry(FakeMcpApplicationFacade()),
          sessions: ref.read(mcpSessionStoreProvider),
          policy: ref.read(mcpPolicyProvider),
          confirmations: ref.read(mcpConfirmationServiceProvider),
          audit: ref.read(mcpAuditLogProvider),
          serverVersion: 'test',
        )),
  ]);
  return container;
}
