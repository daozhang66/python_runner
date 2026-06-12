import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      builder: (dialogContext) => AlertDialog(
        title: const Text('发现新版本'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('当前版本：${updateInfo.currentVersion}'),
                const SizedBox(height: 4),
                Text('最新版本：${updateInfo.latestVersion}'),
                if (updateInfo.publishedAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '发布时间：${DateFormat('yyyy-MM-dd HH:mm').format(updateInfo.publishedAt!.toLocal())}',
                  ),
                ],
                const SizedBox(height: 12),
                const Text(
                  '更新说明',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 240),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(dialogContext)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    updateInfo.releaseNotes.trim().isEmpty
                        ? '当前发布没有填写更新说明。'
                        : updateInfo.releaseNotes.trim(),
                    style: const TextStyle(fontSize: 12, height: 1.45),
                  ),
                ),
                if (updateInfo.apkAsset == null) ...[
                  const SizedBox(height: 10),
                  Text(
                    '这个发布没有上传 APK 资源，将打开 GitHub Release 页面。',
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              if (rememberDismissal) {
                await _rememberDismissedVersion(updateInfo.latestVersion);
              }
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('稍后再说'),
          ),
          TextButton(
            onPressed: () async {
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
              await _bridge.openUrl(updateInfo.htmlUrl);
            },
            child: const Text('发布页'),
          ),
          FilledButton(
            onPressed: () async {
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
              if (updateInfo.apkAsset == null) {
                await _bridge.openUrl(updateInfo.htmlUrl);
                return;
              }
              await _downloadAndInstallUpdate(context, updateInfo);
            },
            child: Text(updateInfo.apkAsset == null ? '打开页面' : '立即更新'),
          ),
        ],
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
    final failedNotifier = ValueNotifier<bool>(false);
    final finished = Completer<void>();
    StreamSubscription? progressSub;
    String? taskId;
    var dialogOpen = false;
    var installStarted = false;

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

    Future<void> installCompletedTask(String completedTaskId) async {
      if (installStarted) return;
      installStarted = true;
      statusTitleNotifier.value = '下载完成，正在打开安装器';
      try {
        await _bridge.installDownloadedApk(completedTaskId);
        if (!context.mounted) return;
        closeDialog();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('安装器已打开'),
            duration: Duration(seconds: 2),
          ),
        );
        completeOnce();
      } catch (error) {
        installStarted = false;
        failedNotifier.value = true;
        statusTitleNotifier.value = '下载失败';
        progressTextNotifier.value = '安装失败：${_formatError(error)}';
      }
    }

    progressSub = _bridge.downloadProgressStream.listen((event) {
      final currentTaskId = event['taskId']?.toString() ?? '';
      if (taskId != null &&
          currentTaskId.isNotEmpty &&
          currentTaskId != taskId) {
        return;
      }

      final status = event['status']?.toString() ?? '';
      final progress = _eventInt(event, 'progress', -1);
      final downloaded = _eventLong(event, 'downloadedBytes', 0);
      final total = _eventLong(event, 'totalBytes', -1);
      final speed = _eventLong(event, 'speedBytesPerSecond', 0);
      final eta = _eventLong(event, 'etaSeconds', -1);

      if (progress >= 0 && total > 0) {
        progressNotifier.value = progress / 100.0;
        progressTextNotifier.value =
            '${_formatByteSize(downloaded)} / ${_formatByteSize(total)} ($progress%)'
            ' · ${_formatByteSize(speed)}/s'
            '${eta >= 0 ? ' · 剩余约 ${_formatEta(eta)}' : ''}';
      } else {
        progressNotifier.value = 0.0;
        progressTextNotifier.value = '正在下载...';
      }

      switch (status) {
        case 'checking':
          statusTitleNotifier.value = '准备下载 v${updateInfo.latestVersion}';
        case 'downloading':
          failedNotifier.value = false;
          statusTitleNotifier.value = '正在下载 v${updateInfo.latestVersion}';
        case 'retrying':
          statusTitleNotifier.value = '网络异常，正在重试';
        case 'failed':
          failedNotifier.value = true;
          statusTitleNotifier.value = '下载失败';
          progressTextNotifier.value =
              event['errorMessage']?.toString().isNotEmpty == true
                  ? event['errorMessage'].toString()
                  : '下载失败，请重试';
        case 'cancelled':
          closeDialog();
          completeOnce();
        case 'completed':
          final completedTaskId =
              currentTaskId.isNotEmpty ? currentTaskId : taskId;
          if (completedTaskId != null) {
            unawaited(installCompletedTask(completedTaskId));
          }
        case 'install_permission_required':
          closeDialog();
          completeOnce();
      }
    });

    if (!context.mounted) return;
    dialogOpen = true;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (progressContext) => AlertDialog(
        title: const Text('Python Runner 更新'),
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
          ValueListenableBuilder<bool>(
            valueListenable: failedNotifier,
            builder: (_, failed, __) => failed
                ? TextButton(
                    onPressed: () async {
                      final id = taskId;
                      if (id == null) return;
                      failedNotifier.value = false;
                      statusTitleNotifier.value = '正在重试';
                      await _bridge.retryDownload(id);
                    },
                    child: const Text('重试'),
                  )
                : const SizedBox.shrink(),
          ),
          TextButton(
            onPressed: () async {
              final id = taskId;
              if (id != null) {
                await _bridge.cancelDownload(id);
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
      taskId = await _bridge.startApkDownload(
        downloadUrl,
        fileName: asset.name,
        version: updateInfo.latestVersion,
        sha256: assetSha256,
      );
      await finished.future;
    } catch (error) {
      if (!context.mounted) return;
      closeDialog();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Python Runner 更新失败：${_formatError(error)}'),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      await progressSub.cancel();
      progressNotifier.dispose();
      progressTextNotifier.dispose();
      statusTitleNotifier.dispose();
      failedNotifier.dispose();
    }
  }

  int _eventInt(Map<dynamic, dynamic> event, String key, int fallback) {
    final value = event[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return fallback;
  }

  int _eventLong(Map<dynamic, dynamic> event, String key, int fallback) {
    final value = event[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return fallback;
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
