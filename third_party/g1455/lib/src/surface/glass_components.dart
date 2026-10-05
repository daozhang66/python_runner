// Level 3 of the three-level structure (research SS7.2): components over the
// primitive, the way `FilledButton` and `Card` sit over `Material`.
//
// **And the first thing building them established is that SS7.2's third level is
// one component with three default sets.** The sketch named
// `GlassButton / GlassBar / GlassCard` as if they were three things; in this
// machine everything that differs between them is the shape, the padding and the
// tap target. The glass is the same glass, the label arithmetic is the same
// arithmetic, and exactly one of the three has behaviour of its own — the
// button, because a press changes the *material* and therefore cannot be a
// layer laid over it. So the body is private, the three names are its presets,
// and this comment is the record rather than three files pretending otherwise.
//
// **What a component adds that `GlassSurface` does not, and it is one thing:
// the label's colour.** A label has to be legible against what is under it, and
// what is under it is not the tint — all three rungs put `mix(backdrop, tint, a)`
// there (D178), so one colour is right at every rung and the only input it needs
// is the declaration the ladder already asks for. That arithmetic lives on
// [GlassFinish.foregroundOver]; what lives here is spending it — and, since
// D204, spending its worst-case twin when nobody has said what is behind the
// glass or the screen is an image, where a mean says nothing about the
// brightest corner ([GlassThemeData.legibility]).
//
// **Three things these deliberately do not do.**
//
//  - **No group.** A blend group is a way to get a picture and not a way to get
//    a price, and there is no count at which it pays for itself: twelve panels
//    declared one group came out at 2.25x stock Material where the same twelve
//    ungrouped were 1.19x (D169). A bar that wrapped its items in one would be
//    charging for a silhouette nobody asked for.
//  - **No repaint boundary between the glass and the content.** Considered and
//    rejected on the numbers rather than on taste: it would keep a content
//    change from re-running the panel's shader, and that shader is 9% of the
//    route's whole addition over the floor (D63) — about 17 000 cycles for a
//    400x60 bar at dpr 3 on D169's per-fragment coefficients, against millions
//    in a frame. A layer per component for an unmeasured saving is exactly what
//    `proxy_role.dart` refuses to sell.
//  - **No safe area.** `SafeArea` exists and an application already has it. A
//    second way to say the same thing is what SS7.3's `GlassId` turned out to be.
//
// **And one number these cannot avoid handing to the application: a component
// is a surface, and surfaces are charged per draw.** The translucency tax
// follows area (D21) with an excess for fragmentation that grows as the square
// of the count (D26, `GlassLoad.fragmentationExcessCycles`), so a bar holding
// five [GlassButton]s is **six** surfaces and thirty-six times one surface's
// excess term. That is not a defect and not forbidden — Apple does put glass
// controls on glass bars — but it is the largest lever left in the package and
// it is decided by whoever writes the tree, so the register counts it.

import 'package:flutter/widgets.dart';

import 'glass_finish.dart';
import 'glass_surface.dart';
import 'glass_theme.dart';

/// The smallest a control may be, logical px — Apple's Human Interface
/// Guidelines, 44 x 44 pt.
///
/// An external documented constant rather than one of ours, which is why it has
/// a name at all: the padding defaults in this file are layout taste and say so,
/// and this is not.
const Size kGlassMinTapTarget = Size(44, 44);

/// The label of a disabled [GlassButton] whose enabled label is black, and
/// whose enabled label is white.
///
/// iOS 26's glass `UIButton` leaves its glass as it is and draws a disabled
/// title in `tertiaryLabel`: (60, 60, 67) at 0.3 in light, (235, 235, 245) at
/// 0.3 in dark — which predicts the simulator's frames over black, grey and
/// white to 0.004 of full scale (D221). Apple picks between the two by the
/// appearance and stops adapting to the backdrop, so its disabled title over
/// glass of the other polarity is all but invisible. The package has no
/// appearance — the platform brightness was measured the wrong guess (D179) —
/// so it picks by the polarity of the label it would have drawn enabled, which
/// is the same choice wherever Apple's is legible.
const Color kGlassDisabledDarkLabel = Color(0x4D3C3C43);
const Color kGlassDisabledLightLabel = Color(0x4DEBEBF5);

