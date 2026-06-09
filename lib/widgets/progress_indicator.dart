import 'package:flutter/material.dart';

class ProgressIndicatorWidget extends StatefulWidget {
  final String label;
  final List<String> logs;

  const ProgressIndicatorWidget({
    super.key,
    required this.label,
    this.logs = const [],
  });

  @override
  State<ProgressIndicatorWidget> createState() =>
      _ProgressIndicatorWidgetState();
}

class _ProgressIndicatorWidgetState extends State<ProgressIndicatorWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            // Gorgeous custom gradient spinner
            RotationTransition(
              turns: _rotationController,
              child: SizedBox(
                width: 20,
                height: 20,
                child: CustomPaint(
                  painter: _GradientSpinnerPainter(
                    color: colors.primary,
                    trackColor: colors.primary.withValues(alpha: 0.1),
                    strokeWidth: 2.5,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
              ),
            ),
          ],
        ),
        if (widget.logs.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 120),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0D1117) : const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.15),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: isDark
                      ? const Color(0xFF161B22)
                      : const Color(0xFF2D2D2D),
                  child: Row(
                    children: [
                      _buildDot(const Color(0xFFFF5F56)),
                      const SizedBox(width: 6),
                      _buildDot(const Color(0xFFFFBD2E)),
                      const SizedBox(width: 6),
                      _buildDot(const Color(0xFF27C93F)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'CONSOLE OUTPUT',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white54 : Colors.white60,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    shrinkWrap: true,
                    itemCount: widget.logs.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Text(
                          widget.logs[index],
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: Color(0xFF39FF14),
                            height: 1.3,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDot(Color color) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _GradientSpinnerPainter extends CustomPainter {
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  _GradientSpinnerPainter({
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Draw background track ring
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawOval(rect, trackPaint);

    // Draw swept gradient arc
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          color.withValues(alpha: 0.0),
          color,
        ],
        stops: const [0.0, 1.0],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;

    // Draw active arc of 270 degrees
    canvas.drawArc(rect, 0, 4.71, false, sweepPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
