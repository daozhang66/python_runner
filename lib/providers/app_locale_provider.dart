import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_provider.dart';

class AppLocaleNotifier extends StateNotifier<Locale> {
  AppLocaleNotifier(this._preferences) : super(_readLocale(_preferences));

  static const _localeKey = 'app_locale';

  final SharedPreferences _preferences;

  static Locale _readLocale(SharedPreferences preferences) {
    return switch (preferences.getString(_localeKey)) {
      'en' => const Locale('en'),
      _ => const Locale('zh'),
    };
  }

  Future<void> setLocale(Locale locale) async {
    if (state == locale) return;
    state = locale;
    await _preferences.setString(_localeKey, locale.languageCode);
  }
}

final appLocaleProvider = StateNotifierProvider<AppLocaleNotifier, Locale>(
  (ref) => AppLocaleNotifier(ref.watch(sharedPreferencesProvider)),
);
