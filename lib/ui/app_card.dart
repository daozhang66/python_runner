import 'package:flutter/material.dart';

import 'app_materials.dart';

/// Shared card chrome; changing style preserves the content's state and layout.
class AppCard extends Card {
  const AppCard({
    super.key,
    super.child,
    super.margin,
    super.shape,
    super.color,
    super.elevation,
    super.clipBehavior,
  });

  @override
  Widget build(BuildContext context) {
    final materials = AppMaterials.of(context);
    final resolvedShape = shape ?? CardTheme.of(context).shape;
    final radius = resolvedShape is RoundedRectangleBorder
        ? resolvedShape.borderRadius.resolve(Directionality.of(context))
        : BorderRadius.circular(16);
    return Card(
      margin: margin,
      shape: shape,
      color: materials.liquid ? Colors.transparent : color,
      elevation: materials.liquid ? 0 : elevation,
      clipBehavior: clipBehavior,
      child: AppGlassSurface(
        cardSurface: true,
        interactive: false,
        baseColor: color ?? materials.content,
        radius: radius,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
