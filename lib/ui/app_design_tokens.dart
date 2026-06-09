import 'package:flutter/material.dart';

/// 统一间距常量，基于 4px 网格。
abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
}

/// 统一圆角常量。
abstract final class AppRadius {
  static const sm = 4.0;
  static const md = 8.0;
  static const lg = 12.0;
  static const xl = 16.0;
  static const pill = 999.0;

  static BorderRadius circular(double value) => BorderRadius.circular(value);
  static BorderRadius get small => circular(sm);
  static BorderRadius get medium => circular(md);
  static BorderRadius get large => circular(lg);
  static BorderRadius get extraLarge => circular(xl);
  static BorderRadius get pillShape => circular(pill);
}

/// 统一动画时长。
abstract final class AppMotion {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 400);
}

/// 统一透明度值。
abstract final class AppOpacity {
  static const border = 0.7;
  static const subtleFill = 0.38;
  static const selectedFill = 0.82;
  static const pinnedFill = 0.72;
}

abstract final class AppThemeColors {
  static const darkBackground = Color(0xFF111318);
  static const darkSurface = Color(0xFF181B22);
  static const darkSurfaceHigh = Color(0xFF202431);
  static const darkSelectedSurface = Color(0xFF2F3A63);
  static const darkPinnedSurface = Color(0xFF283354);
  static const darkBorder = Color(0xFF2B303A);
  static const darkMaskedText = Color(0xFFC8CEDF);
  static const lightMaskedText = Color(0xFF050505);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color maskedText(BuildContext context) =>
      isDark(context) ? darkMaskedText : lightMaskedText;

  static Color scriptSurface(
    BuildContext context,
    ColorScheme colors, {
    required bool selected,
    required bool pinned,
  }) {
    if (!isDark(context)) {
      return selected
          ? colors.primaryContainer.withValues(alpha: AppOpacity.selectedFill)
          : pinned
              ? colors.primaryContainer.withValues(alpha: AppOpacity.pinnedFill)
              : colors.surfaceContainer;
    }
    if (selected) return darkSelectedSurface;
    if (pinned) return darkPinnedSurface;
    return darkSurface;
  }

  static Color scriptBorder(
    BuildContext context,
    ColorScheme colors, {
    required bool selected,
    required bool pinned,
  }) {
    if (!isDark(context)) {
      return pinned
          ? colors.primary.withValues(alpha: 0.42)
          : colors.outlineVariant.withValues(alpha: AppOpacity.border);
    }
    if (selected) return colors.primary.withValues(alpha: 0.36);
    if (pinned) return colors.primary.withValues(alpha: 0.28);
    return darkBorder;
  }

  static Color softIconColor(BuildContext context, ColorScheme colors) =>
      isDark(context) ? colors.primary.withValues(alpha: 0.82) : colors.primary;
}

/// 统一微交互按钮缩放动画组件。
class AppClickAnimator extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleDown;
  final Duration duration;

  const AppClickAnimator({
    super.key,
    required this.child,
    this.onTap,
    this.scaleDown = 0.92,
    this.duration = const Duration(milliseconds: 100),
  });

  @override
  State<AppClickAnimator> createState() => _AppClickAnimatorState();
}

class _AppClickAnimatorState extends State<AppClickAnimator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _scale = Tween<double>(begin: 1.0, end: widget.scaleDown).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: widget.child,
      ),
    );
  }
}
