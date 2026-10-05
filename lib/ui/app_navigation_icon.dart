import 'package:flutter/material.dart';

/// HTTP's short wordmark occupies much less of its glyph square than the other
/// icons. Enlarge its ink while keeping every label on the same baseline.
class AppNavigationIcon extends StatelessWidget {
  const AppNavigationIcon({super.key, required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 32,
        height: 24,
        child: OverflowBox(
          minWidth: 0,
          maxWidth: 32,
          minHeight: 0,
          maxHeight: 32,
          child: Icon(icon,
              size: icon == Icons.http_rounded ? 32 : 24, color: color),
        ),
      );
}
