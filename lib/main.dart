import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as legacy_provider;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'services/native_bridge.dart';
import 'services/database_service.dart';
import 'services/app_logger.dart';
import 'services/app_update_manager.dart';
import 'services/http_inspector_store.dart';
import 'services/network_debug_config.dart';
import 'services/request_override_config.dart';
import 'providers/script_provider.dart';
import 'providers/execution_provider.dart';
import 'providers/package_provider.dart' show PackageProvider;
import 'providers/theme_provider.dart';
import 'pages/script_list_page.dart';
import 'pages/package_manager_page.dart';
import 'pages/network_inspector_page.dart';
import 'pages/settings_page.dart';
import 'pages/run_console_page.dart';
import 'utils/app_page_transitions.dart';
import 'ui/app_design_tokens.dart';
import 'ui/app_theme_palette.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Initialize the unified logger
  final logger = AppLogger.instance;
  await logger.init();
  logger.info('App starting', source: 'main');

  // Load network debug config
  await NetworkDebugConfig.instance.load();

  // Load request override config
  await RequestOverrideConfig.instance.load();

  // Restore persisted HTTP inspector records before the UI starts.
  final httpInspectorStore = HttpInspectorStore.instance;
  await httpInspectorStore.loadDisplayPreferences();
  await httpInspectorStore.ensureLoaded();

  // Load SharedPreferences for Riverpod
  final prefs = await SharedPreferences.getInstance();

  // Global Flutter framework error handler
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    logger.crash(
      'FlutterError: ${details.exceptionAsString()}',
      exception: details.exception,
      stackTrace: details.stack,
      source: 'FlutterError.onError',
    );
  };

  // Platform dispatcher errors (errors not caught by Flutter framework)
  PlatformDispatcher.instance.onError = (error, stack) {
    logger.crash(
      'PlatformDispatcher error: $error',
      exception: error,
      stackTrace: stack,
      source: 'PlatformDispatcher',
    );
    return true;
  };

  final bridge = NativeBridge();
  final db = DatabaseService();

  // runZonedGuarded to catch all async errors
  runZonedGuarded(
    () {
      runApp(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: legacy_provider.MultiProvider(
            providers: [
              legacy_provider.ChangeNotifierProvider(
                  create: (_) => ScriptProvider(bridge, db)),
              legacy_provider.ChangeNotifierProvider(
                  create: (_) => ExecutionProvider(bridge)),
              legacy_provider.ChangeNotifierProvider(
                  create: (_) => PackageProvider(bridge)),
              legacy_provider.ChangeNotifierProvider.value(
                  value: httpInspectorStore),
            ],
            child: const PythonRunnerApp(),
          ),
        ),
      );
    },
    (error, stackTrace) {
      logger.crash(
        'Uncaught async error: $error',
        exception: error,
        stackTrace: stackTrace,
        source: 'runZonedGuarded',
      );
    },
  );
}

class PythonRunnerApp extends ConsumerStatefulWidget {
  const PythonRunnerApp({super.key});

  @override
  ConsumerState<PythonRunnerApp> createState() => _PythonRunnerAppState();
}

