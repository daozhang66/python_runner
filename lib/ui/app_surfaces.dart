import 'package:flutter/material.dart';
import 'app_design_tokens.dart';

/// 统一卡片表面组件。
///
/// 替代散落在各页面的 Card / Container 样式。
/// 支持 normal / pinned / selected 三种视觉状态。
class AppSurface extends StatelessWidget {
  final bool pinned;
  final bool selected;
  final EdgeInsetsGeometry margin;
  final Widget child;

  const AppSurface({
    super.key,
    this.pinned = false,
    this.selected = false,
    this.margin = const EdgeInsets.symmetric(
        horizontal: AppSpacing.md, vertical: AppSpacing.xs),
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const radius = AppRadius.xl;

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: AppThemeColors.scriptSurface(
          context,
          colors,
          selected: selected,
          pinned: pinned,
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: AppThemeColors.scriptBorder(
            context,
            colors,
            selected: selected,
            pinned: pinned,
          ),
          width: AppThemeColors.isDark(context) ? 0.8 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: child,
      ),
    );
  }
}

/// 统一分区卡片，用于设置页、网络详情页等。
///
/// 带标题图标和标题文字的分组容器。
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
    final colors = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm - 2),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.large,
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.4)),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xs),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: colors.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.primary,
                    ),
                  ),
                ],
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}
