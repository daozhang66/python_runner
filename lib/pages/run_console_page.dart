import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/execution_provider.dart';
import '../models/log_entry.dart';
import '../models/execution_state.dart';
import '../providers/script_provider.dart';
import '../utils/ansi_parser.dart';

class RunConsolePage extends StatefulWidget {
  final String scriptName;
  const RunConsolePage({super.key, required this.scriptName});

  @override
  State<RunConsolePage> createState() => _RunConsolePageState();
}

class _RunConsolePageState extends State<RunConsolePage> with WidgetsBindingObserver {
  final _scrollController = ScrollController();
  final _hScrollController = ScrollController(); // 水平滚动
  final _stdinController = TextEditingController();
  final _stdinFocusNode = FocusNode();
  bool _autoScroll = true;
  int _lastLogCount = 0;
  bool _lastWaiting = false;
  double _fontSize = 13.0; // 字体缩放

  static const double _fontSizeMin = 9.0;
  static const double _fontSizeMax = 22.0;
  static const double _fontSizeStep = 1.0;

  String get _displayName => widget.scriptName.replaceAll('.py', '');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    // 页面打开时滚到底部
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  @override
  void didChangeMetrics() {
    // 键盘弹出/收起会触发此回调，自动滚到底部
    if (_autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final atBottom = pos.pixels >= pos.maxScrollExtent - 60;
    if (_autoScroll != atBottom) {
      setState(() => _autoScroll = atBottom);
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  void _submitStdin(ExecutionProvider exec) {
    final input = _stdinController.text;
    _stdinController.clear();
    exec.sendStdin(input);
    // 提交输入后强制恢复自动滚动，确保新输出能自动跟踪
    setState(() => _autoScroll = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
      if (mounted && _stdinFocusNode.canRequestFocus) {
        _stdinFocusNode.requestFocus();
      }
    });
  }

  Future<void> _rerun() async {
    try {
      final exec = context.read<ExecutionProvider>();
      final scriptProvider = context.read<ScriptProvider>();
      await scriptProvider.incrementRunCount(widget.scriptName);
      exec.clearLogs();
      await exec.executeScript(widget.scriptName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('运行失败: $e'), duration: const Duration(seconds: 3)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final exec = context.watch<ExecutionProvider>();
    final logs = exec.logs;
    final isRunning = exec.isRunning && exec.currentScriptName == widget.scriptName;
    final waiting = exec.waitingForInput;

    // Auto-scroll on new logs (use two-frame delay to ensure ListView layout is complete)
    if (_autoScroll && logs.length > _lastLogCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    }
    _lastLogCount = logs.length;

    // 等待输入状态变化时（新一轮交互），强制滚到底部
    if (waiting != _lastWaiting) {
      _lastWaiting = waiting;
      _autoScroll = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    }

    // Auto-focus input field when waiting
    if (waiting) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _stdinFocusNode.canRequestFocus && !_stdinFocusNode.hasFocus) {
          _stdinFocusNode.requestFocus();
        }
      });
    }

    final statusColor = isRunning
        ? Colors.greenAccent
        : (exec.state.status == ExecutionStatus.error
            ? Colors.redAccent
            : Colors.grey);
    final statusText = isRunning
        ? (waiting ? '等待输入' : '运行中')
        : (exec.state.status == ExecutionStatus.error ? '错误' : '已结束');

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
                boxShadow: isRunning
                    ? [BoxShadow(color: statusColor.withValues(alpha: 0.5), blurRadius: 6)]
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _displayName,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                statusText,
                style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        actions: [
          if (isRunning)
            IconButton(
              icon: const Icon(Icons.stop_rounded, color: Colors.redAccent, size: 22),
              onPressed: () => exec.stopExecution(),
              tooltip: '停止',
            )
          else
            IconButton(
              icon: const Icon(Icons.replay_rounded, color: Colors.greenAccent, size: 22),
              onPressed: _rerun,
              tooltip: '重新运行',
            ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 20),
            onPressed: logs.isEmpty
                ? null
                : () {
                    final text = logs.map((e) => AnsiParser.strip(e.content)).join('\n');
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('已复制 ${logs.length} 条日志'),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
            tooltip: '复制日志',
          ),
          // 字体缩小
          IconButton(
            icon: const Icon(Icons.text_decrease_rounded, size: 19),
            onPressed: _fontSize <= _fontSizeMin
                ? null
                : () => setState(() => _fontSize =
                    (_fontSize - _fontSizeStep).clamp(_fontSizeMin, _fontSizeMax)),
            tooltip: '缩小字体',
          ),
          // 字体放大
          IconButton(
            icon: const Icon(Icons.text_increase_rounded, size: 19),
            onPressed: _fontSize >= _fontSizeMax
                ? null
                : () => setState(() => _fontSize =
                    (_fontSize + _fontSizeStep).clamp(_fontSizeMin, _fontSizeMax)),
            tooltip: '放大字体',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            onPressed: logs.isEmpty ? null : () => exec.clearLogs(),
            tooltip: '清空',
          ),
        ],
      ),
      body: Column(
        children: [
          // === Terminal output area ===
          Expanded(
            child: logs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isRunning ? Icons.terminal : Icons.code_off,
                          size: 48,
                          color: Colors.white12,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          isRunning ? '等待输出...' : '暂无输出',
                          style: const TextStyle(color: Colors.white24, fontSize: 14),
                        ),
                      ],
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      // 水平滚动包裹整个 ListView，保证长行不折行
                      return SingleChildScrollView(
                        controller: _hScrollController,
                        scrollDirection: Axis.horizontal,
                        // 内容宽度：至少填满屏幕，超长内容可横向滚动
                        child: SizedBox(
                          width: _terminalContentWidth(constraints.maxWidth, logs),
                          child: Scrollbar(
                            controller: _scrollController,
                            thumbVisibility: true,
                            child: ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                              itemCount: logs.length,
                              itemBuilder: (context, index) =>
                                  _buildLogLine(logs[index]),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // === Scroll-to-bottom hint ===
          if (!_autoScroll && logs.isNotEmpty)
            GestureDetector(
              onTap: () {
                setState(() => _autoScroll = true);
                _scrollToBottom();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6),
                color: const Color(0xFF1F6FEB).withValues(alpha: 0.25),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.arrow_downward, size: 14, color: Colors.white60),
                    SizedBox(width: 4),
                    Text('新输出，点击回到底部',
                        style: TextStyle(color: Colors.white60, fontSize: 12)),
                  ],
                ),
              ),
            ),

