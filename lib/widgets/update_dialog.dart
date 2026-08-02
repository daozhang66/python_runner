import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/update_service.dart';
import '../l10n/app_localizations.dart';
import '../ui/app_design_tokens.dart';

class UpdateDialog extends StatelessWidget {
  final AppUpdateInfo updateInfo;
  final VoidCallback onUpdate;
  final VoidCallback onCancel;
  final VoidCallback? onIgnore;
  final VoidCallback? onViewDetails;

  const UpdateDialog({
    super.key,
    required this.updateInfo,
    required this.onUpdate,
    required this.onCancel,
    this.onIgnore,
    this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = theme.colorScheme;
    final size = MediaQuery.of(context).size;
    final maxContentHeight = size.height * 0.5;

    return Dialog(
      shape: RoundedRectangleBorder(
          borderRadius: AppRadius.circular(AppSpacing.xl)),
      elevation: 0,
      backgroundColor: AppThemeColors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: AppRadius.circular(AppSpacing.xl),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.15),
              blurRadius: 25,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // 装饰性背景图标
            Positioned(
              right: -30,
              top: -20,
              child: Icon(
                Icons.rocket_launch_rounded,
                size: 200,
                color: colorScheme.primary.withValues(alpha: 0.05),
              ),
            ),

            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 标题栏
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        l10n.update,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: AppTextSize.headline,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildVersionChip(
                        context,
                        updateInfo.latestVersion,
                      ),
                    ],
                  ),
                ),

                // 发布日期
                if (updateInfo.publishedAt != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatDate(l10n, updateInfo.publishedAt!),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),

                // 更新日志标题
                if (updateInfo.releaseNotes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            l10n.releaseNotes,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // 更新日志内容
                if (updateInfo.releaseNotes.isNotEmpty)
                  Container(
                    constraints: BoxConstraints(maxHeight: maxContentHeight),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: MarkdownBody(
                          data: _cleanReleaseNotes(updateInfo.releaseNotes),
                          styleSheet: MarkdownStyleSheet(
                            p: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurface,
                              height: 1.6,
                              fontSize: AppTextSize.bodyLarge,
                            ),
                            h1: theme.textTheme.titleLarge?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                            h2: theme.textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                            h3: theme.textTheme.titleSmall?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                            listBullet: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.primary,
                            ),
                            code: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.primary,
                              backgroundColor: colorScheme.primaryContainer
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          onTapLink: (text, href, title) {
                            if (href != null) {
                              launchUrl(
                                Uri.parse(href),
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                        ),
                      ),
                    ),
                  ),

                // APK 大小信息
                if (updateInfo.apkAsset != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.insert_drive_file_outlined,
                          size: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          l10n.fileSize(
                              _formatFileSize(updateInfo.apkAsset!.size)),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),

                if (updateInfo.apkAsset?.checksumError case final error?)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                    child: Semantics(
                      liveRegion: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.checksumUnavailable,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.error,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.checksumUnavailableDetail(error),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // 操作按钮
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 主要更新按钮
                      FilledButton.icon(
                        onPressed: onUpdate,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.download_rounded, size: 20),
                        label: Text(
                          l10n.updateNow,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: AppTextSize.toolbarTitle,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 次要操作按钮
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // 不再提示按钮
                          if (onIgnore != null)
                            TextButton(
                              onPressed: onIgnore,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                foregroundColor: colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.7),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                l10n.dontRemind,
                                style: const TextStyle(
                                    fontSize: AppTextSize.bodyEmphasis),
                              ),
                            ),

                          // 查看详情按钮
                          if (onViewDetails != null)
                            TextButton.icon(
                              onPressed: onViewDetails,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                foregroundColor: colorScheme.primary,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              icon: Icon(Icons.open_in_new, size: 14),
                              label: Text(
                                l10n.viewDetails,
                                style: const TextStyle(
                                    fontSize: AppTextSize.bodyEmphasis),
                              ),
                            ),

                          const Spacer(),

                          // 稍后提醒按钮
                          TextButton(
                            onPressed: onCancel,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              foregroundColor: colorScheme.onSurfaceVariant,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              l10n.remindLater,
                              style: const TextStyle(
                                  fontSize: AppTextSize.bodyEmphasis),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建版本号标签
  Widget _buildVersionChip(BuildContext context, String version) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Text(
        'v$version',
        style: TextStyle(
          fontSize: AppTextSize.body,
          fontWeight: FontWeight.w700,
          color: colorScheme.primary,
        ),
      ),
    );
  }

  /// 清理发布说明（移除模板内容）
  String _cleanReleaseNotes(String notes) {
    // 移除 HTML div 标签之后的内容
    final divIndex = notes.indexOf('<div align');
    if (divIndex != -1) {
      notes = notes.substring(0, divIndex).trim();
    }
    return notes;
  }

  /// 格式化日期
  String _formatDate(AppLocalizations l10n, DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return l10n.today;
    } else if (diff.inDays == 1) {
      return l10n.yesterday;
    } else if (diff.inDays < 7) {
      return l10n.daysAgo(diff.inDays);
    } else {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
  }

  /// 格式化文件大小
  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }
}
