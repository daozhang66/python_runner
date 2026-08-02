import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/app_logger.dart';
import '../l10n/app_localizations.dart';

class AppLogsPage extends StatefulWidget {
  const AppLogsPage({super.key});

  @override
  State<AppLogsPage> createState() => _AppLogsPageState();
}

class _AppLogsPageState extends State<AppLogsPage> {
  final _searchController = TextEditingController();
  final _logger = AppLogger.instance;

  // 筛选状态
  Set<AppLogLevel> _selectedLevels = AppLogLevel.values.toSet();
  String? _selectedSource;
  DateRangeFilter _dateRange = DateRangeFilter.all;
  bool _filterExpanded = false;
  List<AppLogEntry> _filteredLogs = const [];
  Map<String, dynamic> _statistics = const {};
  List<String> _sources = const [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _refreshLogSnapshot();
  }

  void _onSearchChanged() {
    setState(_refreshLogSnapshot);
  }

  void _refreshLogSnapshot() {
    DateTime? startDate;
    DateTime? endDate = DateTime.now();

    switch (_dateRange) {
      case DateRangeFilter.today:
        startDate = DateTime(endDate.year, endDate.month, endDate.day);
        break;
      case DateRangeFilter.last7Days:
        startDate = endDate.subtract(const Duration(days: 7));
        break;
      case DateRangeFilter.all:
        startDate = null;
        endDate = null;
        break;
    }

    _filteredLogs = List<AppLogEntry>.unmodifiable(
      _logger.filterLogs(
        levels: _selectedLevels,
        source: _selectedSource,
        startDate: startDate,
        endDate: endDate,
        searchQuery: _searchController.text.trim(),
      ),
    );
    _statistics = Map<String, dynamic>.unmodifiable(_logger.getStatistics());
    _sources =
        List<String>.unmodifiable(_logger.getAllSources().toList()..sort());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final logs = _filteredLogs;
    final stats = _statistics;
    final sources = _sources;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appLogs),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.refresh,
            onPressed: () => setState(_refreshLogSnapshot),
          ),
          PopupMenuButton(
            icon: const Icon(Icons.more_vert),
            itemBuilder: (context) => [
              PopupMenuItem(
                child: Row(
                  children: [
                    Icon(Icons.file_download_outlined, size: 20),
                    SizedBox(width: 12),
                    Text(l10n.exportLogs),
                  ],
                ),
                onTap: () => _exportLogs(),
              ),
              PopupMenuItem(
                child: Row(
                  children: [
                    Icon(Icons.delete_outline,
                        size: 20, color: Theme.of(context).colorScheme.error),
                    const SizedBox(width: 12),
                    Text(l10n.clearLogs,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                ),
                onTap: () => _clearLogs(),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索框
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _searchController.clear,
                      ),
                    IconButton(
                      icon: Icon(_filterExpanded
                          ? Icons.filter_list
                          : Icons.filter_list_outlined),
                      onPressed: () =>
                          setState(() => _filterExpanded = !_filterExpanded),
                      tooltip: l10n.filter,
                    ),
                  ],
                ),
                hintText: l10n.searchLogContent,
                isDense: true,
              ),
            ),
          ),

          // 筛选器
          if (_filterExpanded)
            _FilterBar(
              selectedLevels: _selectedLevels,
              selectedSource: _selectedSource,
              dateRange: _dateRange,
              sources: sources,
              onLevelsChanged: (levels) => setState(() {
                _selectedLevels = levels;
                _refreshLogSnapshot();
              }),
              onSourceChanged: (source) => setState(() {
                _selectedSource = source;
                _refreshLogSnapshot();
              }),
              onDateRangeChanged: (range) => setState(() {
                _dateRange = range;
                _refreshLogSnapshot();
              }),
            ),

          // 统计信息
          _StatisticsBar(
            total: logs.length,
            infoCount: stats['info'] as int,
            warnCount: stats['warn'] as int,
            errorCount: stats['error'] as int,
          ),

          // 日志列表
          Expanded(
            child: logs.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final entry = logs[logs.length - 1 - index];
                      return _LogCard(
                        entry: entry,
                        onCopy: () => _copyLog(entry),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.article_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            _searchController.text.isEmpty
                ? AppLocalizations.of(context)!.noLogs
                : AppLocalizations.of(context)!.noMatchingLogs,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  Future<void> _copyLog(AppLogEntry entry) async {
    await Clipboard.setData(ClipboardData(text: entry.formatted));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.copied),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _exportLogs() async {
    final content = _logger.exportFilteredLogs(
      levels: _selectedLevels,
      source: _selectedSource,
    );
    await Clipboard.setData(ClipboardData(text: content));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.logsCopied),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx)!.clearLogs),
        content: Text(AppLocalizations.of(ctx)!.clearLogsConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(ctx)!.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(ctx)!.clear),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _logger.clearAll();
      if (mounted) setState(_refreshLogSnapshot);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.logsCleared)),
      );
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════
// 筛选栏
// ═══════════════════════════════════════════════════════════════

class _FilterBar extends StatelessWidget {
  final Set<AppLogLevel> selectedLevels;
  final String? selectedSource;
  final DateRangeFilter dateRange;
  final List<String> sources;
  final ValueChanged<Set<AppLogLevel>> onLevelsChanged;
  final ValueChanged<String?> onSourceChanged;
  final ValueChanged<DateRangeFilter> onDateRangeChanged;

