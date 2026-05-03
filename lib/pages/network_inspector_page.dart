import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/http_inspector_store.dart';
import '../services/native_bridge.dart';

class NetworkInspectorPage extends StatefulWidget {
  const NetworkInspectorPage({super.key});

  @override
  State<NetworkInspectorPage> createState() => _NetworkInspectorPageState();
}

class _NetworkInspectorPageState extends State<NetworkInspectorPage> {
  final _store = HttpInspectorStore.instance;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final records = _store.filteredRecords;
    final colors = Theme.of(context).colorScheme;
    final stats = _computeStats();

    return Scaffold(
      body: Column(
        children: [
          // 鈹€鈹€ Search bar 鈹€鈹€
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: colors.surfaceContainerHighest,
            child: Row(
              children: [
                const Icon(Icons.search, size: 18, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: '搜索 URL / 域名...',
                      border: InputBorder.none, isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: (v) => _store.setFilterDomain(v.trim()),
                  ),
                ),
                if (_store.filterDomain.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      _searchController.clear();
                      _store.setFilterDomain('');
                    },
                  ),
                IconButton(
                  icon: const Icon(Icons.filter_list, size: 20),
                  onPressed: () => _showFilterSheet(context),
                  tooltip: '筛选',
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: _store.count == 0 ? null : () => _confirmClear(context),
                  tooltip: '清空',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          // 鈹€鈹€ Active filters 鈹€鈹€
          if (_store.filterDomain.isNotEmpty ||
              _store.filterMethod.isNotEmpty ||
              _store.filterStatus != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              color: colors.primaryContainer.withValues(alpha: 0.3),
              child: Row(
                children: [
                  const Icon(Icons.filter_alt, size: 14),
                  const SizedBox(width: 6),
                  if (_store.filterDomain.isNotEmpty)
                    _FilterChip(label: '域名: \${_store.filterDomain}',
                        onRemove: () => _store.setFilterDomain('')),
                  if (_store.filterMethod.isNotEmpty)
                    _FilterChip(label: '方法: \${_store.filterMethod}',
                        onRemove: () => _store.setFilterMethod('')),
                  if (_store.filterStatus != null)
                    _FilterChip(
                        label: _store.filterStatus == 0
                            ? '状态: 错误'
                            : '状态: \${_store.filterStatus}xx',
                        onRemove: () => _store.setFilterStatus(null)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _store.clearFilters(),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('清除筛选', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),
          // 鈹€鈹€ Domain tag bar 鈹€鈹€
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
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: EdgeInsets.zero,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                    );
                  },
                ),
              );
            }),
          // 鈹€鈹€ Stats bar 鈹€鈹€
          if (_store.count > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
              child: Row(
                children: [
                  _StatBadge(label: '${stats['total']}', icon: Icons.http, color: colors.primary),
                  const SizedBox(width: 12),
                  _StatBadge(label: '${stats['success']}', icon: Icons.check_circle, color: Colors.green),
                  const SizedBox(width: 12),
                  _StatBadge(label: '${stats['error']}', icon: Icons.error_outline, color: colors.error),
                  const SizedBox(width: 12),
                  if (stats['avgMs'] != null)
                    _StatBadge(label: '${stats['avgMs']}ms', icon: Icons.speed, color: colors.onSurfaceVariant),
                  const Spacer(),
                  Text('全部 \${_store.count}',
                      style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
                ],
              ),
            ),

          // 鈹€鈹€ Request list 鈹€鈹€
          Expanded(
            child: records.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.wifi_find, size: 48, color: colors.onSurfaceVariant.withValues(alpha: 0.3)),
                        const SizedBox(height: 12),
                        Text(
                          _store.count == 0 ? '暂无网络请求记录' : '无匹配的请求',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                        if (_store.count == 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '运行包含 HTTP 请求的脚本后\n请求将自动显示在这里',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant.withValues(alpha: 0.6)),
                            ),
                          ),
                      ],
                    ),
                  )
                : ListView.builder(
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
      ),
    );
  }

  Map<String, dynamic> _computeStats() {
    final all = _store.records;
    var success = 0;
    var errors = 0;
    var totalMs = 0;
    var count = 0;
    for (final r in all) {
      if (r.isSuccess) success++;
      if (r.isError) errors++;
      if (r.durationMs != null) { totalMs += r.durationMs!; count++; }
    }
    return {
      'total': all.length,
      'success': success,
      'error': errors,
      'avgMs': count > 0 ? (totalMs / count).round() : null,
    };
  }

  void _showFilterSheet(BuildContext context) {
    final domainCtrl = TextEditingController(text: _store.filterDomain);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('筛选网络请求', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            TextField(
              controller: domainCtrl,
              decoration: const InputDecoration(
                labelText: 'Domain / URL keyword',
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
            const Text('请求方法', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['', 'GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD'].map((m) {
                final label = m.isEmpty ? '全部' : m;
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
            const Text('状态码', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _statusChip(ctx, null, '全部'),
                _statusChip(ctx, 0, '错误'),
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
                  child: const Text('应用'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => _HttpRecordDetailPage(record: record)));
  }

  void _exportRecords(BuildContext context) {
    final text = _store.exportFiltered();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制 \${_store.filteredRecords.length} 条请求记录到剪贴板'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showExportOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('复制为文本'),
              subtitle: const Text('复制请求记录到剪贴板'),
              onTap: () {
                Navigator.pop(ctx);
                _exportRecords(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_present),
              title: const Text('导出 HAR 文件'),
              subtitle: const Text('可导入 Charles / Fiddler 等工具'),
              onTap: () {
                Navigator.pop(ctx);
                _exportHar(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportHar(BuildContext context) async {
    try {
      final harJson = _store.exportHar(filteredOnly: true);
      final now = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'pyrunner_$now.har';
      final bridge = NativeBridge();
      final path = await bridge.exportLog(harJson, fileName: fileName);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('HAR 文件已导出: \$path'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('HAR 导出失败: \$e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _confirmClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空网络请求记录'),
        content: const Text('确定要清空所有已捕获的网络请求记录吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),

          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _store.clear();
            },
            child: Text('清空', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }
}

// 鈹€鈹€ Record tile 鈹€鈹€
class _HttpRecordTile extends StatelessWidget {
  final HttpRecord record;
  final VoidCallback onTap;

  const _HttpRecordTile({required this.record, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final timeFmt = DateFormat('HH:mm:ss.SSS');

    Color statusColor;
    if (record.errorType != null) {
      statusColor = colors.error;
    } else if (record.statusCode == null) {
      statusColor = colors.onSurfaceVariant;
    } else if (record.statusCode! >= 200 && record.statusCode! < 300) {
      statusColor = Colors.green.shade700;
    } else if (record.statusCode! >= 300 && record.statusCode! < 400) {
      statusColor = Colors.orange;
    } else {
      statusColor = colors.error;
    }

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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // Status badge
            Container(
              width: 44,
              padding: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                record.statusText,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor),
              ),
            ),
            const SizedBox(width: 10),
            // Method
            SizedBox(
              width: 36,
              child: Text(
                record.method,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.primary,
                ),
              ),
            ),
            const SizedBox(width: 6),
            // URL + meta
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    domain,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    record.url,
                    style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
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
                  style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
                ),
                Text(
                  timeFmt.format(record.timestamp),
                  style: TextStyle(fontSize: 9, color: colors.onSurfaceVariant.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// 鈹€鈹€ Filter chip 鈹€鈹€
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

// 鈹€鈹€ Stat badge 鈹€鈹€
class _StatBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _StatBadge({required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color)),
      ],
    );
  }
}

// 鈹€鈹€ Detail page 鈹€鈹€
class _HttpRecordDetailPage extends StatelessWidget {
  final HttpRecord record;
  const _HttpRecordDetailPage({required this.record});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final timeFmt = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');

    return Scaffold(
      appBar: AppBar(
        title: Text('${record.method} ${record.statusText}',
            style: const TextStyle(fontSize: 15)),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: record.toExportText()));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制请求详情'), duration: Duration(seconds: 1)),
              );
            },
            tooltip: '复制',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // 鈹€鈹€ Overview 鈹€鈹€
          _SectionCard(
            title: '概览',
            icon: Icons.info_outline,
            children: [
              _DetailRow('时间', timeFmt.format(record.timestamp)),
              _DetailRow('方法', record.method),
              _DetailRow('URL', record.url),
              _DetailRow('库', record.library),
              _DetailRow('耗时', record.durationText),
              _DetailRow('代理', record.usedProxy ? '是' : '否'),
              _DetailRow('SSL 校验', record.sslVerify ? '是' : '否'),
            ],
          ),
          const SizedBox(height: 8),
          // 鈹€鈹€ Request Headers 鈹€鈹€
          _SectionCard(
            title: '请求头 (${record.requestHeaders.length})',
            icon: Icons.arrow_upward,
            children: record.requestHeaders.entries
                .map((e) => _DetailRow(e.key, e.value))
                .toList(),
          ),
          if (record.requestBody != null && record.requestBody!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _SectionCard(
              title: '请求体',
              icon: Icons.upload,
              children: [_CodeBlock(record.requestBody!)],
            ),
          ],
          const SizedBox(height: 8),
          // 鈹€鈹€ Response 鈹€鈹€
          _SectionCard(
            title: '响应',
            icon: Icons.arrow_downward,
            children: [
              if (record.statusCode != null)
                _DetailRow('状态码', record.statusCode.toString()),
              if (record.errorType != null)
                _DetailRow('错误类型', record.errorType!,
                    valueColor: colors.error),
              if (record.errorMessage != null)
                _DetailRow('错误信息', record.errorMessage!,
                    valueColor: colors.error),
            ],
          ),
          if (record.responseHeaders != null &&
              record.responseHeaders!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _SectionCard(
              title: '响应头 (${record.responseHeaders!.length})',
              icon: Icons.arrow_downward,
              children: record.responseHeaders!.entries
                  .map((e) => _DetailRow(e.key, e.value))
                  .toList(),
            ),
          ],
          if (record.responseBodyPreview != null &&
              record.responseBodyPreview!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _SectionCard(
              title: record.isImageBody
                  ? '响应图片'
                  : record.isMediaBody
                      ? '响应媒体'
                      : '响应体预览',
              icon: record.isImageBody
                  ? Icons.image
                  : record.isMediaBody
                      ? Icons.audiotrack
                      : Icons.description_outlined,
              children: [
                if (record.responseBodyTruncated) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.28)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            record.responseBodyBytes != null
                                ? 'Response body is large. Showing ${_formatByteSize(record.capturedResponseBodyBytes)} / ${_formatByteSize(record.responseBodyBytes!)}.'
                                : '响应体较大，当前仅显示已捕获的内容。',
                            style: TextStyle(fontSize: 11, color: Colors.orange.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (record.isImageBody)
                  _ImagePreview(dataUri: record.responseBodyPreview!)
                else if (record.isMediaBody)
                  _MediaInfoCard(meta: record.mediaMeta!)
                else
                  _CodeBlock(record.responseBodyPreview!),
                if (!record.isMediaBody) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => record.isImageBody
                              ? _ImageFullViewPage(dataUri: record.responseBodyPreview!)
                              : _BodyFullViewPage(
                                  body: record.responseBodyPreview!,
                                  bodyBytes: record.responseBodyBytes,
                                  wasTruncated: record.responseBodyTruncated,
                                  title: '响应体',
                                ),
                        ),
                      ),
                      icon: Icon(record.isImageBody ? Icons.zoom_in : Icons.open_in_full, size: 14),
                      label: Text(record.isImageBody ? '查看原图' : '查看完整内容',
                          style: const TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: colors.primary),
                const SizedBox(width: 6),
                Text(title, style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: colors.primary)),
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailRow(this.label, this.value, {this.valueColor});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
          ),
          Expanded(
            child: SelectableText(value,
                style: TextStyle(fontSize: 11, color: valueColor)),
          ),
        ],
      ),
    );
  }
}

String _formatByteSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _CodeBlock extends StatelessWidget {
  final String text;
  const _CodeBlock(this.text);

  String get _formatted {
    try {
      final parsed = jsonDecode(text);
      return const JsonEncoder.withIndent('  ').convert(parsed);
    } catch (_) {
      return text;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 300),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          _formatted,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
        ),
      ),
    );
  }
}

