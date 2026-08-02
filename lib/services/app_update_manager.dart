import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/download_progress.dart';
import '../widgets/update_dialog.dart';
import 'app_logger.dart';
import 'http_inspector_store.dart';
import 'native_bridge.dart';
import 'network_debug_config.dart';
import 'update_service.dart';

class AppUpdateManager {
  static const String _autoCheckEnabledKey = 'app_update_auto_check_enabled';
  static const String _dismissedVersionKey = 'app_update_dismissed_version';

  final NativeBridge _bridge;
  final UpdateService _updateService;

  AppUpdateManager({
    NativeBridge? bridge,
    UpdateService? updateService,
  })  : _bridge = bridge ?? NativeBridge(),
        _updateService = updateService ?? UpdateService();

  Future<bool> isAutoCheckEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoCheckEnabledKey) ?? true;
  }

  Future<void> setAutoCheckEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoCheckEnabledKey, enabled);
  }

  Future<void> checkForUpdates(
    BuildContext context, {
    required bool manual,
  }) async {
    if (!manual) {
      if (!await isAutoCheckEnabled()) return;
    }

    try {
      final appInfo = await _bridge.getAppInfo();
      final currentVersion = appInfo['version'] ?? '0.0.0';
      final updateInfo = await _updateService.fetchLatestRelease(
        currentVersion: currentVersion,
      );

      if (!context.mounted) return;

      if (!updateInfo.hasUpdate) {
        if (manual) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('当前已是最新版本：${updateInfo.currentVersion}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      if (!manual) {
        final prefs = await SharedPreferences.getInstance();
        final dismissedVersion = prefs.getString(_dismissedVersionKey) ?? '';
        if (dismissedVersion == updateInfo.latestVersion) {
          return;
        }
      }

      if (!context.mounted) return;
      await _showUpdateDialog(
        context,
        updateInfo,
        rememberDismissal: !manual,
      );
    } catch (error, stackTrace) {
      AppLogger.instance.warn(
        'Update check failed: $error',
        source: 'AppUpdateManager',
        detail: stackTrace.toString(),
      );
      if (manual && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('检查更新失败：${_formatError(error)}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _showUpdateDialog(
    BuildContext context,
    AppUpdateInfo updateInfo, {
    required bool rememberDismissal,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => UpdateDialog(
        updateInfo: updateInfo,
        onUpdate: () async {
          if (dialogContext.mounted) {
            Navigator.pop(dialogContext);
          }
          if (updateInfo.apkAsset == null) {
            await _bridge.openUrl(updateInfo.htmlUrl);
            return;
          }
          await _downloadAndInstallUpdate(context, updateInfo);
        },
        onIgnore: rememberDismissal
            ? () async {
                await _rememberDismissedVersion(updateInfo.latestVersion);
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              }
            : null,
      ),
    );
  }

  Future<void> _downloadAndInstallUpdate(
    BuildContext context,
    AppUpdateInfo updateInfo,
  ) async {
    final asset = updateInfo.apkAsset;
    if (asset == null) return;

    // SECURITY: Block auto-install when global network debug hooks affect updates.
    final netDebugConfig = NetworkDebugConfig.instance;
    if (netDebugConfig.affectsGlobalHttpClients) {
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('安全警告'),
          content: const Text(
            '当前已启用网络代理或"允许不安全证书"调试选项。\n\n'
            '在此模式下无法自动安装更新，以防止调试代理或中间人攻击影响更新链路。\n'
            '请先关闭网络调试或手动下载验证。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _bridge.openUrl(updateInfo.htmlUrl);
              },
              child: const Text('打开 Release 页面'),
            ),
          ],
        ),
      );
      return;
    }

    // SECURITY: Require SHA-256 checksum for automatic installation
    final assetSha256 = asset.sha256;
    if (assetSha256 == null || assetSha256.isEmpty) {
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('安全警告'),
          content: const Text(
            '该版本缺少完整性校验信息（SHA-256）。\n\n'
            '为了安全，无法自动安装此更新。\n'
            '您可以访问 GitHub Release 页面手动下载并验证。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _bridge.openUrl(updateInfo.htmlUrl);
              },
              child: const Text('打开 Release 页面'),
            ),
          ],
        ),
      );
      return;
    }

    await HttpInspectorStore.instance.flush();

    // Apply GitHub mirror prefix if configured
    final prefs = await SharedPreferences.getInstance();
    final mirrorPrefix = prefs.getString('github_mirror_prefix') ?? '';
    final downloadUrl = mirrorPrefix.isNotEmpty
        ? '$mirrorPrefix${asset.downloadUrl}'
        : asset.downloadUrl;

    final progressNotifier = ValueNotifier<double>(0.0);
    final progressTextNotifier = ValueNotifier<String>('准备下载...');
    final statusTitleNotifier =
        ValueNotifier<String>('正在下载 v${updateInfo.latestVersion}');
    final finished = Completer<void>();
    String? taskId;
    StreamSubscription<Map<dynamic, dynamic>>? progressSub;
    var dialogOpen = false;

    void completeOnce() {
      if (!finished.isCompleted) {
        finished.complete();
      }
    }

    void closeDialog() {
      if (dialogOpen && context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      dialogOpen = false;
    }

    if (!context.mounted) return;
    dialogOpen = true;

    // 显示下载对话框
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (progressContext) => AlertDialog(
        title: const Center(child: Text('更新')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<String>(
              valueListenable: statusTitleNotifier,
              builder: (_, text, __) => Text(text),
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<double>(
              valueListenable: progressNotifier,
              builder: (_, value, __) => LinearProgressIndicator(
                value: value > 0 ? value : null,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<String>(
              valueListenable: progressTextNotifier,
              builder: (_, text, __) => Text(
                text,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              final id = taskId;
              if (id != null && id.isNotEmpty) {
                unawaited(_bridge.cancelDownload(id));
              }
              closeDialog();
              completeOnce();
            },
            child: const Text('取消'),
          ),
        ],
      ),
    ).then((_) {
      dialogOpen = false;
      completeOnce();
    }));

    try {
      progressSub = _bridge.downloadProgressStream.listen((event) {
        final progress = DownloadProgress.fromMap(event);
        if (progress.type != 'apk_update') return;
        final id = taskId;
        if (id != null && id.isNotEmpty && progress.taskId != id) return;
        // Dialog teardown drives completeOnce() when the context is gone.
        if (!context.mounted) return;
        _handleProgressEvent(
          context,
          updateInfo,
          progress,
          progressNotifier: progressNotifier,
          progressTextNotifier: progressTextNotifier,
          statusTitleNotifier: statusTitleNotifier,
          closeDialog: closeDialog,
          completeOnce: completeOnce,
        );
      });

      taskId = await _bridge.startApkDownload(
        downloadUrl,
        fileName: asset.name,
        version: updateInfo.latestVersion,
        sha256: assetSha256,
      );

      // The progress stream drives install/error/cancel handling; this future
      // completes once a terminal event (or the cancel button) fires.
      await finished.future;
    } catch (error) {
      if (context.mounted) {
        closeDialog();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Python Runner 更新失败：${_formatError(error)}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      completeOnce();
    } finally {
      await progressSub?.cancel();
      progressNotifier.dispose();
      progressTextNotifier.dispose();
      statusTitleNotifier.dispose();
    }
  }

  /// Handles a single native download-progress event: updates the dialog,
  /// and on terminal states triggers install / surfaces errors / closes.
  void _handleProgressEvent(
    BuildContext context,
    AppUpdateInfo updateInfo,
    DownloadProgress progress, {
    required ValueNotifier<double> progressNotifier,
    required ValueNotifier<String> progressTextNotifier,
    required ValueNotifier<String> statusTitleNotifier,
    required void Function() closeDialog,
    required void Function() completeOnce,
  }) {
    switch (progress.status) {
      case DownloadStatus.checking:
        statusTitleNotifier.value = '正在校验 v${updateInfo.latestVersion}';
        progressTextNotifier.value = '检查断点续传...';
        break;
      case DownloadStatus.pending:
      case DownloadStatus.downloading:
        statusTitleNotifier.value = '正在下载 v${updateInfo.latestVersion}';
        if (progress.totalBytes > 0) {
          progressNotifier.value = progress.progress >= 0
              ? progress.progress / 100
              : progress.downloadedBytes / progress.totalBytes;
          progressTextNotifier.value = _formatDownloadLine(progress);
        } else {
          progressNotifier.value = 0.0;
          progressTextNotifier.value = '正在下载...';
        }
        break;
      case DownloadStatus.retrying:
        statusTitleNotifier.value = '网络中断，正在重试 (${progress.retryCount})';
        progressTextNotifier.value =
            progress.errorMessage.isNotEmpty ? progress.errorMessage : '准备重试...';
        break;
      case DownloadStatus.completed:
        statusTitleNotifier.value = '下载完成，正在打开安装器';
        progressNotifier.value = 1.0;
        unawaited(_installCompleted(
          context,
          taskId: progress.taskId,
          closeDialog: closeDialog,
          completeOnce: completeOnce,
        ));
        break;
      case DownloadStatus.failed:
        closeDialog();
        if (context.mounted) {
          final detail =
              progress.errorMessage.isNotEmpty ? progress.errorMessage : '请稍后重试';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Python Runner 更新失败：$detail'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        completeOnce();
        break;
      case DownloadStatus.cancelled:
        closeDialog();
        completeOnce();
        break;
      case DownloadStatus.installPermissionRequired:
        // startApkDownload also throws (code 1011); the catch path reports it.
        break;
      case DownloadStatus.unknown:
        break;
    }
  }

  Future<void> _installCompleted(
    BuildContext context, {
    required String taskId,
    required void Function() closeDialog,
    required void Function() completeOnce,
  }) async {
    try {
      await _bridge.installDownloadedApk(taskId);
      if (context.mounted) {
        closeDialog();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('安装器已打开'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        closeDialog();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Python Runner 安装失败：${_formatError(error)}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      completeOnce();
    }
  }

  String _formatDownloadLine(DownloadProgress progress) {
    final received = _formatByteSize(progress.downloadedBytes);
    final total = _formatByteSize(progress.totalBytes);
    final pct = progress.progress >= 0 ? ' (${progress.progress}%)' : '';
    var line = '$received / $total$pct';
    if (progress.speedBytesPerSecond > 0) {
      line += ' · ${_formatByteSize(progress.speedBytesPerSecond)}/s';
    }
    if (progress.etaSeconds > 0) {
      line += ' · 剩余约 ${_formatEta(progress.etaSeconds)}';
    }
    return line;
  }

  String _formatByteSize(num bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex += 1;
    }
    return '${value.toStringAsFixed(unitIndex == 0 ? 0 : 1)} ${units[unitIndex]}';
  }

  String _formatEta(num seconds) {
    final totalSeconds = seconds.toInt();
    if (totalSeconds < 60) return '$totalSeconds 秒';
    final minutes = totalSeconds ~/ 60;
    final remainSeconds = totalSeconds % 60;
    if (remainSeconds == 0) return '$minutes 分钟';
    return '$minutes 分 $remainSeconds 秒';
  }

  Future<void> _rememberDismissedVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dismissedVersionKey, version);
  }

  String _formatError(Object error) {
    if (error is NativeBridgeException) {
      if (error.code == 1011) {
        return '请先允许安装未知来源应用，然后再次点击更新。';
      }
      return error.message;
    }
    return error.toString();
  }
}
