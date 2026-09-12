import 'package:flutter/material.dart';

import '../../../../models/app_file_entry.dart';

/// A single directory or file row in the file manager list.
///
/// Directory rows navigate on tap; file rows open a preview. Mutable rows
/// expose rename and delete actions through [menuBuilder].
class FileManagerEntryTile extends StatelessWidget {
  final AppFileEntry entry;
  final VoidCallback? onOpen;
  final VoidCallback? onPreview;
  final bool canMutate;
  final List<PopupMenuEntry<String>> Function(BuildContext context)?
      menuBuilder;
  final void Function(String action)? onMenuSelected;

  const FileManagerEntryTile({
    super.key,
    required this.entry,
    this.onOpen,
    this.onPreview,
    this.canMutate = false,
    this.menuBuilder,
    this.onMenuSelected,
  });

  String _formatSize(int size) {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        entry.isDirectory ? Icons.folder_outlined : Icons.description_outlined,
        color: entry.isDirectory ? colors.primary : colors.onSurfaceVariant,
      ),
      title: Text(
        entry.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        entry.isDirectory
            ? entry.path
            : '${_formatSize(entry.size)} · ${entry.path}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canMutate && menuBuilder != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              itemBuilder: menuBuilder!,
              onSelected: onMenuSelected,
            )
          else if (entry.isDirectory)
            const Icon(Icons.chevron_right),
        ],
      ),
      onTap: entry.isDirectory ? onOpen : onPreview,
    );
  }
}
