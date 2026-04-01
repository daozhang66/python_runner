import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/execution_provider.dart';
import '../models/execution_state.dart';
import '../widgets/log_viewer.dart';

class ConsolePage extends StatelessWidget {
  const ConsolePage({super.key});

  @override
  Widget build(BuildContext context) {
    final execProvider = context.watch<ExecutionProvider>();
    final history = execProvider.logHistory;

    return Scaffold(
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                const Icon(Icons.history, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '运行记录 (${history.length})',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
                // Export: save to Downloads
                IconButton(
                  icon: const Icon(Icons.file_download_outlined, size: 20),
                  onPressed: history.isEmpty
                      ? null
                      : () => _showExportDialog(context, execProvider),
                  tooltip: '导出日志',
                  visualDensity: VisualDensity.compact,
                ),
                // Copy: select which to copy
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: history.isEmpty
                      ? null
                      : () => _showCopyDialog(context, execProvider),
                  tooltip: '复制日志',
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: history.isEmpty ? null : () => execProvider.clearHistory(),
                  tooltip: '清除全部',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Expanded(
            child: history.isEmpty
                ? const Center(child: Text('暂无运行记录', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: history.length,
                    itemBuilder: (context, index) {
                      final record = history[history.length - 1 - index];
                      final realIndex = history.length - 1 - index;
                      return _LogRecordTile(
                        record: record,
                        onTap: () => _openLogDetail(context, record),
                        onDelete: () => execProvider.removeHistoryRecord(realIndex),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _openLogDetail(BuildContext context, ScriptLogRecord record) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _LogDetailPage(record: record)),
    );
  }

  /// Show dialog to select which logs to export
  void _showExportDialog(BuildContext context, ExecutionProvider provider) {
    final history = provider.logHistory;
    final selected = List<bool>.filled(history.length, true);
    final timeFmt = DateFormat('MM-dd HH:mm:ss');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('选择要导出的日志'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setDialogState(() {
                        for (int i = 0; i < selected.length; i++) selected[i] = true;
                      }),
                      child: const Text('全选'),
                    ),
                    TextButton(
                      onPressed: () => setDialogState(() {
                        for (int i = 0; i < selected.length; i++) selected[i] = false;
                      }),
                      child: const Text('取消全选'),
                    ),
                  ],
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: history.length,
                    itemBuilder: (_, i) {
                      final idx = history.length - 1 - i;
                      final r = history[idx];
                      return CheckboxListTile(
                        dense: true,
                        value: selected[idx],
                        onChanged: (v) => setDialogState(() => selected[idx] = v ?? false),
                        title: Text(r.scriptName, style: const TextStyle(fontSize: 14)),
                        subtitle: Text(timeFmt.format(r.startTime), style: const TextStyle(fontSize: 11)),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _doSaveToDevice(context, provider, selected);
              },
              child: const Text('保存到设备'),
            ),
          ],
        ),
      ),
    );
  }

  /// Save logs to device's Download directory
  Future<void> _doSaveToDevice(BuildContext context, ExecutionProvider provider, List<bool> selected) async {
    final history = provider.logHistory;
    final dateFmt = DateFormat('yyyy-MM-dd_HH-mm-ss');

    try {
      const channel = MethodChannel('com.daozhang.py/native_bridge');

      // Merge all selected logs into one file
      final buffer = StringBuffer();
      int count = 0;
      for (int i = 0; i < history.length; i++) {
        if (!selected[i]) continue;
        final record = history[i];
        if (count > 0) buffer.write('\n\n${'=' * 60}\n\n');
        buffer.write('脚本: ${record.scriptName}\n');
        buffer.write('时间: ${dateFmt.format(record.startTime)}\n');
        buffer.write('${'─' * 40}\n');
        buffer.write(record.logsAsText);
        count++;
      }

      if (count == 0) return;

      final content = buffer.toString();
      final fileName = 'python_logs_${dateFmt.format(DateTime.now())}.log';

      final path = await channel.invokeMethod('exportLog', {
        'content': content,
        'fileName': fileName,
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已保存 $count 条日志到: $path'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Show dialog to select which log to copy
  void _showCopyDialog(BuildContext context, ExecutionProvider provider) {
    final history = provider.logHistory;
    final timeFmt = DateFormat('MM-dd HH:mm:ss');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择要复制的日志'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: history.length + 1, // +1 for "copy all"
            itemBuilder: (_, i) {
              if (i == 0) {
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.select_all, size: 20),
                  title: const Text('复制全部'),
                  onTap: () {
                    Navigator.pop(ctx);
                    final text = history.map((r) => r.logsAsText).join('\n\n');
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('已复制全部 ${history.length} 条记录'),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                );
              }
              final idx = history.length - i;
              final r = history[idx];
              return ListTile(
                dense: true,
                title: Text(r.scriptName, style: const TextStyle(fontSize: 14)),
                subtitle: Text('${timeFmt.format(r.startTime)}  ${r.logs.length} 条',
                    style: const TextStyle(fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: r.logsAsText));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已复制 ${r.scriptName} 的日志'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ],
      ),
    );
  }
}

class _LogRecordTile extends StatelessWidget {
  final ScriptLogRecord record;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _LogRecordTile({
    required this.record,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat('MM-dd HH:mm:ss');
    final isRunning = record.status == ExecutionStatus.running;
    final isStopping = record.status == ExecutionStatus.stopping;
    final isError = record.status == ExecutionStatus.error;

    final statusIcon = isRunning
        ? const Icon(Icons.circle, size: 10, color: Colors.green)
        : isStopping
            ? const Icon(Icons.hourglass_bottom, size: 14, color: Colors.orange)
            : isError
                ? Icon(Icons.error_outline, size: 14, color: Theme.of(context).colorScheme.error)
                : Icon(Icons.check_circle_outline, size: 14, color: Colors.green.shade700);

    final statusText = isRunning
        ? '运行中'
        : isStopping
            ? '正在停止...'
            : isError
                ? '错误'
                : '完成 (exit: ${record.exitCode ?? "-"})';

    return ListTile(
      leading: statusIcon,
      title: Text(record.scriptName, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        '${timeFmt.format(record.startTime)}  $statusText  ${record.logs.length} 条日志',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: IconButton(
        icon: Icon(Icons.delete_outline, size: 18, color: Theme.of(context).colorScheme.error),
        onPressed: onDelete,
        visualDensity: VisualDensity.compact,
      ),
      onTap: onTap,
    );
  }
}

class _LogDetailPage extends StatelessWidget {
  final ScriptLogRecord record;
  const _LogDetailPage({required this.record});

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    return Scaffold(
      appBar: AppBar(
        title: Text(record.scriptName),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              final text = record.logs.map((e) => e.content).join('\n');
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('已复制 ${record.logs.length} 条日志'),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
            tooltip: '复制日志',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Text(
                  '${timeFmt.format(record.startTime)}  ${record.logs.length} 条日志',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(
            child: LogViewer(logs: record.logs),
          ),
        ],
      ),
    );
  }
}