// 鈹€鈹€ Media info card 鈹€鈹€
class _MediaInfoCard extends StatelessWidget {
  final Map<String, dynamic> meta;
  const _MediaInfoCard({required this.meta});

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _mediaLabel(String type) {
    if (type.startsWith('audio/')) return '闊抽';
    if (type.startsWith('video/')) return '视频';
    return '媒体';
  }

  IconData _mediaIcon(String type) {
    if (type.startsWith('audio/')) return Icons.audiotrack;
    if (type.startsWith('video/')) return Icons.videocam;
    return Icons.perm_media;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final type = meta['type'] as String? ?? 'unknown';
    final size = meta['size'] as int? ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(_mediaIcon(type), size: 40, color: colors.primary),
          const SizedBox(height: 8),
          Text(_mediaLabel(type), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.primary)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _MediaMetaItem(label: '绫诲瀷', value: type),
              const SizedBox(width: 24),
              _MediaMetaItem(label: '大小', value: _formatSize(size)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MediaMetaItem extends StatelessWidget {
  final String label;
  final String value;
  const _MediaMetaItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

// 鈹€鈹€ Full body view page with JSON tree viewer 鈹€鈹€
class _BodyFullViewPage extends StatefulWidget {
  final String body;
  final int? bodyBytes;
  final String title;
  final bool wasTruncated;
  const _BodyFullViewPage({
    required this.body,
    this.bodyBytes,
    required this.title,
    this.wasTruncated = false,
  });

  @override
  State<_BodyFullViewPage> createState() => _BodyFullViewPageState();
}

class _BodyFullViewPageState extends State<_BodyFullViewPage> {
  dynamic _parsedJson;
  String _formatted = '';
  double _fontSize = 12.0;
  final _scrollController = ScrollController();
  bool _showFab = false;
  bool _searchVisible = false;
  final _searchCtrl = TextEditingController();
  int _searchCurrent = -1;
  List<int> _searchMatches = [];
  String _lineNumberedText = '';

  @override
  void initState() {
    super.initState();
    _parseBody();
    _scrollController.addListener(() {
      final show = _scrollController.offset > 300;
      if (show != _showFab) setState(() => _showFab = show);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _BodyFullViewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.body != widget.body) _parseBody();
  }

  bool _isTruncated = false;

  void _parseBody() {
    _isTruncated = widget.wasTruncated;
    // Try 1: parse as-is
    try {
      _parsedJson = jsonDecode(widget.body);
      const encoder = JsonEncoder.withIndent('  ');
      _formatted = encoder.convert(_parsedJson);
    } catch (_) {
      // Try 2: repair truncated JSON
      final repaired = _tryRepairTruncatedJson(widget.body);
      if (repaired != null) {
        try {
          _parsedJson = jsonDecode(repaired);
          const encoder = JsonEncoder.withIndent('  ');
          _formatted = encoder.convert(_parsedJson);
          _isTruncated = true;
        } catch (_) {
          _parsedJson = null;
          _formatted = _looksLikeJson(widget.body) ? _basicFormatJson(widget.body) : widget.body;
        }
      } else {
        _parsedJson = null;
        _formatted = _looksLikeJson(widget.body) ? _basicFormatJson(widget.body) : widget.body;
      }
    }
    _buildLineNumberedText();
  }

  bool _looksLikeJson(String s) {
    final t = s.trimLeft();
    return t.startsWith('{') || t.startsWith('[');
  }

  /// Try to repair a truncated JSON string by cutting back to last valid boundary
  /// and adding missing closing brackets.
  String? _tryRepairTruncatedJson(String input) {
    final marker = '...（已截断）';
    final idx = input.lastIndexOf(marker);
    if (idx <= 0) return null;

    var s = input.substring(0, idx).trimRight();

    // Find the last comma outside of strings 鈥?cut back to a valid boundary
    int lastComma = -1;
    bool inStr = false, esc = false;
    for (int i = 0; i < s.length; i++) {
      if (esc) { esc = false; continue; }
      if (s[i] == '\\') { esc = true; continue; }
      if (s[i] == '"') { inStr = !inStr; continue; }
      if (inStr) continue;
      if (s[i] == ',') lastComma = i;
    }
    if (lastComma > 0) s = s.substring(0, lastComma);

    // Count and close unclosed brackets
    int curly = 0, square = 0;
    inStr = false; esc = false;
    for (int i = 0; i < s.length; i++) {
      if (esc) { esc = false; continue; }
      if (s[i] == '\\') { esc = true; continue; }
      if (s[i] == '"') { inStr = !inStr; continue; }
      if (inStr) continue;
      if (s[i] == '{') curly++;
      if (s[i] == '}') curly--;
      if (s[i] == '[') square++;
      if (s[i] == ']') square--;
    }
    for (int i = 0; i < square; i++) s += ']';
    for (int i = 0; i < curly; i++) s += '}';

    return s;
  }

  /// Basic formatting for JSON-like content that can't be fully parsed.
  String _basicFormatJson(String input) {
    final buf = StringBuffer();
    int indent = 0;
    bool inStr = false, esc = false;
    for (int i = 0; i < input.length; i++) {
      final c = input[i];
      if (esc) { buf.write(c); esc = false; continue; }
      if (c == '\\' && inStr) { buf.write(c); esc = true; continue; }
      if (c == '"') { buf.write(c); inStr = !inStr; continue; }
      if (inStr) { buf.write(c); continue; }
      if (c == '{' || c == '[') {
        buf.writeln(c);
        indent++;
        buf.write('  ' * indent);
      } else if (c == '}' || c == ']') {
        buf.writeln();
        if (indent > 0) indent--;
        buf.write('  ' * indent);
        buf.write(c);
      } else if (c == ',') {
        buf.writeln(c);
        buf.write('  ' * indent);
      } else if (c == ':') {
        buf.write(': ');
      } else if (c != ' ' && c != '\n' && c != '\r' && c != '\t') {
        buf.write(c);
      }
    }
    return buf.toString();
  }

  void _buildLineNumberedText() {
    final lines = _formatted.split('\n');
    final totalWidth = lines.length.toString().length;
    final buf = StringBuffer();
    for (int i = 0; i < lines.length; i++) {
      final num = (i + 1).toString().padLeft(totalWidth);
      buf.writeln('$num  ${lines[i]}');
    }
    _lineNumberedText = buf.toString();
  }

  void _showFontSizeSlider() {
    double tempSize = _fontSize;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          contentPadding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${tempSize.round()} px', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('A', style: TextStyle(fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: tempSize,
                      min: 6.0,
                      max: 32.0,
                      divisions: 26,
                      onChanged: (v) {
                        setDialogState(() => tempSize = v);
                      },
                    ),
                  ),
                  const Text('A', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                setDialogState(() => tempSize = 12.0);
              },
              child: const Text('重置'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() => _fontSize = tempSize);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportJson() async {
    try {
      final bridge = NativeBridge();
      final now = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final path = await bridge.exportLog(_formatted, fileName: 'response_$now.json');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导出: \$path'), duration: const Duration(seconds: 3)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: \$e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  void _doSearch(String query) {
    if (query.isEmpty) {
      setState(() { _searchMatches = []; _searchCurrent = -1; });
      return;
    }
    final lines = _formatted.split('\n');
    final matches = <int>[];
    final q = query.toLowerCase();
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].toLowerCase().contains(q)) matches.add(i);
    }
    setState(() {
      _searchMatches = matches;
      _searchCurrent = matches.isNotEmpty ? 0 : -1;
    });
    if (matches.isNotEmpty) _scrollToLine(matches[0]);
  }

  void _nextSearchMatch() {
    if (_searchMatches.isEmpty) return;
    setState(() {
      _searchCurrent = (_searchCurrent + 1) % _searchMatches.length;
    });
    _scrollToLine(_searchMatches[_searchCurrent]);
  }

  void _prevSearchMatch() {
    if (_searchMatches.isEmpty) return;
    setState(() {
      _searchCurrent = (_searchCurrent - 1 + _searchMatches.length) % _searchMatches.length;
    });
    _scrollToLine(_searchMatches[_searchCurrent]);
  }

  void _scrollToLine(int lineIndex) {
    // Approximate: each line is roughly fontSize * 1.5 height
    final approxOffset = lineIndex * _fontSize * 1.5;
    _scrollController.animateTo(
      approxOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isJson = _parsedJson != null;
    final colors = Theme.of(context).colorScheme;
    final lineCount = _formatted.split('\n').length;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(widget.title, style: const TextStyle(fontSize: 15)),
            if (isJson) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('JSON',
                    style: TextStyle(fontSize: 10, color: colors.onPrimaryContainer)),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, size: 20),
            onPressed: () => setState(() => _searchVisible = !_searchVisible),
            tooltip: '搜索',
          ),
          if (isJson)
            IconButton(
              icon: const Icon(Icons.account_tree, size: 20),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _JsonTreePage(data: _parsedJson),
                ),
              ),
              tooltip: '树形视图',
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            tooltip: '更多',
            position: PopupMenuPosition.under,
            itemBuilder: (_) => [
              const PopupMenuItem<String>(
                value: 'font',
                child: Row(
                  children: [
                    Icon(Icons.format_size, size: 18),
                    SizedBox(width: 8),
                    Text('字体大小', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'copy',
                child: Row(
                  children: [
                    Icon(Icons.copy, size: 18),
                    SizedBox(width: 8),
                    Text('复制全部', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.file_download_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('导出 JSON', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ],
            onSelected: (v) {
              switch (v) {
                case 'font':
                  _showFontSizeSlider();
                case 'copy':
                  Clipboard.setData(ClipboardData(text: _formatted));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
                  );
                case 'export':
                  _exportJson();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 鈹€鈹€ Search bar 鈹€鈹€
          if (_searchVisible)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: colors.surfaceContainerHighest,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      autofocus: true,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: '搜索内容...',
                        border: InputBorder.none, isDense: true,
                      ),
                      onSubmitted: _doSearch,
                      onChanged: (v) { if (v.isEmpty) _doSearch(''); },
                    ),
                  ),
                  if (_searchMatches.isNotEmpty)
                    Text('${_searchCurrent + 1}/${_searchMatches.length}',
                        style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_up, size: 18),
                    onPressed: _prevSearchMatch,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                    onPressed: _nextSearchMatch,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() { _searchVisible = false; _searchMatches = []; _searchCurrent = -1; });
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          // 鈹€鈹€ Info bar 鈹€鈹€
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Row(
              children: [
                if (_isTruncated) ...[
                  Icon(Icons.warning_amber, size: 12, color: Colors.orange.shade700),
                  const SizedBox(width: 3),
                    Text('已截断', style: TextStyle(fontSize: 10, color: Colors.orange.shade700)),
                  const SizedBox(width: 8),
                ],
                Text('$lineCount 行', style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant)),
                if (widget.bodyBytes != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    _isTruncated
                        ? '已捕获 \${_formatByteSize(utf8.encode(widget.body).length)} / \${_formatByteSize(widget.bodyBytes!)}'
                        : _formatByteSize(widget.bodyBytes!),
                    style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
                  ),
                ],
                const Spacer(),
                Text('${_formatted.length} 字符', style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant)),
              ],
            ),
          ),
          // 鈹€鈹€ Content: single SelectableText for performance 鈹€鈹€
          Expanded(
            child: Stack(
                children: [
                  SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        _lineNumberedText,
                        style: TextStyle(fontFamily: 'monospace', fontSize: _fontSize, height: 1.5),
                      ),
                    ),
                  ),
                  if (_showFab)
                    Positioned(
                      right: 12,
                      bottom: 16,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 36,
                            height: 36,
                            child: FloatingActionButton.small(
                              heroTag: 'top',
                              onPressed: () => _scrollController.animateTo(0,
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOut),
                              child: const Icon(Icons.keyboard_arrow_up, size: 20),
                            ),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            width: 36,
                            height: 36,
                            child: FloatingActionButton.small(
                              heroTag: 'bottom',
                              onPressed: () => _scrollController.animateTo(
                                  _scrollController.position.maxScrollExtent,
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOut),
                              child: const Icon(Icons.keyboard_arrow_down, size: 20),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
          ),
        ],
      ),
    );
  }
}

