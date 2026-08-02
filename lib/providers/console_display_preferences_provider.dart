import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_provider.dart';

class ConsoleDisplayPreferences {
  const ConsoleDisplayPreferences({
    required this.autoFollowOutput,
  });

  final bool autoFollowOutput;

  ConsoleDisplayPreferences copyWith({bool? autoFollowOutput}) {
    return ConsoleDisplayPreferences(
      autoFollowOutput: autoFollowOutput ?? this.autoFollowOutput,
    );
  }
}

class ConsoleDisplayPreferencesNotifier
    extends StateNotifier<ConsoleDisplayPreferences> {
  ConsoleDisplayPreferencesNotifier(this._preferences)
      : super(
          ConsoleDisplayPreferences(
            autoFollowOutput:
                _preferences.getBool(_autoFollowOutputKey) ?? true,
          ),
        );

  static const _autoFollowOutputKey = 'console_auto_follow_output';

  final SharedPreferences _preferences;

  Future<void> setAutoFollowOutput(bool value) async {
    if (state.autoFollowOutput == value) return;
    state = state.copyWith(autoFollowOutput: value);
    await _preferences.setBool(_autoFollowOutputKey, value);
  }
}

final consoleDisplayPreferencesProvider = StateNotifierProvider<
    ConsoleDisplayPreferencesNotifier, ConsoleDisplayPreferences>(
  (ref) => ConsoleDisplayPreferencesNotifier(
    ref.watch(sharedPreferencesProvider),
  ),
);
