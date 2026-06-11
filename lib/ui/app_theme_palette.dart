import 'package:flutter/material.dart';

enum AppThemePalette {
  ocean(
    key: 'ocean',
    label: '海蓝',
    description: '清爽偏理性的默认冷色',
    lightSeed: Color(0xFF2C6BE0),
    darkSeed: Color(0xFF7AA8FF),
    previewColor: Color(0xFF2C6BE0),
    darkOnly: false,
  ),
  jade(
    key: 'jade',
    label: '青玉',
    description: '更柔和的青绿色工作台',
    lightSeed: Color(0xFF0E8F72),
    darkSeed: Color(0xFF52C3A5),
    previewColor: Color(0xFF0E8F72),
    darkOnly: false,
  ),
  claude(
    key: 'claude',
    label: 'Claude',
    description: '暖白纸感与咖啡色调',
    lightSeed: null,
    darkSeed: null,
    previewColor: Color(0xFFD97757),
    darkOnly: false,
  ),
  codex(
    key: 'codex',
    label: 'Codex',
    description: '冷静蓝灰与专业工具感',
    lightSeed: Color(0xFF3D5F85),
    darkSeed: Color(0xFF8EB4DE),
    previewColor: Color(0xFF3D5F85),
    darkOnly: false,
  ),
  vscode(
    key: 'vscode',
    label: 'VS Code',
    description: '熟悉的编辑器深色蓝调',
    lightSeed: null,
    darkSeed: null,
    previewColor: Color(0xFF007ACC),
    darkOnly: true,
  ),
  githubDark(
    key: 'githubDark',
    label: 'GitHub Dark',
    description: '接近 GitHub 的暗色代码界面',
    lightSeed: null,
    darkSeed: null,
    previewColor: Color(0xFF2F81F7),
    darkOnly: true,
  ),
  gruvbox(
    key: 'gruvbox',
    label: 'Gruvbox',
    description: '复古暖色终端风格',
    lightSeed: null,
    darkSeed: null,
    previewColor: Color(0xFFFABD2F),
    darkOnly: true,
  ),
  highContrast(
    key: 'highContrast',
    label: '高对比',
    description: '黑底高亮，提升辨识度',
    lightSeed: null,
    darkSeed: null,
    previewColor: Color(0xFF64D2FF),
    darkOnly: true,
  );

  const AppThemePalette({
    required this.key,
    required this.label,
    required this.description,
    required this.lightSeed,
    required this.darkSeed,
    required this.previewColor,
    required this.darkOnly,
  });

  final String key;
  final String label;
  final String description;
  final Color? lightSeed;
  final Color? darkSeed;
  final Color previewColor;
  final bool darkOnly;

  bool get isSeedBased => lightSeed != null;

  static AppThemePalette fromKey(String? key) {
    return AppThemePalette.values.firstWhere(
      (palette) => palette.key == key,
      orElse: () => AppThemePalette.ocean,
    );
  }

  ColorScheme? handCraftedScheme(Brightness brightness) {
    if (isSeedBased) return null;
    switch (this) {
      case AppThemePalette.claude:
        return brightness == Brightness.light
            ? _claudeLightScheme
            : _claudeDarkScheme;
      case AppThemePalette.vscode:
        return _vscodeScheme;
      case AppThemePalette.githubDark:
        return _githubDarkScheme;
      case AppThemePalette.gruvbox:
        return _gruvboxScheme;
      case AppThemePalette.highContrast:
        return _highContrastScheme;
      default:
        return null;
    }
  }
}