// 鈹€鈹€ Full-screen JSON tree page 鈹€鈹€
class _JsonTreePage extends StatelessWidget {
  final dynamic data;
  const _JsonTreePage({required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('JSON 树形查看', style: TextStyle(fontSize: 15)),
      ),
      body: SelectionArea(
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _JsonTreeNode(data: data, depth: 0, fontSize: 12),
          ),
        ),
      ),
    );
  }
}

class _JsonTreeNode extends StatefulWidget {
  final dynamic data;
  final int depth;
  final double fontSize;
  const _JsonTreeNode({super.key, required this.data, required this.depth, required this.fontSize});

  @override
  State<_JsonTreeNode> createState() => _JsonTreeNodeState();
}

class _JsonTreeNodeState extends State<_JsonTreeNode> {
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    // Auto-collapse deep nodes
    _expanded = widget.depth < 2;
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final depth = widget.depth;
    final fs = widget.fontSize;

    if (data is Map) return _buildObject(data, depth, fs);
    if (data is List) return _buildArray(data, depth, fs);
    return _buildPrimitive(data, fs);
  }

  Widget _buildObject(Map<dynamic, dynamic> map, int depth, double fs) {
    final colors = Theme.of(context).colorScheme;
    final items = map.entries.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              SizedBox(
                width: 12,
                child: Text(_expanded ? '▼' : '▶',
                    style: TextStyle(fontSize: fs - 3, color: colors.primary)),
              ),
              Text('{', style: TextStyle(fontFamily: 'monospace', fontSize: fs, color: colors.onSurface)),
              if (!_expanded) ...[
                Text(' ${map.length} keys ', style: TextStyle(fontSize: fs - 2, color: colors.onSurfaceVariant)),
                Text('}', style: TextStyle(fontFamily: 'monospace', fontSize: fs, color: colors.onSurface)),
              ],
            ],
          ),
        ),
        if (_expanded)
          Padding(
            padding: EdgeInsets.only(left: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < items.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('"${items[i].key}": ',
                            style: TextStyle(
                                fontFamily: 'monospace', fontSize: fs,
                                color: Colors.blue.shade700)),
                        _JsonValue(
                          data: items[i].value,
                          depth: depth + 1,
                          fontSize: fs,
                          trailing: i < items.length - 1 ? ',' : null,
                        ),
                      ],
                    ),
                  ),
                Text('}', style: TextStyle(fontFamily: 'monospace', fontSize: fs, color: colors.onSurface)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildArray(List<dynamic> list, int depth, double fs) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              SizedBox(
                width: 12,
                child: Text(_expanded ? '▼' : '▶',
                    style: TextStyle(fontSize: fs - 3, color: colors.primary)),
              ),
              Text('[', style: TextStyle(fontFamily: 'monospace', fontSize: fs, color: colors.onSurface)),
              if (!_expanded) ...[
                Text(' ${list.length} items ', style: TextStyle(fontSize: fs - 2, color: colors.onSurfaceVariant)),
                Text(']', style: TextStyle(fontFamily: 'monospace', fontSize: fs, color: colors.onSurface)),
              ],
            ],
          ),
        ),
        if (_expanded)
          Padding(
            padding: EdgeInsets.only(left: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < list.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: _JsonValue(
                      data: list[i],
                      depth: depth + 1,
                      fontSize: fs,
                      trailing: i < list.length - 1 ? ',' : null,
                    ),
                  ),
                Text(']', style: TextStyle(fontFamily: 'monospace', fontSize: fs, color: colors.onSurface)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildPrimitive(dynamic value, double fs) {
    return Text(
      _primitiveText(value),
      style: TextStyle(fontFamily: 'monospace', fontSize: fs, color: _primitiveColor(value)),
    );
  }
}

/// Wraps a value: shows inline for primitives, expandable for objects/arrays.
class _JsonValue extends StatelessWidget {
  final dynamic data;
  final int depth;
  final double fontSize;
  final String? trailing;
  const _JsonValue({required this.data, required this.depth, required this.fontSize, this.trailing});

  @override
  Widget build(BuildContext context) {
    if (data is Map || data is List) {
      // Complex types: no trailing comma in tree view (avoids floating symbol)
      return _JsonTreeNode(data: data, depth: depth, fontSize: fontSize);
    }
    return Text(
      _primitiveText(data) + (trailing ?? ''),
      style: TextStyle(fontFamily: 'monospace', fontSize: fontSize, color: _primitiveColor(data)),
    );
  }
}

// 鈹€鈹€ Helpers 鈹€鈹€

String _primitiveText(dynamic value) {
  if (value == null) return 'null';
  if (value is bool) return value.toString();
  if (value is num) return value.toString();
  if (value is String) return '"${value}"';
  return value.toString();
}

Color _primitiveColor(dynamic value) {
  if (value == null) return Colors.grey;
  if (value is bool) return Colors.purple;
  if (value is num) return Colors.orange.shade800;
  if (value is String) return Colors.green.shade700;
  return Colors.black;
}

// 鈹€鈹€ Image preview widget 鈹€鈹€
class _ImagePreview extends StatelessWidget {
  final String dataUri;
  const _ImagePreview({required this.dataUri});

  Uint8List? _decodeDataUri() {
    // data:image/png;base64,AAAA...
    final commaIdx = dataUri.indexOf(',');
    if (commaIdx < 0) return null;
    final base64Str = dataUri.substring(commaIdx + 1);
    try {
      return base64Decode(base64Str);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _decodeDataUri();
    if (bytes == null) {
      return const Text('(图片解码失败)', style: TextStyle(fontSize: 12));
    }
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Text('(图片渲染失败)', style: TextStyle(fontSize: 12)),
          ),
        ),
      ),
    );
  }
}

// 鈹€鈹€ Image full view page (pinch-to-zoom) 鈹€鈹€
class _ImageFullViewPage extends StatelessWidget {
  final String dataUri;
  const _ImageFullViewPage({required this.dataUri});

  Uint8List? _decodeDataUri() {
    final commaIdx = dataUri.indexOf(',');
    if (commaIdx < 0) return null;
    try {
      return base64Decode(dataUri.substring(commaIdx + 1));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _decodeDataUri();
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: const Text('图片预览', style: TextStyle(fontSize: 15)),
      ),
      body: bytes == null
          ? Center(child: Text('(图片解码失败)', style: TextStyle(color: colors.error)))
          : InteractiveViewer(
              minScale: 0.2,
              maxScale: 8.0,
              child: Center(
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      Center(child: Text('(图片渲染失败)', style: TextStyle(color: colors.error))),
                ),
              ),
            ),
    );
  }
}
