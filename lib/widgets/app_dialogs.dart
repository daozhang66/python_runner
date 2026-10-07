import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../ui/app_design_tokens.dart';
import '../ui/app_materials.dart';

const double _dialogRadiusValue = AppRadius.dialog;
const BorderRadius _dialogRadius = BorderRadius.all(
  Radius.circular(_dialogRadiusValue),
);

Color appDialogBackgroundColor(BuildContext context, bool enableBlur) {
  final colors = Theme.of(context).colorScheme;
  final surface =
      Theme.of(context).dialogTheme.backgroundColor ??
      colors.surfaceContainerHigh;
  return surface.withValues(alpha: enableBlur ? 0.74 : 1);
}

Widget appDialogFrame({required bool enableBlur, required Widget child}) {
  if (child is AppAlertDialog) return child;
  if (!enableBlur) return child;

  return ClipRRect(
    borderRadius: _dialogRadius,
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
      child: child,
    ),
  );
}

/// AlertDialog retains its layout; only the bounded material under it changes.
class AppAlertDialog extends AlertDialog {
  const AppAlertDialog({
    super.key,
    super.icon,
    super.iconPadding,
    super.iconColor,
    super.title,
    super.titlePadding,
    super.titleTextStyle,
    super.content,
    super.contentPadding,
    super.contentTextStyle,
    super.actions,
    super.actionsPadding,
    super.actionsAlignment,
    super.actionsOverflowAlignment,
    super.actionsOverflowDirection,
    super.actionsOverflowButtonSpacing,
    super.buttonPadding,
    super.backgroundColor,
    super.elevation,
    super.shadowColor,
    super.surfaceTintColor,
    super.semanticLabel,
    super.insetPadding,
    super.clipBehavior,
    super.shape,
    super.alignment,
    super.constraints,
    super.scrollable,
  });

  @override
  Widget build(BuildContext context) {
    final dialog = super.build(context);
    final liquid = AppMaterials.of(context).liquid;
    // Explicit legacy blur colors are preserved in classic mode.
    final legacyBlur = backgroundColor != null && backgroundColor!.a < 1;
    if (dialog is! Dialog) return dialog;
    return Dialog(
      backgroundColor: liquid || legacyBlur
          ? Colors.transparent
          : dialog.backgroundColor,
      elevation: dialog.elevation,
      shadowColor: dialog.shadowColor,
      surfaceTintColor: dialog.surfaceTintColor,
      insetPadding: dialog.insetPadding,
      clipBehavior: dialog.clipBehavior,
      shape: dialog.shape,
      alignment: dialog.alignment,
      constraints: dialog.constraints,
      semanticsRole: dialog.semanticsRole,
      child: AppGlassSurface(
        enabled: liquid || legacyBlur,
        overlay: true,
        sampleBackdrop: true,
        baseColor:
            (backgroundColor ??
                    Theme.of(context).dialogTheme.backgroundColor ??
                    Theme.of(context).colorScheme.surfaceContainerHigh)
                .withValues(alpha: 1),
        radius: _dialogRadius,
        child: dialog.child ?? const SizedBox.shrink(),
      ),
    );
  }
}

Future<T?> showAppModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  ShapeBorder? shape,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  BoxConstraints? constraints,
  bool useRootNavigator = false,
  Color? barrierColor,
  double? elevation,
  Clip? clipBehavior,
  RouteSettings? routeSettings,
}) {
  final liquid = AppMaterials.of(context).liquid;
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: liquid ? Colors.transparent : backgroundColor,
    shape: shape,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: showDragHandle,
    constraints: constraints,
    useRootNavigator: useRootNavigator,
    barrierColor: barrierColor,
    elevation: elevation,
    clipBehavior: clipBehavior,
    routeSettings: routeSettings,
    sheetAnimationStyle: liquid
        ? const AnimationStyle(
            duration: Duration(milliseconds: 180),
            reverseDuration: Duration(milliseconds: 140),
          )
        : null,
    builder: (context) => AppGlassSurface(
      overlay: true,
      sampleBackdrop: true,
      baseColor:
          (backgroundColor ??
                  Theme.of(context).bottomSheetTheme.backgroundColor ??
                  Theme.of(context).colorScheme.surfaceContainerLow)
              .withValues(alpha: 1),
      radius: shape is RoundedRectangleBorder
          ? shape.borderRadius.resolve(Directionality.of(context))
          : _dialogRadius,
      child: builder(context),
    ),
  );
}
