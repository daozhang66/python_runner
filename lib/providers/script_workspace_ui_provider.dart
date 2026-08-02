import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_provider.dart';

/// Persisted presentation preferences only. Script business state is owned by
/// `scriptWorkspaceControllerProvider` (Level 2 Riverpod migration complete);
/// this provider keeps UI-only preferences separate from business data.
class ScriptWorkspaceUiState {
  const ScriptWorkspaceUiState({
    required this.isGridView,
    this.selectedScriptName,
  });

  final bool isGridView;
  final String? selectedScriptName;

  ScriptWorkspaceUiState copyWith({
    bool? isGridView,
    String? selectedScriptName,
    bool clearSelectedScript = false,
  }) {
    return ScriptWorkspaceUiState(
      isGridView: isGridView ?? this.isGridView,
      selectedScriptName: clearSelectedScript
          ? null
          : selectedScriptName ?? this.selectedScriptName,
    );
  }
}

class ScriptWorkspaceUiNotifier extends StateNotifier<ScriptWorkspaceUiState> {
  ScriptWorkspaceUiNotifier(this._preferences)
      : super(
          ScriptWorkspaceUiState(
            isGridView: _preferences.getBool(_gridViewKey) ?? false,
            selectedScriptName: _preferences.getString(_selectedScriptKey),
          ),
        );

  static const _gridViewKey = 'script_grid_view';
  static const _selectedScriptKey = 'script_tablet_selected_name';

  final SharedPreferences _preferences;

  Future<void> setGridView(bool value) async {
    if (state.isGridView == value) return;
    state = state.copyWith(isGridView: value);
    await _preferences.setBool(_gridViewKey, value);
  }

  Future<void> setSelectedScript(String? name) async {
    final normalized = name?.trim();
    if (state.selectedScriptName == normalized) return;
    state = state.copyWith(
      selectedScriptName: normalized,
      clearSelectedScript: normalized == null || normalized.isEmpty,
    );
    if (normalized == null || normalized.isEmpty) {
      await _preferences.remove(_selectedScriptKey);
    } else {
      await _preferences.setString(_selectedScriptKey, normalized);
    }
  }
}

final scriptWorkspaceUiProvider =
    StateNotifierProvider<ScriptWorkspaceUiNotifier, ScriptWorkspaceUiState>(
  (ref) => ScriptWorkspaceUiNotifier(ref.watch(sharedPreferencesProvider)),
);