class _PythonRunnerAppState extends ConsumerState<PythonRunnerApp>
    with WidgetsBindingObserver {
  static const _lightSystemUiOverlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );
  static const _darkSystemUiOverlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
  );

  ThemeData? _cachedLightTheme;
  ThemeData? _cachedDarkTheme;
  ColorScheme? _cachedLightScheme;
  ColorScheme? _cachedDarkScheme;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _flushHttpInspectorRecords() {
    unawaited(HttpInspectorStore.instance.flush());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
          legacy_provider.Provider.of<ExecutionProvider>(context, listen: false)
              .syncFloatingBallVisibility());
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _flushHttpInspectorRecords();
      unawaited(AppLogger.instance.flush());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  ThemeData _buildTheme(
    ColorScheme colorScheme,
    AppThemePalette? selectedPreset,
    String? fontFamily,
  ) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final cachedTheme = isDark ? _cachedDarkTheme : _cachedLightTheme;
    final cachedScheme = isDark ? _cachedDarkScheme : _cachedLightScheme;
    if (cachedTheme != null &&
        (identical(cachedScheme, colorScheme) || cachedScheme == colorScheme)) {
      return cachedTheme;
    }

    final isHandCraftedDark =
        isDark && selectedPreset != null && !selectedPreset.isSeedBased;
    final bgColor = isHandCraftedDark
        ? colorScheme.surface
        : (isDark
            ? AppThemeColors.darkBackground
            : AppThemeColors.pageBackground(colorScheme));
    final cardColor = isHandCraftedDark
        ? colorScheme.surfaceContainer
        : (isDark
            ? AppThemeColors.darkSurface
            : AppThemeColors.cardSurface(colorScheme));
    final borderColor = isHandCraftedDark
        ? colorScheme.outline
        : (isDark
            ? AppThemeColors.darkBorder
            : colorScheme.outlineVariant.withValues(alpha: 0.44));
    final navIndicator = isHandCraftedDark
        ? colorScheme.primaryContainer
        : (isDark
            ? AppThemeColors.darkPinnedSurface
            : AppThemeColors.navigationIndicator(colorScheme));

    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: bgColor,
      canvasColor: isDark ? bgColor : null,
      cardTheme: CardThemeData(
        elevation: 0,
        color: cardColor,
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.cardHorizontal,
          vertical: AppSpacing.cardVertical,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          side: BorderSide(color: borderColor),
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: isDark ? bgColor : colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        shape: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: colorScheme.outlineVariant.withValues(alpha: 0.32),
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(
            color: colorScheme.primary.withValues(alpha: 0.82),
            width: 3,
          ),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 68,
        backgroundColor:
            isDark ? bgColor : AppThemeColors.cardSurface(colorScheme),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: navIndicator,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurface.withValues(alpha: 0.38);
          }
          if (states.contains(WidgetState.selected)) {
            return colorScheme.onPrimary;
          }
          return colorScheme.onSurfaceVariant;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurface.withValues(alpha: 0.12);
          }
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return isDark
              ? colorScheme.surfaceContainerHighest
              : colorScheme.surfaceContainerHigh;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          return colorScheme.outline.withValues(alpha: isDark ? 0.58 : 0.42);
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          side: WidgetStatePropertyAll(
            BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.58),
            ),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return isHandCraftedDark
                  ? colorScheme.primaryContainer
                  : AppThemeColors.navigationIndicator(colorScheme);
            }
            return isHandCraftedDark
                ? colorScheme.surfaceContainerHigh
                : AppThemeColors.cardSurface(colorScheme);
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.primary;
            }
            return colorScheme.onSurfaceVariant;
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
        showDragHandle: true,
      ),
      popupMenuTheme: PopupMenuThemeData(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isHandCraftedDark
            ? colorScheme.surfaceContainerHigh
            : AppThemeColors.softSurface(colorScheme),
        selectedColor: isHandCraftedDark
            ? colorScheme.primaryContainer
            : AppThemeColors.navigationIndicator(colorScheme),
        secondarySelectedColor: isHandCraftedDark
            ? colorScheme.primaryContainer
            : AppThemeColors.navigationIndicator(colorScheme),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        secondaryLabelStyle: TextStyle(color: colorScheme.onPrimaryContainer),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      dividerColor: colorScheme.outlineVariant.withValues(alpha: 0.32),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? colorScheme.surfaceContainerHigh
            : AppThemeColors.softSurface(colorScheme),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.62),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.62),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(
            color: colorScheme.primary.withValues(alpha: 0.84),
            width: 1.4,
          ),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );

    if (isDark) {
      _cachedDarkTheme = theme;
      _cachedDarkScheme = colorScheme;
    } else {
      _cachedLightTheme = theme;
      _cachedLightScheme = colorScheme;
    }
    return theme;
  }

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        // 更新动态颜色到 provider
        if (themeState.useDynamicColor && lightDynamic != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            themeNotifier.setDynamicPrimary(lightDynamic.primary);
          });
        }

        // 决定 ColorScheme
        final ColorScheme lightScheme;
        final ColorScheme darkScheme;

        if (themeState.useDynamicColor &&
            lightDynamic != null &&
            darkDynamic != null) {
          // Material You 模式
          lightScheme = ColorScheme.fromSeed(
            seedColor: lightDynamic.primary,
            brightness: Brightness.light,
            dynamicSchemeVariant: themeState.schemeVariant,
          );
          darkScheme = ColorScheme.fromSeed(
            seedColor: darkDynamic.primary,
            brightness: Brightness.dark,
            dynamicSchemeVariant: themeState.schemeVariant,
          );
        } else if (themeState.selectedPreset != null &&
            !themeState.selectedPreset!.isSeedBased) {
          // 手工主题（VS Code、GitHub Dark 等）
          lightScheme =
              themeState.selectedPreset!.handCraftedScheme(Brightness.light)!;
          darkScheme =
              themeState.selectedPreset!.handCraftedScheme(Brightness.dark)!;
        } else {
          // Seed-based 主题
          lightScheme = ColorScheme.fromSeed(
            seedColor: themeState.seedColor,
            brightness: Brightness.light,
            dynamicSchemeVariant: themeState.schemeVariant,
          );
          darkScheme = ColorScheme.fromSeed(
            seedColor: themeState.seedColor,
            brightness: Brightness.dark,
            dynamicSchemeVariant: themeState.schemeVariant,
          );
        }

        final isDarkOnly = themeState.selectedPreset?.darkOnly ?? false;

        return MaterialApp(
          navigatorKey: appNavigatorKey,
          title: 'Python运行器',
          debugShowCheckedModeBanner: false,
          themeMode: isDarkOnly ? ThemeMode.dark : themeState.mode,
          builder: (context, child) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: isDark
                  ? _darkSystemUiOverlayStyle
                  : _lightSystemUiOverlayStyle,
              child: child ?? const SizedBox.shrink(),
            );
          },
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('zh', 'CN'),
            Locale('en', 'US'),
          ],
          locale: const Locale('zh', 'CN'),
          theme: _buildTheme(
            lightScheme,
            themeState.selectedPreset,
            themeState.fontFamilyName,
          ),
          darkTheme: _buildTheme(
            darkScheme,
            themeState.selectedPreset,
            themeState.fontFamilyName,
          ),
          home: SplashGate(
            child: HomePage(
              currentThemeMode: isDarkOnly ? ThemeMode.dark : themeState.mode,
            ),
          ),
        );
      },
    );
  }
}

