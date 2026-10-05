import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'app_materials.dart';

/// Keeps Material's trigger and menu entries, with one anchored glass transition.
class AppPopupMenuButton<T> extends PopupMenuButton<T> {
  const AppPopupMenuButton(
      {super.key,
      required super.itemBuilder,
      super.initialValue,
      super.onOpened,
      super.onSelected,
      super.onCanceled,
      super.tooltip,
      super.elevation,
      super.shadowColor,
      super.surfaceTintColor,
      super.padding,
      super.menuPadding,
      super.child,
      super.borderRadius,
      super.splashRadius,
      super.icon,
      super.iconSize,
      super.offset,
      super.enabled,
      super.shape,
      super.color,
      super.iconColor,
      super.enableFeedback,
      super.constraints,
      super.position,
      super.clipBehavior,
      super.useRootNavigator,
      super.popUpAnimationStyle,
      super.routeSettings,
      super.style,
      super.requestFocus});
  @override
  PopupMenuButtonState<T> createState() => _GlassMenuButtonState<T>();
}

class _GlassMenuButtonState<T> extends PopupMenuButtonState<T> {
  bool _open = false;
  @override
  void showButtonMenu() {
    if (!AppMaterials.of(context).liquid) {
      super.showButtonMenu();
      return;
    }
    if (_open || !widget.enabled) return;
    final entries = widget.itemBuilder(context);
    if (entries.isEmpty) return;
    final navigator =
        Navigator.of(context, rootNavigator: widget.useRootNavigator);
    final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
    final trigger = context.findRenderObject()! as RenderBox;
    final anchor = (trigger.localToGlobal(Offset.zero, ancestor: overlay) +
            widget.offset) &
        trigger.size;
    final route = _GlassMenuRoute<T>(
        anchor: anchor,
        entries: entries,
        themes: InheritedTheme.capture(from: context, to: navigator.context),
        padding: MediaQuery.paddingOf(context),
        direction: Directionality.of(context),
        reduced: MediaQuery.disableAnimationsOf(context),
        label: MaterialLocalizations.of(context).popupMenuLabel,
        dismissLabel:
            MaterialLocalizations.of(context).modalBarrierDismissLabel,
        menuPadding: widget.menuPadding,
        menuConstraints: widget.constraints,
        settings: widget.routeSettings,
        requestFocus: widget.requestFocus);
    _open = true;
    widget.onOpened?.call();
    navigator.push<T>(route).then((value) {
      _open = false;
      if (!mounted) return;
      if (value == null) {
        widget.onCanceled?.call();
      } else {
        widget.onSelected?.call(value);
      }
    });
  }
}

class _GlassMenuRoute<T> extends PopupRoute<T> {
  _GlassMenuRoute(
      {required this.anchor,
      required this.entries,
      required this.themes,
      required this.padding,
      required this.direction,
      required this.reduced,
      required this.label,
      required this.dismissLabel,
      this.menuPadding,
      this.menuConstraints,
      super.settings,
      super.requestFocus});
  final Rect anchor;
  final List<PopupMenuEntry<T>> entries;
  final CapturedThemes themes;
  final EdgeInsets padding;
  final TextDirection direction;
  final bool reduced;
  final String label, dismissLabel;
  final EdgeInsetsGeometry? menuPadding;
  final BoxConstraints? menuConstraints;
  @override
  Duration get transitionDuration =>
      reduced ? Duration.zero : const Duration(milliseconds: 260);
  @override
  Duration get reverseTransitionDuration =>
      reduced ? Duration.zero : const Duration(milliseconds: 180);
  @override
  bool get barrierDismissible => true;
  @override
  Color? get barrierColor => null;
  @override
  String get barrierLabel => dismissLabel;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    return themes.wrap(Builder(
        builder: (context) => CustomSingleChildLayout(
              delegate: _MenuPosition(
                  anchor,
                  padding + MediaQuery.viewInsetsOf(context),
                  direction,
                  menuConstraints),
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, child) => _MenuMorph(
                    anchor: anchor,
                    progress: Curves.easeOutCubic.transform(animation.value),
                    child: child!),
                child: Semantics(
                  scopesRoute: true,
                  namesRoute: true,
                  explicitChildNodes: true,
                  role: SemanticsRole.menu,
                  label: label,
                  child: IntrinsicWidth(
                      stepWidth: menuConstraints == null ? null : 56,
                      child: AppGlassSurface(
                        overlay: true,
                        sampleBackdrop: true,
                        radius: const BorderRadius.all(Radius.circular(20)),
                        child: Shortcuts(
                            shortcuts: const {
                              SingleActivator(LogicalKeyboardKey.arrowDown):
                                  NextFocusIntent(),
                              SingleActivator(LogicalKeyboardKey.arrowUp):
                                  PreviousFocusIntent(),
                            },
                            child: FocusTraversalGroup(
                                child: SingleChildScrollView(
                              padding: menuPadding ??
                                  const EdgeInsets.symmetric(vertical: 8),
                              child: ListBody(children: entries),
                            ))),
                      )),
                ),
              ),
            )));
  }
}

