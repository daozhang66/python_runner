import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'app_navigation_destinations.dart';
import 'app_navigation_icon.dart';
import 'navigation_lens_content.dart';
import 'navigation_motion.dart';

/// Floating navigation: drag previews stay local until the user releases.
class ClassicBottomNavigation extends StatefulWidget {
  const ClassicBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  }) : assert(selectedIndex >= 0 &&
            selectedIndex < AppNavigationDestinations.count);

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  State<ClassicBottomNavigation> createState() =>
      _ClassicBottomNavigationState();
}

class _ClassicBottomNavigationState extends State<ClassicBottomNavigation>
    with TickerProviderStateMixin {
  static const _barHeight = 64.0;
  late final _motion =
      NavigationMotion(vsync: this, index: widget.selectedIndex);
  bool _dragging = false;
  Offset _lastPointer = Offset.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion.setReducedMotion(
        MediaQuery.disableAnimationsOf(context), widget.selectedIndex);
  }

  @override
  void didUpdateWidget(covariant ClassicBottomNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _dragging = false;
      if (!_motion.settlingTo(widget.selectedIndex)) {
        _motion.settle(widget.selectedIndex);
      }
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  double _logicalPosition(Offset local, double width, TextDirection direction) {
    final physical =
        (local.dx / (width / AppNavigationDestinations.count) - 0.5)
            .clamp(0.0, (AppNavigationDestinations.count - 1).toDouble());
    return direction == TextDirection.rtl
        ? AppNavigationDestinations.count - 1 - physical
        : physical;
  }

  void _commit(int index) {
    if (!mounted) return;
    final tap = !_dragging;
    _dragging = false;
    _motion.settle(index, pulse: tap);
    if (index != widget.selectedIndex) widget.onDestinationSelected(index);
  }

  void _cancel() {
    if (!mounted) return;
    _dragging = false;
    _motion.settle(widget.selectedIndex);
  }

  Widget _buildLabels(List<String> labels, Color color,
          {double position = 0, double growth = 0}) =>
      Row(children: [
        for (var index = 0; index < labels.length; index++)
          Expanded(
            child: Transform.scale(
              scale:
                  1 + growth * (1 - (index - position).abs().clamp(0.0, 1.0)),
              transformHitTests: false,
              child: _NavigationLabel(
                  label: labels[index],
                  icon: AppNavigationDestinations.icons[index],
                  color: color),
            ),
          ),
      ]);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final direction = Directionality.of(context);
    final labels = AppNavigationDestinations.labels(l10n);

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
                if (width <= 8) return const SizedBox(height: _barHeight);
                final slotWidth = width / AppNavigationDestinations.count;
                return Listener(
                  onPointerDown: (event) {
                    if (event.buttons == 1) {
                      _motion.pressAt(
                          _logicalPosition(
                              event.localPosition, width, direction),
                          time: event.timeStamp);
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
                      _motion.follow(
                          _logicalPosition(_lastPointer, width, direction),
                          time: details.sourceTimeStamp);
                    },
                    onHorizontalDragUpdate: (details) {
                      if (!_dragging) return;
                      _lastPointer = details.localPosition;
                      _motion.follow(
                          _logicalPosition(_lastPointer, width, direction),
                          time: details.sourceTimeStamp);
                    },
                    onHorizontalDragEnd: (_) {
                      if (!_dragging) return;
                      if (_lastPointer.dy < -32 ||
                          _lastPointer.dy > _barHeight + 32) {
                        _cancel();
                      } else {
                        _commit(_motion.preview!
                            .round()
                            .clamp(0, AppNavigationDestinations.count - 1));
                      }
                    },
                    onHorizontalDragCancel: _cancel,
                    child: SizedBox(
                      height: _barHeight,
                      child: AnimatedBuilder(
                        animation: _motion,
                        builder: (context, _) {
                          final logical = _motion.position.clamp(0.0,
                              (AppNavigationDestinations.count - 1).toDouble());
                          final visual = direction == TextDirection.rtl
                              ? AppNavigationDestinations.count - 1 - logical
                              : logical;
                          final expanded = _motion.press;
                          final baseWidth = (slotWidth * 0.8)
                              .clamp(math.min(64.0, width - 8),
                                  math.min(96.0, width - 8))
                              .toDouble();
                          final indicatorWidth =
                              math.min(baseWidth + expanded * 20, width + 8);
                          final indicatorHeight = 52 + expanded * 18;
                          // Growth must not push the end capsules away from
                          // the finger. The outer padding supplies overflow room.
                          final indicator = Rect.fromCenter(
                              center: Offset(
                                  (visual + 0.5) * slotWidth, _barHeight / 2),
                              width: indicatorWidth,
                              height: indicatorHeight);

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
                              Positioned.fromRect(
                                rect: indicator,
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
                              Positioned.fill(
                                child: NavigationLensContent(
                                  lens: indicator,
                                  unselected: _buildLabels(
                                      labels, colors.onSurfaceVariant),
                                  selected: _buildLabels(
                                      labels, colors.onSecondaryContainer,
                                      position: logical,
                                      growth: 0.12 * _motion.progress),
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
                                        selected: widget.selectedIndex == index,
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
    required this.selected,
    required this.onTap,
    required this.onTapCancel,
  });

  final int index;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onTapCancel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ValueKey('navigation-item-$index'),
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Tooltip(
          triggerMode: TooltipTriggerMode.manual,
          message: label,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(32),
              splashFactory: NoSplash.splashFactory,
              highlightColor: Colors.transparent,
              onTap: onTap,
              onTapCancel: onTapCancel,
              child: const SizedBox(
                  height: _ClassicBottomNavigationState._barHeight),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavigationLabel extends StatelessWidget {
  const _NavigationLabel(
      {required this.label, required this.icon, required this.color});
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppNavigationIcon(icon: icon, color: color),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium!
                      .copyWith(letterSpacing: 0, color: color)),
            ),
          ),
        ],
      );
}