  const _FilterBar({
    required this.selectedLevels,
    required this.selectedSource,
    required this.dateRange,
    required this.sources,
    required this.onLevelsChanged,
    required this.onSourceChanged,
    required this.onDateRangeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 级别筛选
          Text(AppLocalizations.of(context)!.level,
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: AppLogLevel.values.map((level) {
              final isSelected = selectedLevels.contains(level);
              return FilterChip(
                label: Text(level.name.toUpperCase()),
                selected: isSelected,
                onSelected: (selected) {
                  final newLevels = Set<AppLogLevel>.from(selectedLevels);
                  if (selected) {
                    newLevels.add(level);
                  } else {
                    newLevels.remove(level);
                  }
                  if (newLevels.isNotEmpty) {
                    onLevelsChanged(newLevels);
                  }
                },
                avatar: _buildLevelIcon(level, isSelected),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          // 来源筛选
          Text(AppLocalizations.of(context)!.source,
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: Text(AppLocalizations.of(context)!.all),
                selected: selectedSource == null,
                onSelected: (selected) => onSourceChanged(null),
              ),
              ...sources.map((source) {
                return FilterChip(
                  label: Text(source),
                  selected: selectedSource == source,
                  onSelected: (selected) =>
                      onSourceChanged(selected ? source : null),
                );
              }),
            ],
          ),
          const SizedBox(height: 12),

          // 时间范围
          Text(AppLocalizations.of(context)!.time,
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: DateRangeFilter.values.map((range) {
              return ChoiceChip(
                label: Text(_dateRangeLabel(context, range)),
                selected: dateRange == range,
                onSelected: (selected) => onDateRangeChanged(range),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelIcon(AppLogLevel level, bool isSelected) {
    IconData icon;
    Color color;

    switch (level) {
      case AppLogLevel.info:
        icon = Icons.info_outline;
        color = Colors.green;
        break;
      case AppLogLevel.warn:
        icon = Icons.warning_amber_outlined;
        color = Colors.orange;
        break;
      case AppLogLevel.error:
        icon = Icons.error_outline;
        color = Colors.red;
        break;
    }

    return Icon(icon, size: 16, color: isSelected ? color : null);
  }

  String _dateRangeLabel(BuildContext context, DateRangeFilter range) {
    final l10n = AppLocalizations.of(context)!;
    switch (range) {
      case DateRangeFilter.today:
        return l10n.today;
      case DateRangeFilter.last7Days:
        return l10n.lastSevenDays;
      case DateRangeFilter.all:
        return l10n.all;
    }
  }
}

enum DateRangeFilter { today, last7Days, all }

// ═══════════════════════════════════════════════════════════════
// 统计栏
// ═══════════════════════════════════════════════════════════════

class _StatisticsBar extends StatelessWidget {
  final int total;
  final int infoCount;
  final int warnCount;
  final int errorCount;

  const _StatisticsBar({
    required this.total,
    required this.infoCount,
    required this.warnCount,
    required this.errorCount,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.primaryContainer.withValues(alpha: 0.3),
            colors.secondaryContainer.withValues(alpha: 0.2),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(
            label: AppLocalizations.of(context)!.total,
            value: total,
            color: colors.primary,
          ),
          _StatItem(label: 'INFO', value: infoCount, color: Colors.green),
          _StatItem(label: 'WARN', value: warnCount, color: Colors.orange),
          _StatItem(label: 'ERROR', value: errorCount, color: Colors.red),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _StatItem({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 日志卡片
// ═══════════════════════════════════════════════════════════════

class _LogCard extends StatelessWidget {
  final AppLogEntry entry;
  final VoidCallback onCopy;

  const _LogCard({
    required this.entry,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final levelColor = _getLevelColor();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: levelColor.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: levelColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(_getLevelIcon(), size: 20, color: levelColor),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: levelColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                entry.level.name.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: levelColor,
                ),
              ),
            ),
            if (entry.source != null) ...[
              const SizedBox(width: 8),
              Text(
                entry.source!,
                style: TextStyle(
                  fontSize: 11,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
            const Spacer(),
            Text(
              _formatTime(context, entry.timestamp),
              style: TextStyle(
                fontSize: 11,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            entry.message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              entry.detail != null
                  ? '${entry.message}\n\n${entry.detail}'
                  : entry.message,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy, size: 16),
                label: Text(AppLocalizations.of(context)!.copy),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getLevelColor() {
    switch (entry.level) {
      case AppLogLevel.info:
        return Colors.green;
      case AppLogLevel.warn:
        return Colors.orange;
      case AppLogLevel.error:
        return Colors.red;
    }
  }

  IconData _getLevelIcon() {
    switch (entry.level) {
      case AppLogLevel.info:
        return Icons.info_outline;
      case AppLogLevel.warn:
        return Icons.warning_amber_outlined;
      case AppLogLevel.error:
        return Icons.error_outline;
    }
  }

  String _formatTime(BuildContext context, DateTime timestamp) {
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inSeconds < 60) {
      return l10n.justNow;
    } else if (diff.inMinutes < 60) {
      return l10n.minutesAgo(diff.inMinutes);
    } else if (diff.inHours < 24) {
      return l10n.hoursAgo(diff.inHours);
    } else {
      return DateFormat('MM-dd HH:mm').format(timestamp);
    }
  }
}
