import 'package:flutter/material.dart';

/// One lens outline is shared by the track cutout and both content masks.
class NavigationLensClipper extends CustomClipper<Path> {
  const NavigationLensClipper({required this.lens, this.inverse = false});
  final Rect lens;
  final bool inverse;

  @override
  Path getClip(Size size) {
    final pill = Path()
      ..addRRect(RRect.fromRectAndRadius(
          lens, Radius.circular(lens.shortestSide / 2)));
    if (!inverse) return pill;
    return Path.combine(
        PathOperation.difference,
        Path()..addRect((Offset.zero & size).expandToInclude(lens).inflate(24)),
        pill);
  }

  @override
  bool shouldReclip(NavigationLensClipper oldClipper) =>
      lens != oldClipper.lens || inverse != oldClipper.inverse;
}

/// These are paint-only copies. Hit targets and semantic labels live above them.
class NavigationLensContent extends StatelessWidget {
  const NavigationLensContent(
      {super.key,
      required this.lens,
      required this.unselected,
      required this.selected});
  final Rect lens;
  final Widget unselected;
  final Widget selected;

  @override
  Widget build(BuildContext context) => IgnorePointer(
          child: ExcludeSemantics(
        child: Stack(fit: StackFit.expand, children: [
          ClipPath(
              key: const ValueKey('navigation-content-outside'),
              clipper: NavigationLensClipper(lens: lens, inverse: true),
              child: unselected),
          ClipPath(
              key: const ValueKey('navigation-content-inside'),
              clipper: NavigationLensClipper(lens: lens),
              child: selected),
        ]),
      ));
}
