import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../services/native_bridge.dart';
import '../services/app_logger.dart';
import '../services/app_update_manager.dart';
import '../services/network_debug_config.dart';
import '../services/request_override_config.dart';
import '../runtime/runtime_manager.dart';
import '../ui/app_design_tokens.dart';
import '../ui/app_theme_palette.dart';
import 'update_log_page.dart';

part 'settings_actions.dart';
part 'settings_sections.dart';
part 'settings_widgets.dart';

class SettingsPage extends StatefulWidget {
  final ValueChanged<ThemeMode> onThemeChanged;
  final ThemeMode currentThemeMode;
  final ValueChanged<AppThemePalette> onThemePaletteChanged;
  final AppThemePalette currentThemePalette;
  final ValueChanged<bool> onMaterialYouChanged;
  final bool currentMaterialYouEnabled;

  const SettingsPage({
    super.key,
    required this.onThemeChanged,
    required this.currentThemeMode,
    required this.onThemePaletteChanged,
    required this.currentThemePalette,
    required this.onMaterialYouChanged,
    required this.currentMaterialYouEnabled,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _mirrorController = TextEditingController();
  final _exportDirController = TextEditingController();
  final _workingDirController = TextEditingController();
  final _proxyHostController = TextEditingController();
  final _proxyPortController = TextEditingController();
  final _globalUaController = TextEditingController();
  final _globalHeadersController = TextEditingController();
  final _globalCookieController = TextEditingController();
  final _githubMirrorController = TextEditingController();
  int _timeout = 60;
  bool _netDebugMode = false;
  bool _netAllowInsecure = false;
  bool _overrideEnabled = false;
  bool _recordRequests = true;
  bool _recordResponseBody = false;
  int _defaultHttpTimeout = 30;
  bool _followRedirects = true;
  bool _forceProxy = false;
  String? _requestConfigError;
  bool _autoCheckUpdates = true;
  bool _floatingBallEnabled = false;
  String _runtimeBackend = RuntimeManager.chaquopyBackendId;
  final _bridge = NativeBridge();
  final _appUpdateManager = AppUpdateManager();
  bool _checkingUpdate = false;
  bool _installingLinuxLike = false;
  bool _linuxLikeAvailable = false;
  int _engineDropdownKey = 0;
  String _installStage = '';
  int _installPercent = 0;
  String _installMessage = '';
  StreamSubscription? _installProgressSub;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ── General ──
          _buildAppearanceSection(),

          _buildRuntimeSection(),
          _buildNetworkDebugSection(),
          _buildDiagnosticsSection(),
          _buildAboutSection(),
        ],
      ),
    );
  }

  // ── Section builders ──

  @override
  void dispose() {
    _installProgressSub?.cancel();
    _mirrorController.dispose();
    _exportDirController.dispose();
    _workingDirController.dispose();
    _proxyHostController.dispose();
    _proxyPortController.dispose();
    _globalUaController.dispose();
    _globalHeadersController.dispose();
    _globalCookieController.dispose();
    _githubMirrorController.dispose();
    super.dispose();
  }
}
