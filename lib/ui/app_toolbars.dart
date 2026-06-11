import 'package:flutter/material.dart';
import 'app_design_tokens.dart';

/// 统一搜索栏组件。
///
/// 用于脚本搜索、网络搜索、终端搜索、库搜索等。
class AppSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;
  final bool autofocus;
  final List<Widget> trailingActions;

  const AppSearchBar({
    super.key,
    required this.controller,
    this.hintText = '搜索...',
    required this.onChanged,
    this.onClear,
    this.autofocus = false,
    this.trailingActions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldFill =
        isDark ? colors.surfaceContainer : AppThemeColors.softSurface(colors);
    final fieldBorder =
        isDark ? colors.outline : colors.outlineVariant.withValues(alpha: 0.48);
    final hintColor = isDark
        ? colors.onSurfaceVariant.withValues(alpha: 0.68)
        : colors.onSurfaceVariant.withValues(alpha: 0.82);
    final iconColor = isDark
        ? colors.onSurfaceVariant.withValues(alpha: 0.9)
        : colors.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: fieldFill,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: fieldBorder),
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                          color: colors.shadow.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Row(
                children: [
                  Icon(Icons.search, size: 18, color: iconColor),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      autofocus: autofocus,
                      enableSuggestions: false,
                      autocorrect: false,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: hintText,
                        hintStyle: TextStyle(color: hintColor),
                        border: InputBorder.none,
                        filled: false,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 0,
                          vertical: AppSpacing.sm - 2,
                        ),
                      ),
                      onChanged: onChanged,
                    ),
                  ),
                  if (controller.text.isNotEmpty && onClear != null)
                    IconButton(
                      icon: Icon(Icons.close, size: 16, color: iconColor),
                      onPressed: onClear,
                      visualDensity: VisualDensity.compact,
                      tooltip: '清空',
                    ),
                ],
              ),
            ),
          ),
          if (trailingActions.isNotEmpty) const SizedBox(width: AppSpacing.sm),
          ...trailingActions,
        ],
      ),
    );
  }
}

/// 统一工具栏按钮。
///
/// 用于编辑器、终端、网络详情页工具栏。
class AppToolbarButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool active;
  final double iconSize;

  const AppToolbarButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.active = false,
    this.iconSize = 18,
  });

  @override
  State<AppToolbarButton> createState() => _AppToolbarButtonState();
}

class _AppToolbarButtonState extends State<AppToolbarButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.90).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Listener(
      onPointerDown: (_) {
        if (widget.onPressed != null) _controller.forward();
      },
      onPointerUp: (_) {
        if (widget.onPressed != null) _controller.reverse();
      },
      onPointerCancel: (_) {
        if (widget.onPressed != null) _controller.reverse();
      },
      child: ScaleTransition(
        scale: _scale,
        child: IconButton(
          icon: Icon(widget.icon, size: widget.iconSize),
          color: widget.active ? colors.primary : colors.onSurfaceVariant,
          onPressed: widget.onPressed,
          visualDensity: VisualDensity.compact,
          tooltip: widget.tooltip,
        ),
      ),
    );
  }
}
