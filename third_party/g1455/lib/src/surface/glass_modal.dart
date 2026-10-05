// The modal layer: an alert, a sheet, a menu.
//
// What was read off Apple's own (spike 33, iOS 26.5, iPhone 17 Pro, each put
// up programmatically over spike 27's grid and photographed against the bare
// grid):
//
//  - **the dim** behind an alert and behind a sheet is the same: black at
//    0.20 (0.201–0.203 over three channels, solved from the grid's two
//    levels);
//  - **the alert** is 320 pt wide, its corner a continuous one of 34 pt
//    (`layer.cornerRadius`), its text 30 pt in from its sides and its title
//    22 pt below its top; two actions sit side by side as 48 pt capsules 8 pt
//    apart, 16 pt in from the sides and the bottom;
//  - **the sheet** at the medium detent floats 8 pt in from the screen's
//    sides and bottom, its corner the engine's `RSuperellipse` of 36 pt (a
//    superellipse of exponent 3 and 51 pt reach, fitted at 0.54 device px
//    rms), with a grabber at its top.
//
// Not read, and named where it is used: the alert's action fill, the menu's
// size and radius, and every animation. The glass of all three is the theme's
// finish — what Apple's material is was measured once (S4), and a modal is
// the same material.
//
// **Where these must be built.** A glass surface is captured by the
// `GlassHost` above it, and an overlay is wherever its `Overlay` is — for
// `showGlassDialog` and `showGlassSheet` the navigator's, for a menu the
// nearest one. So the host has to be above the navigator, which in a
// `WidgetsApp` / `MaterialApp` is `builder:`. Built anywhere else they find no
// host, and say so in debug rather than drawing glass that samples nothing.
//
// **Each is lifted** ([GlassAbove], [kGlassModalLift]): a dialog over a page
// with glass bars has to show the bars, and bars over glass cards are
// themselves a level above the cards. Over a page with no glass, the lift
// costs nothing — the host numbers only the levels that are occupied.

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'glass_above.dart';
import 'glass_finish.dart';
import 'glass_host.dart';
import 'glass_surface.dart';
import 'glass_theme.dart';

/// The dim behind an alert and a sheet (spike 33).
const Color kGlassModalDim = Color.fromRGBO(0, 0, 0, 0.20);

/// The alert's width and corner, logical px (spike 33).
const double kGlassAlertWidth = 320;
const double kGlassAlertRadius = 34;

/// The sheet's inset from the screen and its corner, logical px (spike 33).
const double kGlassSheetInset = 8;
const double kGlassSheetRadius = 36;

/// iOS's `systemFill`, (120, 120, 128) at 0.20 — the alert's action capsules
/// look like it and were not measured: they lie on the alert's own glass, and
/// one backdrop cannot separate a fill from the material under it.
const Color _kActionFill = Color.fromRGBO(120, 120, 128, 0.20);

/// Says, in debug, when a modal was built outside any `GlassHost`.
void _assertHosted(BuildContext context, String what) {
  assert(() {
    if (GlassProxyScope.maybeOf(context) == null) {
      throw FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary('$what was built with no GlassHost above it.'),
        ErrorDescription(
          'A glass surface is captured by the GlassHost above it, and a modal is built in '
          'the Overlay it is shown in — for a dialog or a sheet the navigator\'s.',
        ),
        ErrorHint(
          'Put the GlassHost above the navigator: WidgetsApp / MaterialApp(builder: '
          '(context, child) => GlassHost(child: child!)).',
        ),
      ]);
    }
    return true;
  }());
}

/// The text style, icon theme and app themes in force where a dialog or a
/// sheet was asked for, carried to the navigator's overlay it is built in —
/// as `showDialog` does. Without them the route's content inherits what
/// stands above the navigator, which in a `MaterialApp` is its error style:
/// red, monospace, underlined in yellow. The glass's own scopes are not
/// `InheritedTheme`s, so a page's group or level is not carried with them.
CapturedThemes _capture(BuildContext context, NavigatorState navigator) =>
    InheritedTheme.capture(from: context, to: navigator.context);

