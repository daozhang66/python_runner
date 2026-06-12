part of 'script_list_page.dart';

class _ScriptFolderCard extends StatelessWidget {
  final String name;
  final bool masked;
  final int count;
  final bool isProject;
  final bool hasMainFile;
  final bool grid;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _ScriptFolderCard({
    super.key,
    required this.name,
    required this.masked,
    required this.count,
    this.isProject = false,
    this.hasMainFile = false,
    required this.grid,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final icon = isProject ? Icons.account_tree_rounded : Icons.folder_rounded;
    final subtitle = isProject
        ? (hasMainFile ? '项目 · 已设置主程序' : '项目 · 未设置主程序')
        : '$count 个脚本';
    final content = InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: EdgeInsets.all(grid ? 12 : 14),
        child: grid
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    icon,
                    size: 42,
                    color: AppThemeColors.softIconColor(context, colors),
                  ),
                  const Spacer(),
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: masked
                          ? AppThemeColors.maskedText(context)
                          : colors.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style:
                        TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                  ),
                ],
              )
            : Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppThemeColors.isDark(context)
                          ? colors.surfaceContainerHigh
                          : colors.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      icon,
                      color: AppThemeColors.isDark(context)
                          ? AppThemeColors.softIconColor(context, colors)
                          : colors.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: masked
                                ? AppThemeColors.maskedText(context)
                                : colors.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: colors.onSurfaceVariant),
                ],
              ),
      ),
    );

    return _ScriptCardSurface(
      colors: colors,
      selected: false,
      pinned: false,
      margin: grid
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: content,
    );
  }
}

class _ScriptGridCard extends StatelessWidget {
  final String name;
  final bool masked;
  final DateTime modifiedAt;
  final int runCount;
  final DateFormat dateFormat;
  final bool pinned;
  final bool? selected;
  final Widget? dragHandle;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onRun;

  const _ScriptGridCard({
    super.key,
    required this.name,
    required this.masked,
    required this.modifiedAt,
    required this.runCount,
    required this.dateFormat,
    required this.pinned,
    this.selected,
    this.dragHandle,
    required this.onTap,
    required this.onLongPress,
    this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final displayName = name.replaceAll('.py', '');
    final runLabel = runCount > 0 ? '运行 $runCount 次' : '未运行';

    return _ScriptCardSurface(
      colors: colors,
      selected: selected == true,
      pinned: pinned,
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _ScriptIcon(colors: colors, size: 36, fontSize: 13),
                      const Spacer(),
                      if (pinned && selected == null)
                        _PinnedBadge(colors: colors),
                      if (pinned && selected == null) const SizedBox(width: 6),
                      if (selected != null)
                        Icon(
                            selected!
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked,
                            size: 22,
                            color: selected! ? colors.primary : colors.outline)
                      else if (onRun != null)
                        _QuickRunButton(onPressed: onRun!),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(displayName,
                      style: TextStyle(
                          fontSize: 14,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: masked
                              ? AppThemeColors.maskedText(context)
                              : colors.onSurface),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const Spacer(),
                  Row(
                    children: [
                      Flexible(
                        child: _ScriptMetaChip(
                          colors: colors,
                          icon: Icons.history_rounded,
                          label: dateFormat.format(modifiedAt),
                          compact: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(runLabel,
                      style: TextStyle(fontSize: 11, color: colors.primary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (dragHandle != null)
              Positioned(
                right: 8,
                bottom: 20,
                child: dragHandle!,
              ),
          ],
        ),
      ),
    );
  }
}

class _GridDragHandle extends StatelessWidget {
  final Color color;

  const _GridDragHandle({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 28,
      child: Center(
        child: Icon(Icons.drag_indicator, size: 18, color: color),
      ),
    );
  }
}

class _ScriptGridPlaceholder extends StatelessWidget {
  final ColorScheme colors;

  const _ScriptGridPlaceholder({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.primary.withValues(alpha: 0.32),
          width: 1.2,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.open_with_rounded,
        size: 24,
        color: colors.primary.withValues(alpha: 0.55),
      ),
    );
  }
}

class _ScriptCardSurface extends StatelessWidget {
  final ColorScheme colors;
  final bool selected;
  final bool pinned;
  final EdgeInsetsGeometry margin;
  final Widget child;

  const _ScriptCardSurface({
    super.key,
    required this.colors,
    required this.selected,
    required this.pinned,
    required this.margin,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: AppThemeColors.scriptSurface(
          context,
          colors,
          selected: selected,
          pinned: pinned,
        ),
        borderRadius: radius,
        border: Border.all(
          color: AppThemeColors.scriptBorder(
            context,
            colors,
            selected: selected,
            pinned: pinned,
          ),
          width: AppThemeColors.isDark(context) ? 0.8 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: child,
      ),
    );
  }
}

class _ScriptIcon extends StatelessWidget {
  final ColorScheme colors;
  final double size;
  final double fontSize;

  const _ScriptIcon({
    required this.colors,
    required this.size,
    this.fontSize = 15,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppThemeColors.isDark(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? colors.surfaceContainerHigh : colors.primaryContainer,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      alignment: Alignment.center,
      child: Text(
        'Py',
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: isDark
              ? colors.primary.withValues(alpha: 0.88)
              : colors.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _ScriptMetaChip extends StatelessWidget {
  final ColorScheme colors;
  final IconData icon;
  final String label;
  final bool compact;

  const _ScriptMetaChip({
    required this.colors,
    required this.icon,
    required this.label,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: compact ? 11 : 12, color: colors.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: compact ? 10.5 : 11,
            color: colors.onSurfaceVariant,
            height: 1,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _PinnedBadge extends StatelessWidget {
  final ColorScheme colors;

  const _PinnedBadge({required this.colors});

  @override
  Widget build(BuildContext context) {
    final isDark = AppThemeColors.isDark(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: isDark ? 0.16 : 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.push_pin,
            size: 10,
            color: colors.primary.withValues(alpha: isDark ? 0.86 : 1),
          ),
          const SizedBox(width: 2),
          Text(
            '置顶',
            style: TextStyle(
              fontSize: 10,
              height: 1,
              fontWeight: FontWeight.w700,
              color: colors.primary.withValues(alpha: isDark ? 0.86 : 1),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickRunButton extends StatefulWidget {
  final VoidCallback onPressed;

  const _QuickRunButton({required this.onPressed});

  @override
  State<_QuickRunButton> createState() => _QuickRunButtonState();
}

class _QuickRunButtonState extends State<_QuickRunButton>
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
    _scale = Tween<double>(begin: 1.0, end: 0.88).animate(
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
    final isDark = AppThemeColors.isDark(context);
    return ScaleTransition(
      scale: _scale,
      child: Tooltip(
        message: '运行',
        child: SizedBox.square(
          dimension: 34,
          child: Material(
            color: isDark
                ? AppThemeColors.darkSurfaceHigh
                : colors.primaryContainer,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTapDown: (_) => _controller.forward(),
              onTapCancel: () => _controller.reverse(),
              onTap: () {
                _controller.reverse();
                widget.onPressed();
              },
              child: Icon(
                Icons.play_arrow_rounded,
                size: 20,
                color: isDark
                    ? colors.primary.withValues(alpha: 0.9)
                    : colors.onPrimaryContainer,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
