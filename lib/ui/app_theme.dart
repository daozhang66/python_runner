import 'package:flutter/material.dart';

import 'app_design_tokens.dart';
import 'app_materials.dart';
import 'app_visual_style.dart';
import 'app_button_layer.dart';
import '../utils/app_page_transitions.dart';

/// Shared by the application and visual tests. The caller owns palette choice.
abstract final class AppTheme {
  static ThemeData build(
    ColorScheme colors, {
    String? fontFamily,
    AppVisualStyle visualStyle = AppVisualStyle.classic,
  }) {
    final materials = AppMaterials.fromColors(colors, visualStyle);
    final liquid = materials.liquid;
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
      borderRadius: liquid ? AppRadius.extraLarge : AppRadius.medium,
      borderSide: BorderSide(color: liquid ? materials.edge : quietBorder),
    );
    final buttonShape = liquid
        ? const StadiumBorder()
        : RoundedRectangleBorder(borderRadius: AppRadius.large);
    ButtonStyle buttonStyle({bool glassBackground = true}) => ButtonStyle(
      shape: WidgetStatePropertyAll(buttonShape),
      textStyle: WidgetStatePropertyAll(text.labelLarge),
      animationDuration: Duration(milliseconds: liquid ? 180 : 100),
      splashFactory: liquid ? NoSplash.splashFactory : InkRipple.splashFactory,
      backgroundBuilder: liquid && glassBackground
          ? appGlassButtonBackground
          : null,
      foregroundBuilder: liquid ? appGlassButtonForeground : null,
      backgroundColor: liquid && glassBackground
          ? const WidgetStatePropertyAll(Colors.transparent)
          : null,
    );

    return base.copyWith(
      pageTransitionsTheme: liquid
          ? PageTransitionsTheme(
              builders: {
                for (final platform in TargetPlatform.values)
                  platform: const DirectPageTransitionsBuilder(),
              },
            )
          : base.pageTransitionsTheme,
      extensions: [materials],
      textTheme: text,
      primaryTextTheme: _zeroTracking(base.primaryTextTheme),
      scaffoldBackgroundColor: colors.surface,
      canvasColor: colors.surface,
      splashFactory: liquid ? NoSplash.splashFactory : InkRipple.splashFactory,
      cardTheme: CardThemeData(
        elevation: liquid ? 2 : 0,
        shadowColor: materials.shadow,
        color: liquid ? materials.content : colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.cardHorizontal,
          vertical: AppSpacing.cardVertical,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: liquid ? AppRadius.extraLarge : AppRadius.medium,
          side: BorderSide(color: liquid ? materials.edge : quietBorder),
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
        style: buttonStyle(),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: buttonStyle()),
      outlinedButtonTheme: OutlinedButtonThemeData(style: buttonStyle()),
      textButtonTheme: TextButtonThemeData(
        style: buttonStyle(glassBackground: false),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: liquid
            ? buttonStyle(glassBackground: false).copyWith(
                shape: const WidgetStatePropertyAll(CircleBorder()),
                // Icon-only actions are unframed. Keep transient press feedback
                // without allocating a glass surface around every glyph.
                splashFactory: InkRipple.splashFactory,
                // IconButton inherits body text for its internal Material;
                // changing this to label text breaks theme interpolation.
                textStyle: const WidgetStatePropertyAll<TextStyle?>(null),
              )
            : null,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: buttonStyle().copyWith(
          backgroundColor: liquid
              ? WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? colors.secondaryContainer
                      : materials.control,
                )
              : null,
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppRadius.medium),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: liquid
            ? materials.overlay
            : colors.surfaceContainerHigh,
        // A shared width budget keeps custom dialogs with full-width content
        // from spreading to the screen edge when their chrome is transparent.
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 560),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.dialog),
          side: liquid ? BorderSide(color: materials.edge) : BorderSide.none,
        ),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: liquid
            ? materials.overlay
            : colors.surfaceContainerLow,
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
        color: liquid ? materials.overlay : colors.surfaceContainer,
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
        fillColor: liquid ? materials.control : colors.surfaceContainerLow,
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
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
