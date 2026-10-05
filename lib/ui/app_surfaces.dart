import 'package:flutter/material.dart';

import 'app_design_tokens.dart';
import 'app_settings_section.dart';
import 'app_materials.dart';
import 'app_glass_press.dart';

/// 统一卡片表面组件。
///
/// 替代散落在各页面的 Card / Container 样式。
/// 支持 normal / pinned / selected 三种视觉状态。
class AppSurface extends StatelessWidget {
  final bool pinned;
  final bool selected;

  /// Opt in on migrated tool screens; the script workspace keeps its styling.
  final bool tonal;
  final EdgeInsetsGeometry margin;
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;

  const AppSurface({
    super.key,
    this.pinned = false,
    this.selected = false,
    this.tonal = false,
    this.margin = const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.xs,
    ),
    this.onTap,
    this.onLongPress,
    this.semanticLabel,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final radius = tonal ? AppRadius.md : AppRadius.xl;
    final native =
        AppMaterials.of(context).liquid && AppMaterials.hasGlassHost(context);

    return Container(
      margin: margin,
      decoration: native
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              boxShadow: [
                BoxShadow(
                  color: AppMaterials.of(context).shadow,
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            )
          : AppMaterials.of(context).liquid
          ? AppMaterials.of(context).decoration(
              context,
              BorderRadius.circular(radius),
              base: selected
                  ? colors.secondaryContainer
                  : pinned
                  ? colors.primaryContainer
                  : null,
            )
          : BoxDecoration(
              color: tonal
                  ? (selected
                        ? colors.secondaryContainer
                        : AppMaterials.of(context).liquid
                        ? AppMaterials.of(context).content
                        : colors.surfaceContainerLow)
                  : AppThemeColors.scriptSurface(
                      context,
                      colors,
                      selected: selected,
                      pinned: pinned,
                    ),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: tonal
                    ? (selected
                          ? colors.primary
                          : colors.outlineVariant.withValues(alpha: 0.5))
                    : AppThemeColors.scriptBorder(
                        context,
                        colors,
                        selected: selected,
                        pinned: pinned,
                      ),
                width: AppThemeColors.isDark(context) ? 0.8 : 1,
              ),
            ),
      clipBehavior: Clip.antiAlias,
      child: AppGlassPress(
        feedbackInsideSurface: true,
        enabled: onTap != null || onLongPress != null,
        child: AppGlassSurface(
          enabled: native,
          cardSurface: true,
          borderColor: AppThemeColors.scriptBorder(
            context,
            colors,
            selected: selected,
            pinned: pinned,
          ),
          interactive: onTap != null || onLongPress != null,
          radius: BorderRadius.circular(radius),
          baseColor: selected
              ? colors.secondaryContainer
              : pinned
              ? colors.primaryContainer
              : null,
          child: Semantics(
            button: onTap != null,
            label: semanticLabel,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                onLongPress: onLongPress,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Retains the existing API while presenting details as unframed sections.
class AppSectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const AppSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return AppSettingsSection(icon: icon, title: title, children: children);
  }
}
