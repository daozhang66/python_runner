import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/theme_provider.dart';
import '../ui/app_theme_palette.dart';
import '../widgets/app_dialogs.dart';
import '../l10n/app_localizations.dart';

// Flutter 3.44.2 deprecated RadioListTile.groupValue/onChanged in favor of
// RadioGroup; keep using them here until we migrate to RadioGroup ancestor.
// ignore_for_file: deprecated_member_use

class ThemeSettingsPage extends ConsumerWidget {
  const ThemeSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.themeAndColors),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // 主题模式
          _ThemeModeSection(
            currentMode: themeState.mode,
            onModeChanged: themeNotifier.setThemeMode,
          ),

          // Material You
          _MaterialYouSection(
            enabled: themeState.useDynamicColor,
            onChanged: themeNotifier.setUseDynamicColor,
          ),

          // 配色方案
          if (!themeState.useDynamicColor) ...[
            _PresetThemesSection(
              selectedPreset: themeState.selectedPreset,
              currentSeedColor: themeState.seedColor,
              onPresetSelected: themeNotifier.setPresetTheme,
            ),
            _FluxdoColorsSection(
              customColors: themeState.customColors,
              currentSeedColor: themeState.seedColor,
              onColorSelected: themeNotifier.setSeedColor,
              onAddColor: () => _showColorPicker(context, themeNotifier),
              onRemoveColor: themeNotifier.removeCustomColor,
            ),
          ],

          // 高级选项
          if (!themeState.useDynamicColor)
            _AdvancedOptionsSection(
              schemeVariant: themeState.schemeVariant,
              fontFamily: themeState.fontFamily,
              enableBlurEffect: themeState.enableBlurEffect,
              onSchemeVariantChanged: themeNotifier.setSchemeVariant,
              onFontFamilyChanged: themeNotifier.setFontFamily,
              onBlurEffectChanged: themeNotifier.setEnableBlurEffect,
            ),
        ],
      ),
    );
  }

  Future<void> _showColorPicker(
      BuildContext context, ThemeNotifier notifier) async {
    Color? selectedColor;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx)!.selectColor),
        content: SingleChildScrollView(
          child: ColorPicker(
            onColorChanged: (color) => selectedColor = color,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(ctx)!.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (selectedColor != null) {
                notifier.addCustomColor(selectedColor!);
              }
              Navigator.pop(ctx);
            },
            child: Text(AppLocalizations.of(ctx)!.add),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 主题模式选择
// ═══════════════════════════════════════════════════════════════

class _ThemeModeSection extends StatelessWidget {
  final ThemeMode currentMode;
  final Future<void> Function(ThemeMode) onModeChanged;

  const _ThemeModeSection({
    required this.currentMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.brightness_6_outlined,
                    size: 20, color: colors.primary),
                const SizedBox(width: 10),
                Text(
                  AppLocalizations.of(context)!.themeMode,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () =>
                  _showThemeModePicker(context, currentMode, onModeChanged),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  border:
                      Border.all(color: colors.outline.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(_getModeIcon(currentMode),
                        size: 20, color: colors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _getModeName(context, currentMode),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios,
                        size: 16, color: colors.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getModeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return Icons.light_mode_outlined;
      case ThemeMode.system:
        return Icons.brightness_auto_outlined;
      case ThemeMode.dark:
        return Icons.dark_mode_outlined;
    }
  }

  String _getModeName(BuildContext context, ThemeMode mode) {
    final l10n = AppLocalizations.of(context)!;
    switch (mode) {
      case ThemeMode.light:
        return l10n.light;
      case ThemeMode.system:
        return l10n.followSystem;
      case ThemeMode.dark:
        return l10n.dark;
    }
  }

  Future<void> _showThemeModePicker(
    BuildContext context,
    ThemeMode current,
    Future<void> Function(ThemeMode) onChanged,
  ) async {
    final selected = await showDialog<ThemeMode>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) => Consumer(
        builder: (context, ref, _) {
          final enableBlur =
              ref.watch(themeProvider.select((s) => s.enableBlurEffect));
          final dialog = AlertDialog(
            backgroundColor: appDialogBackgroundColor(ctx, enableBlur),
            surfaceTintColor: Colors.transparent,
            title: Text(AppLocalizations.of(ctx)!.selectThemeMode),
            contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<ThemeMode>(
                  value: ThemeMode.light,
                  groupValue: current,
                  title: Text(AppLocalizations.of(ctx)!.light),
                  secondary: const Icon(Icons.light_mode_outlined),
                  onChanged: (value) => Navigator.pop(ctx, value),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.system,
                  groupValue: current,
                  title: Text(AppLocalizations.of(ctx)!.followSystem),
                  secondary: const Icon(Icons.brightness_auto_outlined),
                  onChanged: (value) => Navigator.pop(ctx, value),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.dark,
                  groupValue: current,
                  title: Text(AppLocalizations.of(ctx)!.dark),
                  secondary: const Icon(Icons.dark_mode_outlined),
                  onChanged: (value) => Navigator.pop(ctx, value),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(AppLocalizations.of(ctx)!.cancel),
              ),
            ],
          );

          return appDialogFrame(enableBlur: enableBlur, child: dialog);
        },
      ),
    );

    if (selected != null && selected != current) {
      await onChanged(selected);
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// Material You 开关
// ═══════════════════════════════════════════════════════════════

class _MaterialYouSection extends StatelessWidget {
  final bool enabled;
  final Future<void> Function(bool) onChanged;

  const _MaterialYouSection({
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.color_lens_outlined,
                      size: 20, color: colors.primary),
                  const SizedBox(width: 10),
                  Text(
                    'Material You',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.primary,
                    ),
                  ),
                ],
              ),
            ),
            SwitchListTile(
              secondary: Icon(
                enabled ? Icons.auto_awesome : Icons.auto_awesome_outlined,
                color: enabled ? colors.primary : null,
              ),
              title: Text(AppLocalizations.of(context)!.materialYouWallpaper),
              subtitle: Text(
                enabled
                    ? AppLocalizations.of(context)!.materialYouOn
                    : AppLocalizations.of(context)!.materialYouOff,
                style: const TextStyle(fontSize: 12),
              ),
              value: enabled,
              onChanged: (v) => onChanged(v),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 预设主题（Python Runner 9 个主题）
// ═══════════════════════════════════════════════════════════════

class _PresetThemesSection extends StatelessWidget {
  final AppThemePalette? selectedPreset;
  final Color currentSeedColor;
  final Future<void> Function(AppThemePalette) onPresetSelected;

  const _PresetThemesSection({
    required this.selectedPreset,
    required this.currentSeedColor,
    required this.onPresetSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final presets = AppThemePalette.values.where((p) => p.isSeedBased).toList();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.palette_outlined, size: 20, color: colors.primary),
                const SizedBox(width: 10),
                Text(
                  AppLocalizations.of(context)!.presetThemes,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: presets.map((preset) {
                final isSelected = selectedPreset == preset;
                return _ColorCard(
                  color: preset.previewColor,
                  label: _presetLabel(context, preset),
                  selected: isSelected,
                  onTap: () => onPresetSelected(preset),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
String _presetLabel(BuildContext context, AppThemePalette preset) {
  final l10n = AppLocalizations.of(context)!;
  switch (preset) {
    case AppThemePalette.ocean:
      return l10n.themeOcean;
    case AppThemePalette.mint:
      return l10n.themeMint;
    case AppThemePalette.lilac:
      return l10n.themeLilac;
    case AppThemePalette.highContrast:
      return l10n.themeHighContrast;
    case AppThemePalette.claude:
      return 'Claude';
    case AppThemePalette.codex:
      return 'Codex';
    case AppThemePalette.vscode:
      return 'VS Code';
    case AppThemePalette.githubDark:
      return 'GitHub Dark';
    case AppThemePalette.gruvbox:
      return 'Gruvbox';
  }
}

// FluxDO 经典色
// ═══════════════════════════════════════════════════════════════

class _FluxdoColorsSection extends StatelessWidget {
  final List<Color> customColors;
  final Color currentSeedColor;
  final Future<void> Function(Color) onColorSelected;
  final VoidCallback onAddColor;
  final Future<void> Function(Color) onRemoveColor;

  const _FluxdoColorsSection({
    required this.customColors,
    required this.currentSeedColor,
    required this.onColorSelected,
    required this.onAddColor,
    required this.onRemoveColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.palette, size: 20, color: colors.primary),
                const SizedBox(width: 10),
                Text(
                  AppLocalizations.of(context)!.moreColors,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ...ThemeNotifier.fluxdoClassicColors.map((color) {
                  final isSelected =
                      currentSeedColor.toARGB32() == color.toARGB32();
                  return _ColorCard(
                    color: color,
                    label: _colorName(context, color),
                    selected: isSelected,
                    onTap: () => onColorSelected(color),
                  );
                }),
                ...customColors.map((color) {
                  final isSelected =
                      currentSeedColor.toARGB32() == color.toARGB32();
                  return _ColorCard(
                    color: color,
                    label:
                        '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                    selected: isSelected,
                    onTap: () => onColorSelected(color),
                    onLongPress: () => _confirmRemove(context, color),
                  );
                }),
                InkWell(
                  onTap: onAddColor,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color:
                          colors.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colors.outline.withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, size: 32, color: colors.primary),
                        const SizedBox(height: 4),
                        Text(
                          AppLocalizations.of(context)!.add,
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _colorName(BuildContext context, Color color) {
    final l10n = AppLocalizations.of(context)!;
    if (color == Colors.blue) return l10n.blue;
    if (color.toARGB32() == 0xFF6750A4) return l10n.purple;
    if (color == Colors.green) return l10n.green;
    if (color == Colors.orange) return l10n.orange;
    if (color == Colors.pink) return l10n.pink;
    if (color == Colors.teal || color == Colors.cyan) return l10n.teal;
    if (color == Colors.red) return l10n.red;
    if (color == Colors.indigo) return l10n.indigo;
    if (color == Colors.amber) return l10n.amber;
    return l10n.color;
  }

  Future<void> _confirmRemove(BuildContext context, Color color) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx)!.deleteColor),
        content: Text(AppLocalizations.of(ctx)!.deleteColorConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(ctx)!.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(ctx)!.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await onRemoveColor(color);
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// 颜色卡片
// ═══════════════════════════════════════════════════════════════

class _ColorCard extends StatelessWidget {
  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _ColorCard({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color,
              color.withValues(alpha: 0.7),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? colors.primary
                : colors.outline.withValues(alpha: 0.2),
            width: selected ? 3 : 1,
          ),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Stack(
          children: [
            if (selected)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: colors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check,
                    size: 16,
                    color: colors.onPrimary,
                  ),
                ),
              ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 高级选项
// ═══════════════════════════════════════════════════════════════

class _AdvancedOptionsSection extends StatelessWidget {
  final DynamicSchemeVariant schemeVariant;
  final AppFontFamily fontFamily;
  final bool enableBlurEffect;
  final Future<void> Function(DynamicSchemeVariant) onSchemeVariantChanged;
  final Future<void> Function(AppFontFamily) onFontFamilyChanged;
  final Future<void> Function(bool) onBlurEffectChanged;

  const _AdvancedOptionsSection({
    required this.schemeVariant,
    required this.fontFamily,
    required this.enableBlurEffect,
    required this.onSchemeVariantChanged,
    required this.onFontFamilyChanged,
    required this.onBlurEffectChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, size: 20, color: colors.primary),
                const SizedBox(width: 10),
                Text(
                  AppLocalizations.of(context)!.advancedOptions,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 配色算法
            InkWell(
              onTap: () => _showSchemeVariantPicker(
                  context, schemeVariant, onSchemeVariantChanged),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  border:
                      Border.all(color: colors.outline.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context)!.colorSchemeAlgorithm,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _variantName(context, schemeVariant),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: colors.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios,
                        size: 16, color: colors.onSurfaceVariant),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 毛玻璃效果
            SwitchListTile(
              value: enableBlurEffect,
              onChanged: onBlurEffectChanged,
              title: Text(
                AppLocalizations.of(context)!.blurEffect,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                AppLocalizations.of(context)!.blurEffectDescription,
                style: TextStyle(fontSize: 12),
              ),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),
            // 字体选择
            InkWell(
              onTap: () => _showFontFamilyPicker(
                  context, fontFamily, onFontFamilyChanged),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  border:
                      Border.all(color: colors.outline.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context)!.font,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _fontFamilyName(context, fontFamily),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: colors.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios,
                        size: 16, color: colors.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _variantName(BuildContext context, DynamicSchemeVariant variant) {
    final l10n = AppLocalizations.of(context)!;
    switch (variant) {
      case DynamicSchemeVariant.tonalSpot:
        return l10n.variantTonalSpot;
      case DynamicSchemeVariant.fidelity:
        return l10n.variantFidelity;
      case DynamicSchemeVariant.content:
        return l10n.variantContent;
      case DynamicSchemeVariant.monochrome:
        return l10n.variantMonochrome;
      case DynamicSchemeVariant.neutral:
        return l10n.variantNeutral;
      case DynamicSchemeVariant.vibrant:
        return l10n.variantVibrant;
      case DynamicSchemeVariant.expressive:
        return l10n.variantExpressive;
      case DynamicSchemeVariant.rainbow:
        return l10n.variantRainbow;
      case DynamicSchemeVariant.fruitSalad:
        return l10n.variantFruitSalad;
    }
  }

  String _fontFamilyName(BuildContext context, AppFontFamily family) {
    switch (family) {
      case AppFontFamily.system:
        return AppLocalizations.of(context)!.followSystem;
      case AppFontFamily.miSans:
        return 'MiSans';
    }
  }

  String _variantDescription(
      BuildContext context, DynamicSchemeVariant variant) {
    final l10n = AppLocalizations.of(context)!;
    switch (variant) {
      case DynamicSchemeVariant.tonalSpot:
        return l10n.variantTonalSpotDescription;
      case DynamicSchemeVariant.fidelity:
        return l10n.variantFidelityDescription;
      case DynamicSchemeVariant.content:
        return l10n.variantContentDescription;
      case DynamicSchemeVariant.monochrome:
        return l10n.variantMonochromeDescription;
      case DynamicSchemeVariant.neutral:
        return l10n.variantNeutralDescription;
      case DynamicSchemeVariant.vibrant:
        return l10n.variantVibrantDescription;
      case DynamicSchemeVariant.expressive:
        return l10n.variantExpressiveDescription;
      case DynamicSchemeVariant.rainbow:
        return l10n.variantRainbowDescription;
      case DynamicSchemeVariant.fruitSalad:
        return l10n.variantFruitSaladDescription;
    }
  }

  Future<void> _showSchemeVariantPicker(
    BuildContext context,
    DynamicSchemeVariant current,
    Future<void> Function(DynamicSchemeVariant) onChanged,
  ) async {
    final selected = await showDialog<DynamicSchemeVariant>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) => Consumer(
        builder: (context, ref, _) {
          final enableBlur =
              ref.watch(themeProvider.select((s) => s.enableBlurEffect));
          final dialog = AlertDialog(
            backgroundColor: appDialogBackgroundColor(ctx, enableBlur),
            surfaceTintColor: Colors.transparent,
            title: Text(AppLocalizations.of(ctx)!.selectColorSchemeAlgorithm),
            contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: DynamicSchemeVariant.values.map((variant) {
                  return RadioListTile<DynamicSchemeVariant>(
                    value: variant,
                    groupValue: current,
                    title: Text(_variantName(ctx, variant)),
                    subtitle: Text(
                      _variantDescription(ctx, variant),
                      style: const TextStyle(fontSize: 12),
                    ),
                    onChanged: (value) => Navigator.pop(ctx, value),
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(AppLocalizations.of(ctx)!.cancel),
              ),
            ],
          );

          return appDialogFrame(enableBlur: enableBlur, child: dialog);
        },
      ),
    );

    if (selected != null && selected != current) {
      await onChanged(selected);
    }
  }

  Future<void> _showFontFamilyPicker(
    BuildContext context,
    AppFontFamily current,
    Future<void> Function(AppFontFamily) onChanged,
  ) async {
    final selected = await showDialog<AppFontFamily>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) => Consumer(
        builder: (context, ref, _) {
          final enableBlur =
              ref.watch(themeProvider.select((s) => s.enableBlurEffect));
          final dialog = AlertDialog(
            backgroundColor: appDialogBackgroundColor(ctx, enableBlur),
            surfaceTintColor: Colors.transparent,
            title: Text(AppLocalizations.of(ctx)!.selectFont),
            contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: AppFontFamily.values.map((family) {
                return RadioListTile<AppFontFamily>(
                  value: family,
                  groupValue: current,
                  title: Text(_fontFamilyName(ctx, family)),
                  onChanged: (value) => Navigator.pop(ctx, value),
                );
              }).toList(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(AppLocalizations.of(ctx)!.cancel),
              ),
            ],
          );

          return appDialogFrame(enableBlur: enableBlur, child: dialog);
        },
      ),
    );

    if (selected != null && selected != current) {
      await onChanged(selected);
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// 简易颜色选择器
// ═══════════════════════════════════════════════════════════════

class ColorPicker extends StatefulWidget {
  final ValueChanged<Color> onColorChanged;

  const ColorPicker({super.key, required this.onColorChanged});

  @override
  State<ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<ColorPicker> {
  double _hue = 0.0;
  double _saturation = 1.0;
  double _lightness = 0.5;

  Color get _color =>
      HSLColor.fromAHSL(1.0, _hue, _saturation, _lightness).toColor();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 颜色预览
        Container(
          height: 80,
          decoration: BoxDecoration(
            color: _color,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.grey.withValues(alpha: 0.3),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // 色相
        _buildSlider(
          label: AppLocalizations.of(context)!.hue,
          value: _hue,
          max: 360,
          onChanged: (v) {
            setState(() => _hue = v);
            widget.onColorChanged(_color);
          },
        ),
        // 饱和度
        _buildSlider(
          label: AppLocalizations.of(context)!.saturation,
          value: _saturation,
          max: 1,
          onChanged: (v) {
            setState(() => _saturation = v);
            widget.onColorChanged(_color);
          },
        ),
        // 亮度
        _buildSlider(
          label: AppLocalizations.of(context)!.lightness,
          value: _lightness,
          max: 1,
          onChanged: (v) {
            setState(() => _lightness = v);
            widget.onColorChanged(_color);
          },
        ),
      ],
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        Slider(
          value: value,
          min: 0,
          max: max,
          divisions: 100,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