// Claude 系 — 浅色 (基于 LineCode Pro coffee)
const _claudeLightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFFD97757),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFF1D4C6),
  onPrimaryContainer: Color(0xFF5B2E1A),
  secondary: Color(0xFFB86F50),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFF1D4C6),
  onSecondaryContainer: Color(0xFF5B2E1A),
  tertiary: Color(0xFF6A7F46),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFD4E8B0),
  onTertiaryContainer: Color(0xFF2E3D14),
  error: Color(0xFFB5473F),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFF5D0CC),
  onErrorContainer: Color(0xFF5C1E1A),
  surface: Color(0xFFFBF7EF),
  onSurface: Color(0xFF2B2118),
  onSurfaceVariant: Color(0xFF6C5A49),
  surfaceContainerLowest: Color(0xFFFFFDF8),
  surfaceContainerLow: Color(0xFFF4EFE6),
  surfaceContainer: Color(0xFFEEE5D8),
  surfaceContainerHigh: Color(0xFFE7DCCA),
  surfaceContainerHighest: Color(0xFFDED2BF),
  outline: Color(0xFFDDD0BF),
  outlineVariant: Color(0xFFE8DDCF),
  inverseSurface: Color(0xFF2B2118),
  onInverseSurface: Color(0xFFF4EFE6),
  inversePrimary: Color(0xFFFFB599),
);

// Claude 系 — 深色 (暖棕深色变体)
const _claudeDarkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFD97757),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFF5B2E1A),
  onPrimaryContainer: Color(0xFFF1D4C6),
  secondary: Color(0xFFC06840),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFF5B2E1A),
  onSecondaryContainer: Color(0xFFF1D4C6),
  tertiary: Color(0xFF7A9B52),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFF2E3D14),
  onTertiaryContainer: Color(0xFFD4E8B0),
  error: Color(0xFFE85D4A),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFF5C1E1A),
  onErrorContainer: Color(0xFFF5D0CC),
  surface: Color(0xFF1A1410),
  onSurface: Color(0xFFECE0D4),
  onSurfaceVariant: Color(0xFFA89382),
  surfaceContainerLowest: Color(0xFF120E0A),
  surfaceContainerLow: Color(0xFF1A1410),
  surfaceContainer: Color(0xFF231C16),
  surfaceContainerHigh: Color(0xFF2D241D),
  surfaceContainerHighest: Color(0xFF3A2F26),
  outline: Color(0xFF3E352D),
  outlineVariant: Color(0xFF4A3F35),
  inverseSurface: Color(0xFFECE0D4),
  onInverseSurface: Color(0xFF2B2118),
  inversePrimary: Color(0xFF8B3D26),
);

// VS Code — 深色
const _vscodeScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF007ACC),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFF073A5A),
  onPrimaryContainer: Color(0xFF9FDBFF),
  secondary: Color(0xFF094771),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFF073A5A),
  onSecondaryContainer: Color(0xFF9FDBFF),
  tertiary: Color(0xFFDCDCAA),
  onTertiary: Color(0xFF1E1E1E),
  tertiaryContainer: Color(0xFF3C3C3C),
  onTertiaryContainer: Color(0xFFDCDCAA),
  error: Color(0xFFF48771),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFF5A1D1D),
  onErrorContainer: Color(0xFFF48771),
  surface: Color(0xFF1E1E1E),
  onSurface: Color(0xFFD4D4D4),
  onSurfaceVariant: Color(0xFFA6A6A6),
  surfaceContainerLowest: Color(0xFF181818),
  surfaceContainerLow: Color(0xFF1E1E1E),
  surfaceContainer: Color(0xFF252526),
  surfaceContainerHigh: Color(0xFF2D2D30),
  surfaceContainerHighest: Color(0xFF333333),
  outline: Color(0xFF3C3C3C),
  outlineVariant: Color(0xFF454545),
  inverseSurface: Color(0xFFD4D4D4),
  onInverseSurface: Color(0xFF1E1E1E),
  inversePrimary: Color(0xFF004D80),
);

