// A toolbar's group of buttons: several actions in one glass capsule.
//
// Read off Apple's own `UIToolbar` on iOS 26.5, iPhone 17 Pro (spike 33):
// a toolbar of four items, the first alone and three after a flexible space,
// comes out as **two** glass shapes — a 48 pt circle for the one and a
// 159 x 48 pt capsule for the three. Apple groups adjacent items into one
// glass; it does not put a glass behind each.
//
// That is also the cheap way to build it here, and it is why this is a widget
// and not advice: a surface is charged per draw, and the fragmentation excess
// grows as the square of the surface count (D26) — three buttons as three
// [GlassButton]s are three surfaces where Apple draws one. So a group is one
// [GlassSurface], and pressing an item brightens that item's part of it the
// way [GlassButton] brightens its whole: the finish's rim, added, over the
// item's cell clipped to the capsule (D185's rule about `plus` holds — nothing
// between the overlay and the glass opens a `saveLayer`).

import 'package:flutter/widgets.dart';

import 'glass_components.dart' show kGlassMinTapTarget;
import 'glass_finish.dart';
import 'glass_surface.dart';
import 'glass_theme.dart';

/// The group's height, and the circle a group of one is (spike 33).
const double kGlassToolbarHeight = 48;

/// Each item's width in a group of more than one: 159 pt for three
/// (spike 33).
const double kGlassToolbarItemWidth = 53;

/// One action of a [GlassButtonGroup].
@immutable
class GlassToolbarItem {
  const GlassToolbarItem({required this.icon, required this.onPressed, this.label});

  final Widget icon;

  /// Null disables the item.
  final VoidCallback? onPressed;

  /// What the semantics say; the icon alone says nothing to a screen reader.
  final String? label;
}

/// Adjacent actions in one glass capsule — a circle for one — as iOS 26's
/// toolbar draws them. One surface whatever the count.
class GlassButtonGroup extends StatefulWidget {
  const GlassButtonGroup({required this.items, this.finish, this.pressedOverlay, super.key}) : assert(items.length > 0);

  final List<GlassToolbarItem> items;

  /// The optics. Null takes the theme's.
  final GlassFinish? finish;

  /// What is added over a held item's cell. Null takes the finish's rim, as
  /// [GlassButton] does.
  final Color? pressedOverlay;

  @override
  State<GlassButtonGroup> createState() => _GlassButtonGroupState();
}

class _GlassButtonGroupState extends State<GlassButtonGroup> {
  int? _held;

  @override
  Widget build(BuildContext context) {
    final GlassThemeData theme = GlassTheme.of(context);
    final GlassFinish finish = widget.finish ?? theme.finish;
    final Color overlay = widget.pressedOverlay ?? finish.rim;
    final int n = widget.items.length;
    final double width = n == 1 ? kGlassToolbarHeight : n * kGlassToolbarItemWidth;
    final Color label = theme.legibility(finish).label;
    return SizedBox(
      width: width,
      height: kGlassToolbarHeight,
      child: GlassSurface(
        borderRadius: kGlassCapsule,
        finish: widget.finish,
        child: CustomPaint(
          painter: _held == null ? null : _CellOverlay(_held!, n, overlay),
          child: IconTheme.merge(
            data: IconThemeData(color: label, size: 22),
            child: Row(
              children: <Widget>[
                for (var i = 0; i < n; i++) Expanded(child: _item(i)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(int i) {
    final GlassToolbarItem item = widget.items[i];
    final bool enabled = item.onPressed != null;
    void hold(bool on) {
      if ((on ? i : null) != _held) {
        setState(() => _held = on ? i : null);
      }
    }

    return Semantics(
      button: true,
      enabled: enabled,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => hold(true) : null,
        onTapUp: enabled ? (_) => hold(false) : null,
        onTapCancel: enabled ? () => hold(false) : null,
        onTap: item.onPressed,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: kGlassMinTapTarget.height),
          child: Center(
            child: enabled ? item.icon : Opacity(opacity: 0.3, child: item.icon),
          ),
        ),
      ),
    );
  }
}

/// Adds a colour over item [index]'s cell, clipped to the capsule.
class _CellOverlay extends CustomPainter {
  const _CellOverlay(this.index, this.count, this.color);

  final int index;
  final int count;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (color.a <= 0) {
      return;
    }
    final double cell = size.width / count;
    canvas
      ..save()
      ..clipRSuperellipse(kGlassCapsule.toRSuperellipse(Offset.zero & size).scaleRadii())
      ..drawRect(
        Rect.fromLTWH(cell * index, 0, cell, size.height),
        Paint()
          ..blendMode = BlendMode.plus
          ..color = color,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_CellOverlay oldDelegate) =>
      oldDelegate.index != index || oldDelegate.count != count || oldDelegate.color != color;
}
