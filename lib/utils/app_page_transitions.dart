import 'package:flutter/material.dart';

import '../ui/app_materials.dart';

class AppPageTransitions {
  const AppPageTransitions._();

  static Route<T> fadeThrough<T>(Widget page) {
    return _AppPageRoute<T>(
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(opacity: curved, child: child);
      },
    );
  }

  static Route<T> sharedAxisLeftRight<T>(Widget page) {
    return _AppPageRoute<T>(
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        final offset = Tween<Offset>(
          begin: const Offset(0.16, 0),
          end: Offset.zero,
        ).animate(curved);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(position: offset, child: child),
        );
      },
    );
  }

  static Route<T> scaleIn<T>(Widget page) {
    return _AppPageRoute<T>(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        final scale = Tween<double>(begin: 0.96, end: 1).animate(curved);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(scale: scale, child: child),
        );
      },
    );
  }
}

/// Full-screen glass pages use direct navigation; their own controls still
/// animate. This avoids repeatedly repainting two refracting page trees.
class DirectPageTransitionsBuilder extends PageTransitionsBuilder {
  const DirectPageTransitionsBuilder();
  @override
  Duration get transitionDuration => Duration.zero;
  @override
  Duration get reverseTransitionDuration => Duration.zero;
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

class _AppPageRoute<T> extends PageRouteBuilder<T> {
  _AppPageRoute({
    required super.pageBuilder,
    required RouteTransitionsBuilder transitionsBuilder,
    required super.transitionDuration,
    required super.reverseTransitionDuration,
  }) : super(
         transitionsBuilder: (context, animation, secondary, child) {
           if (_direct(context)) return child;
           return transitionsBuilder(context, animation, secondary, child);
         },
       );

  static bool _direct(BuildContext context) =>
      AppMaterials.of(context).liquid ||
      MediaQuery.disableAnimationsOf(context);
  bool get _skip => navigator != null && _direct(navigator!.context);
  @override
  Duration get transitionDuration =>
      _skip ? Duration.zero : super.transitionDuration;
  @override
  Duration get reverseTransitionDuration =>
      _skip ? Duration.zero : super.reverseTransitionDuration;
}
