part of 'network_inspector_page.dart';

class _HttpRecordTile extends StatelessWidget {
  final HttpRecord record;
  final VoidCallback onTap;

  const _HttpRecordTile({required this.record, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final timeFmt = DateFormat('HH:mm:ss.SSS');

    // Extract domain from URL
    String domain;
    try {
      final uri = Uri.parse(record.url);
      domain = uri.host;
    } catch (_) {
      domain = record.url;
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          children: [
            _buildStatusBadge(context),
            const SizedBox(width: 3),
            _buildMethodBadge(context),
            const SizedBox(width: 8),
            // URL + meta
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    domain,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    record.url,
                    style:
                        TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            // Duration + time
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  record.durationText,
                  style:
                      TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
                ),
                Text(
                  timeFmt.format(record.timestamp),
                  style: TextStyle(
                      fontSize: 9,
                      color: colors.onSurfaceVariant.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMethodBadge(BuildContext context) {
    return AppStatusBadge(
      label: record.method,
      tone: AppBadgeTone.info,
      fontSize: 8.5,
    );
  }

  Widget _buildStatusBadge(BuildContext context) {
    final tone = record.errorType != null
        ? AppBadgeTone.error
        : record.statusCode == null
            ? AppBadgeTone.neutral
            : record.statusCode! >= 200 && record.statusCode! < 300
                ? AppBadgeTone.success
                : record.statusCode! >= 300 && record.statusCode! < 400
                    ? AppBadgeTone.warning
                    : AppBadgeTone.error;
    return AppStatusBadge(
      label: record.statusText,
      tone: tone,
      fontSize: 8.5,
    );
  }
}

// --- Filter chip ---
class _FilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _FilterChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Chip(
        label: Text(label, style: const TextStyle(fontSize: 10)),
        deleteIcon: const Icon(Icons.close, size: 14),
        onDeleted: onRemove,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.zero,
        labelPadding: const EdgeInsets.only(left: 6),
      ),
    );
  }
}

// --- Stat badge ---
class _StatBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _StatBadge(
      {required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w500, color: color)),
      ],
    );
  }
}

// --- Detail page ---
