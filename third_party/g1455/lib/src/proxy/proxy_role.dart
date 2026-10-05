// What a subtree is, as far as the glass proxy is concerned — declared by the
// application, because the engine cannot report it.
//
// This is the third time the same shape appears here and the first time it is
// public. `Overlay.opaque` exists because opacity is not readable from a render
// tree; `CoverDeclaration` in `occlusion.dart` exists for the same reason (D42,
// and the commonest opaque widget in Flutter — `ColoredBox` — paints through a
// private render object); `reduceTransparency` does not reach Dart at all
// (D59), so the host declares it. The engine does not supply the reason; the
// application does.
//
// **What this is not.** Automatic content simplification lost its argument
// already: replacing text and images with mean-colour blocks saves 24…28% and
// costs 0.95…9.6 ΔE, while lowering the proxy resolution saves 47…73% and costs
// 0.47 — so the generic version is beaten on both axes at once and is struck out
// of the roadmap (D28, D29). Nothing here is sold as "cheaper pixels". The three
// things it *is* for:
//
//  - Content that cannot be read at all. A platform view or a `Texture` paints
//    nothing into a recording — `PlatformViewLayer::Paint` without an embedder
//    draws nothing and logs an error (`platform_view_layer.cc:36-41`) — so the
//    stock capture leaves a hole there too. A stub is the only option, not the
//    cheap one.
//  - Retake frequency. A subtree replaced by a stub cannot dirty the proxy, and
//    the retake ceiling is a finish parameter rather than a constant (D30).
//  - Foreign side effects. The pass executes somebody else's `paint()`, which
//    moved the corpus's own counters by 2–12 per pass. Counters, analytics and
//    lazy initialisation all happen a second time per frame, and
//    [GlassProxy.hidden] is the only way to stop them.
//
// Nothing here changes the real frame: in the live pipeline every one of these
// is a `RenderProxyBox` that paints its child.

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The four declarations, in the order of how much they subtract.
enum GlassProxyRole {
  /// Not drawn into the proxy, and not descended into.
  ///
  /// Painter's order still holds, so this is a subtraction and not a hole:
  /// whatever painted earlier at that place stays visible. Over a page with an
  /// opaque background the result is the background.
  hidden,

  /// Drawn by a [GlassProxyPainter] instead of by the subtree's own `paint`.
  replace,

  /// Paints opaquely over its own box, so the descent may stop before it.
  ///
  /// Read by `OcclusionPlan`, not by the pass: a declaration says "this covers
  /// itself", never "this covers the region" — the geometry decides that, and
  /// letting a declaration skip it turned every `ColoredBox` in a tree into a
  /// full-screen cover once already.
  opaque,

  /// Exempt from canvas-level policy inside the subtree.
  ///
  /// Today that policy is exactly the shadow filter, and this exists because
  /// half of it is a heuristic: `ShadowFilter.dropMaskFiltered` drops anything
  /// painted through a `MaskFilter`, which is *usually* a shadow. A design that
  /// blurs a highlight on purpose has no other way to keep it.
  verbatim,
}

/// Draws a stand-in for a subtree in the proxy.
///
/// Deliberately shaped like `CustomPainter`, including the `runtimeType`
/// comparison in front of [shouldRepaint] — this is the same problem and there
/// is no reason to make it look like a different one. Two differences, both
/// deliberate:
///
///  - The canvas is clipped to `size` before [paint] runs. A `CustomPainter`
///    that overdraws produces a visible artefact somebody notices; a stub that
///    overdraws corrupts the backdrop of surfaces elsewhere on the screen, with
///    no visual signal anywhere and no pixel test that would catch it.
///  - [isOpaque] is read, and answering true makes the stub an occlusion cover
///    as well as a substitution.
abstract class GlassProxyPainter {
  const GlassProxyPainter();

  /// Paints the stand-in. Local space: the subtree's origin is `Offset.zero`,
  /// exactly as in `CustomPainter`.
  void paint(Canvas canvas, Size size);

  /// Whether the proxy has to be re-recorded because this painter replaced
  /// [oldPainter].
  ///
  /// The retake oracle is what reads this, through
  /// [RenderGlassProxy.proxyChanges]. A painter that always answers false is a
  /// subtree that can never dirty the proxy — which is the cost lever this
  /// class carries, and it is a lever over *frames*, not over pixels.
  bool shouldRepaint(covariant GlassProxyPainter oldPainter);

  /// Whether [paint] covers the whole of `size` opaquely.
  ///
  /// The same claim [GlassProxyRole.opaque] makes, and it is unverifiable the
  /// same way. A rounded stub is not opaque: the corners are exactly where a
  /// covered pixel would survive.
  bool get isOpaque => false;
}

/// A stub of one flat colour — the cheapest thing that stands for a subtree.
class SolidProxyPainter extends GlassProxyPainter {
  const SolidProxyPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawRect(Offset.zero & size, Paint()..color = color);

  @override
  bool shouldRepaint(SolidProxyPainter oldPainter) => oldPainter.color != color;

  @override
  bool get isOpaque => color.a >= 1.0;
}

/// A stub of one gradient. Keeps a local mean where a flat colour would not —
/// which is the axis a blur cannot restore (D29): a low-pass removes what is
/// above its cutoff and cannot bring back a mean that is no longer there.
class GradientProxyPainter extends GlassProxyPainter {
  const GradientProxyPainter(this.gradient);

  final Gradient gradient;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
  }

  @override
  bool shouldRepaint(GradientProxyPainter oldPainter) => oldPainter.gradient != gradient;
}

