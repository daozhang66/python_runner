import 'package:flutter/material.dart';

import 'app_design_tokens.dart';

/// Low-cost loading placeholder that uses a single implicit color transition.
class AppSkeleton extends StatelessWidget {
  const AppSkeleton({
    super.key,
    this.height = 16,
    this.width,
    this.radius = AppRadius.md,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<Color?>(
      duration: const Duration(milliseconds: 900),
      tween: ColorTween(
        begin: colors.surfaceContainerHighest.withValues(alpha: 0.42),
        end: colors.surfaceContainerHighest.withValues(alpha: 0.7),
      ),
      builder: (context, color, _) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      onEnd: () {},
    );
  }
}

class AppListSkeleton extends StatelessWidget {
  const AppListSkeleton({
    super.key,
    this.itemCount = 5,
  });

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) => const SizedBox(
        height: 76,
        child: Row(
          children: [
            AppSkeleton(width: 44, height: 44, radius: AppRadius.pill),
            SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppSkeleton(width: 148),
                  SizedBox(height: AppSpacing.sm),
                  AppSkeleton(width: 96, height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
