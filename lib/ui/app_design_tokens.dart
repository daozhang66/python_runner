import 'package:flutter/material.dart';

/// 统一间距常量，基于 4px 网格。
abstract final class AppSpacing {
  static const hairline = 1.0;
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;

  // 卡片间距语义化常量
  static const cardVertical = 8.0;
  static const cardHorizontal = 16.0;
}

/// Typography and compact control metrics that must remain consistent across
/// dense operational screens without changing their established layout.
abstract final class AppTextSize {
  static const nano = 8.5;
  static const micro = 9.0;
  static const compact = 10.0;
  static const compactEmphasis = 10.5;
  static const label = 11.0;
  static const body = 12.0;
  static const bodyEmphasis = 13.0;
  static const bodyLarge = 14.0;
  static const toolbarTitle = 15.0;
  static const title = 16.0;
  static const headline = 20.0;
}

abstract final class AppControlMetrics {
  static const compactMetaMaxWidth = 132.0;
  static const regularMetaMaxWidth = 180.0;
  static const compactMetaIcon = 11.0;
  static const regularMetaIcon = 12.0;
  static const terminalLogLineHeight = 1.3;
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
  static const transparent = Colors.transparent;
  static const terminalDarkCanvas = Color(0xFF0D1117);
  static const terminalDarkSurface = Color(0xFF161B22);
  static const terminalDarkText = Color(0xFFE6EDF3);
  static const terminalDarkMuted = Color(0xFF8B949E);
  static const terminalDarkToolbarText = Color(0xFFC9D1D9);
  static const terminalDarkAccent = Color(0xFF79C0FF);
  static const terminalDarkError = Color(0xFFF85149);
  static const terminalDarkBorder = Color(0xFF30363D);
  static const terminalDarkControl = Color(0xFF21262D);
  static const terminalLightCanvas = Color(0xFFFAFAFA);
  static const terminalLightSurface = Color(0xFFF0F0F0);
  static const terminalLightInput = Color(0xFFFFFFFF);
  static const consoleLightCanvas = Color(0xFF1E1E1E);
  static const consoleLightSurface = Color(0xFF2D2D2D);
  static const consoleWindowClose = Color(0xFFFF5F56);
  static const consoleWindowMinimize = Color(0xFFFFBD2E);
  static const consoleWindowMaximize = Color(0xFF27C93F);
  static const jsonNull = Color(0xFF7B8190);
  static const jsonBoolean = Color(0xFF7A52C7);
  static const jsonNumber = Color(0xFFB26418);
  static const jsonString = Color(0xFF1D8A63);
  static const splashDarkSurface = Color(0xFF121212);
  static const splashDarkEnd = Color(0xFF0F172A);
  static const splashLightSurface = Color(0xFFFFFFFF);
  static const splashLightEnd = Color(0xFFEAF2FF);
  static const darkBackground = Color(0xFF111318);
  static const darkSurface = Color(0xFF181B22);
  static const darkSurfaceHigh = Color(0xFF202431);
  static const darkSelectedSurface = Color(0xFF2F3A63);
  static const darkPinnedSurface = Color(0xFF283354);
  static const darkBorder = Color(0xFF2B303A);
  static const darkMaskedText = Color(0xFFC8CEDF);
  static const lightMaskedText = Color(0xFF050505);

  static Color terminalLog(BuildContext context) =>
      Theme.of(context).colorScheme.tertiary;

  static Color terminalCanvas(bool isDark) =>
      isDark ? terminalDarkCanvas : terminalLightCanvas;

  static Color terminalSurface(bool isDark) =>
      isDark ? terminalDarkSurface : terminalLightSurface;

  static Color terminalInput(bool isDark) =>
      isDark ? terminalDarkCanvas : terminalLightInput;

  static Color terminalText(ColorScheme colors, bool isDark) =>
      isDark ? terminalDarkText : colors.onSurface;

  static Color terminalMuted(ColorScheme colors, bool isDark) =>
      isDark ? terminalDarkMuted : colors.onSurfaceVariant;

  static Color terminalAccent(ColorScheme colors, bool isDark) =>
      isDark ? terminalDarkAccent : colors.primary;

  static Color terminalError(ColorScheme colors, bool isDark) =>
      isDark ? terminalDarkError : colors.error;

  static Color terminalBorder(ColorScheme colors, bool isDark) => isDark
      ? terminalDarkBorder
      : colors.outlineVariant.withValues(alpha: AppOpacity.border);

  static Color splashSurface(bool isDark) =>
      isDark ? splashDarkSurface : splashLightSurface;

  static List<Color> splashGradient(bool isDark) => isDark
      ? const [splashDarkSurface, splashDarkEnd]
      : const [splashLightSurface, splashLightEnd];

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color maskedText(BuildContext context) =>
      isDark(context) ? darkMaskedText : lightMaskedText;

  static Color pageBackground(ColorScheme colors) =>
      Color.alphaBlend(colors.primary.withValues(alpha: 0.008), colors.surface);

  static Color cardSurface(ColorScheme colors) =>
      Color.alphaBlend(colors.primary.withValues(alpha: 0.012), colors.surface);

  static Color softSurface(ColorScheme colors) =>
      Color.alphaBlend(colors.primary.withValues(alpha: 0.018), colors.surface);

  static Color codeSurface(ColorScheme colors) => cardSurface(colors);

  static Color navigationIndicator(ColorScheme colors) => Color.alphaBlend(
      colors.primary.withValues(alpha: 0.12), colors.primaryContainer);

  static Color scriptSurface(
    BuildContext context,
    ColorScheme colors, {
    required bool selected,
    required bool pinned,
  }) {
    if (!isDark(context)) {
      return selected
          ? navigationIndicator(colors)
          : pinned
              ? colors.primaryContainer.withValues(alpha: AppOpacity.pinnedFill)
              : cardSurface(colors);
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