/// A glass bar: the navigation layer, which is where Apple's guidelines put this
/// material.
///
/// A capsule by default, because that is what a floating bar is in iOS 26 and
/// because SS5.3's rule — Apple uses a pill for controls, never a squircle — is
/// about exactly this shape. See [kGlassCapsule] for how a capsule is declared
/// and what declaring one found.
///
/// One surface, and its items are content rather than glass. Putting
/// [GlassButton]s in it is allowed and costs what the file comment says it
/// costs.
///
/// ```dart
/// GlassBar(
///   child: Row(
///     mainAxisAlignment: MainAxisAlignment.spaceEvenly,
///     children: <Widget>[Icon(Icons.arrow_back), Text('Library'), Icon(Icons.search)],
///   ),
/// )
/// ```
class GlassBar extends StatelessWidget {
  const GlassBar({
    required this.child,
    this.borderRadius = kGlassCapsule,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.finish,
    super.key,
  });

  /// The corner radii. [kGlassCapsule] by default.
  final BorderRadius borderRadius;

  /// Space between the glass and the items.
  ///
  /// **Layout taste, not a measurement**, and named as such wherever it appears
  /// in this file: S4 read Apple's *material* — its transmission, its blur, its
  /// rim — and no metric of its metrics. A number here dressed as a calibration
  /// would be the one kind of constant this project does not allow.
  final EdgeInsets padding;

  /// The optics. Null takes the theme's.
  final GlassFinish? finish;

  final Widget child;

  @override
  Widget build(BuildContext context) => _GlassPanel(
    borderRadius: borderRadius,
    padding: padding,
    finish: finish,
    child: child,
  );
}

/// A glass card: the same panel as [GlassBar] with a corner instead of a
/// capsule.
///
/// **The same body and different advice, and the advice is Apple's own:** the
/// HIG puts Liquid Glass in the navigation and functional layers and keeps it
/// out of the content layer, and a card is the content layer. The package has no
/// way to detect which layer it is in — the same shape of gap as the ladder's
/// (D175) — so this is a component with a warning rather than a refusal.
///
/// The measured half of the warning points the same way. A card is the widget
/// that multiplies: the translucency tax follows area (D21) and the
/// fragmentation excess grows as the square of the surface count (D26), so a
/// list of glass cards walks up the only large lever the package has left. The
/// register says so — `GlassLedger.read` returns the count, the area and a
/// verdict — and a screen of these is what it is for.
class GlassCard extends StatelessWidget {
  const GlassCard({
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.padding = const EdgeInsets.all(16),
    this.finish,
    super.key,
  });

  /// The corner radii. 24 by default, which is [GlassSurface]'s own default and
  /// the middle of the range the reference material was read at.
  final BorderRadius borderRadius;

  /// Space between the glass and the content. Layout taste — see
  /// [GlassBar.padding].
  final EdgeInsets padding;

  /// The optics. Null takes the theme's.
  final GlassFinish? finish;

  final Widget child;

  @override
  Widget build(BuildContext context) => _GlassPanel(
    borderRadius: borderRadius,
    padding: padding,
    finish: finish,
    child: child,
  );
}

/// A glass control: a capsule that takes a tap and brightens while held.
///
/// The one component of the three with behaviour rather than defaults, and the
/// reason is the press: **Apple's glass brightens while it is held, which means
/// the material changes rather than something being laid over it.** So the
/// overlay is drawn onto the surface's own canvas with [BlendMode.plus], and the
/// press therefore re-runs the panel's shader — which is named rather than
/// avoided: the shader is 9% of the route's addition over the floor (D63) and a
/// control is one small panel.
///
/// **`plus` is scoped by a `saveLayer` and by nothing else.** A
/// `RepaintBoundary` does not open one — it lowers to
/// `SceneBuilder.pushOffset`, and that engine layer paints its children onto the
/// same canvas — so the overlay reaches the glass through one; an [Opacity], a
/// `ColorFilter` or an `ImageFilter` between the two does open one, and then the
/// press adds to transparency and comes out wrong. Both halves of that were
/// measured, one of them by a break that failed to break (D185).
///
/// **What it brightens by is the rim's own measured amount and nothing new.**
/// [pressedOverlay] defaults to the finish's [GlassFinish.rim] — 50.2 code
/// values of neutral white, fitted across seven rims of two Apple materials
/// (D86-D88) — spent over the whole shape instead of along its edge. Apple's own
/// press step was never measured here (S4 captured static bands), so a fraction
/// of this would be a guess where this is at least a quantity somebody read off
/// the reference. Pass your own to disagree.
///
/// The tap target is [kGlassMinTapTarget] at the smallest, and the whole capsule
/// takes the tap rather than only where the label is: the gesture handler is
/// outside the surface and opaque, because a [GlassSurface] is a
/// `RenderProxyBox` and hit-tests only its child.
class GlassButton extends StatefulWidget {
  const GlassButton({
    required this.child,
    this.onPressed,
    this.borderRadius = kGlassCapsule,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
    this.minSize = kGlassMinTapTarget,
    this.pressedOverlay,
    this.finish,
    this.semanticLabel,
    super.key,
  });

