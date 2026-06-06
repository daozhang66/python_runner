import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
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
import 'pages/script_list_page.dart';
import 'pages/package_manager_page.dart';
import 'pages/network_inspector_page.dart';
import 'pages/settings_page.dart';
import 'pages/run_console_page.dart';
import 'utils/app_page_transitions.dart';

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
  await HttpInspectorStore.instance.ensureLoaded();

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
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ScriptProvider(bridge, db)),
            ChangeNotifierProvider(create: (_) => ExecutionProvider(bridge)),
            ChangeNotifierProvider(create: (_) => PackageProvider(bridge)),
          ],
          child: const PythonRunnerApp(),
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

class PythonRunnerApp extends StatefulWidget {
  const PythonRunnerApp({super.key});

  @override
  State<PythonRunnerApp> createState() => _PythonRunnerAppState();
}

class _PythonRunnerAppState extends State<PythonRunnerApp>
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

  ThemeMode _themeMode = ThemeMode.system;
  bool _materialYouEnabled = true;
  ThemeData? _cachedLightTheme;
  ThemeData? _cachedDarkTheme;
  ColorScheme? _cachedLightScheme;
  ColorScheme? _cachedDarkScheme;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadTheme();
  }

  void _flushHttpInspectorRecords() {
    unawaited(HttpInspectorStore.instance.flush());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(context.read<ExecutionProvider>().syncFloatingBallVisibility());
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _flushHttpInspectorRecords();
      unawaited(AppLogger.instance.flush());
    }
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('theme_mode') ?? 'system';
    setState(() {
      _themeMode = ThemeMode.values
          .firstWhere((e) => e.name == mode, orElse: () => ThemeMode.system);
      _materialYouEnabled = prefs.getBool('material_you_enabled') ?? false;
    });
  }

  Future<void> _setTheme(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.name);
    setState(() => _themeMode = mode);
  }

  Future<void> _setMaterialYouEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('material_you_enabled', enabled);
    setState(() => _materialYouEnabled = enabled);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  ThemeData _buildTheme(ColorScheme colorScheme) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final cachedTheme = isDark ? _cachedDarkTheme : _cachedLightTheme;
    final cachedScheme = isDark ? _cachedDarkScheme : _cachedLightScheme;
    if (cachedTheme != null &&
        (identical(cachedScheme, colorScheme) || cachedScheme == colorScheme)) {
      return cachedTheme;
    }

    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.grey.shade200,
          ),
        ),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        elevation: 0,
        height: 60,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final lightScheme = _materialYouEnabled && lightDynamic != null
            ? lightDynamic
            : ColorScheme.fromSeed(
                seedColor: const Color(0xFF1A73E8),
                brightness: Brightness.light,
              );
        final darkScheme = _materialYouEnabled && darkDynamic != null
            ? darkDynamic
            : ColorScheme.fromSeed(
                seedColor: const Color(0xFF1A73E8),
                brightness: Brightness.dark,
              );
        return MaterialApp(
          navigatorKey: appNavigatorKey,
          title: 'Python运行器',
          debugShowCheckedModeBanner: false,
          themeMode: _themeMode,
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
          theme: _buildTheme(lightScheme),
          darkTheme: _buildTheme(darkScheme),
          home: SplashGate(
            child: HomePage(
              onThemeChanged: _setTheme,
              currentThemeMode: _themeMode,
              onMaterialYouChanged: _setMaterialYouEnabled,
              currentMaterialYouEnabled: _materialYouEnabled,
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
  final ValueChanged<ThemeMode> onThemeChanged;
  final ThemeMode currentThemeMode;
  final ValueChanged<bool> onMaterialYouChanged;
  final bool currentMaterialYouEnabled;

  const HomePage({
    super.key,
    required this.onThemeChanged,
    required this.currentThemeMode,
    required this.onMaterialYouChanged,
    required this.currentMaterialYouEnabled,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  final _appUpdateManager = AppUpdateManager();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(context.read<ExecutionProvider>().syncFloatingBallVisibility());
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
              onSettingsTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsPage(
                    onThemeChanged: widget.onThemeChanged,
                    currentThemeMode: widget.currentThemeMode,
                    onMaterialYouChanged: widget.onMaterialYouChanged,
                    currentMaterialYouEnabled: widget.currentMaterialYouEnabled,
                  ),
                  fullscreenDialog: true,
                ),
              ),
            ),
            const NetworkInspectorPage(),
            const PackageManagerPage(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.code), label: '脚本'),
            NavigationDestination(icon: Icon(Icons.http), label: '网络'),
            NavigationDestination(
                icon: Icon(Icons.inventory_2_outlined), label: '库管理'),
          ],
        ),
      ),
    );
  }
}
