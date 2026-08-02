import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart' as legacy_provider;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../services/native_bridge.dart';
import '../services/app_logger.dart';
import '../services/app_update_manager.dart';
import '../services/network_debug_config.dart';
import '../services/request_override_config.dart';
import '../runtime/runtime_manager.dart';
import '../providers/execution_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/app_locale_provider.dart';
import '../providers/infrastructure_providers.dart';
import '../l10n/app_localizations.dart';
import '../widgets/app_dialogs.dart';
import 'update_log_page.dart';
import 'theme_settings_page.dart';
import 'app_logs_page.dart';
import 'app_file_picker_page.dart';
import 'request_override_editor_page.dart';

part 'settings_actions.dart';
part 'settings_sections.dart';
part 'settings_widgets.dart';

class SettingsPage extends ConsumerStatefulWidget {
  final ThemeMode currentThemeMode;

  const SettingsPage({
    super.key,
    required this.currentThemeMode,
  });

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _mirrorController = TextEditingController();
  String? _exportDir;
  String? _workingDir;
  final _proxyHostController = TextEditingController();
  final _proxyPortController = TextEditingController();
  final _githubMirrorController = TextEditingController();
  int _timeout = 60;
  bool _netDebugMode = false;
  bool _netAllowInsecure = false;
  bool _overrideEnabled = false;
  bool _recordRequests = true;
  bool _recordResponseBody = false;
  bool _autoCheckUpdates = true;
  String _runtimeBackend = RuntimeManager.chaquopyBackendId;
  final _bridge = NativeBridge();
  final _appUpdateManager = AppUpdateManager();
  bool _checkingUpdate = false;
  bool _linuxLikeAvailable = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: Text(AppLocalizations.of(context)!.settings),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          SliverList(
            delegate: SliverChildListDelegate([
              _buildAppearanceSection(),
              _buildRuntimeSection(),
              _buildNetworkDebugSection(),
              _buildDiagnosticsSection(),
              _buildAboutSection(),
            ]),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
        ],
      ),
    );
  }

  // ── Section builders ──

  @override
  void dispose() {
    _mirrorController.dispose();
    _proxyHostController.dispose();
    _proxyPortController.dispose();
    _githubMirrorController.dispose();
    super.dispose();
  }
}
