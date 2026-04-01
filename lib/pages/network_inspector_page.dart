import 'dart:convert';
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

    return Scaffold(
      body: Column(
        children: [
          // ── Top bar ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: colors.surfaceContainerHighest,
            child: Row(
              children: [
                const Icon(Icons.http, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '网络请求 (${records.length}/${_store.count})',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.filter_list, size: 20),
                  onPressed: () => _showFilterSheet(context),
                  tooltip: '筛选',
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.file_download_outlined, size: 20),
                  onPressed: records.isEmpty ? null : () => _showExportOptions(context),
                  tooltip: '导出',
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
          // ── Active filters ──
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
                    _FilterChip(label: '域名: ${_store.filterDomain}',
                        onRemove: () => _store.setFilterDomain('')),
                  if (_store.filterMethod.isNotEmpty)
                    _FilterChip(label: '方法: ${_store.filterMethod}',
                        onRemove: () => _store.setFilterMethod('')),
                  if (_store.filterStatus != null)
                    _FilterChip(
                        label: _store.filterStatus == 0
                            ? '状态: 错误'
                            : '状态: ${_store.filterStatus}xx',
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
          // ── Request list ──
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
                labelText: '域名 / URL 关键字',
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
        content: Text('已复制 ${_store.filteredRecords.length} 条请求记录到剪贴板'),
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
              title: const Text('导出为 HAR 文件'),
              subtitle: const Text('可被 Charles / Fiddler 等工具导入'),
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
            content: Text('HAR 文件已导出: $path'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('HAR 导出失败: $e'),
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

// ── Record tile ──
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

// ── Filter chip ──
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

// ── Detail page ──
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
          // ── Overview ──
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
          // ── Request Headers ──
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
          // ── Response ──
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
              title: '响应体预览',
              icon: Icons.description_outlined,
              children: [
                _CodeBlock(
                  record.responseBodyPreview!.length > 200
                      ? '${record.responseBodyPreview!.substring(0, 200)}...'
                      : record.responseBodyPreview!,
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _BodyFullViewPage(
                          body: record.responseBodyPreview!,
                          title: '响应体',
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.open_in_full, size: 14),
                    label: const Text('查看完整内容', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ),
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

class _CodeBlock extends StatelessWidget {
  final String text;
  const _CodeBlock(this.text);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: SelectableText(
        text,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
      ),
    );
  }
}

// ── Full body view page with JSON formatting ──
class _BodyFullViewPage extends StatelessWidget {
  final String body;
  final String title;
  const _BodyFullViewPage({required this.body, required this.title});

  String _formatBody(String raw) {
    // Try to parse and pretty-print as JSON
    try {
      final decoded = jsonDecode(raw);
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(decoded);
    } catch (_) {
      return raw;
    }
  }

  bool _isJson(String raw) {
    try {
      jsonDecode(raw);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatted = _formatBody(body);
    final isJson = _isJson(body);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(title, style: const TextStyle(fontSize: 15)),
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
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: formatted));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
              );
            },
            tooltip: '复制',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            formatted,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.5),
          ),
        ),
      ),
    );
  }
}
