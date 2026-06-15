import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/update_dialog.dart';
import 'app_logger.dart';
import 'download_service.dart';
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
      barrierDismissible: false,
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
        onCancel: () {
          if (dialogContext.mounted) {
            Navigator.pop(dialogContext);
          }
        },
        onIgnore: rememberDismissal
            ? () async {
                await _rememberDismissedVersion(updateInfo.latestVersion);
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              }
            : null,
        onViewDetails: () async {
          await _bridge.openUrl(updateInfo.htmlUrl);
        },
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
    final startTime = DateTime.now();
    CancelToken? cancelToken;
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
          TextButton(
            onPressed: () {
              cancelToken?.cancel('用户取消');
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
      // 使用 Dio 下载
      cancelToken = CancelToken();
      final tempDir = Directory.systemTemp;
      final savePath = '${tempDir.path}/${asset.name}';

      // 删除旧文件（如果存在）
      final file = File(savePath);
      if (await file.exists()) {
        await file.delete();
      }

      await DownloadService.instance.download(
        url: downloadUrl,
        savePath: savePath,
        onProgress: (received, total) {
          if (total > 0) {
            final progress = (received / total * 100).toInt();
            progressNotifier.value = received / total;

            final speed = received > 0 && progressNotifier.value > 0
                ? (received / (DateTime.now().millisecondsSinceEpoch - startTime.millisecondsSinceEpoch) * 1000).toInt()
                : 0;

            progressTextNotifier.value =
                '${_formatByteSize(received)} / ${_formatByteSize(total)} ($progress%)';

            if (speed > 0) {
              progressTextNotifier.value += ' · ${_formatByteSize(speed)}/s';
              final remaining = total - received;
              final eta = (remaining / speed).toInt();
              if (eta > 0) {
                progressTextNotifier.value += ' · 剩余约 ${_formatEta(eta)}';
              }
            }

            statusTitleNotifier.value = '正在下载 v${updateInfo.latestVersion}';
          } else {
            progressNotifier.value = 0.0;
            progressTextNotifier.value = '正在下载...';
          }
        },
        cancelToken: cancelToken,
      );

      // 下载完成，安装
      if (!context.mounted) return;
      statusTitleNotifier.value = '下载完成，正在打开安装器';

      await _bridge.installApkFile(savePath);

      if (!context.mounted) return;
      closeDialog();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('安装器已打开'),
          duration: Duration(seconds: 2),
        ),
      );

      completeOnce();
    } on DioException catch (error) {
      if (error.type == DioExceptionType.cancel) {
        // 用户取消
        closeDialog();
        completeOnce();
        return;
      }

      if (!context.mounted) return;
      closeDialog();

      String errorMsg = '下载失败';
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        errorMsg = '下载超时，请检查网络连接';
      } else if (error.type == DioExceptionType.badResponse) {
        errorMsg = '服务器响应错误：${error.response?.statusCode}';
      } else if (error.message != null) {
        errorMsg = '下载失败：${error.message}';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Python Runner 更新失败：$errorMsg'),
          duration: const Duration(seconds: 3),
        ),
      );
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
      cancelToken?.cancel();
      progressNotifier.dispose();
      progressTextNotifier.dispose();
      statusTitleNotifier.dispose();
    }
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
