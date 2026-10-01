import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../l10n/app_localizations.dart';

/// Floating navigation: drag previews stay local until the user releases.
class AppBottomNavigation extends StatefulWidget {
  const AppBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  }) : assert(selectedIndex >= 0 && selectedIndex < 3);

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  State<AppBottomNavigation> createState() => _AppBottomNavigationState();
}

class _AppBottomNavigationState extends State<AppBottomNavigation>
    with TickerProviderStateMixin {
  static const _barHeight = 64.0;
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 420,
    damping: 36,
  );

  late final AnimationController _position = AnimationController.unbounded(
    vsync: this,
    value: widget.selectedIndex.toDouble(),
  );
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 130),
    reverseDuration: const Duration(milliseconds: 240),
  );
  double? _preview;
  double _releaseStretch = 0;
  double _releasePress = 1;
  bool _dragging = false;
  bool _reduceMotion = false;
  Offset _lastPointer = Offset.zero;

  double get _visiblePosition => _preview == null
      ? _position.value
      : _position.value * 0.28 + _preview! * 0.72;

  double get _stretch => _preview == null
      ? _releaseStretch * (_press.value / _releasePress).clamp(0, 1)
      : (_preview! - _position.value).abs().clamp(0, 0.85);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _position.value = _preview ?? widget.selectedIndex.toDouble();
      _press.value = 0;
    }
  }

  @override
  void didUpdateWidget(covariant AppBottomNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _settle(widget.selectedIndex);
    }
  }

  @override
  void dispose() {
    _position.dispose();
    _press.dispose();
    super.dispose();
  }

  double _logicalPosition(Offset local, double width, TextDirection direction) {
    final physical = (local.dx / (width / 3) - 0.5).clamp(0.0, 2.0);
    return direction == TextDirection.rtl ? 2 - physical : physical;
  }

  void _follow(double target) {
    if (!mounted) return;
    setState(() {
      _preview = target;
      _releaseStretch = 0;
    });
    if (_reduceMotion) {
      _position.value = target;
    } else {
      _press.forward();
      _position.animateTo(
        target,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _settle(int index) {
    // Capture the painted position before removing the pointer preview, so a
    // release or cancellation never jumps back to the lagging animation.
    final position = _visiblePosition;
    final stretch = _stretch;
    _preview = null;
    _dragging = false;
    _releaseStretch = stretch;
    _releasePress = math.max(_press.value, 0.001);
    _position.value = position;
    if (_reduceMotion) {
      _position.value = index.toDouble();
      _press.value = 0;
    } else {
      _position.animateWith(
        SpringSimulation(_spring, position, index.toDouble(), 0),
      );
      _press.reverse();
    }
  }

  void _commit(int index) {
    if (!mounted) return;
    setState(() => _settle(index));
    if (index != widget.selectedIndex) {
      widget.onDestinationSelected(index);
    }
  }

  void _cancel() {
    if (!mounted) return;
    setState(() => _settle(widget.selectedIndex));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final direction = Directionality.of(context);
    final labels = [l10n.scripts, l10n.network, l10n.packageManager];
    const icons = [
      Icons.code_rounded,
      Icons.http_rounded,
      Icons.inventory_2_rounded,
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Align(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final slotWidth = width / 3;
                return Listener(
                  onPointerDown: (event) {
                    if (event.buttons == 1) {
                      _follow(_logicalPosition(
                          event.localPosition, width, direction));
                    }
                  },
                  // A canceled, already accepted drag can otherwise report an
                  // end event. Clear the preview before the recognizer commits.
                  onPointerCancel: (_) => _cancel(),
                  child: GestureDetector(
                    key: const ValueKey('navigation-gesture-area'),
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (details) {
                      _dragging = true;
                      _lastPointer = details.localPosition;
                      _follow(_logicalPosition(_lastPointer, width, direction));
                    },
                    onHorizontalDragUpdate: (details) {
                      if (!_dragging) return;
                      _lastPointer = details.localPosition;
                      _follow(_logicalPosition(_lastPointer, width, direction));
                    },
                    onHorizontalDragEnd: (_) {
                      if (!_dragging) return;
                      if (_lastPointer.dy < -32 ||
                          _lastPointer.dy > _barHeight + 32) {
                        _cancel();
                      } else {
                        _commit(_preview!.round().clamp(0, 2));
                      }
                    },
                    onHorizontalDragCancel: _cancel,
                    child: SizedBox(
                      height: _barHeight,
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_position, _press]),
                        builder: (context, _) {
                          final logical = _visiblePosition.clamp(0.0, 2.0);
                          final visual = direction == TextDirection.rtl
                              ? 2 - logical
                              : logical;
                          final expanded = _reduceMotion ? 0.0 : _press.value;
                          final baseWidth = (slotWidth * 0.8).clamp(64.0, 96.0);
                          final indicatorWidth =
                              (baseWidth * (1 + expanded * 0.16) +
                                      (_reduceMotion
                                          ? 0
                                          : _stretch * slotWidth * 0.6))
                                  .clamp(baseWidth, width - 8);
                          final indicatorHeight = 52 + expanded * 18;
                          final center = ((visual + 0.5) * slotWidth).clamp(
                              indicatorWidth / 2, width - indicatorWidth / 2);
                          final highlighted =
                              (_preview ?? widget.selectedIndex.toDouble())
                                  .round();

                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: Material(
                                  key: const ValueKey('navigation-surface'),
                                  color: colors.surfaceContainer,
                                  elevation: 3,
                                  shadowColor:
                                      colors.shadow.withValues(alpha: 0.16),
                                  surfaceTintColor: Colors.transparent,
                                  shape: const StadiumBorder(),
                                ),
                              ),
                              Positioned(
                                left: center - indicatorWidth / 2,
                                top: (_barHeight - indicatorHeight) / 2,
                                width: indicatorWidth,
                                height: indicatorHeight,
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    key: const ValueKey('navigation-indicator'),
                                    decoration: ShapeDecoration(
                                      color: colors.secondaryContainer,
                                      shape: const StadiumBorder(),
                                    ),
                                  ),
                                ),
                              ),
                              Row(
                                children: [
                                  for (var index = 0;
                                      index < labels.length;
                                      index++)
                                    Expanded(
                                      child: _NavigationItem(
                                        index: index,
                                        label: labels[index],
                                        icon: icons[index],
                                        selected: widget.selectedIndex == index,
                                        highlighted: highlighted == index,
                                        onTap: () => _commit(index),
                                        onTapCancel: () {
                                          if (!_dragging) _cancel();
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.index,
    required this.label,
    required this.icon,
    required this.selected,
    required this.highlighted,
    required this.onTap,
    required this.onTapCancel,
  });

  final int index;
  final String label;
  final IconData icon;
  final bool selected;
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback onTapCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = highlighted
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurfaceVariant;
    return Semantics(
      key: ValueKey('navigation-item-$index'),
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Tooltip(
          message: label,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(32),
              splashFactory: NoSplash.splashFactory,
              highlightColor: Colors.transparent,
              onTap: onTap,
              onTapCancel: onTapCancel,
              child: SizedBox(
                height: _AppBottomNavigationState._barHeight,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 24, color: color),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: MediaQuery.withClampedTextScaling(
                        maxScaleFactor: 1.3,
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium!.copyWith(
                            letterSpacing: 0,
                            color: color,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
