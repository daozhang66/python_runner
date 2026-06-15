import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/theme_provider.dart';
import '../ui/app_theme_palette.dart';
import '../widgets/app_dialogs.dart';

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
        title: const Text('主题与配色'),
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
        title: const Text('选择颜色'),
        content: SingleChildScrollView(
          child: ColorPicker(
            onColorChanged: (color) => selectedColor = color,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (selectedColor != null) {
                notifier.addCustomColor(selectedColor!);
              }
              Navigator.pop(ctx);
            },
            child: const Text('添加'),
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
                  '主题模式',
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
                        _getModeName(currentMode),
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

  String _getModeName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.system:
        return '跟随系统';
      case ThemeMode.dark:
        return '深色';
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
            title: const Text('选择主题模式'),
            contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<ThemeMode>(
                  value: ThemeMode.light,
                  groupValue: current,
                  title: const Text('浅色'),
                  secondary: const Icon(Icons.light_mode_outlined),
                  onChanged: (value) => Navigator.pop(ctx, value),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.system,
                  groupValue: current,
                  title: const Text('跟随系统'),
                  secondary: const Icon(Icons.brightness_auto_outlined),
                  onChanged: (value) => Navigator.pop(ctx, value),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.dark,
                  groupValue: current,
                  title: const Text('深色'),
                  secondary: const Icon(Icons.dark_mode_outlined),
                  onChanged: (value) => Navigator.pop(ctx, value),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
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
              title: const Text('跟随系统壁纸动态取色'),
              subtitle: Text(
                enabled
                    ? 'Android 12+ · 已启用，配色方案将跟随壁纸'
                    : 'Android 12+ · 关闭后可使用下方自定义配色',
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
                  '预设主题',
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
                  label: preset.label,
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
                  '更多颜色',
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
                    label: _colorName(color),
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
                          '添加',
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

  String _colorName(Color color) {
    if (color == Colors.blue) return '蓝色';
    if (color.toARGB32() == 0xFF6750A4) return '紫色';
    if (color == Colors.green) return '绿色';
    if (color == Colors.orange) return '橙色';
    if (color == Colors.pink) return '粉色';
    if (color == Colors.teal) return '青色';
    if (color == Colors.red) return '红色';
    if (color == Colors.indigo) return '靛蓝';
    if (color == Colors.amber) return '琥珀';
    if (color == Colors.cyan) return '青色';
    return '颜色';
  }

  Future<void> _confirmRemove(BuildContext context, Color color) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除颜色'),
        content: const Text('确定要删除这个自定义颜色吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
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
                  '高级选项',
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
                            '配色算法',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _variantName(schemeVariant),
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
              title: const Text(
                '毛玻璃效果',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              subtitle: const Text(
                '为对话框启用毛玻璃背景模糊效果（需要配色算法支持）',
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
                            '字体',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _fontFamilyName(fontFamily),
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

  String _variantName(DynamicSchemeVariant variant) {
    switch (variant) {
      case DynamicSchemeVariant.tonalSpot:
        return '柔和色调（推荐）';
      case DynamicSchemeVariant.fidelity:
        return '高保真';
      case DynamicSchemeVariant.content:
        return '内容优先';
      case DynamicSchemeVariant.monochrome:
        return '单色';
      case DynamicSchemeVariant.neutral:
        return '中性';
      case DynamicSchemeVariant.vibrant:
        return '鲜艳';
      case DynamicSchemeVariant.expressive:
        return '表现力';
      case DynamicSchemeVariant.rainbow:
        return '彩虹';
      case DynamicSchemeVariant.fruitSalad:
        return '水果沙拉';
    }
  }

  String _fontFamilyName(AppFontFamily family) {
    switch (family) {
      case AppFontFamily.system:
        return '跟随系统';
      case AppFontFamily.miSans:
        return 'MiSans';
    }
  }

  String _variantDescription(DynamicSchemeVariant variant) {
    switch (variant) {
      case DynamicSchemeVariant.tonalSpot:
        return '平衡的柔和色调，适合大多数场景';
      case DynamicSchemeVariant.fidelity:
        return '高度保真原始颜色，最接近种子色';
      case DynamicSchemeVariant.content:
        return '强调内容可读性的配色';
      case DynamicSchemeVariant.monochrome:
        return '极简单色配色，黑白灰为主';
      case DynamicSchemeVariant.neutral:
        return '中性低饱和度配色';
      case DynamicSchemeVariant.vibrant:
        return '鲜艳高饱和度配色';
      case DynamicSchemeVariant.expressive:
        return '富有表现力的大胆配色';
      case DynamicSchemeVariant.rainbow:
        return '彩虹般的多彩配色';
      case DynamicSchemeVariant.fruitSalad:
        return '水果沙拉般的丰富配色';
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
            title: const Text('选择配色算法'),
            contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: DynamicSchemeVariant.values.map((variant) {
                  return RadioListTile<DynamicSchemeVariant>(
                    value: variant,
                    groupValue: current,
                    title: Text(_variantName(variant)),
                    subtitle: Text(
                      _variantDescription(variant),
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
                child: const Text('取消'),
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
            title: const Text('选择字体'),
            contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: AppFontFamily.values.map((family) {
                return RadioListTile<AppFontFamily>(
                  value: family,
                  groupValue: current,
                  title: Text(_fontFamilyName(family)),
                  onChanged: (value) => Navigator.pop(ctx, value),
                );
              }).toList(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
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
          label: '色相',
          value: _hue,
          max: 360,
          onChanged: (v) {
            setState(() => _hue = v);
            widget.onColorChanged(_color);
          },
        ),
        // 饱和度
        _buildSlider(
          label: '饱和度',
          value: _saturation,
          max: 1,
          onChanged: (v) {
            setState(() => _saturation = v);
            widget.onColorChanged(_color);
          },
        ),
        // 亮度
        _buildSlider(
          label: '亮度',
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