/// Wraps a modal's glass: lifted, and materializing with [progress] —
/// Apple's `.materialize` (D216), blur first and tint last, the content fading
/// in on top.
class _Materializing extends StatelessWidget {
  const _Materializing({required this.progress, required this.builder});

  final Animation<double> progress;
  final Widget Function(BuildContext context, double t) builder;

  @override
  Widget build(BuildContext context) => GlassAbove(
    lift: kGlassModalLift,
    child: AnimatedBuilder(
      animation: progress,
      builder: (BuildContext context, Widget? _) => builder(context, progress.value.clamp(0.0, 1.0)),
    ),
  );
}

// ---------------------------------------------------------------------------
// Alert

/// One button of a [GlassAlert].
@immutable
class GlassAlertAction {
  const GlassAlertAction({required this.label, this.onPressed, this.isDefault = false, this.isDestructive = false});

  final String label;

  /// Null disables it.
  final VoidCallback? onPressed;

  /// Drawn bold, as iOS's preferred action is.
  final bool isDefault;

  /// Drawn in iOS's red.
  final bool isDestructive;
}

/// Shows [builder]'s widget — a [GlassAlert], typically — over a dim, centred,
/// in the navigator's overlay. See the file comment for where the host has to
/// be.
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
  String barrierLabel = 'Dismiss',
  Duration transitionDuration = const Duration(milliseconds: 250),
}) {
  final NavigatorState navigator = Navigator.of(context);
  final CapturedThemes themes = _capture(context, navigator);
  return navigator.push<T>(
    RawDialogRoute<T>(
      barrierDismissible: barrierDismissible,
      barrierLabel: barrierLabel,
      barrierColor: kGlassModalDim,
      transitionDuration: transitionDuration,
      pageBuilder: (BuildContext context, Animation<double> animation, Animation<double> _) =>
          themes.wrap(SafeArea(child: Center(child: builder(context)))),
    ),
  );
}

/// iOS 26's alert, on glass.
class GlassAlert extends StatelessWidget {
  const GlassAlert({
    required this.title,
    this.message,
    this.actions = const <GlassAlertAction>[],
    this.finish,
    super.key,
  });

  final Widget title;
  final Widget? message;
  final List<GlassAlertAction> actions;

  /// The optics. Null takes the theme's.
  final GlassFinish? finish;

