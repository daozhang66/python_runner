import 'package:flutter/material.dart';
import 'app_design_tokens.dart';

/// 状态徽标颜色语义。
enum AppBadgeTone {
  success,
  warning,
  error,
  info,
  neutral,
}

/// 统一状态徽标。
///
/// 用于运行状态、HTTP 状态码、安装状态等。
class AppStatusBadge extends StatelessWidget {
  final String label;
  final AppBadgeTone tone;
  final IconData? icon;
  final double fontSize;

  const AppStatusBadge({
    super.key,
    required this.label,
    this.tone = AppBadgeTone.neutral,
    this.icon,
    this.fontSize = 10,
  });

  Color _backgroundColor(ColorScheme colors) {
    final base = _foregroundColor(colors);
    return base.withValues(alpha: 0.12);
  }

  Color _foregroundColor(ColorScheme colors) {
    return switch (tone) {
      AppBadgeTone.success => Colors.green.shade700,
      AppBadgeTone.warning => Colors.orange,
      AppBadgeTone.error => colors.error,
      AppBadgeTone.info => colors.primary,
      AppBadgeTone.neutral => colors.onSurfaceVariant,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fg = _foregroundColor(colors);

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm - 2, vertical: 2),
      decoration: BoxDecoration(
        color: _backgroundColor(colors),
        borderRadius: AppRadius.small,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 2, color: fg),
            const SizedBox(width: 2),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              height: 1,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// 统一计数徽标。
///
/// 用于脚本数量、库数量、请求数量等。
class AppCountBadge extends StatelessWidget {
  final int count;
  final double fontSize;

  const AppCountBadge({
    super.key,
    required this.count,
    this.fontSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color:
            colors.primaryContainer.withValues(alpha: AppOpacity.selectedFill),
        borderRadius: AppRadius.pillShape,
      ),
      child: Text(
        count.toString(),
        style: TextStyle(
          fontSize: fontSize,
          height: 1.1,
          fontWeight: FontWeight.w700,
          color: colors.onPrimaryContainer,
        ),
      ),
    );
  }
}
