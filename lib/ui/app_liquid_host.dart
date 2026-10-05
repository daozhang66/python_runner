import 'package:flutter/material.dart';
import 'package:g1455/g1455.dart';

/// One shared backdrop atlas, above the navigator so menus and dialogs can
/// refract the same scene as cards and controls. Keep it mounted across styles.
class AppLiquidHost extends StatelessWidget {
  const AppLiquidHost({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => GlassHost(
    // Follow the app's explicit theme, even when it differs from the OS.
    finish: GlassFinish.regular(
      appearance: Theme.of(context).brightness,
      backdrop: Theme.of(context).colorScheme.surface,
    ),
    backdrop: Theme.of(context).colorScheme.surface,
    highContrast: MediaQuery.highContrastOf(context),
    child: child,
  );
}
