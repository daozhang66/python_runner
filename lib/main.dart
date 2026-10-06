import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as legacy_provider;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dynamic_color/dynamic_color.dart';

import 'services/native_bridge.dart';
import 'services/workspace_access.dart';
import 'features/backup/application/backup_bootstrap.dart';
import 'features/files/domain/file_manager_location.dart'
    show defaultScriptWorkingDirectory;
import 'services/app_logger.dart';
import 'services/app_update_manager.dart';
import 'services/http_inspector_store.dart';
import 'services/network_debug_config.dart';
import 'services/request_override_config.dart';
import 'providers/execution_provider.dart';
import 'features/packages/application/package_controller.dart';
import 'features/mcp/application/mcp_server_controller.dart';
import 'features/mcp/presentation/mcp_overlay_theme.dart';
import 'providers/theme_provider.dart';
import 'providers/app_locale_provider.dart';
import 'features/scripts/presentation/pages/script_list_page.dart';
import 'pages/package_manager_page.dart';
import 'pages/network_inspector_page.dart';
import 'pages/settings_page.dart';
import 'ui/app_design_tokens.dart';
import 'ui/app_bottom_navigation.dart';
import 'ui/app_navigation_pages.dart';
import 'ui/app_responsive.dart';
import 'ui/app_theme_palette.dart';
import 'ui/app_theme.dart';
import 'ui/app_liquid_host.dart';
import 'ui/classic_bottom_navigation.dart';
import 'l10n/app_localizations.dart';

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

  // Recovery owns admission before any workspace widgets or MCP services start.
  WorkspaceAccess.instance.blockForRecovery();

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
  final execution = ExecutionProvider(bridge);

  // runApp must run in the same zone as WidgetsFlutterBinding.ensureInitialized()
  // (the root zone); uncaught async errors are already reported through
  // PlatformDispatcher.instance.onError above.
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        mcpExecutionOwnerProvider.overrideWithValue(execution),
      ],
      child: legacy_provider.MultiProvider(
        providers: [
          legacy_provider.ChangeNotifierProvider.value(value: execution),
          legacy_provider.ChangeNotifierProvider.value(
            value: httpInspectorStore,
          ),
        ],
        child: const BackupBootstrap(child: PythonRunnerApp()),
      ),
    ),
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
  AppThemePalette? _cachedLightPreset;
  AppThemePalette? _cachedDarkPreset;
  String? _cachedLightFontFamily;
  String? _cachedDarkFontFamily;
  AppVisualStyle? _cachedLightVisualStyle;
  AppVisualStyle? _cachedDarkVisualStyle;

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
    AppVisualStyle visualStyle,
  ) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final cachedTheme = isDark ? _cachedDarkTheme : _cachedLightTheme;
    final cachedScheme = isDark ? _cachedDarkScheme : _cachedLightScheme;
    final cachedPreset = isDark ? _cachedDarkPreset : _cachedLightPreset;
    final cachedFontFamily = isDark
        ? _cachedDarkFontFamily
        : _cachedLightFontFamily;
    if (cachedTheme != null &&
        (identical(cachedScheme, colorScheme) || cachedScheme == colorScheme) &&
        cachedPreset == selectedPreset &&
        cachedFontFamily == fontFamily &&
        (isDark ? _cachedDarkVisualStyle : _cachedLightVisualStyle) ==
            visualStyle) {
      return cachedTheme;
    }

    final theme = AppTheme.build(
      colorScheme,
      fontFamily: fontFamily,
      visualStyle: visualStyle,
    );

    if (isDark) {
      _cachedDarkTheme = theme;
      _cachedDarkScheme = colorScheme;
      _cachedDarkPreset = selectedPreset;
      _cachedDarkFontFamily = fontFamily;
      _cachedDarkVisualStyle = visualStyle;
    } else {
      _cachedLightTheme = theme;
      _cachedLightScheme = colorScheme;
      _cachedLightPreset = selectedPreset;
      _cachedLightFontFamily = fontFamily;
      _cachedLightVisualStyle = visualStyle;
    }
    return theme;
  }

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeProvider);
    final appLocale = ref.watch(appLocaleProvider);

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
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
          lightScheme = themeState.selectedPreset!.handCraftedScheme(
            Brightness.light,
          )!;
          darkScheme = themeState.selectedPreset!.handCraftedScheme(
            Brightness.dark,
          )!;
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
          onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
          debugShowCheckedModeBanner: false,
          themeMode: isDarkOnly ? ThemeMode.dark : themeState.mode,
          builder: (context, child) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: isDark
                  ? _darkSystemUiOverlayStyle
                  : _lightSystemUiOverlayStyle,
              child: AppLiquidHost(
                child: McpOverlayTheme(child: child ?? const SizedBox.shrink()),
              ),
            );
          },
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: appLocale,
          theme: _buildTheme(
            lightScheme,
            themeState.selectedPreset,
            themeState.fontFamilyName,
            themeState.visualStyle,
          ),
          darkTheme: _buildTheme(
            darkScheme,
            themeState.selectedPreset,
            themeState.fontFamilyName,
            themeState.visualStyle,
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
            onTimeout: () => PermissionStatus.denied,
          );
        } else {
          await Permission.storage.request().timeout(
            const Duration(seconds: 5),
            onTimeout: () => PermissionStatus.denied,
          );
        }

        // MANAGE_EXTERNAL_STORAGE is only relevant on Android 11+ and can jump
        // into vendor-specific settings UIs. Keep it non-blocking here.
        if (androidInfo >= 30 &&
            !await Permission.manageExternalStorage.isGranted) {
          unawaited(
            Permission.manageExternalStorage.request().timeout(
              const Duration(seconds: 5),
              onTimeout: () => PermissionStatus.denied,
            ),
          );
        }

        // The default working directory should exist as soon as the app
        // opens. Storage permissions are now (best-effort) granted, so the
        // creation can succeed even on the very first launch.
        await _ensureDefaultWorkingDirectory();
      }
    } catch (e) {
      AppLogger.instance.warn(
        'Permission request error: $e',
        source: 'SplashGate',
      );
    }
  }

  Future<void> _ensureDefaultWorkingDirectory() async {
    try {
      await NativeBridge().ensureFileManagerDirectory(
        defaultScriptWorkingDirectory,
      );
    } catch (e) {
      // Non-fatal: the file manager and the script runtime retry creation
      // when they need the directory.
      AppLogger.instance.warn(
        'Default working directory creation failed: $e',
        source: 'SplashGate',
      );
    }
  }

  Future<int> _safeAndroidVersion() async {
    try {
      return int.parse(
        Platform.operatingSystemVersion
            .split('Android ')
            .last
            .split(' ')
            .first
            .split('.')
            .first,
      );
    } catch (_) {
      return 0;
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Widget _buildSplashText(String text, {required TextStyle style}) {
    return Text(text, textAlign: TextAlign.center, style: style);
  }

  Widget _buildSplashContent(
    BuildContext context, {
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
              colors: [primaryColor, primaryColor.withValues(alpha: 0.4)],
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
          AppLocalizations.of(context)!.appTitle,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        _buildSplashText(
          AppLocalizations.of(context)!.pythonRunnerSlogan,
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
    final bgColor = AppThemeColors.splashSurface(isDark);
    final primaryColor = colors.primary;
    final gradientColors = AppThemeColors.splashGradient(isDark);

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
                context,
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
          ? KeyedSubtree(key: const ValueKey('home'), child: widget.child)
          : splash,
    );
  }
}

class HomePage extends ConsumerStatefulWidget {
  final ThemeMode currentThemeMode;

  const HomePage({super.key, required this.currentThemeMode});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _currentIndex = 0;
  int _beforeSettingsIndex = 0;
  final _appUpdateManager = AppUpdateManager();
  final _scriptListController = ScriptListPageController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdatesOnLaunch();
    });
  }

  void _selectTab(int index) {
    if (_currentIndex == index) return;
    if (index == 3) _beforeSettingsIndex = _currentIndex;
    if (_currentIndex == 3) _scriptListController.refreshRuntimePreference();
    FocusManager.instance.primaryFocus?.unfocus();
    if (index == 2) {
      unawaited(ref.read(packageControllerProvider.notifier).ensureLoaded());
    }
    setState(() => _currentIndex = index);
  }

  Widget _buildNavigationRail() {
    final localizations = AppLocalizations.of(context)!;
    return NavigationRail(
      selectedIndex: _currentIndex,
      onDestinationSelected: _selectTab,
      labelType: NavigationRailLabelType.all,
      destinations: [
        NavigationRailDestination(
          icon: const Icon(Icons.code_outlined),
          selectedIcon: const Icon(Icons.code),
          label: Text(localizations.scripts),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.http_outlined),
          selectedIcon: const Icon(Icons.http),
          label: Text(localizations.network),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.inventory_2_outlined),
          selectedIcon: const Icon(Icons.inventory_2),
          label: Text(localizations.packageManager),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.settings_outlined),
          selectedIcon: const Icon(Icons.settings),
          label: Text(localizations.settings),
        ),
      ],
    );
  }

  Widget _buildPageStack({bool animate = false}) {
    return AppNavigationPages(
      index: _currentIndex,
      animate: animate,
      children: [
        ScriptListPage(controller: _scriptListController),
        const NetworkInspectorPage(),
        const PackageManagerPage(),
        SettingsPage(currentThemeMode: widget.currentThemeMode),
      ],
    );
  }

  Future<void> _checkForUpdatesOnLaunch() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    await _appUpdateManager.checkForUpdates(context, manual: false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_currentIndex == 3) {
            _selectTab(_beforeSettingsIndex);
            return;
          }
          if (_currentIndex == 0 && _scriptListController.handleBack()) {
            return;
          }
          const MethodChannel('com.daozhang.py/native_bridge')
              .invokeMethod('moveToBackground');
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (AppBreakpoints.isTabletWidth(constraints.maxWidth)) {
            return Scaffold(
              body: SafeArea(
                child: Row(
                  children: [
                    _buildNavigationRail(),
                    const VerticalDivider(width: 1),
                    Expanded(child: _buildPageStack()),
                  ],
                ),
              ),
            );
          }

          return Scaffold(
            appBar: null,
            extendBody: true,
            body: SafeArea(
              bottom: false,
              child: _buildPageStack(),
            ),
            bottomNavigationBar:
                ref.watch(
                  themeProvider.select((state) => state.liquidNavigation),
                )
                ? AppBottomNavigation(
                    selectedIndex: _currentIndex,
                    onDestinationSelected: _selectTab,
                  )
                : ClassicBottomNavigation(
                    selectedIndex: _currentIndex,
                    onDestinationSelected: _selectTab,
                  ),
          );
        },
      ),
    );
  }
}