class SplashGate extends StatefulWidget {
  final Widget child;
  const SplashGate({super.key, required this.child});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate>
    with SingleTickerProviderStateMixin {
  static const _minimumSplashDuration = Duration(milliseconds: 600);

  bool _ready = false;
  late AnimationController _animController;
  late Animation<double> _fadeIn;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeIn = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );
    _animController.forward();
    _initialize();
  }

  Future<void> _initialize() async {
    final stopwatch = Stopwatch()..start();
    final remaining = _minimumSplashDuration - stopwatch.elapsed;
    if (remaining > Duration.zero) {
      await Future.delayed(remaining);
    }
    if (mounted) {
      setState(() => _ready = true);
    }
    unawaited(_requestPermissions());
  }

  Future<void> _requestPermissions() async {
    if (!Platform.isAndroid) return;

    try {
      if (Platform.isAndroid) {
        final androidInfo = await _safeAndroidVersion();

        // Never block startup on permission dialogs. Some ROMs may hold the
        // Future until the settings page fully returns, which caused the splash
        // screen to spin forever on certain devices.
        if (androidInfo >= 33) {
          await [
            Permission.photos,
            Permission.videos,
            Permission.audio,
          ].request().timeout(
                const Duration(seconds: 5),
                onTimeout: () => <Permission, PermissionStatus>{},
              );
          await Permission.notification.request().timeout(
              const Duration(seconds: 5),
              onTimeout: () => PermissionStatus.denied);
        } else {
          await Permission.storage.request().timeout(const Duration(seconds: 5),
              onTimeout: () => PermissionStatus.denied);
        }

        // MANAGE_EXTERNAL_STORAGE is only relevant on Android 11+ and can jump
        // into vendor-specific settings UIs. Keep it non-blocking here.
        if (androidInfo >= 30 &&
            !await Permission.manageExternalStorage.isGranted) {
          unawaited(
            Permission.manageExternalStorage.request().timeout(
                const Duration(seconds: 5),
                onTimeout: () => PermissionStatus.denied),
          );
        }
      }
    } catch (e) {
      AppLogger.instance
          .warn('Permission request error: $e', source: 'SplashGate');
    }
  }

  Future<int> _safeAndroidVersion() async {
    try {
      return int.parse(Platform.operatingSystemVersion
          .split('Android ')
          .last
          .split(' ')
          .first
          .split('.')
          .first);
    } catch (_) {
      return 0;
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Widget _buildSplashText(
    String text, {
    required TextStyle style,
  }) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: style,
    );
  }

  Widget _buildSplashContent({
    required Color primaryColor,
    required Color surfaceColor,
    required ColorScheme colors,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 88,
          height: 88,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                primaryColor,
                primaryColor.withValues(alpha: 0.4),
              ],
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: Text(
                'Py',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w300,
                  color: primaryColor,
                  letterSpacing: -1,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        _buildSplashText(
          'Python 运行器',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        _buildSplashText(
          '人生苦短，我用 Python',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: colors.onSurfaceVariant.withValues(alpha: 0.82),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 34),
        SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: primaryColor.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    final primaryColor = colors.primary;
    final gradientColors = isDark
        ? [
            const Color(0xFF121212),
            const Color(0xFF0F172A),
          ]
        : [
            Colors.white,
            const Color(0xFFEAF2FF),
          ];

    final splash = Scaffold(
      key: const ValueKey('splash'),
      backgroundColor: bgColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: gradientColors,
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fadeIn,
            child: ScaleTransition(
              scale: _scale,
              child: _buildSplashContent(
                primaryColor: primaryColor,
                surfaceColor: bgColor,
                colors: colors,
              ),
            ),
          ),
        ),
      ),
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _ready
          ? KeyedSubtree(
              key: const ValueKey('home'),
              child: widget.child,
            )
          : splash,
    );
  }
}

