import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/native_bridge.dart';
import '../services/update_service.dart';

class UpdateLogPage extends StatefulWidget {
  final UpdateService updateService;
  final Future<void> Function(String url)? openUrl;
  final int limit;

  UpdateLogPage({
    super.key,
    UpdateService? updateService,
    this.openUrl,
    this.limit = 20,
  }) : updateService = updateService ?? UpdateService();

  @override
  State<UpdateLogPage> createState() => _UpdateLogPageState();
}

class _UpdateLogPageState extends State<UpdateLogPage> {
  final _searchController = TextEditingController();
  final _bridge = NativeBridge();
  List<ReleaseLogEntry> _entries = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await widget.updateService.fetchReleaseLogs(
        limit: widget.limit,
      );
      if (!mounted) return;
      setState(() => _entries = entries);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<ReleaseLogEntry> get _filteredEntries {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _entries;
    return _entries.where((entry) {
      final haystack = [
        entry.tagName,
        entry.version,
        entry.releaseName,
        entry.releaseNotes,
      ].join('\n').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  Future<void> _openRelease(ReleaseLogEntry entry) async {
    if (entry.htmlUrl.isEmpty) return;
    try {
      final opener = widget.openUrl;
      if (opener == null) {
        await _bridge.openUrl(entry.htmlUrl);
      } else {
        await opener(entry.htmlUrl);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('打开发布页失败：$error'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('更新日志')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              key: const Key('updateLogSearchField'),
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清除搜索',
                        icon: const Icon(Icons.clear),
                        onPressed: _searchController.clear,
                      ),
                hintText: '搜索版本或更新内容',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadLogs,
              child: _buildContent(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loading && _entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _entries.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          Icon(
            Icons.cloud_off_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            '更新日志加载失败',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton.icon(
              onPressed: _loadLogs,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ),
        ],
      );
    }

    final entries = _filteredEntries;
    if (entries.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 96),
          Icon(
            Icons.article_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            _searchController.text.trim().isEmpty ? '暂无更新日志' : '没有匹配的更新日志',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      itemCount: entries.length,
      itemBuilder: (context, index) => _ReleaseLogCard(
        entry: entries[index],
        onOpenRelease: () => _openRelease(entries[index]),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

class _ReleaseLogCard extends StatelessWidget {
  final ReleaseLogEntry entry;
  final VoidCallback onOpenRelease;

  const _ReleaseLogCard({
    required this.entry,
    required this.onOpenRelease,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        title: Row(
          children: [
            Text(
              entry.tagName.isEmpty ? '未命名版本' : entry.tagName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (entry.isPrerelease) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.tertiaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '预发布',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onTertiaryContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.releaseName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                _formatDate(entry.publishedAt),
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              entry.hasReleaseNotes
                  ? entry.releaseNotes.trim()
                  : '当前发布没有填写更新说明。',
              style: const TextStyle(fontSize: 13, height: 1.45),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (entry.apkAsset != null)
                Text(
                  'APK：${entry.apkAsset!.name}',
                  style:
                      TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                ),
              const Spacer(),
              TextButton.icon(
                onPressed: entry.htmlUrl.isEmpty ? null : onOpenRelease,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('发布页'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? dateTime) {
    if (dateTime == null) return '发布时间未知';
    return DateFormat('yyyy-MM-dd HH:mm').format(dateTime.toLocal());
  }
}
