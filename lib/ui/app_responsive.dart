import 'package:flutter/material.dart';

/// Shared adaptive layout rules for the Android phone and tablet targets.
abstract final class AppBreakpoints {
  static const tabletMinWidth = 600.0;

  static bool isTabletWidth(double width) => width >= tabletMinWidth;

  static bool isTablet(BuildContext context) =>
      isTabletWidth(MediaQuery.sizeOf(context).width);

  static int scriptGridColumns(BuildContext context) =>
      isTablet(context) ? 3 : 2;
}

/// Selects a compact or tablet layout from the available width.
class AppResponsiveLayout extends StatelessWidget {
  const AppResponsiveLayout({
    super.key,
    required this.compact,
    required this.tablet,
  });

  final Widget compact;
  final Widget tablet;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return AppBreakpoints.isTabletWidth(constraints.maxWidth)
            ? tablet
            : compact;
      },
    );
  }
}
