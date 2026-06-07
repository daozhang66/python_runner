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

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color:
            isDark ? const Color(0xFF161B22) : colors.surfaceContainerHighest,
      ),
      child: Row(
        children: [
          Icon(Icons.search,
              size: 18, color: isDark ? Colors.white38 : Colors.grey),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: autofocus,
              enableSuggestions: false,
              autocorrect: false,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle:
                    TextStyle(color: isDark ? Colors.white30 : Colors.grey),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm - 4, vertical: AppSpacing.sm - 2),
              ),
              onChanged: onChanged,
            ),
          ),
          if (controller.text.isNotEmpty && onClear != null)
            IconButton(
              icon: Icon(Icons.close, size: 16, color: colors.onSurfaceVariant),
              onPressed: onClear,
              visualDensity: VisualDensity.compact,
              tooltip: '清空',
            ),
          ...trailingActions,
        ],
      ),
    );
  }
}

/// 统一工具栏按钮。
///
/// 用于编辑器、终端、网络详情页工具栏。
class AppToolbarButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return IconButton(
      icon: Icon(icon, size: iconSize),
      color: active ? colors.primary : colors.onSurfaceVariant,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      tooltip: tooltip,
    );
  }
}
