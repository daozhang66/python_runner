import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

const double _dialogRadiusValue = 28;
const BorderRadius _dialogRadius =
    BorderRadius.all(Radius.circular(_dialogRadiusValue));

Color appDialogBackgroundColor(BuildContext context, bool enableBlur) {
  final colors = Theme.of(context).colorScheme;
  return colors.surface.withValues(alpha: enableBlur ? 0.74 : 1);
}

Widget appDialogFrame({
  required bool enableBlur,
  required Widget child,
}) {
  if (!enableBlur) return child;

  return ClipRRect(
    borderRadius: _dialogRadius,
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
      child: child,
    ),
  );
}