          // === Input area ===
          if (isRunning || waiting)
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                border: Border(
                  top: BorderSide(
                    color: waiting
                        ? Colors.greenAccent.withValues(alpha: 0.6)
                        : Colors.white10,
                    width: waiting ? 2 : 1,
                  ),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: waiting
                              ? Colors.greenAccent.withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '>',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: waiting ? Colors.greenAccent : const Color(0x33FFFFFF),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _stdinController,
                          focusNode: _stdinFocusNode,
                          enabled: waiting,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                            color: Colors.white,
                          ),
                          cursorColor: Colors.greenAccent,
                          decoration: InputDecoration(
                            hintText: waiting ? '请输入...' : '等待脚本请求输入...',
                            hintStyle: TextStyle(
                              color: waiting ? Colors.white30 : Colors.white10,
                              fontSize: 13,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                          ),
                          onSubmitted: waiting ? (_) => _submitStdin(exec) : null,
                        ),
                      ),
                      if (waiting)
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _submitStdin(exec),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              child: const Icon(Icons.send_rounded,
                                  size: 20, color: Colors.greenAccent),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLogLine(LogEntry log) {
    Color defaultColor;
    switch (log.type) {
      case LogType.stderr:
      case LogType.error:
        defaultColor = const Color(0xFFFF6B6B);
        break;
      case LogType.info:
        defaultColor = const Color(0xFF58A6FF);
        break;
      case LogType.stdout:
        defaultColor = const Color(0xFFE6EDF3);
        break;
    }

    final spans = AnsiParser.parse(log.content, defaultColor: defaultColor);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0.5),
      child: SelectableText.rich(
        TextSpan(
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: _fontSize,
            height: 1.5,
          ),
          children: spans,
        ),
        // 不换行，保持终端格式对齐（水平滚动由外层 SingleChildScrollView 处理）
        maxLines: 1,
      ),
    );
  }

  /// 估算终端内容区域的水平宽度。
  /// 取最长行的字符数 × 每字符宽度，最小保证不小于屏幕宽度。
  double _terminalContentWidth(double screenWidth, List<LogEntry> logs) {
    if (logs.isEmpty) return screenWidth;
    // 用当前字号估算等宽字体字符宽度（约 0.6 倍字号）
    final charWidth = _fontSize * 0.6;
    int maxLen = 0;
    for (final log in logs) {
      final len = AnsiParser.strip(log.content).length;
      if (len > maxLen) maxLen = len;
    }
    // 加上左右 padding (28px) 和少量余量
    final contentWidth = maxLen * charWidth + 28 + 40;
    return contentWidth > screenWidth ? contentWidth : screenWidth;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _hScrollController.dispose();
    _stdinController.dispose();
    _stdinFocusNode.dispose();
    super.dispose();
  }
}
