import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/app_theme_palette.dart';

/// Color 转 ARGB32 扩展方法
extension ColorExt on Color {
  int toARGB32() =>
      (a * 255).round() << 24 |
      (r * 255).round() << 16 |
      (g * 255).round() << 8 |
      (b * 255).round();
}

/// 内置字体选项
enum AppFontFamily {
  /// 跟随系统默认字体
  system,

  /// MiSans 字体
  miSans,
}

/// App Theme State
class ThemeState {
  final ThemeMode mode;
  final Color seedColor;
  final bool useDynamicColor;
  final AppFontFamily fontFamily;
  final DynamicSchemeVariant schemeVariant;

  /// 用户自定义颜色列表
  final List<Color> customColors;

  /// 系统动态色原始 primary（由 DynamicColorBuilder 提供）
  final Color? dynamicPrimary;

  /// 选中的预设主题（如果有）
  final AppThemePalette? selectedPreset;

  /// 启用对话框毛玻璃效果（需要配色算法支持）
  final bool enableBlurEffect;

  const ThemeState({
    required this.mode,
    required this.seedColor,
    this.useDynamicColor = false,
    this.fontFamily = AppFontFamily.system,
    this.schemeVariant = DynamicSchemeVariant.tonalSpot,
    this.customColors = const [],
    this.dynamicPrimary,
    this.selectedPreset,
    this.enableBlurEffect = false,
  });

  /// 获取实际用于 ThemeData 的 fontFamily 字符串
  String? get fontFamilyName {
    switch (fontFamily) {
      case AppFontFamily.miSans:
        return 'MiSans';
      case AppFontFamily.system:
        return null;
    }
  }

  ThemeState copyWith({
    ThemeMode? mode,
    Color? seedColor,
    bool? useDynamicColor,
    AppFontFamily? fontFamily,
    DynamicSchemeVariant? schemeVariant,
    List<Color>? customColors,
    Color? dynamicPrimary,
    AppThemePalette? selectedPreset,
    bool clearPreset = false,
    bool? enableBlurEffect,
  }) {
    return ThemeState(
      mode: mode ?? this.mode,
      seedColor: seedColor ?? this.seedColor,
      useDynamicColor: useDynamicColor ?? this.useDynamicColor,
      fontFamily: fontFamily ?? this.fontFamily,
      schemeVariant: schemeVariant ?? this.schemeVariant,
      customColors: customColors ?? this.customColors,
      dynamicPrimary: dynamicPrimary ?? this.dynamicPrimary,
      selectedPreset:
          clearPreset ? null : (selectedPreset ?? this.selectedPreset),
      enableBlurEffect: enableBlurEffect ?? this.enableBlurEffect,
    );
  }
}

/// App Theme Notifier
class ThemeNotifier extends StateNotifier<ThemeState> {
  static const String _themeModeKey = 'theme_mode';
  static const String _seedColorKey = 'seed_color';
  static const String _dynamicColorKey = 'use_dynamic_color';
  static const String _fontFamilyKey = 'font_family';
  static const String _schemeVariantKey = 'scheme_variant';
  static const String _customColorsKey = 'custom_colors';
  static const String _selectedPresetKey = 'selected_preset';
  static const String _enableBlurEffectKey = 'enable_blur_effect';

  final SharedPreferences _prefs;

  // FluxDO 经典预设颜色（补充到 Python Runner 的 9 个主题之外）
  static const List<Color> fluxdoClassicColors = [
    Colors.blue, // 蓝色
    Colors.green, // 绿色
    Colors.orange, // 橙色
    Colors.pink, // 粉色
    Colors.teal, // 青色
    Colors.red, // 红色
    Colors.indigo, // 靛蓝
    Colors.amber, // 琥珀
  ];

  ThemeNotifier(this._prefs) : super(_loadTheme(_prefs));

