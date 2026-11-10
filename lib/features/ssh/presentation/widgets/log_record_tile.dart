import 'dart:convert';

import 'package:flutter/material.dart';

import '../../application/log/log_record.dart';
import '../ssh_text.dart';

/// One log record as a card-like row: what kind of event it is, who caused
/// it, the summary, and (depending on the detail level) a monospace block
/// with the output or arguments.
class LogRecordTile extends StatelessWidget {
  const LogRecordTile({super.key, required this.record, required this.level});

  final LogRecord record;
  final int level;

  static (String, IconData) _kind(SshText t, String k) => switch (k) {
        'cmd' => (t('命令', 'Command'), Icons.chevron_right),
        'out' => (t('输出', 'Output'), Icons.subject),
        'run' => (t('运行', 'Run'), Icons.play_arrow_outlined),
        'run_out' => (t('脚本输出', 'Script output'), Icons.subject),
        'run_err' => (t('脚本错误', 'Script error'), Icons.error_outline),
        'run_in' => (t('脚本输入', 'Script input'), Icons.keyboard_outlined),
        'session' => (t('会话', 'Session'), Icons.terminal),
        'mcp_toolCall' => (t('AI 调用', 'AI call'), Icons.build_outlined),
        'mcp_connect' => (t('AI 连接', 'AI connected'), Icons.login),
        'mcp_disconnect' => (t('AI 断开', 'AI disconnected'), Icons.logout),
        'mcp_server' => (t('服务', 'Service'), Icons.dns_outlined),
        'read' => (t('读取输出', 'Read output'), Icons.visibility_outlined),
        'open' => (t('打开终端', 'Open terminal'), Icons.add_box_outlined),
        'close' => (t('关闭终端', 'Close terminal'), Icons.close),
        'message' => (t('AI 留言', 'AI message'), Icons.chat_bubble_outline),
        'msg' => (t('消息', 'Message'), Icons.chat_bubble_outline),
        'inbox' => (t('读取留言', 'Read messages'), Icons.inbox_outlined),
        'control' => (t('控制', 'Control'), Icons.tune),
        'denied' => (t('已拒绝', 'Refused'), Icons.block),
        _ => (k, Icons.circle_outlined),
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = SshText.of(context);
    final time = record.time;
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
    final color = switch (record.a) {
      'human' => scheme.primary,
      'ai' => scheme.tertiary,
      _ => scheme.outline,
    };
    final who = switch (record.a) {
      'human' => t('你', 'You'),
      'ai' => 'AI',
      _ => t('系统', 'System'),
    };
    final (label, icon) = _kind(t, record.k);
    final isError = record.k == 'run_err' || record.k == 'denied';
    final isCommand = record.k == 'cmd';
    final detail = visibleLogDetail(record, level);
    final extra = level >= 2 && record.x != null && record.x!.isNotEmpty
        ? jsonEncode(record.x)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 36,
            margin: const EdgeInsets.only(right: 8, top: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon,
                        size: 13, color: isError ? scheme.error : color),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isError ? scheme.error : color,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '$who${record.sid.isEmpty ? '' : ' · ${record.sid}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: scheme.outline),
                      ),
                    ),
                    Text(
                      stamp,
                      style: TextStyle(fontSize: 10.5, color: scheme.outline),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                SelectableText(
                  isCommand ? '\$ ${record.s}' : record.s,
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: isCommand ? 'monospace' : null,
                    fontWeight: record.i == 0 ? FontWeight.w600 : FontWeight.w400,
                    color: isError ? scheme.error : null,
                  ),
                ),
                if (detail != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isError
                          ? scheme.errorContainer.withValues(alpha: 0.45)
                          : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      detail,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        fontFamily: 'monospace',
                        color: isError
                            ? scheme.onErrorContainer
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (extra != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: SelectableText(
                      extra,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontFamily: 'monospace',
                        color: scheme.outline,
                      ),
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