  /// Called on a tap. Null disables the control, which is also what the
  /// semantics say: the glass stays as it is and the label dims to
  /// [kGlassDisabledDarkLabel] or [kGlassDisabledLightLabel].
  final VoidCallback? onPressed;

  /// The corner radii. [kGlassCapsule] by default.
  final BorderRadius borderRadius;

  /// Space between the glass and the label. Layout taste — see
  /// [GlassBar.padding].
  final EdgeInsets padding;

  /// The smallest the control may be. [kGlassMinTapTarget] by default.
  final Size minSize;

  /// What is added over the whole shape while the control is held.
  ///
  /// Null takes the finish's rim, which is the only additive quantity in this
  /// package that was measured rather than chosen. `Color(0x00000000)` is a
  /// control that draws nothing.
  final Color? pressedOverlay;

  /// The optics. Null takes the theme's.
  final GlassFinish? finish;

  /// What a screen reader says in place of [child] — for a button that is
  /// only an icon, which says nothing. Null lets [child]'s own semantics speak.
  final String? semanticLabel;

  final Widget child;

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _held = false;

  @override
  void didUpdateWidget(GlassButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Disabled under a finger: the framework cancels the tap from inside the
    // build that removed the handlers, through the `onTapCancel` it was built
    // with, and a `setState` there is one during build. Let go first and that
    // cancel finds nothing to do (D221).
    if (widget.onPressed == null) {
      _held = false;
    }
  }

  void _setHeld(bool value) {
    if (_held == value) {
      return;
    }
    setState(() => _held = value);
  }

