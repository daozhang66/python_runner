import 'package:flutter/material.dart';
import 'package:python_runner/services/native_bridge.dart';

import '../../application/log/log_record.dart';
import '../../application/log/segmented_log_store.dart';
import '../../application/log/terminal_logs.dart';
import '../ssh_text.dart';
import '../widgets/log_record_tile.dart';

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// The three logs: terminal sessions, AI conversation and AI operations.
/// Each can be shown as a summary, standard or detailed, and exported or
/// deleted.
class TerminalLogsPage extends StatefulWidget {
  const TerminalLogsPage({super.key, this.initialChannel = LogChannel.terminal});

  final LogChannel initialChannel;

  @override
  State<TerminalLogsPage> createState() => _TerminalLogsPageState();
}

class _TerminalLogsPageState extends State<TerminalLogsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: LogChannel.values.length,
    vsync: this,
    initialIndex: widget.initialChannel.index,
  );
  int _level = 1;
  int _reload = 0;
  final Map<LogChannel, String?> _session = <LogChannel, String?>{
    for (final channel in LogChannel.values) channel: null,
  };

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  LogChannel get _channel => LogChannel.values[_tabs.index];

  String _label(SshText t, LogChannel channel) => switch (channel) {
        LogChannel.terminal => t('终端页', 'Terminal'),
        LogChannel.conversation => t('AI 对话', 'AI chat'),
        LogChannel.operations => t('AI 操作', 'AI operations'),
      };

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _export() async {
    final t = SshText.of(context);
    final channel = _channel;
    final jsonl = await showDialog<bool>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(t('导出${_label(t, channel)}日志', 'Export ${_label(t, channel)} log')),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              t(
                '可读文本（按当前详略级别）',
                'Readable text (at the current detail level)',
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              t(
                'JSON Lines（完整详细、便于程序处理）',
                'JSON Lines (full detail, machine readable)',
              ),
            ),
          ),
        ],
      ),
    );
    if (jsonl == null || !mounted) return;
    final store = await TerminalLogs.instance.store(channel);
    if (store == null) {
      if (mounted) _toast(t('日志目录不可用', 'The log directory is not available'));
      return;
    }
    final text = await store.exportText(
      maxImportance: jsonl ? 2 : _level,
      sessionId: _session[channel],
      jsonl: jsonl,
    );
    if (!mounted) return;
    if (text.trim().isEmpty) {
      _toast(t('没有可导出的内容', 'Nothing to export'));
      return;
    }
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    try {
      final path = await NativeBridge().exportLog(
        text,
        fileName:
            'pyrunner_${channel.dirName}_$stamp.${jsonl ? 'jsonl' : 'log'}',
      );
      if (!mounted) return;
      _toast(
        path.isEmpty
            ? t('已导出', 'Exported')
            : t('已导出到 $path', 'Exported to $path'),
      );
    } catch (e) {
      if (mounted) _toast('$e');
    }
  }

  Future<void> _delete() async {
    final t = SshText.of(context);
    final channel = _channel;
    final session = _session[channel];
    final scope = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(t('删除${_label(t, channel)}日志', 'Delete the ${_label(t, channel)} log')),
        children: [
          if (session != null)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'session'),
              child: Text(t('只删当前会话（$session）', 'Only this session ($session)')),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'old'),
            child: Text(t('删除 7 天前的记录', 'Delete records older than 7 days')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'all'),
            child: Text(t('全部删除', 'Delete everything')),
          ),
        ],
      ),
    );
    if (scope == null || !mounted) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('确认删除？', 'Delete?')),
        content: Text(t('删除后无法恢复。', 'This cannot be undone.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('删除', 'Delete')),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final store = await TerminalLogs.instance.store(channel);
    if (store == null) return;
    switch (scope) {
      case 'session':
        await store.deleteSession(session!);
      case 'old':
        await store.deleteBefore(
          DateTime.now().subtract(const Duration(days: 7)),
        );
      default:
        await store.deleteAll();
    }
    if (!mounted) return;
    setState(() {
      _session[channel] = null;
      _reload++;
    });
    _toast(t('已删除', 'Deleted'));
  }

  @override
  Widget build(BuildContext context) {
    final t = SshText.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t('日志', 'Logs')),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            for (final channel in LogChannel.values)
              Tab(text: _label(t, channel)),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'export':
                  await _export();
                case 'delete':
                  await _delete();
                case 'record':
                  await TerminalLogs.instance
                      .setRecordTerminal(!TerminalLogs.instance.recordTerminal);
                  if (mounted) setState(() {});
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'export', child: Text(t('导出…', 'Export…'))),
              PopupMenuItem(value: 'delete', child: Text(t('删除…', 'Delete…'))),
              if (_channel == LogChannel.terminal)
                CheckedPopupMenuItem(
                  value: 'record',
                  checked: TerminalLogs.instance.recordTerminal,
                  child: Text(t('记录终端输入输出', 'Record terminal input and output')),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                segments: [
                  ButtonSegment(value: 0, label: Text(t('简略', 'Summary'))),
                  ButtonSegment(value: 1, label: Text(t('标准', 'Standard'))),
                  ButtonSegment(value: 2, label: Text(t('详细', 'Detailed'))),
                ],
                selected: {_level},
                onSelectionChanged: (selection) =>
                    setState(() => _level = selection.first),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                switch (_level) {
                  0 => t('只显示每条记录的一句话摘要', 'One line per record'),
                  1 => t('精简显示：输出只显示前几行，AI 调用只显示关键项', 'Digest: output is cut to a few lines, AI calls show only the essentials'),
                  _ => t('完整显示：每次运行脚本的全部终端输出、完整 JSON、读取记录', 'Everything: all terminal output of every script run, full JSON, read records'),
                },
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                for (final channel in LogChannel.values)
                  _LogList(
                    key: ValueKey('${channel.name}-$_level-$_reload-${_session[channel]}'),
                    channel: channel,
                    level: _level,
                    sessionId: _session[channel],
                    onSession: (id) => setState(() => _session[channel] = id),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LogList extends StatefulWidget {
  const _LogList({
    super.key,
    required this.channel,
    required this.level,
    required this.sessionId,
    required this.onSession,
  });

  final LogChannel channel;
  final int level;
  final String? sessionId;
  final ValueChanged<String?> onSession;

  @override
  State<_LogList> createState() => _LogListState();
}

class _LogListState extends State<_LogList> {
  static const int _pageSize = 200;

  final ScrollController _scroll = ScrollController();
  final List<LogRecord> _records = <LogRecord>[];
  LogStats? _stats;
  bool _loading = true;
  bool _hasMore = true;
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) _load();
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_hasMore) return;
    final first = _records.isEmpty;
    final store = await TerminalLogs.instance.store(widget.channel);
    if (store == null) {
      if (mounted) {
        setState(() {
          _unavailable = true;
          _loading = false;
        });
      }
      return;
    }
    final page = await store.readPage(
      limit: _pageSize,
      beforeMicros: first ? null : _records.last.t,
      sessionId: widget.sessionId,
      maxImportance: widget.level,
    );
    final stats = first ? await store.stats() : _stats;
    if (!mounted) return;
    setState(() {
      _records.addAll(page);
      _hasMore = page.length >= _pageSize;
      _loading = false;
      _stats = stats;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = SshText.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_unavailable) {
      return Center(child: Text(t('日志目录不可用', 'The log directory is not available')));
    }
    final sessions = <String>{
      if (widget.sessionId != null) widget.sessionId!,
      for (final record in _records)
        if (record.sid.isNotEmpty) record.sid,
    }.toList();
    final stats = _stats;
    return Column(
      children: [
        if (stats != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                t(
                  '占用 ${_formatBytes(stats.bytes)}，${stats.segments} 个分片（已封存的分片用 gzip 压缩）',
                  '${_formatBytes(stats.bytes)} on disk, ${stats.segments} segments (sealed ones are gzip-compressed)',
                ),
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        if (sessions.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(t('全部', 'All')),
                    selected: widget.sessionId == null,
                    onSelected: (_) => widget.onSession(null),
                  ),
                ),
                for (final id in sessions)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(id),
                      selected: widget.sessionId == id,
                      onSelected: (_) => widget.onSession(id),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: _records.isEmpty
              ? Center(child: Text(t('还没有记录', 'No records yet')))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: _records.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _records.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return LogRecordTile(
                      record: _records[index],
                      level: widget.level,
                    );
                  },
                ),
        ),
      ],
    );
  }
}
