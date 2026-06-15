import 'dart:async';
import 'package:flutter/material.dart';
import '../services/native_bridge.dart';

/// 运行引擎管理页面
///
/// 用于安装、修复 Linux-like 运行引擎
class RuntimeManagerPage extends StatefulWidget {
  const RuntimeManagerPage({super.key});

  @override
  State<RuntimeManagerPage> createState() => _RuntimeManagerPageState();
}

class _RuntimeManagerPageState extends State<RuntimeManagerPage> {
  final _bridge = NativeBridge();
  bool _installing = false;
  bool _available = false;
  String _installStage = '';
  int _installPercent = 0;
  String _installMessage = '';
  StreamSubscription? _installProgressSub;

  @override
  void initState() {
    super.initState();
    _checkAvailability();
  }

  @override
  void dispose() {
    _installProgressSub?.cancel();
    super.dispose();
  }

  Future<void> _checkAvailability() async {
    try {
      final info = await _bridge.getLinuxLikeRuntimeInfo();
      if (mounted) {
        setState(() {
          _available = info['available'] == 'true';
        });
      }
    } catch (e) {
      // Ignore
    }
  }

  Future<void> _installRuntime() async {
    if (_installing) return;

    setState(() {
      _installing = true;
      _installStage = '';
      _installPercent = 0;
      _installMessage = '';
    });

    _installProgressSub = _bridge.installProgressStream.listen((event) {
      if (mounted) {
        setState(() {
          _installStage = event['stage']?.toString() ?? '';
          _installPercent = (event['percent'] as num?)?.toInt() ?? 0;
          _installMessage = event['message']?.toString() ?? '';
        });
      }
    });

    try {
      await _bridge.prepareLinuxLikeRuntime();
      const manifestUrl =
          'https://github.com/daozhangXDZ/PythonRunner/releases/download/v1.4.0/linux-like-runtime-manifest.json';
      await _bridge.installLinuxLikeRuntime(manifestUrl: manifestUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Linux-like 运行引擎安装成功')),
        );
        await _checkAvailability();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('安装失败: $e')),
        );
      }
    } finally {
      await _installProgressSub?.cancel();
      _installProgressSub = null;
      if (mounted) {
        setState(() => _installing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('管理引擎'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 状态卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _available ? Icons.check_circle : Icons.info_outline,
                        color: _available ? Colors.green : colors.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _available
                              ? 'Linux-like 运行引擎已安装'
                              : 'Linux-like 运行引擎未安装',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!_available) ...[
                    const SizedBox(height: 12),
                    Text(
                      '需要下载约 104MB 的 Debian + Python + pip + build-essential 环境包',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 安装/修复按钮
          if (_installing)
            _InstallProgressCard(
              stage: _installStage,
              percent: _installPercent,
              message: _installMessage,
            )
          else
            FilledButton.icon(
              onPressed: _installRuntime,
              icon: const Icon(Icons.download),
              label: Text(_available ? '修复运行引擎' : '安装运行引擎'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),

          const SizedBox(height: 24),

          // 说明
          Text(
            '关于 Linux-like 运行引擎',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Linux-like 运行引擎是一个实验性运行环境，提供完整的 Linux 环境，'
            '支持更多 Python 包和工具。\n\n'
            '• 包含 Debian 基础系统\n'
            '• 预装 Python 3 和 pip\n'
            '• 支持编译原生扩展\n'
            '• 更好的兼容性',
            style: TextStyle(
              fontSize: 13,
              color: colors.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// 安装进度卡片
class _InstallProgressCard extends StatelessWidget {
  final String stage;
  final int percent;
  final String message;

  const _InstallProgressCard({
    required this.stage,
    required this.percent,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              stage.isNotEmpty ? stage : '准备中...',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: percent > 0 ? percent / 100 : null,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Text(
              message.isNotEmpty ? message : '正在处理...',
              style: TextStyle(
                fontSize: 12,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