class _MenuPosition extends SingleChildLayoutDelegate {
  _MenuPosition(this.anchor, this.insets, this.direction, this.menuConstraints);
  final Rect anchor;
  final EdgeInsets insets;
  final TextDirection direction;
  final BoxConstraints? menuConstraints;
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final available =
        math.max(0.0, constraints.maxWidth - insets.horizontal - 16);
    final limits = menuConstraints;
    // Size to content up to a 280 logical-pixel cap. The old forced minWidth
    // stretched short menus across the screen.
    return BoxConstraints(
        minWidth: limits == null ? 0 : math.min(limits.minWidth, available),
        maxWidth: limits == null
            ? math.min(280.0, available)
            : math.min(limits.maxWidth, available),
        maxHeight: math.max(0, constraints.maxHeight - insets.vertical - 16));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = insets.left + 8;
    final right =
        math.max(left, size.width - insets.right - childSize.width - 8);
    final top = insets.top + 8;
    final bottom =
        math.max(top, size.height - insets.bottom - childSize.height - 8);
    final x = direction == TextDirection.ltr
        ? anchor.right - childSize.width
        : anchor.left;
    return Offset(x.clamp(left, right), anchor.top.clamp(top, bottom));
  }

  @override
  bool shouldRelayout(_MenuPosition old) =>
      anchor != old.anchor ||
      insets != old.insets ||
      direction != old.direction ||
      menuConstraints != old.menuConstraints;
}

class _MenuMorph extends SingleChildRenderObjectWidget {
  const _MenuMorph(
      {required this.anchor, required this.progress, required super.child});
  final Rect anchor;
  final double progress;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMenuMorph(anchor, progress);
  @override
  void updateRenderObject(
      BuildContext context, covariant RenderProxyBox renderObject) {
    final render = renderObject as _RenderMenuMorph;
    render.anchor = anchor;
    render.progress = progress;
    render.markNeedsPaint();
    render.markNeedsSemanticsUpdate();
  }
}

class _RenderMenuMorph extends RenderProxyBox {
  _RenderMenuMorph(this.anchor, this.progress);
  Rect anchor;
  double progress;
  final _layer = LayerHandle<TransformLayer>();
  @override
  bool get alwaysNeedsCompositing => true;
  Matrix4 _matrix() {
    final origin = localToGlobal(Offset.zero);
    final sx = size.width == 0 ? 1.0 : anchor.width / size.width;
    final sy = size.height == 0 ? 1.0 : anchor.height / size.height;
    return Matrix4.identity()
      ..translateByDouble((anchor.left - origin.dx) * (1 - progress),
          (anchor.top - origin.dy) * (1 - progress), 0, 1)
      ..scaleByDouble(sx + (1 - sx) * progress, sy + (1 - sy) * progress, 1, 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    _layer.layer = context.pushTransform(true, offset, _matrix(), super.paint,
        oldLayer: _layer.layer);
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.multiply(_matrix());
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      progress >= 0.98 && super.hitTest(result, position: position);
  @override
  void dispose() {
    _layer.layer = null;
    super.dispose();
  }
}
