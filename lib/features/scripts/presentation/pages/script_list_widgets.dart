part of 'script_list_page.dart';

// Script workspace widgets stay in the presentation library for focused ownership.

/// 仅监听指定脚本的数据变化，避免修改时间或运行次数变化触发整个 Sliver 重建。
class _ScriptDataScope extends ConsumerWidget {
  const _ScriptDataScope({
    required this.scriptName,
    required this.builder,
  });

  final String scriptName;
  final Widget Function(BuildContext context, ScriptFile script) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final script = ref.watch(
      scriptWorkspaceControllerProvider.select(
        (state) => state.scriptByName(scriptName),
      ),
    );
    if (script == null) return const SizedBox.shrink();
    return builder(context, script);
  }
}

class _ScriptFolderCard extends StatelessWidget {
  final String name;
  final bool masked;
  final int count;
  final bool isProject;
  final bool hasMainFile;
  final bool grid;
  final bool? selected;
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
    this.selected,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final icon = isProject ? Icons.account_tree_rounded : Icons.folder_rounded;
    final l10n = AppLocalizations.of(context)!;
    final subtitle = isProject
        ? (hasMainFile
            ? l10n.projectMainProgramSet
            : l10n.projectMainProgramNotSet)
        : l10n.scriptsCount(count);
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
                  Row(
                    children: [
                      Icon(
                        icon,
                        size: 42,
                        color: AppThemeColors.softIconColor(context, colors),
                      ),
                      const Spacer(),
                      if (selected != null)
                        Icon(
                          selected!
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked,
                          size: 22,
                          color: selected! ? colors.primary : colors.outline,
                        ),
                    ],
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
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: AppThemeColors.isDark(context)
                          ? LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                colors.primaryContainer.withValues(alpha: 0.2),
                                colors.primaryContainer.withValues(alpha: 0.1),
                              ],
                            )
                          : LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                colors.primaryContainer,
                                colors.primaryContainer.withValues(alpha: 0.7),
                              ],
                            ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: colors.primary.withValues(alpha: 0.08),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      icon,
                      size: 26,
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
                  if (selected != null)
                    Icon(
                      selected!
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked,
                      size: 24,
                      color: selected! ? colors.primary : colors.outline,
                    )
                  else
                    Icon(Icons.chevron_right_rounded,
                        color: colors.onSurfaceVariant),
                ],
              ),
      ),
    );

    return _ScriptCardSurface(
      colors: colors,
      selected: selected == true,
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
    final l10n = AppLocalizations.of(context)!;
    final runLabel = runCount > 0 ? l10n.runsCount(runCount) : l10n.notRun;

    return _ScriptCardSurface(
      colors: colors,
      selected: selected == true,
      pinned: pinned,
      margin: EdgeInsets.zero,
      child: Semantics(
        button: true,
        label: l10n.scriptSemanticLabel(displayName),
        hint: onRun == null ? l10n.openScript : l10n.openAndRunScript,
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
                        _ScriptIcon(
                            colors: colors,
                            size: 36,
                            fontSize: 13,
                            pinned: pinned),
                        const Spacer(),
                        if (pinned && selected == null)
                          _PinnedBadge(colors: colors),
                        if (pinned && selected == null)
                          const SizedBox(width: 6),
                        if (selected != null)
                          Icon(
                              selected!
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked,
                              size: 22,
                              color:
                                  selected! ? colors.primary : colors.outline)
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

class _ScriptDetailsPanel extends StatelessWidget {
  const _ScriptDetailsPanel({
    required this.script,
    required this.groupName,
    required this.dateFormat,
    required this.onEdit,
    required this.onRun,
    required this.onOpenConsole,
    required this.onTogglePinned,
    required this.localizations,
  });

  final dynamic script;
  final String groupName;
  final DateFormat dateFormat;
  final VoidCallback onEdit;
  final VoidCallback onRun;
  final VoidCallback onOpenConsole;
  final VoidCallback onTogglePinned;
  final AppLocalizations localizations;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final displayName = script.name.toString().replaceAll('.py', '');

    return legacy_provider.Selector<ExecutionProvider, bool>(
      selector: (_, provider) =>
          provider.isRunning && provider.currentScriptName == script.name,
      builder: (context, isRunning, _) {
        return SafeArea(
          child: Semantics(
            container: true,
            label: localizations.scriptDetails,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              children: [
                AppSectionHeader(
                  title: localizations.scriptDetails,
                  icon: Icons.description_outlined,
                  trailing: AppStatusBadge(
                    label:
                        isRunning ? localizations.running : localizations.idle,
                    tone:
                        isRunning ? AppBadgeTone.success : AppBadgeTone.neutral,
                    icon: isRunning
                        ? Icons.play_circle_outline
                        : Icons.circle_outlined,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  script.name.toString(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontFamily: 'monospace',
                    fontFamilyFallback: const ['MiSans'],
                  ),
                ),
                const SizedBox(height: 24),
                AppSurface(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _ScriptDetailRow(
                        icon: Icons.folder_outlined,
                        label: localizations.scriptGroup,
                        value: groupName,
                      ),
                      _ScriptDetailRow(
                        icon: Icons.calendar_today_outlined,
                        label: localizations.createdAt,
                        value: dateFormat.format(script.createdAt as DateTime),
                      ),
                      _ScriptDetailRow(
                        icon: Icons.schedule_outlined,
                        label: localizations.lastModified,
                        value: dateFormat.format(script.modifiedAt as DateTime),
                      ),
                      _ScriptDetailRow(
                        icon: Icons.play_circle_outline,
                        label: localizations.runCount,
                        value: '${script.runCount}',
                      ),
                      _ScriptDetailRow(
                        icon: script.isPinned
                            ? Icons.push_pin_rounded
                            : Icons.push_pin_outlined,
                        label: localizations.scriptStatus,
                        value: script.isPinned
                            ? localizations.pinned
                            : localizations.regularScript,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(localizations.edit),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(44, 44),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: onRun,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(localizations.run),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(44, 44),
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: localizations.openConsole,
                      child: IconButton.filledTonal(
                        constraints:
                            const BoxConstraints(minWidth: 44, minHeight: 44),
                        onPressed: onOpenConsole,
                        tooltip: localizations.openConsole,
                        icon: const Icon(Icons.terminal_rounded),
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: script.isPinned
                          ? localizations.unpin
                          : localizations.pin,
                      child: IconButton.filledTonal(
                        constraints:
                            const BoxConstraints(minWidth: 44, minHeight: 44),
                        onPressed: onTogglePinned,
                        tooltip: script.isPinned
                            ? localizations.unpin
                            : localizations.pin,
                        icon: Icon(
                          script.isPinned
                              ? Icons.push_pin_rounded
                              : Icons.push_pin_outlined,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ScriptDetailRow extends StatelessWidget {
  const _ScriptDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, size: 20, color: colors.onSurfaceVariant),
      title: Text(label),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
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
    return RepaintBoundary(
      child: Container(
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
          boxShadow: [
            if (!AppThemeColors.isDark(context))
              BoxShadow(
                color: colors.shadow.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: child,
        ),
      ),
    );
  }
}

class _ScriptIcon extends StatelessWidget {
  final ColorScheme colors;
  final double size;
  final double fontSize;
  final bool pinned;

  const _ScriptIcon({
    required this.colors,
    required this.size,
    this.fontSize = 15,
    this.pinned = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppThemeColors.isDark(context);

    // 置顶状态使用更高对比度的颜色
    final gradient = pinned
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    colors.primary.withValues(alpha: 0.25),
                    colors.primary.withValues(alpha: 0.15),
                  ]
                : [
                    colors.primary.withValues(alpha: 0.18),
                    colors.primary.withValues(alpha: 0.12),
                  ],
          )
        : (isDark
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colors.surfaceContainerHigh,
                  colors.surfaceContainer,
                ],
              )
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colors.primaryContainer,
                  colors.primaryContainer.withValues(alpha: 0.8),
                ],
              ));

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: isDark ? 0.05 : 0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        'Py',
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: pinned
              ? colors.primary.withValues(alpha: 0.95)
              : (isDark
                  ? colors.primary.withValues(alpha: 0.88)
                  : colors.onPrimaryContainer),
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
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: compact
            ? AppControlMetrics.compactMetaMaxWidth
            : AppControlMetrics.regularMetaMaxWidth,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: compact
                ? AppControlMetrics.compactMetaIcon
                : AppControlMetrics.regularMetaIcon,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize:
                    compact ? AppTextSize.compactEmphasis : AppTextSize.label,
                color: colors.onSurfaceVariant,
                height: 1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
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
            AppLocalizations.of(context)!.pinned,
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
        message: AppLocalizations.of(context)!.run,
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
