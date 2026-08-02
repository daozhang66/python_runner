import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/providers/app_locale_provider.dart';
import 'package:python_runner/providers/console_display_preferences_provider.dart';
import 'package:python_runner/providers/script_workspace_ui_provider.dart';
import 'package:python_runner/providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  ProviderContainer createContainer(SharedPreferences preferences) {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('console auto-follow defaults on and persists explicit changes',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final container = createContainer(preferences);

    expect(
      container.read(consoleDisplayPreferencesProvider).autoFollowOutput,
      isTrue,
    );

    await container
        .read(consoleDisplayPreferencesProvider.notifier)
        .setAutoFollowOutput(false);

    expect(preferences.getBool('console_auto_follow_output'), isFalse);
    expect(
      container.read(consoleDisplayPreferencesProvider).autoFollowOutput,
      isFalse,
    );
  });

  test('script selection persists and clears without touching business data',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final container = createContainer(preferences);

    await container
        .read(scriptWorkspaceUiProvider.notifier)
        .setSelectedScript('daily.py');
    expect(preferences.getString('script_tablet_selected_name'), 'daily.py');

    await container
        .read(scriptWorkspaceUiProvider.notifier)
        .setSelectedScript(null);
    expect(
      container.read(scriptWorkspaceUiProvider).selectedScriptName,
      isNull,
    );
    expect(preferences.containsKey('script_tablet_selected_name'), isFalse);
  });

  test('language defaults to Chinese and persists the selected locale',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final container = createContainer(preferences);

    expect(container.read(appLocaleProvider), const Locale('zh'));
    await container
        .read(appLocaleProvider.notifier)
        .setLocale(const Locale('en'));

    expect(preferences.getString('app_locale'), 'en');
    expect(container.read(appLocaleProvider), const Locale('en'));

    final restoredContainer = createContainer(preferences);
    expect(restoredContainer.read(appLocaleProvider), const Locale('en'));

    await restoredContainer
        .read(appLocaleProvider.notifier)
        .setLocale(const Locale('zh'));
    expect(preferences.getString('app_locale'), 'zh');
    expect(restoredContainer.read(appLocaleProvider), const Locale('zh'));
  });

  test('invalid saved language falls back to Chinese', () async {
    SharedPreferences.setMockInitialValues({'app_locale': 'system'});
    final preferences = await SharedPreferences.getInstance();
    final container = createContainer(preferences);

    expect(container.read(appLocaleProvider), const Locale('zh'));
  });
}