  @override
  Widget build(BuildContext context) {
    final GlassFinish finish = widget.finish ?? GlassTheme.of(context).finish;
    final Color overlay = widget.pressedOverlay ?? finish.rim;
    return Semantics(
      button: true,
      enabled: widget.onPressed != null,
      label: widget.semanticLabel,
      child: GestureDetector(
        // Opaque, so the whole capsule takes the tap and not only the part the
        // label covers. Outside the surface for the same reason.
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onPressed == null ? null : (_) => _setHeld(true),
        onTapUp: widget.onPressed == null ? null : (_) => _setHeld(false),
        onTapCancel: widget.onPressed == null ? null : () => _setHeld(false),
        onTap: widget.onPressed,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: widget.minSize.width,
            minHeight: widget.minSize.height,
          ),
          child: _GlassPanel(
            borderRadius: widget.borderRadius,
            padding: widget.padding,
            finish: widget.finish,
            overlay: _held ? overlay : null,
            enabled: widget.onPressed != null,
            // Factors of one: centred inside the minimum size, and no larger
            // than the label otherwise. A bare `Center` takes every pixel it is
            // offered, so a button in a `Wrap` or a `Column` was a bar.
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              // A label is not text to select: a drag across a page that
              // selects would otherwise take it along.
              child: SelectionContainer.disabled(
                child: ExcludeSemantics(excluding: widget.semanticLabel != null, child: widget.child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The body all three components are presets of.
class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.borderRadius,
    required this.padding,
    required this.finish,
    required this.child,
    this.overlay,
    this.enabled = true,
  });

  final BorderRadius borderRadius;
  final EdgeInsets padding;
  final GlassFinish? finish;
  final Color? overlay;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final GlassThemeData theme = GlassTheme.of(context);
    final GlassFinish effective = finish ?? theme.finish;
    return GlassSurface(
      borderRadius: borderRadius,
      finish: finish,
      child: CustomPaint(
        // Nothing between this and the glass that would open a `saveLayer`, and
        // that is the whole requirement: `plus` adds to whatever is already on
        // the canvas it is recorded on, and a `saveLayer` above it would make
        // that transparency instead of the glass. A `RepaintBoundary` is **not**
        // one — it lowers to `SceneBuilder.pushOffset`, whose engine layer
        // paints its children onto the same canvas — so one here changes
        // nothing, which is measured rather than assumed (the break that failed
        // to break, D185). An `Opacity`, a `ColorFilter` or an `ImageFilter`
        // does open one, and then the press adds to nothing; that is a hazard
        // for whoever wraps a control, and it is why this sits directly over the
        // surface rather than under anything convenient.
        painter: overlay == null ? null : _GlassOverlay(borderRadius, overlay!),
        child: Padding(
          padding: padding,
          child: _labelled(context, theme, effective, child),
        ),
      ),
    );
  }

  /// Sets the label colour from the level the glass shows.
  ///
  /// Against the declared backdrop when it is flat, and against **every**
  /// backdrop when it is rich or undeclared ([GlassThemeData.legibility]). The
  /// second case used to leave the colour alone (D184), because the two
  /// available guesses — the tint, and the platform brightness — were both
  /// measured wrong (D179). The worst case is not a third guess: it is a bound
  /// that needs nothing but the finish, and on [GlassFinish.regularDark] it is
  /// white at 6.05, AA over any image there is (D204). What remains worth
  /// saying is when even the bound is below AA — a light, thin finish over an
  /// undeclared screen — and that is what the report says now.
  Widget _labelled(
    BuildContext context,
    GlassThemeData theme,
    GlassFinish finish,
    Widget child,
  ) {
    final GlassLegibility legibility = theme.legibility(finish);
    if (theme.backdrop == null &&
        !theme.richBackdrop &&
        legibility.finish.worstContrast(legibility.label) < kTextContrastAA) {
      _reportIllegible(legibility.finish.worstContrast(legibility.label));
    }
    final Color foreground = enabled
        ? legibility.label
        : legibility.label.computeLuminance() < 0.5
        ? kGlassDisabledDarkLabel
        : kGlassDisabledLightLabel;
    return IconTheme.merge(
      data: IconThemeData(color: foreground),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: foreground),
        child: child,
      ),
    );
  }
}

/// Said once per process, not once per frame: the condition is a property of the
/// tree, and this runs in every build of every component.
bool _warnedIllegible = false;

/// Re-arms the report above.
///
/// A once-per-process complaint is unobservable to the second test that wants to
/// see it, and a report nothing can read is the same as no report. Debug-shaped
/// rather than public: `assert` strips the complaint in profile anyway.
@visibleForTesting
void debugResetGlassBackdropReport() => _warnedIllegible = false;

void _reportIllegible(double worst) {
  assert(() {
    if (_warnedIllegible) {
      return true;
    }
    _warnedIllegible = true;
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: FlutterError(
          'A glass component has no GlassThemeData.backdrop, and its finish is '
          'not legible over every backdrop: the best label reaches a contrast of '
          '${worst.toStringAsFixed(2)} in the worst case, under WCAG AA (4.5).\n'
          'The label was chosen against every backdrop because nothing said which '
          'one is behind the glass (D204). Declare the screen background on '
          'GlassHost or GlassTheme if it is flat — then the label is chosen '
          'against it — or set richBackdrop and minLabelContrast if it is an '
          'image, and the glass is dimmed until the label reaches the floor.',
        ),
        library: 'glass',
        context: ErrorDescription('while building a glass component'),
      ),
    );
    return true;
  }());
}

/// Adds a colour over the whole shape, in the layer it is recorded in.
class _GlassOverlay extends CustomPainter {
  const _GlassOverlay(this.borderRadius, this.color);

  final BorderRadius borderRadius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (color.a <= 0) {
      return;
    }
    canvas.drawRSuperellipse(
      // `scaleRadii` for the same reason `RenderGlassSurface.shapeAt` does it:
      // a capsule is declared as a radius larger than the box, and the overlay
      // has to be the shape the glass under it is.
      borderRadius.toRSuperellipse(Offset.zero & size).scaleRadii(),
      Paint()
        ..blendMode = BlendMode.plus
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_GlassOverlay oldDelegate) =>
      oldDelegate.color != color || oldDelegate.borderRadius != borderRadius;
}
