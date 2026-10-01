import 'package:flutter/material.dart';

import 'app_design_tokens.dart';

/// Shared by the application and visual tests. The caller owns palette choice.
abstract final class AppTheme {
  static ThemeData build(ColorScheme colors, {String? fontFamily}) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      fontFamily: fontFamily,
    );
    final text = _zeroTracking(base.textTheme).copyWith(
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.4,
        letterSpacing: 0,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        fontSize: 12,
        height: 1.4,
        letterSpacing: 0,
      ),
    );
    final quietBorder = colors.outlineVariant.withValues(alpha: 0.5);
    final fieldBorder = OutlineInputBorder(
      borderRadius: AppRadius.medium,
      borderSide: BorderSide(color: quietBorder),
    );

    return base.copyWith(
      textTheme: text,
      primaryTextTheme: _zeroTracking(base.primaryTextTheme),
      scaffoldBackgroundColor: colors.surface,
      canvasColor: colors.surface,
      splashFactory: InkRipple.splashFactory,
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.cardHorizontal,
          vertical: AppSpacing.cardVertical,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.medium,
          side: BorderSide(color: quietBorder),
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleLarge,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.onSurfaceVariant,
        textColor: colors.onSurface,
        selectedColor: colors.onSecondaryContainer,
        selectedTileColor: colors.secondaryContainer,
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: quietBorder,
        labelColor: colors.primary,
        unselectedLabelColor: colors.onSurfaceVariant,
        labelStyle: text.labelLarge,
        unselectedLabelStyle: text.labelLarge,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: colors.primary, width: 3),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        // Leave colors to the button variant, so tonal and disabled states
        // retain their Material 3 semantics instead of becoming primary fills.
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const StadiumBorder(),
          textStyle: text.labelLarge,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppRadius.medium),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.dialog),
        ),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.dialog),
          ),
        ),
        showDragHandle: true,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shadowColor: colors.shadow.withValues(alpha: 0.16),
        textStyle: text.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.large),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: colors.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.large),
      ),
      dividerColor: quietBorder,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerLow,
        border: fieldBorder,
        enabledBorder: fieldBorder,
        disabledBorder: fieldBorder.copyWith(
          borderSide: BorderSide(
            color: colors.onSurface.withValues(alpha: 0.12),
          ),
        ),
        focusedBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
        errorBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: colors.error),
        ),
        focusedErrorBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: colors.error, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  static TextTheme _zeroTracking(TextTheme text) => text.copyWith(
        displayLarge: text.displayLarge?.copyWith(letterSpacing: 0),
        displayMedium: text.displayMedium?.copyWith(letterSpacing: 0),
        displaySmall: text.displaySmall?.copyWith(letterSpacing: 0),
        headlineLarge: text.headlineLarge?.copyWith(letterSpacing: 0),
        headlineMedium: text.headlineMedium?.copyWith(letterSpacing: 0),
        headlineSmall: text.headlineSmall?.copyWith(letterSpacing: 0),
        titleLarge: text.titleLarge?.copyWith(letterSpacing: 0),
        titleMedium: text.titleMedium?.copyWith(letterSpacing: 0),
        titleSmall: text.titleSmall?.copyWith(letterSpacing: 0),
        bodyLarge: text.bodyLarge?.copyWith(letterSpacing: 0),
        bodyMedium: text.bodyMedium?.copyWith(letterSpacing: 0),
        bodySmall: text.bodySmall?.copyWith(letterSpacing: 0),
        labelLarge: text.labelLarge?.copyWith(letterSpacing: 0),
        labelMedium: text.labelMedium?.copyWith(letterSpacing: 0),
        labelSmall: text.labelSmall?.copyWith(letterSpacing: 0),
      );
}