  @override
  Widget build(BuildContext context) {
    _assertHosted(context, 'GlassAlert');
    final Animation<double> progress = ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation;
    final GlassThemeData theme = GlassTheme.of(context);
    final Color label = theme.legibility(finish ?? theme.finish).label;
    final double width = math.min(kGlassAlertWidth, MediaQuery.sizeOf(context).width - 2 * 16);
    return _Materializing(
      progress: progress,
      builder: (BuildContext context, double t) => SizedBox(
        width: width,
        child: GlassSurface(
          borderRadius: const BorderRadius.all(Radius.circular(kGlassAlertRadius)),
          finish: finish,
          // Materialized, not grown: Apple's frame is whole from the first
          // frame (D216), and `presence` erodes a lone panel to its medial
          // axis — a bright horizontal line for the first frames.
          materialize: t,
          child: Opacity(
            opacity: Curves.easeIn.transform(t),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: label),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 22, 0, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      child: DefaultTextStyle.merge(
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                        child: title,
                      ),
                    ),
                    if (message != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(30, 6, 30, 0),
                        child: DefaultTextStyle.merge(
                          style: TextStyle(fontSize: 15, color: label.withValues(alpha: label.a * 0.6)),
                          child: message!,
                        ),
                      ),
                    if (actions.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 20),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _actions(label)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _actions(Color label) {
    Widget button(GlassAlertAction a) => _AlertButton(action: a, label: label);
    if (actions.length == 2) {
      return Row(
        children: <Widget>[
          Expanded(child: button(actions[0])),
          const SizedBox(width: 8),
          Expanded(child: button(actions[1])),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var i = 0; i < actions.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: 8),
          button(actions[i]),
        ],
      ],
    );
  }
}

class _AlertButton extends StatefulWidget {
  const _AlertButton({required this.action, required this.label});

  final GlassAlertAction action;
  final Color label;

  @override
  State<_AlertButton> createState() => _AlertButtonState();
}

class _AlertButtonState extends State<_AlertButton> {
  bool _held = false;

  @override
  Widget build(BuildContext context) {
    final GlassAlertAction a = widget.action;
    final bool enabled = a.onPressed != null;
    final Color colour = a.isDestructive ? const Color(0xFFFF3B30) : widget.label;
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _held = true) : null,
        onTapUp: enabled ? (_) => setState(() => _held = false) : null,
        onTapCancel: enabled ? () => setState(() => _held = false) : null,
        onTap: a.onPressed,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            shape: const StadiumBorder(),
            color: _held ? _kActionFill.withValues(alpha: _kActionFill.a * 2) : _kActionFill,
          ),
          child: Text(
            a.label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 17,
              fontWeight: a.isDefault ? FontWeight.w600 : FontWeight.w400,
              color: enabled ? colour : colour.withValues(alpha: colour.a * 0.3),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sheet

/// Shows [builder]'s widget in a glass sheet rising from the bottom, over a
/// dim. Dragged down, it follows the finger and goes past a third of its
/// height or on a flick. See the file comment for where the host has to be.
///
/// [constraints] bound the sheet inside the window's margins, as
/// `showModalBottomSheet`'s do: a `maxWidth` keeps it at its content's width
/// and centred on a wide window, where a sheet across the whole width leaves
/// its content in a corner of the glass. Null, it spans the window.
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  GlassFinish? finish,
  bool showGrabber = true,
  bool barrierDismissible = true,
  String barrierLabel = 'Dismiss',
  BoxConstraints? constraints,
}) {
  final NavigatorState navigator = Navigator.of(context);
  return navigator.push<T>(
    _GlassSheetRoute<T>(
      builder: builder,
      themes: _capture(context, navigator),
      finish: finish,
      showGrabber: showGrabber,
      dismissible: barrierDismissible,
      dismissLabel: barrierLabel,
      constraints: constraints,
    ),
  );
}

class _GlassSheetRoute<T> extends PopupRoute<T> {
  _GlassSheetRoute({
    required this.builder,
    required this.themes,
    required this.finish,
    required this.showGrabber,
    required this.dismissible,
    required this.dismissLabel,
    required this.constraints,
  });

  final WidgetBuilder builder;
  final CapturedThemes themes;
  final GlassFinish? finish;
  final bool showGrabber;
  final bool dismissible;
  final String dismissLabel;
  final BoxConstraints? constraints;

  @override
  Color get barrierColor => kGlassModalDim;

  @override
  bool get barrierDismissible => dismissible;

  @override
  String get barrierLabel => dismissLabel;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 350);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) =>
      themes.wrap(_GlassSheet(route: this));

  void _drag(double fraction) {
    final AnimationController? c = controller;
    if (c != null) {
      c.value = (c.value - fraction).clamp(0.0, 1.0);
    }
  }

  void _release(double velocityFraction) {
    final AnimationController? c = controller;
    if (c == null) {
      return;
    }
    if (velocityFraction > 1.5 || c.value < 2 / 3) {
      navigator?.pop();
    } else {
      c.forward();
    }
  }
}

class _GlassSheet extends StatelessWidget {
  const _GlassSheet({required this.route});

  final _GlassSheetRoute<Object?> route;

