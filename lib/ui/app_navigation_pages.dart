import 'package:flutter/material.dart';

/// Keeps visited workspaces alive; only committed navigation animates the pages.
class AppNavigationPages extends StatefulWidget {
  const AppNavigationPages({
    super.key,
    required this.index,
    required this.children,
    this.animate = true,
  }) : assert(index >= 0 && index < children.length);

  final int index;
  final List<Widget> children;
  final bool animate;

  @override
  State<AppNavigationPages> createState() => _AppNavigationPagesState();
}

class _AppNavigationPagesState extends State<AppNavigationPages> {
  late final PageController _controller =
      PageController(initialPage: widget.index);

  @override
  void didUpdateWidget(covariant AppNavigationPages oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index && _controller.hasClients) {
      if (!widget.animate || MediaQuery.disableAnimationsOf(context)) {
        _controller.jumpToPage(widget.index);
      } else {
        _controller.animateToPage(
          widget.index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView(
      controller: _controller,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var index = 0; index < widget.children.length; index++)
          _KeptNavigationPage(
            key: ValueKey(index),
            child: TickerMode(
              enabled: index == widget.index,
              child: ExcludeFocus(
                excluding: index != widget.index,
                child: ExcludeSemantics(
                  excluding: index != widget.index,
                  child: IgnorePointer(
                    ignoring: index != widget.index,
                    child: widget.children[index],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _KeptNavigationPage extends StatefulWidget {
  const _KeptNavigationPage({super.key, required this.child});

  final Widget child;

  @override
  State<_KeptNavigationPage> createState() => _KeptNavigationPageState();
}

class _KeptNavigationPageState extends State<_KeptNavigationPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
