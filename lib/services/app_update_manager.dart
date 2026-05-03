import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_logger.dart';
import 'http_inspector_store.dart';
import 'native_bridge.dart';
import 'update_service.dart';

class AppUpdateManager {
  static const String _autoCheckEnabledKey = 'app_update_auto_check_enabled';
  static const String _lastCheckAtKey = 'app_update_last_check_at';
  static const String _dismissedVersionKey = 'app_update_dismissed_version';
  static const Duration _autoCheckInterval = Duration(hours: 12);

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
    final prefs = await SharedPreferences.getInstance();
    if (!manual) {
      if (!await isAutoCheckEnabled()) return;
      final lastCheckAt = DateTime.tryParse(
        prefs.getString(_lastCheckAtKey) ?? '',
      );
      if (lastCheckAt != null &&
          DateTime.now().difference(lastCheckAt) < _autoCheckInterval) {
        return;
      }
    }

    await prefs.setString(_lastCheckAtKey, DateTime.now().toIso8601String());

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
        final dismissedVersion = prefs.getString(_dismissedVersionKey) ?? '';
        if (dismissedVersion == updateInfo.latestVersion) {
          return;
        }
      }

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
                    color: Theme.of(dialogContext).colorScheme.surfaceContainerHighest,
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
                      color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
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

    await HttpInspectorStore.instance.flush();

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (progressContext) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('正在下载更新包...')),
          ],
        ),
      ),
    );

    try {
      await _bridge.downloadAndInstallApk(
        asset.downloadUrl,
        fileName: asset.name,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('安装器已打开'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('更新失败：${_formatError(error)}'),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
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