  @override
  Widget build(BuildContext context) {
    _assertHosted(context, 'A glass sheet');
    final Animation<double> progress = route.animation ?? kAlwaysCompleteAnimation;
    final EdgeInsets safe = MediaQuery.paddingOf(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(kGlassSheetInset, safe.top + kGlassSheetInset, kGlassSheetInset, kGlassSheetInset),
        child: ConstrainedBox(
          constraints: route.constraints ?? const BoxConstraints(),
          child: GlassAbove(
            lift: kGlassModalLift,
            child: AnimatedBuilder(
              animation: progress,
              builder: (BuildContext context, Widget? child) {
                final double t = Curves.easeOutCubic.transform(progress.value.clamp(0.0, 1.0));
                return FractionalTranslation(translation: Offset(0, 1.05 * (1 - t)), child: child);
              },
              child: GestureDetector(
                onVerticalDragUpdate: (DragUpdateDetails d) {
                  final double h = context.size?.height ?? 1;
                  route._drag(d.primaryDelta! / h);
                },
                onVerticalDragEnd: (DragEndDetails d) {
                  final double h = context.size?.height ?? 1;
                  route._release(d.primaryVelocity! / h);
                },
                child: GlassSurface(
                  borderRadius: const BorderRadius.all(Radius.circular(kGlassSheetRadius)),
                  finish: route.finish,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (route.showGrabber)
                        Center(
                          child: Container(
                            margin: const EdgeInsets.only(top: 5, bottom: 4),
                            width: 36,
                            height: 5,
                            decoration: const ShapeDecoration(shape: StadiumBorder(), color: Color(0x4D3C3C43)),
                          ),
                        ),
                      Flexible(child: Builder(builder: route.builder)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Menu

/// One row of a [GlassMenuAnchor]'s menu.
@immutable
class GlassMenuItem {
  const GlassMenuItem({required this.label, this.icon, this.onPressed, this.isDestructive = false});

  final String label;
  final Widget? icon;

  /// Null disables it. The menu closes after it runs.
  final VoidCallback? onPressed;
  final bool isDestructive;
}

/// What a [GlassMenuAnchor]'s or a [GlassPopoverAnchor]'s builder is given to
/// open and close what it anchors.
class GlassMenuController {
  _AnchoredState<StatefulWidget>? _state;

  bool get isOpen => _state?._open ?? false;
  void open() => _state?._show();
  void close() => _state?._hide();
}

/// A menu's width, row height and corner, logical px (spike 34: iOS 26.5's
/// `UIMenu` from a button, 250 wide, rows of 42 with 10 above and below, the
/// corner the engine's `RSuperellipse` of 31.5 — fitted at 0.23 pt rms).
const double kGlassMenuWidth = 250;
const double kGlassMenuRowHeight = 42;
const double kGlassMenuRadius = 31.5;
const double _kMenuPad = 10;

/// A glass menu that grows out of [builder]'s anchor, in the nearest
/// `Overlay`, which has to be under the `GlassHost`.
///
/// Placed as Apple places a button's menu (spike 34): **over** the anchor, not
/// beside it — its corner on the anchor's matching corner, the anchor hidden
/// while it is open — opening downward from the anchor's top when there is
/// room and upward from its bottom when not, and then with **its items in
/// reverse**, so that the first one is still nearest the finger. The side it
/// aligns to is the anchor's half of the screen. No dim behind it (0.00 code
/// values, against the alert's and the sheet's 0.20).
///
/// Not read: the opening animation, which is shorter than the 0.43 s the
/// reference's screenshots were apart. This one grows out of the anchor —
/// from the anchor's size and capsule to its own, about the corner it shares
/// with the anchor, so the button reads as turning into the menu — while it
/// materializes (D216); never through `presence`, which erodes a lone panel to
/// a line.
class GlassMenuAnchor extends StatefulWidget {
  const GlassMenuAnchor({
    required this.items,
    required this.builder,
    this.controller,
    this.finish,
    this.width = kGlassMenuWidth,
    this.barrierLabel = 'Dismiss',
    super.key,
  });

  final List<GlassMenuItem> items;
  final Widget Function(BuildContext context, GlassMenuController controller) builder;
  final GlassMenuController? controller;
  final GlassFinish? finish;
  final double width;

  /// What a screen reader says of the space around the open menu, whose tap
  /// closes it.
  final String barrierLabel;

  @override
  State<GlassMenuAnchor> createState() => _GlassMenuAnchorState();
}

/// A glass panel of any content that grows out of [builder]'s anchor, as
/// [GlassMenuAnchor]'s menu does, and stays open until a tap outside it or
/// [GlassMenuController.close] — a popover, for content that is changed in
/// place rather than chosen once.
///
/// Its height is not known before it is laid out, so the side it opens to is
/// the anchor's half of the screen: down from an anchor in the upper half, up
/// from one in the lower.
class GlassPopoverAnchor extends StatefulWidget {
  const GlassPopoverAnchor({
    required this.popoverBuilder,
    required this.builder,
    this.controller,
    this.finish,
    this.width = 320,
    this.radius = kGlassMenuRadius,
    this.barrierLabel = 'Dismiss',
    super.key,
  });

  /// The panel's content. Built under a text style and icon theme in the
  /// label colour the theme chose for [finish].
  final WidgetBuilder popoverBuilder;
  final Widget Function(BuildContext context, GlassMenuController controller) builder;
  final GlassMenuController? controller;
  final GlassFinish? finish;
  final double width;
  final double radius;

  /// See [GlassMenuAnchor.barrierLabel].
  final String barrierLabel;

  @override
  State<GlassPopoverAnchor> createState() => _GlassPopoverAnchorState();
}

/// Where an anchored panel stands: whether it opens down, the corner it
/// shares with the anchor, and the screen offsets that pin that corner.
typedef _Placement = ({bool down, Alignment corner, double? left, double? right, double? top, double? bottom});

/// What a menu and a popover share: the overlay, the controller, the hidden
/// anchor, the barrier, and a panel growing out of the anchor's corner.
abstract class _AnchoredState<W extends StatefulWidget> extends State<W> with SingleTickerProviderStateMixin<W> {
  final OverlayPortalController _portal = OverlayPortalController();
  late final GlassMenuController _controller = _widgetController ?? GlassMenuController();
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    reverseDuration: const Duration(milliseconds: 200),
  );
  bool _open = false;

  GlassMenuController? get _widgetController;
  Widget Function(BuildContext context, GlassMenuController controller) get _anchorBuilder;
  GlassFinish? get _finish;
  double get _width;
  double get _radius;
  String get _barrierLabel;

  /// Where the panel goes for an anchor at [at] on [screen].
  _Placement _place(Rect at, Size screen, EdgeInsets safe);

  /// The panel's content, in the label colour.
  Widget _content(BuildContext context, _Placement placement);

  @override
  void initState() {
    super.initState();
    _controller._state = this;
  }

  @override
  void dispose() {
    if (identical(_controller._state, this)) {
      _controller._state = null;
    }
    _progress.dispose();
    super.dispose();
  }

  void _show() {
    if (_open) {
      return;
    }
    setState(() => _open = true);
    _portal.show();
    _progress.forward();
  }

  void _hide() {
    if (!_open) {
      return;
    }
    setState(() => _open = false);
    _progress.reverse().then((_) {
      if (mounted && !_open) {
        _portal.hide();
      }
    });
  }

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: _portal,
    overlayChildBuilder: _overlay,
    // Hidden while the panel stands over it, as Apple's button is: the panel
    // is what it turned into. `Visibility`, not `Opacity` — an anchor that is
    // a glass button must not go under a `saveLayer` (D185). Its semantics
    // are dropped by `ExcludeSemantics` rather than by `Visibility`: in 3.47.1
    // `_RenderVisibility.visible=` marks paint and not semantics, though what
    // it visits for semantics depends on it, and closing over an anchor with
    // a semantics node of its own trips `!semantics.parentDataDirty`.
    child: ExcludeSemantics(
      excluding: _open,
      child: Visibility(
        visible: !_open,
        maintainState: true,
        maintainAnimation: true,
        maintainSize: true,
        maintainInteractivity: true,
        maintainSemantics: true,
        child: _anchorBuilder(context, _controller),
      ),
    ),
  );

  /// Pins the panel's left or right edge, by the anchor's half of the screen,
  /// kept 8 px inside it.
  ({Alignment corner, double? left, double? right}) _side(Rect at, Size screen) {
    // Spike 34: on the right half the panel's right edge is 3 pt past the
    // anchor's, on the left half its left edge 4 pt before.
    final bool right = at.center.dx > screen.width / 2;
    final double left = (right ? at.right + 3 - _width : at.left - 4).clamp(
      8.0,
      math.max(8.0, screen.width - _width - 8),
    );
    return right
        ? (corner: Alignment.topRight, left: null, right: screen.width - left - _width)
        : (corner: Alignment.topLeft, left: left, right: null);
  }

  Widget _overlay(BuildContext context) {
    _assertHosted(context, '$W\'s panel');
    final RenderBox? anchor = this.context.findRenderObject() as RenderBox?;
    final RenderBox? overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (anchor == null || overlay == null || !anchor.hasSize) {
      return const SizedBox.shrink();
    }
    final Rect at = MatrixUtils.transformRect(anchor.getTransformTo(overlay), Offset.zero & anchor.size);
    final _Placement place = _place(at, overlay.size, MediaQuery.paddingOf(context));
    final GlassThemeData theme = GlassTheme.of(context);
    final Color label = theme.legibility(_finish ?? theme.finish).label;
    // Grown from the anchor's own capsule: at nought the glass is the button.
    final double from = at.shortestSide / 2;
    return Stack(
      children: <Widget>[
        Positioned.fill(
          // Labelled, or a screen reader finds a tap target that says nothing
          // and no other way to close a popover.
          child: Semantics(
            label: _barrierLabel,
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _hide),
          ),
        ),
        Positioned(
          left: place.left,
          right: place.right,
          top: place.top,
          bottom: place.bottom,
          child: _Materializing(
            progress: CurvedAnimation(parent: _progress, curve: Curves.easeOutCubic),
            builder: (BuildContext context, double t) => GlassSurface(
              borderRadius: BorderRadius.all(Radius.circular(lerpDouble(from, _radius, t)!)),
              finish: _finish,
              // See the alert: materialized, never eroded to a line.
              materialize: t,
              child: _Grow(
                progress: t,
                from: at.size,
                width: _width,
                corner: place.corner,
                child: Opacity(
                  opacity: Curves.easeIn.transform(t),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(color: label, fontSize: 17),
                    child: IconTheme.merge(
                      data: IconThemeData(color: label, size: 20),
                      child: Builder(builder: (BuildContext context) => _content(context, place)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GlassMenuAnchorState extends _AnchoredState<GlassMenuAnchor> {
  @override
  GlassMenuController? get _widgetController => widget.controller;
  @override
  Widget Function(BuildContext, GlassMenuController) get _anchorBuilder => widget.builder;
  @override
  GlassFinish? get _finish => widget.finish;
  @override
  double get _width => widget.width;
  @override
  double get _radius => kGlassMenuRadius;
  @override
  String get _barrierLabel => widget.barrierLabel;

  double get _height => widget.items.length * kGlassMenuRowHeight + 2 * _kMenuPad;

  @override
  _Placement _place(Rect at, Size screen, EdgeInsets safe) {
    final side = _side(at, screen);
    // Spike 34: opening down, the menu's top is 1 pt above the anchor's; up,
    // its bottom 1 pt below the anchor's — unless that would put its top
    // under the status bar, and then the top is pinned there instead.
    final bool down = at.top - 1 + _height <= screen.height - safe.bottom - 8;
    final double top = down ? at.top - 1 : math.max(safe.top + 8, at.bottom + 1 - _height);
    final bool bottomPinned = !down && top > safe.top + 8;
    return (
      down: down,
      corner: Alignment(side.corner.x, bottomPinned ? 1 : -1),
      left: side.left,
      right: side.right,
      top: bottomPinned ? null : top,
      bottom: bottomPinned ? screen.height - at.bottom - 1 : null,
    );
  }

  @override
  Widget _content(BuildContext context, _Placement placement) {
    // Reversed whenever it opens upward, whichever end is pinned: the first
    // item nearest the finger.
    final List<GlassMenuItem> items = placement.down ? widget.items : widget.items.reversed.toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: _kMenuPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[for (final GlassMenuItem item in items) _row(item, kGlassMenuRowHeight)],
      ),
    );
  }

  Widget _row(GlassMenuItem item, double height) {
    final bool enabled = item.onPressed != null;
    // Spike 34: the icon ahead of the label, centred 40 pt in; the label from
    // 64 pt to 28 pt short of the right edge.
    final Widget content = Row(
      children: <Widget>[
        SizedBox(width: 48, child: Center(child: item.icon ?? const SizedBox.shrink())),
        Expanded(child: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 28),
      ],
    );
    Widget row = Padding(padding: const EdgeInsets.only(left: 16), child: content);
    if (item.isDestructive) {
      row = DefaultTextStyle.merge(
        style: const TextStyle(color: Color(0xFFFF3B30)),
        child: IconTheme.merge(
          data: const IconThemeData(color: Color(0xFFFF3B30)),
          child: row,
        ),
      );
    }
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled
            ? () {
                _hide();
                item.onPressed!();
              }
            : null,
        child: SizedBox(
          height: height,
          child: enabled ? row : Opacity(opacity: 0.3, child: row),
        ),
      ),
    );
  }
}

class _GlassPopoverAnchorState extends _AnchoredState<GlassPopoverAnchor> {
  @override
  GlassMenuController? get _widgetController => widget.controller;
  @override
  Widget Function(BuildContext, GlassMenuController) get _anchorBuilder => widget.builder;
  @override
  GlassFinish? get _finish => widget.finish;
  @override
  double get _width => widget.width;
  @override
  double get _radius => widget.radius;
  @override
  String get _barrierLabel => widget.barrierLabel;

  @override
  _Placement _place(Rect at, Size screen, EdgeInsets safe) {
    final side = _side(at, screen);
    final bool down = at.center.dy < screen.height / 2;
    return (
      down: down,
      corner: Alignment(side.corner.x, down ? -1 : 1),
      left: side.left,
      right: side.right,
      top: down ? at.top - 1 : null,
      bottom: down ? null : screen.height - at.bottom - 1,
    );
  }

  @override
  Widget _content(BuildContext context, _Placement placement) => widget.popoverBuilder(context);
}

/// Lays its child out at [width] and its own height, and is itself that size
/// lerped from [from] by [progress] — the child pinned at [corner] and clipped
/// to what has grown so far. Resized, not scaled: the glass above it is a
/// shape of this size, and a `Transform` would scale the content and leave the
/// shape's corner radius in the wrong units.
class _Grow extends SingleChildRenderObjectWidget {
  const _Grow({required this.progress, required this.from, required this.width, required this.corner, super.child});

  final double progress;
  final Size from;
  final double width;
  final Alignment corner;

  @override
  _RenderGrow createRenderObject(BuildContext context) =>
      _RenderGrow(progress: progress, from: from, width: width, corner: corner);

  @override
  void updateRenderObject(BuildContext context, _RenderGrow renderObject) => renderObject
    ..progress = progress
    ..from = from
    ..width = width
    ..corner = corner;
}

class _RenderGrow extends RenderShiftedBox {
  _RenderGrow({required this._progress, required this._from, required this._width, required this._corner})
    : super(null);

  double _progress;
  set progress(double value) {
    if (value != _progress) {
      _progress = value;
      markNeedsLayout();
    }
  }

  Size _from;
  set from(Size value) {
    if (value != _from) {
      _from = value;
      markNeedsLayout();
    }
  }

  double _width;
  set width(double value) {
    if (value != _width) {
      _width = value;
      markNeedsLayout();
    }
  }

  Alignment _corner;
  set corner(Alignment value) {
    if (value != _corner) {
      _corner = value;
      markNeedsLayout();
    }
  }

  final LayerHandle<ClipRectLayer> _clip = LayerHandle<ClipRectLayer>();

  @override
  void performLayout() {
    final RenderBox? child = this.child;
    if (child == null) {
      size = constraints.constrain(_from);
      return;
    }
    child.layout(
      BoxConstraints.tightFor(width: _width).copyWith(maxHeight: constraints.maxHeight),
      parentUsesSize: true,
    );
    final Size full = child.size;
    size = constraints.constrain(Size.lerp(_from, full, _progress)!);
    (child.parentData! as BoxParentData).offset = _corner.alongOffset(
      Offset(size.width - full.width, size.height - full.height),
    );
  }

  bool get _clipped => child != null && (child!.size.width > size.width || child!.size.height > size.height);

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) {
      return;
    }
    if (!_clipped) {
      _clip.layer = null;
      super.paint(context, offset);
      return;
    }
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      super.paint,
      oldLayer: _clip.layer,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      (Offset.zero & size).contains(position) && super.hitTestChildren(result, position: position);

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }
}