// GitHub Dark
const _githubDarkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF2F81F7),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFF0D419D),
  onPrimaryContainer: Color(0xFFA5D6FF),
  secondary: Color(0xFF1F6FEB),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFF0D419D),
  onSecondaryContainer: Color(0xFFA5D6FF),
  tertiary: Color(0xFFD29922),
  onTertiary: Color(0xFF0D1117),
  tertiaryContainer: Color(0xFF3D2E00),
  onTertiaryContainer: Color(0xFFD29922),
  error: Color(0xFFF85149),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFF5A1A1A),
  onErrorContainer: Color(0xFFF85149),
  surface: Color(0xFF0D1117),
  onSurface: Color(0xFFE6EDF3),
  onSurfaceVariant: Color(0xFF8B949E),
  surfaceContainerLowest: Color(0xFF010409),
  surfaceContainerLow: Color(0xFF0D1117),
  surfaceContainer: Color(0xFF161B22),
  surfaceContainerHigh: Color(0xFF21262D),
  surfaceContainerHighest: Color(0xFF30363D),
  outline: Color(0xFF30363D),
  outlineVariant: Color(0xFF21262D),
  inverseSurface: Color(0xFFE6EDF3),
  onInverseSurface: Color(0xFF0D1117),
  inversePrimary: Color(0xFF0D419D),
);

// Gruvbox — 深色
const _gruvboxScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFFABD2F),
  onPrimary: Color(0xFF282828),
  primaryContainer: Color(0xFF665C2E),
  onPrimaryContainer: Color(0xFFFABD2F),
  secondary: Color(0xFF458588),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFF1D3B3D),
  onSecondaryContainer: Color(0xFF83C092),
  tertiary: Color(0xFFB8BB26),
  onTertiary: Color(0xFF282828),
  tertiaryContainer: Color(0xFF3D3E0E),
  onTertiaryContainer: Color(0xFFB8BB26),
  error: Color(0xFFFB4934),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFF5A1A12),
  onErrorContainer: Color(0xFFFB4934),
  surface: Color(0xFF282828),
  onSurface: Color(0xFFEBDBB2),
  onSurfaceVariant: Color(0xFFBDAE93),
  surfaceContainerLowest: Color(0xFF1D2021),
  surfaceContainerLow: Color(0xFF282828),
  surfaceContainer: Color(0xFF32302F),
  surfaceContainerHigh: Color(0xFF3C3836),
  surfaceContainerHighest: Color(0xFF504945),
  outline: Color(0xFF504945),
  outlineVariant: Color(0xFF665C54),
  inverseSurface: Color(0xFFEBDBB2),
  onInverseSurface: Color(0xFF282828),
  inversePrimary: Color(0xFF665C2E),
);

// 高对比 — 深色
const _highContrastScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF64D2FF),
  onPrimary: Color(0xFF000000),
  primaryContainer: Color(0xFF063B4C),
  onPrimaryContainer: Color(0xFF64D2FF),
  secondary: Color(0xFF004D80),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFF063B4C),
  onSecondaryContainer: Color(0xFF64D2FF),
  tertiary: Color(0xFF30D158),
  onTertiary: Color(0xFF000000),
  tertiaryContainer: Color(0xFF0A3D1A),
  onTertiaryContainer: Color(0xFF30D158),
  error: Color(0xFFFF453A),
  onError: Color(0xFF000000),
  errorContainer: Color(0xFF5A1010),
  onErrorContainer: Color(0xFFFF453A),
  surface: Color(0xFF000000),
  onSurface: Color(0xFFFFFFFF),
  onSurfaceVariant: Color(0xFFC7C7CC),
  surfaceContainerLowest: Color(0xFF000000),
  surfaceContainerLow: Color(0xFF050505),
  surfaceContainer: Color(0xFF101010),
  surfaceContainerHigh: Color(0xFF1A1A1A),
  surfaceContainerHighest: Color(0xFF2A2A2A),
  outline: Color(0xFF666666),
  outlineVariant: Color(0xFF3A3A3C),
  inverseSurface: Color(0xFFFFFFFF),
  onInverseSurface: Color(0xFF000000),
  inversePrimary: Color(0xFF004D80),
);