class HomePage extends StatefulWidget {
  final ThemeMode currentThemeMode;

  const HomePage({
    super.key,
    required this.currentThemeMode,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  final _appUpdateManager = AppUpdateManager();
  final _scriptListController = ScriptListPageController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        legacy_provider.Provider.of<ExecutionProvider>(
          context,
          listen: false,
        ).syncFloatingBallVisibility(),
      );
      _checkForUpdatesOnLaunch();
      // When floating ball triggers a script, switch to script tab and open console page
      ExecutionProvider.setNavigateToConsoleHandler((scriptName) {
        if (!mounted) return;
        setState(() => _currentIndex = 0);
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          appNavigatorKey.currentState?.push(
            AppPageTransitions.fadeThrough(
              RunConsolePage(scriptName: scriptName),
            ),
          );
        });
      });
    });
  }

  @override
  void dispose() {
    ExecutionProvider.setNavigateToConsoleHandler(null);
    super.dispose();
  }

  void _selectTab(int index) {
    if (index == 2) {
      unawaited(
        legacy_provider.Provider.of<PackageProvider>(
          context,
          listen: false,
        ).ensurePackagesLoaded(),
      );
    }
    setState(() => _currentIndex = index);
  }

  Widget _buildBottomNavigation(ColorScheme colors) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark
        ? colors.surfaceContainerHigh
        : Color.alphaBlend(
            colors.surfaceContainerHighest.withValues(alpha: 0.34),
            colors.surface,
          );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(
          top: BorderSide(
            color: colors.outlineVariant.withValues(alpha: isDark ? 0.55 : 0.5),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: NavigationBar(
        backgroundColor: Colors.transparent,
        selectedIndex: _currentIndex,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.code_outlined),
            selectedIcon: Icon(Icons.code),
            label: '脚本',
          ),
          NavigationDestination(
            icon: Icon(Icons.http_outlined),
            selectedIcon: Icon(Icons.http),
            label: '网络',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: '库管理',
          ),
        ],
      ),
    );
  }

  Future<void> _checkForUpdatesOnLaunch() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    await _appUpdateManager.checkForUpdates(
      context,
      manual: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_currentIndex == 0 && _scriptListController.handleBack()) {
            return;
          }
          const MethodChannel('com.daozhang.py/native_bridge')
              .invokeMethod('moveToBackground');
        }
      },
      child: Scaffold(
        appBar: null,
        body: IndexedStack(
          index: _currentIndex,
          children: [
            ScriptListPage(
              controller: _scriptListController,
              onSettingsTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsPage(
                    currentThemeMode: widget.currentThemeMode,
                  ),
                  fullscreenDialog: true,
                ),
              ).then((_) => _scriptListController.refreshRuntimePreference()),
            ),
            const NetworkInspectorPage(),
            const PackageManagerPage(),
          ],
        ),
        bottomNavigationBar: _buildBottomNavigation(
          Theme.of(context).colorScheme,
        ),
      ),
    );
  }
}