  static ThemeState _loadTheme(SharedPreferences prefs) {
    // Load Mode
    final savedMode = prefs.getString(_themeModeKey);
    ThemeMode mode = ThemeMode.system;
    if (savedMode == 'light') {
      mode = ThemeMode.light;
    } else if (savedMode == 'dark') {
      mode = ThemeMode.dark;
    }

    // 迁移旧版主题配置
    final oldPaletteKey = prefs.getString('theme_palette');
    Color? migratedColor;
    AppThemePalette? migratedPreset;

    if (oldPaletteKey != null) {
      migratedPreset = AppThemePalette.fromKey(oldPaletteKey);
      if (migratedPreset.isSeedBased) {
        migratedColor = migratedPreset.lightSeed;
      }
      prefs.remove('theme_palette'); // 清理旧配置
    }

    // Load Color
    final savedColorValue = prefs.getInt(_seedColorKey);
    Color seedColor = migratedColor ?? Colors.blue;
    if (savedColorValue != null) {
      seedColor = Color(savedColorValue);
    }

    // Load Selected Preset
    final savedPresetKey = prefs.getString(_selectedPresetKey);
    AppThemePalette? selectedPreset = migratedPreset;
    if (savedPresetKey != null) {
      selectedPreset = AppThemePalette.fromKey(savedPresetKey);
    }

    // Load Dynamic Color
    final oldMaterialYou = prefs.getBool('material_you_enabled');
    final useDynamicColor =
        prefs.getBool(_dynamicColorKey) ?? oldMaterialYou ?? false;
    if (oldMaterialYou != null) {
      prefs.remove('material_you_enabled'); // 清理旧配置
    }

    // Load Font Family
    final savedFontFamily = prefs.getString(_fontFamilyKey);
    AppFontFamily fontFamily = AppFontFamily.system;
    if (savedFontFamily == 'monospace' ||
        savedFontFamily == 'miSans' ||
        savedFontFamily == 'MiSans') {
      fontFamily = AppFontFamily.miSans;
    }

    // Load Scheme Variant
    final savedVariant = prefs.getString(_schemeVariantKey);
    DynamicSchemeVariant schemeVariant = DynamicSchemeVariant.tonalSpot;
    for (final v in DynamicSchemeVariant.values) {
      if (v.name == savedVariant) {
        schemeVariant = v;
        break;
      }
    }

    // Load Custom Colors
    final savedCustomColors = prefs.getStringList(_customColorsKey) ?? [];
    final customColors = savedCustomColors
        .map((s) => int.tryParse(s))
        .where((v) => v != null)
        .map((v) => Color(v!))
        .toList();

    // Load Blur Effect
    final enableBlurEffect = prefs.getBool(_enableBlurEffectKey) ?? false;

    return ThemeState(
      mode: mode,
      seedColor: seedColor,
      useDynamicColor: useDynamicColor,
      fontFamily: fontFamily,
      schemeVariant: schemeVariant,
      customColors: customColors,
      selectedPreset: selectedPreset,
      enableBlurEffect: enableBlurEffect,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(mode: mode);
    String value = 'system';
    if (mode == ThemeMode.light) {
      value = 'light';
    } else if (mode == ThemeMode.dark) {
      value = 'dark';
    }
    await _prefs.setString(_themeModeKey, value);
  }

  Future<void> setSeedColor(Color color) async {
    state = state.copyWith(
      seedColor: color,
      useDynamicColor: false,
      clearPreset: true,
    );
    await _prefs.setInt(_seedColorKey, color.toARGB32());
    await _prefs.setBool(_dynamicColorKey, false);
    await _prefs.remove(_selectedPresetKey);
  }

  Future<void> setPresetTheme(AppThemePalette preset) async {
    if (preset.isSeedBased && preset.lightSeed != null) {
      state = state.copyWith(
        seedColor: preset.lightSeed!,
        useDynamicColor: false,
        selectedPreset: preset,
      );
      await _prefs.setInt(_seedColorKey, preset.lightSeed!.toARGB32());
      await _prefs.setBool(_dynamicColorKey, false);
      await _prefs.setString(_selectedPresetKey, preset.key);
    }
  }

  Future<void> setUseDynamicColor(bool value) async {
    state = state.copyWith(useDynamicColor: value, clearPreset: value);
    await _prefs.setBool(_dynamicColorKey, value);
    if (value) {
      await _prefs.remove(_selectedPresetKey);
    }
  }

  void setDynamicPrimary(Color? color) {
    if (state.dynamicPrimary != color) {
      state = state.copyWith(dynamicPrimary: color);
    }
  }

  Future<void> setSchemeVariant(DynamicSchemeVariant variant) async {
    state = state.copyWith(schemeVariant: variant);
    await _prefs.setString(_schemeVariantKey, variant.name);
  }

  Future<void> addCustomColor(Color color) async {
    final newColors = [...state.customColors, color];
    state = state.copyWith(customColors: newColors);
    await _saveCustomColors(newColors);
  }

  Future<void> removeCustomColor(Color color) async {
    final newColors = state.customColors
        .where((c) => c.toARGB32() != color.toARGB32())
        .toList();
    state = state.copyWith(customColors: newColors);
    // 如果删除的正好是当前选中色，回退到默认蓝色
    if (state.seedColor.toARGB32() == color.toARGB32() &&
        !state.useDynamicColor) {
      await setSeedColor(Colors.blue);
    }
    await _saveCustomColors(newColors);
  }

  Future<void> _saveCustomColors(List<Color> colors) async {
    await _prefs.setStringList(
      _customColorsKey,
      colors.map((c) => c.toARGB32().toString()).toList(),
    );
  }

  Future<void> setFontFamily(AppFontFamily fontFamily) async {
    state = state.copyWith(fontFamily: fontFamily);
    switch (fontFamily) {
      case AppFontFamily.system:
        await _prefs.setString(_fontFamilyKey, 'system');
      case AppFontFamily.miSans:
        await _prefs.setString(_fontFamilyKey, 'miSans');
    }
  }

  Future<void> setEnableBlurEffect(bool value) async {
    state = state.copyWith(enableBlurEffect: value);
    await _prefs.setBool(_enableBlurEffectKey, value);
  }
}

/// SharedPreferences Provider
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError();
});

/// Theme Provider
final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ThemeNotifier(prefs);
});