/// Declares what its subtree is in the glass proxy.
///
/// One widget for four declarations rather than four widgets, because all four
/// are the same statement — the app telling the proxy something the render tree
/// does not carry — and splitting them would make the caller learn four names to
/// find one.
///
/// **Nesting: the outermost wins, and the inner one is then unreachable.** A
/// [GlassProxy.replace] under a [GlassProxy.hidden] is never visited, because
/// the descent stops at the outer one. That is worth knowing rather than
/// pretending the two compose.
class GlassProxy extends SingleChildRenderObjectWidget {
  /// See [GlassProxyRole.hidden].
  const GlassProxy.hidden({super.key, required Widget super.child}) : role = GlassProxyRole.hidden, painter = null;

  /// See [GlassProxyRole.replace]. [child] still lays out and still paints into
  /// the real frame; only the proxy sees [painter] instead.
  const GlassProxy.replace({super.key, required Widget super.child, required this.painter})
    : role = GlassProxyRole.replace;

  /// See [GlassProxyRole.opaque].
  const GlassProxy.opaque({super.key, required Widget super.child}) : role = GlassProxyRole.opaque, painter = null;

  /// See [GlassProxyRole.verbatim].
  const GlassProxy.verbatim({super.key, required Widget super.child}) : role = GlassProxyRole.verbatim, painter = null;

  final GlassProxyRole role;

  /// Non-null exactly when [role] is [GlassProxyRole.replace].
  final GlassProxyPainter? painter;

  @override
  RenderGlassProxy createRenderObject(BuildContext context) => RenderGlassProxy(role: role, painter: painter);

  @override
  void updateRenderObject(BuildContext context, RenderGlassProxy renderObject) {
    // Painter first: a role change from `replace` to anything else would
    // otherwise leave the old painter in place for the width of one assignment,
    // and the setters notify.
    renderObject
      ..painter = painter
      ..role = role;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(EnumProperty<GlassProxyRole>('role', role))
      ..add(DiagnosticsProperty<GlassProxyPainter>('painter', painter, defaultValue: null));
  }
}

/// The marker the proxy pass reads. In the real frame it is a plain proxy box.
///
/// Being a render object of our own is what keeps the lookup at O(1): the node
/// arrives at `PaintingContext.paintChild` by itself and the pass does one `is`
/// check on it. Any design where the pass *searches* for a declaration pays on
/// every node of the tree instead.
class RenderGlassProxy extends RenderProxyBox {
  RenderGlassProxy({
    GlassProxyRole role = GlassProxyRole.opaque,
    GlassProxyPainter? painter,
    RenderBox? child,
  }) // Not initializing formals: both fields are behind setters that notify,
    // and the constructor must not notify a listener nobody could have
    // attached yet.
    // ignore: prefer_initializing_formals
    : _role = role,
       // ignore: prefer_initializing_formals
       _painter = painter,
       super(child);

  GlassProxyRole get role => _role;
  GlassProxyRole _role;
  set role(GlassProxyRole value) {
    if (value == _role) {
      return;
    }
    _role = value;
    _proxyChanges.notify();
  }

  GlassProxyPainter? get painter => _painter;
  GlassProxyPainter? _painter;
  set painter(GlassProxyPainter? value) {
    final GlassProxyPainter? old = _painter;
    if (identical(old, value)) {
      return;
    }
    _painter = value;
    // `RenderCustomPaint._didUpdatePainter`'s rule (`custom_paint.dart`): a
    // different implementation is a repaint whatever it says about itself,
    // because `shouldRepaint` may only compare against its own kind.
    if (old == null || value == null || value.runtimeType != old.runtimeType || value.shouldRepaint(old)) {
      _proxyChanges.notify();
    }
  }

  /// Fires when this subtree's contribution to the proxy has changed.
  ///
  /// The retake oracle's input — subscribed by `GlassHost` through
  /// `RetakeOracle.watch` since D142, and inert for every application before
  /// that. A `Listenable` and not a comment because an axis with no observable
  /// trace is not an axis, and `shouldRepaint` returning false has to be
  /// distinguishable from `shouldRepaint` never having been called.
  ///
  /// It fires on this subtree's *declaration* changing, which is a role or a
  /// painter. Content that repaints in place under an ordinary widget is
  /// invisible here and says so through `GlassProxyHandle.noteChange`.
  Listenable get proxyChanges => _proxyChanges;
  final _ProxyChanges _proxyChanges = _ProxyChanges();

  /// Draws the stub at [offset], clipped to this box.
  void paintProxy(Canvas canvas, Offset offset) {
    final GlassProxyPainter? p = _painter;
    if (p == null) {
      return;
    }
    canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..clipRect(Offset.zero & size);
    p.paint(canvas, size);
    canvas.restore();
  }

  /// How many markers of each role the subtree holds.
  ///
  /// The other half of the counters the pass keeps: a marker that is in the tree
  /// and never reached — because an ancestor was hidden, or because the region
  /// does not contain it — is otherwise indistinguishable from one that fired.
  static Map<GlassProxyRole, int> countIn(RenderObject root) {
    final counts = <GlassProxyRole, int>{};
    void visit(RenderObject node) {
      if (node is RenderGlassProxy) {
        counts.update(node.role, (int n) => n + 1, ifAbsent: () => 1);
      }
      node.visitChildren(visit);
    }

    visit(root);
    return counts;
  }

  @override
  void dispose() {
    _proxyChanges.dispose();
    super.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(EnumProperty<GlassProxyRole>('role', role))
      ..add(DiagnosticsProperty<GlassProxyPainter>('painter', painter, defaultValue: null));
  }
}

/// `ChangeNotifier.notifyListeners` is `@protected`, and this notifier is a
/// field rather than a superclass — a `RenderObject` already has a `dispose`
/// and a listener list of its own, and mixing a second set into it would put
/// two unrelated lifecycles on one object.
class _ProxyChanges extends ChangeNotifier {
  void notify() => notifyListeners();
}
