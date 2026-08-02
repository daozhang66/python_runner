import 'dart:async';
import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:re_editor/re_editor.dart';
import '../services/http_inspector_store.dart';
import '../services/native_bridge.dart';
import '../l10n/app_localizations.dart';
import '../ui/app_badges.dart';
import '../ui/app_design_tokens.dart';
import '../ui/app_empty_state.dart';
import '../ui/app_surfaces.dart';
import '../ui/app_toolbars.dart';

part 'network_inspector_detail.dart';
part 'network_inspector_widgets.dart';

class NetworkInspectorPage extends StatefulWidget {
  const NetworkInspectorPage({super.key});

  @override
  State<NetworkInspectorPage> createState() => _NetworkInspectorPageState();
}

class _NetworkInspectorPageState extends State<NetworkInspectorPage> {
  final _searchController = TextEditingController();
  HttpInspectorStore _store = HttpInspectorStore.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_store.loadDisplayPreferences());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final providedStore = context.read<HttpInspectorStore?>();
    final nextStore = providedStore ?? HttpInspectorStore.instance;
    if (identical(nextStore, _store)) return;
    _store = nextStore;
    unawaited(_store.loadDisplayPreferences());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
          title: Text(localizations.networkRequests,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
      body: ListenableBuilder(
        listenable: _store,
        builder: (context, _) {
          final records = _store.filteredRecords;
          final stats = _store.visibleStats;
          return Column(
            children: [
              AppSearchBar(
                controller: _searchController,
                hintText: localizations.searchUrlOrDomain,
                onChanged: (v) => _store.setFilterDomain(v.trim()),
                onClear: () {
                  _searchController.clear();
                  _store.setFilterDomain('');
                },
                trailingActions: [
                  IconButton(
                    icon: const Icon(Icons.visibility_outlined, size: 20),
                    selectedIcon:
                        const Icon(Icons.visibility_off_outlined, size: 20),
                    isSelected: _store.hideNoiseMethods,
                    onPressed: () =>
                        _store.setHideNoiseMethods(!_store.hideNoiseMethods),
                    tooltip: _store.hideNoiseMethods
                        ? localizations.showNoiseRequests
                        : localizations.hideNoiseRequests,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.filter_list, size: 20),
                    onPressed: () => _showFilterSheet(context),
                    tooltip: localizations.filter,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed:
                        _store.count == 0 ? null : () => _confirmClear(context),
                    tooltip: localizations.clear,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              // --- Active filters ---
              if (_store.filterDomain.isNotEmpty ||
                  _store.filterMethod.isNotEmpty ||
                  _store.filterStatus != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  color: AppThemeColors.navigationIndicator(colors),
                  child: Row(
                    children: [
                      const Icon(Icons.filter_alt, size: 14),
                      const SizedBox(width: 6),
                      if (_store.filterDomain.isNotEmpty)
                        _FilterChip(
                            label:
                                localizations.domainFilter(_store.filterDomain),
                            onRemove: () => _store.setFilterDomain('')),
                      if (_store.filterMethod.isNotEmpty)
                        _FilterChip(
                            label:
                                localizations.methodFilter(_store.filterMethod),
                            onRemove: () => _store.setFilterMethod('')),
                      if (_store.filterStatus != null)
                        _FilterChip(
                            label: _store.filterStatus == 0
                                ? localizations.statusFilterError
                                : localizations.statusFilter(
                                    '${_store.filterStatus}xx',
                                  ),
                            onRemove: () => _store.setFilterStatus(null)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => _store.clearFilters(),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: Text(localizations.clearFilters,
                            style: const TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                ),
              // --- Domain tag bar ---
              if (_store.count > 0)
                Builder(builder: (context) {
                  final domains = _store.domainStats;
                  if (domains.isEmpty) return const SizedBox.shrink();
                  return Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: domains.length > 20 ? 21 : domains.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (_, i) {
                        if (i == 20) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Chip(
                              label: Text('+${domains.length - 20}',
                                  style: const TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              padding: EdgeInsets.zero,
                            ),
                          );
                        }
                        final d = domains[i];
                        final selected = _store.filterDomain == d.key;
                        return FilterChip(
                          label: Text('${d.key} (${d.value})',
                              style: const TextStyle(fontSize: 10)),
                          selected: selected,
                          onSelected: (_) {
                            _searchController.text = selected ? '' : d.key;
                            _store.setFilterDomain(selected ? '' : d.key);
                          },
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          padding: EdgeInsets.zero,
                          labelPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                        );
                      },
                    ),
                  );
                }),
              if (_store.count > 0) _buildRequestDashboard(stats),

              // --- Request list ---
              Expanded(
                child: records.isEmpty
                    ? AppEmptyState(
                        icon: Icons.wifi_find,
                        title: _store.count == 0
                            ? localizations.noNetworkRequests
                            : localizations.noMatchingRequests,
                        subtitle: _store.count == 0
                            ? localizations.runNetworkScriptHint
                            : _emptyRequestSubtitle(localizations),
                      )
                    : ListView.builder(
                        scrollCacheExtent: const ScrollCacheExtent.pixels(200),
                        addAutomaticKeepAlives: false,
                        addRepaintBoundaries: true,
                        itemCount: records.length,
                        itemBuilder: (context, index) {
                          final record = records[index];
                          return _HttpRecordTile(
                            record: record,
                            onTap: () => _openDetail(context, record),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _emptyRequestSubtitle(AppLocalizations localizations) {
    if (_store.hideNoiseMethods && _store.hiddenNoiseCount > 0) {
      return localizations.showNoiseRequests;
    }
    return localizations.tryClearingFilters;
  }

  void _showFilterSheet(BuildContext context) {
    final domainCtrl = TextEditingController(text: _store.filterDomain);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(ctx)!.filterNetworkRequests,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            TextField(
              controller: domainCtrl,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(ctx)!.domainOrUrlKeyword,
                hintText: 'example.com',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (v) {
                _store.setFilterDomain(v.trim());
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 12),
            Text(AppLocalizations.of(ctx)!.requestMethod,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                '',
                'GET',
                'POST',
                'PUT',
                'DELETE',
                'PATCH',
                'HEAD',
                'DNS',
                'CONNECT',
                'PROCESS'
              ].map((m) {
                final label = m.isEmpty ? AppLocalizations.of(ctx)!.all : m;
                final selected = _store.filterMethod == m;
                return ChoiceChip(
                  label: Text(label, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  onSelected: (_) {
                    _store.setFilterMethod(m);
                    Navigator.pop(ctx);
                  },
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Text(AppLocalizations.of(ctx)!.statusCode,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _statusChip(ctx, null, AppLocalizations.of(ctx)!.all),
                _statusChip(ctx, 0, AppLocalizations.of(ctx)!.error),
                _statusChip(ctx, 200, '2xx'),
                _statusChip(ctx, 300, '3xx'),
                _statusChip(ctx, 400, '4xx'),
                _statusChip(ctx, 500, '5xx'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    _store.setFilterDomain(domainCtrl.text.trim());
                    Navigator.pop(ctx);
                  },
                  child: Text(AppLocalizations.of(ctx)!.apply),
                ),
              ],
            ),
          ],
        ),
      ),
    ).whenComplete(() => domainCtrl.dispose());
  }

  Widget _statusChip(BuildContext ctx, int? value, String label) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: _store.filterStatus == value,
      onSelected: (_) {
        _store.setFilterStatus(value);
        Navigator.pop(ctx);
      },
      visualDensity: VisualDensity.compact,
    );
  }

  void _openDetail(BuildContext context, HttpRecord record) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => _HttpRecordDetailPage(record: record)));
  }

  Widget _buildRequestDashboard(Map<String, dynamic> stats) {
    final colors = Theme.of(context).colorScheme;
    final visibleTotal = stats['total'] as int? ?? 0;
    final countLabel = visibleTotal == _store.count
        ? AppLocalizations.of(context)!.allRequestsCount(_store.count)
        : AppLocalizations.of(context)!
            .visibleRequestsCount(visibleTotal, _store.count);
    return AppSurface(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            _StatBadge(
                label: '${stats['total']}',
                icon: Icons.http,
                color: colors.primary),
            const SizedBox(width: 12),
            _StatBadge(
                label: '${stats['success']}',
                icon: Icons.check_circle,
                color: Color.alphaBlend(
                    colors.primary.withValues(alpha: 0.36), colors.tertiary)),
            const SizedBox(width: 12),
            _StatBadge(
                label: '${stats['error']}',
                icon: Icons.error_outline,
                color: colors.error),
            const SizedBox(width: 12),
            if (stats['avgMs'] != null)
              _StatBadge(
                  label: '${stats['avgMs']}ms',
                  icon: Icons.speed,
                  color: colors.onSurfaceVariant),
            const Spacer(),
            Text(countLabel,
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  void _confirmClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx)!.clearNetworkRequests),
        content: Text(AppLocalizations.of(ctx)!.clearNetworkRequestsConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(ctx)!.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _store.clear();
            },
            child: Text(
              AppLocalizations.of(ctx)!.clear,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Record tile ---
