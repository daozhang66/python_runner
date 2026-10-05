import 'package:flutter/material.dart';
import 'app_card.dart';

/// A quiet section without changing the order or behavior of its controls.
class AppSettingsSection extends StatelessWidget {
  const AppSettingsSection({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    this.contentPadding = EdgeInsets.zero,
    this.framed = false,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;
  final EdgeInsetsGeometry contentPadding;

  /// Settings can retain card grouping without changing other detail screens.
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final content = ListTileTheme.merge(
      titleTextStyle: theme.textTheme.bodyMedium,
      subtitleTextStyle: theme.textTheme.bodySmall?.copyWith(
        color: colors.onSurfaceVariant,
      ),
      iconColor: colors.onSurfaceVariant,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Semantics(
              header: true,
              child: Row(
                children: [
                  Icon(icon, size: 20, color: colors.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: contentPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
          if (!framed)
            Divider(
              height: 16,
              indent: 16,
              endIndent: 16,
              color: colors.outlineVariant.withValues(alpha: 0.4),
            ),
        ],
      ),
    );
    const margin = EdgeInsets.symmetric(horizontal: 12, vertical: 6);
    return framed
        ? AppCard(
            margin: margin,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: content,
            ),
          )
        : Padding(padding: margin, child: content);
  }
}
