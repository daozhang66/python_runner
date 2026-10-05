import 'package:flutter/material.dart';

import 'app_materials.dart';
import 'app_glass_feedback.dart';

/// Press feedback is visual only; scrolling and the child's gestures keep ownership.
class AppGlassPress extends StatefulWidget {
  const AppGlassPress({
    super.key,
    required this.child,
    this.enabled = true,
    this.scaleOnPress = true,
    this.clipShape,
    this.feedbackInsideSurface = false,
  });
  final Widget child;
  final bool enabled;
  final bool scaleOnPress;
  final ShapeBorder? clipShape;
  final bool feedbackInsideSurface;
  @override
  State<AppGlassPress> createState() => _AppGlassPressState();
}

class _AppGlassPressState extends State<AppGlassPress>
    with SingleTickerProviderStateMixin {
  Offset? _down;
  Offset _waveOrigin = Offset.zero;
  bool _pressed = false;
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  void _release() {
    _down = null;
    if (_pressed && mounted) {
      setState(() => _pressed = false);
      // The front collapses back toward the touch instead of freezing mid
      // surface. Reverse from wherever it is so fast taps still feel elastic.
      _wave.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled =
        widget.enabled &&
        AppMaterials.of(context).liquid &&
        !MediaQuery.disableAnimationsOf(context);
    return Listener(
      onPointerDown: (event) {
        if (!enabled || _down != null) return;
        _down = event.localPosition;
        _waveOrigin = event.localPosition;
        setState(() => _pressed = true);
        _wave.forward(from: 0);
      },
      onPointerMove: (event) {
        if (_down != null && (event.localPosition - _down!).distance > 8) {
          _release();
        }
      },
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: AnimatedScale(
        scale: enabled && widget.scaleOnPress && _pressed ? 0.985 : 1,
        duration: enabled ? const Duration(milliseconds: 110) : Duration.zero,
        curve: Curves.easeOutCubic,
        child: AppGlassFeedbackScope(
          animation: _wave,
          point: _waveOrigin,
          enabled: enabled,
          shape: widget.clipShape,
          child: widget.feedbackInsideSurface
              ? widget.child
              : AppGlassFeedbackLayer(child: widget.child),
        ),
      ),
    );
  }
}
