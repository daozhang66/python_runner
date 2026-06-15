import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/native_bridge.dart';
import '../services/update_service.dart';
import '../ui/app_design_tokens.dart';

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
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.surfaceContainerLow,
              colors.surface,
            ],
          ),
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: const Border(),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colors.primaryContainer,
                  colors.secondaryContainer,
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: colors.primary.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              Icons.rocket_launch_rounded,
              size: 24,
              color: colors.onPrimaryContainer,
            ),
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  entry.tagName.isEmpty ? '未命名版本' : entry.tagName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              if (entry.isPrerelease) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        colors.tertiaryContainer,
                        colors.tertiaryContainer.withValues(alpha: 0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(
                      color: colors.tertiary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '预发布',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: colors.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Icon(Icons.schedule, size: 12, color: colors.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  _formatDate(entry.publishedAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          children: [
            // Markdown 渲染区域
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: double.infinity,
                  child: entry.hasReleaseNotes
                      ? MarkdownBody(
                          data: entry.releaseNotes.trim(),
                          selectable: true,
                          styleSheet: MarkdownStyleSheet(
                            p: const TextStyle(fontSize: 13, height: 1.5),
                            h1: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: colors.primary,
                            ),
                            h2: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: colors.primary,
                            ),
                            h3: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurface,
                            ),
                            listBullet: TextStyle(color: colors.primary),
                            code: TextStyle(
                              backgroundColor: colors.surfaceContainerHigh
                                  .withValues(alpha: 0.8),
                              color: colors.primary,
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                            codeblockDecoration: BoxDecoration(
                              color: colors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            blockquote: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                            blockquoteDecoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                  color: colors.primary,
                                  width: 3,
                                ),
                              ),
                            ),
                          ),
                          onTapLink: (text, href, title) {
                            if (href != null) {
                              launchUrl(Uri.parse(href),
                                  mode: LaunchMode.externalApplication);
                            }
                          },
                        )
                      : Text(
                          '当前发布没有填写更新说明。',
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: entry.htmlUrl.isEmpty ? null : onOpenRelease,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('发布页'),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime? dateTime) {
    if (dateTime == null) return '发布时间未知';
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inDays == 0) {
      return '今天 ${DateFormat('HH:mm').format(dateTime.toLocal())}';
    } else if (diff.inDays == 1) {
      return '昨天 ${DateFormat('HH:mm').format(dateTime.toLocal())}';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} 天前';
    } else {
      return DateFormat('yyyy-MM-dd HH:mm').format(dateTime.toLocal());
    }
  }
}
