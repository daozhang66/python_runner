import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/execution_provider.dart';
import '../../console/presentation/pages/run_console_page.dart';
import '../../ssh/application/log/log_record.dart';
import '../../ssh/presentation/pages/terminal_hub_page.dart';
import '../../ssh/presentation/pages/terminal_logs_page.dart';
import '../../ssh/presentation/ssh_text.dart';
import '../application/mcp_server_controller.dart';
import '../application/mcp_terminal_service.dart';

/// The page where the person can do what [item] waits for: the terminal that
/// asks for a password, or the console of the script that waits for input.
Route<void> routeForAttention(AiAttention item) {
  return MaterialPageRoute<void>(
    builder: (_) => item.kind == 'script'
        ? RunConsolePage(scriptName: item.target)
        : TerminalHubPage(initialSessionId: item.target),
  );
}

/// Opens the AI chat: what the AI said to the person and what the person
/// wrote back, what waits for the person, and the controls for AI terminal
/// access.
Future<void> showAiChatSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const AiChatSheet(),
  );
}

class AiChatSheet extends ConsumerStatefulWidget {
  const AiChatSheet({super.key});

  @override
  ConsumerState<AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends ConsumerState<AiChatSheet> {
  final TextEditingController _controller = TextEditingController();
  ExecutionProvider? _execution;

  @override
  void initState() {
    super.initState();
    final service = ref.read(mcpTerminalServiceProvider);
    service.loadSettings();
    try {
      _execution = ref.read(mcpExecutionOwnerProvider);
    } catch (_) {
      // No app execution attached (widget tests): no running-script row.
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => service.markSeen());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send(McpTerminalService service) {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    service.userSay(text);
    _controller.clear();
  }

  /// Leaves the sheet and opens [route] on the app's navigator.
  void _goTo(Route<void> route) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(route);
  }

  void _openAttention(AiAttention item) {
    item.opened = true;
    _goTo(routeForAttention(item));
  }

  Widget _buildNow(McpTerminalService service, SshText t) {
    final scheme = Theme.of(context).colorScheme;
    final items = service.attention;
    final execution = _execution;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Column(
        children: [
          for (final item in items)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    item.kind == 'script' ? Icons.keyboard_outlined : Icons.password,
                    size: 18,
                    color: scheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.text,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _openAttention(item),
                    child: Text(t('去输入', 'Open')),
                  ),
                ],
              ),
            ),
          if (execution != null)
            ListenableBuilder(
              listenable: execution,
              builder: (context, _) {
                final name = execution.currentScriptName;
                final announced = items
                    .any((i) => i.kind == 'script' && i.target == name);
                if (!execution.isRunning || name == null || announced) {
                  return const SizedBox.shrink();
                }
                return Row(
                  children: [
                    const Icon(Icons.play_circle_outline, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t('正在运行：$name', 'Running: $name'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _goTo(
                        MaterialPageRoute<void>(
                          builder: (_) => RunConsolePage(scriptName: name),
                        ),
                      ),
                      child: Text(t('查看控制台', 'Console')),
                    ),
                  ],
                );
              },
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _goTo(
                MaterialPageRoute<void>(
                  builder: (_) => const TerminalHubPage(),
                ),
              ),
              icon: const Icon(Icons.terminal, size: 18),
              label: Text(t('打开终端页', 'Open terminals')),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(mcpTerminalServiceProvider);
    final scheme = Theme.of(context).colorScheme;
    final t = SshText.of(context);
    final thread = service.thread;
    if (service.unreadCount > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => service.markSeen());
    }
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
              child: Row(
                children: [
                  Icon(Icons.smart_toy_outlined, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t('AI 对话', 'AI chat'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: service.paused
                        ? t('恢复 AI 使用终端', 'Resume AI terminal access')
                        : t('暂停 AI 使用终端', 'Pause AI terminal access'),
                    icon: Icon(
                      service.paused
                          ? Icons.play_circle_outline
                          : Icons.pause_circle_outline,
                      color: service.paused ? scheme.error : null,
                    ),
                    onPressed: () => service.setPaused(!service.paused),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'confirm':
                          service.setConfirmEach(!service.confirmEach);
                        case 'log':
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const TerminalLogsPage(
                                initialChannel: LogChannel.conversation,
                              ),
                            ),
                          );
                        case 'ops':
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const TerminalLogsPage(
                                initialChannel: LogChannel.operations,
                              ),
                            ),
                          );
                        case 'clear':
                          service.clearThread();
                      }
                    },
                    itemBuilder: (context) => [
                      CheckedPopupMenuItem<String>(
                        value: 'confirm',
                        checked: service.confirmEach,
                        child: Text(t('AI 发每条命令前先问我', 'Ask me before each AI command')),
                      ),
                      PopupMenuItem<String>(
                        value: 'log',
                        child: Text(t('查看对话日志', 'Conversation log')),
                      ),
                      PopupMenuItem<String>(
                        value: 'ops',
                        child: Text(t('查看 AI 操作日志', 'AI operations log')),
                      ),
                      PopupMenuItem<String>(
                        value: 'clear',
                        child: Text(t('清空这里的对话', 'Clear this chat')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (service.paused)
              Container(
                width: double.infinity,
                color: scheme.errorContainer,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text(
                  t('AI 的终端访问已暂停，它的终端工具会被拒绝。', 'AI terminal access is paused; its terminal tools are refused.'),
                  style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
                ),
              ),
            _buildNow(service, t),
            Expanded(
              child: thread.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          t(
                            'AI 通过 MCP 给你留言时会出现在这里。终端或脚本在等你输入（比如密码）时，上面会出现「去输入」，从别的 App 切回来也会自动带你过去。\n平时直接在你的 AI 对话 App 里跟它说就行。',
                            'Messages the AI leaves over MCP appear here. When a terminal or script waits for you (a password, for example) an "Open" button shows up above, and switching back from another app takes you there.\nUsually you can simply talk to the AI in your AI app.',
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      itemCount: thread.length,
                      itemBuilder: (context, index) {
                        final entry = thread[thread.length - 1 - index];
                        return _Bubble(entry: entry);
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: t('给 AI 留言…', 'Write to the AI…'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    tooltip: t('发送', 'Send'),
                    icon: const Icon(Icons.send),
                    onPressed: () => _send(service),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.entry});

  final AiChatEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (entry.system) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.tertiaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            entry.text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.onTertiaryContainer),
          ),
        ),
      );
    }
    final time = entry.time;
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${two(time.hour)}:${two(time.minute)}';
    return Align(
      alignment: entry.fromAi ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: entry.fromAi
              ? scheme.surfaceContainerHighest
              : scheme.primaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(entry.text),
            const SizedBox(height: 2),
            Text(
              stamp,
              style: TextStyle(fontSize: 10, color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
