// Glass that stands on its neighbours rather than inside them: a bar over a
// list of glass cards, a scroll edge over that list, a menu or a sheet over a
// page that has glass of its own.
//
// Levels are counted by the tree (D214): a lens refracts the bar it is written
// *inside*, and two sibling panels that overlap are one level over one
// backdrop. Both rules are right for what they were built for and both are
// blind to the commonest screen there is — glass cards scrolling under a glass
// bar — because the bar is the cards' sibling, the capture skips every glass
// subtree, and the bar therefore shows the page with the cards cut out of it.
//
// Overlap on screen would not fix that without breaking the second rule, and
// paint order is the same question asked of every pair. So it is declared:
// everything under a [GlassAbove] is [GlassAbove.lift] levels higher than its
// position in the tree says, and its walk draws the glass below it through
// that glass's own frame, exactly as a lens's walk draws its bar.
//
// What it costs is what a level costs (D214): one more snapshot on every frame
// that records, and nothing on a screen with no glass under the lifted one —
// the host numbers the levels that are occupied, so a lifted bar over plain
// content is level 0 and is captured with everything else.

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Raises every glass surface below it [lift] levels above the glass beside it.
///
/// Wrap what stands on other glass: an app bar or a tab bar over glass cards,
/// a [GlassScrollEdge], a menu, a dialog, a sheet. A surface's level is the
/// number of captured glass surfaces it is written inside plus the lifts above
/// it; a level's capture draws every glass of a lower level, so the bar sees
/// the cards.
///
/// **Glass beside a lifted subtree but painted on top of it is drawn into its
/// capture anyway** — levels are a declaration, not paint order. A bar left
/// unlifted over a lifted scroll edge appears blurred in the edge's backdrop;
/// lift the bar with it ([GlassScrollEdge.child] does).
class GlassAbove extends SingleChildRenderObjectWidget {
  const GlassAbove({this.lift = 1, super.child, super.key}) : assert(lift > 0);

  /// How many levels the glass below is raised. One for a bar over a page; a
  /// modal layer over bars that are themselves lifted takes two
  /// ([kGlassModalLift]).
  final int lift;

  @override
  RenderGlassAbove createRenderObject(BuildContext context) => RenderGlassAbove(lift);

  @override
  void updateRenderObject(BuildContext context, RenderGlassAbove renderObject) {
    renderObject.lift = lift;
  }
}

/// The lift of a modal layer — a menu, a dialog, a sheet: above the page's
/// glass and above bars lifted over it.
const int kGlassModalLift = 2;

/// The render object behind [GlassAbove]: a marker the host reads off the
/// tree, and nothing else — it paints, lays out and hit-tests as its child.
class RenderGlassAbove extends RenderProxyBox {
  RenderGlassAbove(this._lift);

  int get lift => _lift;
  int _lift;
  set lift(int value) {
    if (value == _lift) {
      return;
    }
    _lift = value;
    // The host reads levels when it captures; a repaint here is what gets a
    // frame to capture on, since nothing else about the tree changed.
    markNeedsPaint();
  }
}
