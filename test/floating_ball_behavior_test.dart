import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:python_runner/providers/execution_provider.dart';
import 'package:python_runner/services/native_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('script stdout is not mirrored to floating ball output panel',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {
      'floating_ball_enabled': true,
    });

    ExecutionProvider.setNavigateToConsoleHandler(null);

    final bridge = _FloatingBallBridgeFake();
    final provider = ExecutionProvider(bridge);
    await provider.executeScript('demo.py');

    bridge.emitLog({
      'type': 'stdout',
      'content': 'normal terminal output',
      'timestamp': DateTime(2026).millisecondsSinceEpoch,
    });
    await tester.pump();

    expect(bridge.pushedOutputs, isEmpty);

    provider.dispose();
    await tester.pump(const Duration(milliseconds: 600));
    ExecutionProvider.setNavigateToConsoleHandler(null);
  });

  testWidgets(
      'pending floating-ball run navigates when callback registers later',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {
      'floating_ball_enabled': true,
    });
    ExecutionProvider.setNavigateToConsoleHandler(null);

    final bridge = _FloatingBallBridgePendingRunFake();
    final provider = ExecutionProvider(bridge);

    await tester.pump(const Duration(milliseconds: 700));
    expect(provider.currentScriptName, 'from_ball.py');

    String? firstNavigate;
    ExecutionProvider.setNavigateToConsoleHandler((scriptName) {
      firstNavigate = scriptName;
    });
    await tester.pump();
    expect(firstNavigate, 'from_ball.py');

    String? duplicateNavigate;
    ExecutionProvider.setNavigateToConsoleHandler((scriptName) {
      duplicateNavigate = scriptName;
    });
    await tester.pump();
    expect(duplicateNavigate, isNull);

    provider.dispose();
    await tester.pump(const Duration(milliseconds: 600));
    ExecutionProvider.setNavigateToConsoleHandler(null);
  });

  testWidgets('enabled floating ball is re-shown when app lifecycle resumes',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {
      'floating_ball_enabled': true,
    });
    ExecutionProvider.setNavigateToConsoleHandler(null);

    final bridge = _FloatingBallBridgeFake();
    final provider = ExecutionProvider(bridge);
    await tester.pump(const Duration(milliseconds: 100));
    bridge.shownScripts.clear();

    await provider.syncFloatingBallVisibility();

    expect(bridge.shownScripts, contains(''));

    provider.dispose();
    await tester.pump(const Duration(milliseconds: 600));
    ExecutionProvider.setNavigateToConsoleHandler(null);
  });

  test('floating ball does not auto-open running output panel', () {
    final source = File(
            'android/app/src/main/kotlin/com/daozhang/py/FloatingBallService.kt')
        .readAsStringSync();

    expect(source, isNot(contains('if (!isPanelVisible) showPanel()')));
    expect(source, isNot(contains('FLAG_LAYOUT_NO_LIMITS')));
    expect(source, contains('coerceIn(0, maxBallX())'));
    expect(source, contains('coerceIn(0, maxBallY())'));
  });

  test(
      'floating ball auto-collapses to an edge handle and tap expands it first',
      () {
    final source = File(
            'android/app/src/main/kotlin/com/daozhang/py/FloatingBallService.kt')
        .readAsStringSync();

    expect(source, contains('private var isCollapsed = true'));
    expect(source, contains('private fun collapseToEdge()'));
    expect(source, contains('private fun expandFromEdge()'));
    expect(source, contains('private fun revealBall('));
    expect(source, contains('private fun scheduleCollapse()'));
    expect(source, contains('if (isCollapsed) {'));
    expect(source, contains('expandFromEdge()'));
    expect(source, contains('scheduleCollapse()'));
    expect(source, contains('revealBall(5000L)'));
    expect(
      source,
      contains(
          'private val collapsedVisiblePx by lazy { (24 * density).toInt() }'),
    );
    expect(source, contains('collapsedVisiblePx'));
  });

  test('drag release collapses immediately after edge snap', () {
    final source = File(
            'android/app/src/main/kotlin/com/daozhang/py/FloatingBallService.kt')
        .readAsStringSync();
    final snapToEdgeBody = RegExp(
      r'private fun snapToEdge\(\) \{([\s\S]*?)\n    private fun maxBallX',
    ).firstMatch(source)!.group(1)!;

    expect(snapToEdgeBody, contains('collapseToEdge()'));
    expect(snapToEdgeBody, isNot(contains('scheduleCollapse()')));
  });

  test('drag release resets dragging state before snap so collapse can happen',
      () {
    final source = File(
            'android/app/src/main/kotlin/com/daozhang/py/FloatingBallService.kt')
        .readAsStringSync();

    expect(source, contains('MotionEvent.ACTION_UP -> {'));
    expect(source, contains('isDragging = false'));
    expect(source, contains('isInTrashZone = false'));
    expect(source, contains('snapToEdge()'));
  });

  test('expanded ball tap opens floating panel so quick-run remains available',
      () {
    final source = File(
            'android/app/src/main/kotlin/com/daozhang/py/FloatingBallService.kt')
        .readAsStringSync();

    expect(source, contains('showPanel()'));
    expect(source, contains('private fun openApp()'));
  });

  test(
      'floating ball script run intent is consumed on cold start and new intent',
      () {
    final source =
        File('android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt')
            .readAsStringSync();

    expect(
        source, contains('private fun handleRunScriptIntent(intent: Intent?)'));
    expect('handleRunScriptIntent(intent)'.allMatches(source).length,
        greaterThanOrEqualTo(2));
    expect(source, contains('setIntent(intent)'));
  });

  test('floating ball quick run uses MainActivity as the single pending source',
      () {
    final serviceSource = File(
            'android/app/src/main/kotlin/com/daozhang/py/FloatingBallService.kt')
        .readAsStringSync();
    final activitySource =
        File('android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt')
            .readAsStringSync();

    expect(serviceSource, contains('Intent.FLAG_ACTIVITY_CLEAR_TOP'));
    expect(serviceSource,
        isNot(contains('putString(KEY_PENDING_RUN_SCRIPT, name)')));
    expect(activitySource, contains('KEY_PENDING_RUN_SCRIPT'));
    expect(activitySource,
        contains('getSharedPreferences(FLOATING_BALL_PREFS_NAME'));
    expect(activitySource, contains('remove(KEY_PENDING_RUN_SCRIPT)'));
  });

  test('floating ball native bridge checks overlay permission before showing',
      () {
    final activitySource =
        File('android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt')
            .readAsStringSync();
    final settingsSource = [
      'lib/pages/settings_page.dart',
      'lib/pages/settings_actions.dart',
      'lib/pages/settings_sections.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');

    expect(activitySource, contains('private fun canShowFloatingBall()'));
    expect(
        activitySource, contains('android.provider.Settings.canDrawOverlays'));
    expect(activitySource, contains('startFloatingBallService(intent)'));
    expect(settingsSource, contains('_setFloatingBallEnabled'));
    expect(settingsSource, contains('_syncFloatingBallAfterPermissionReturn'));
    expect(settingsSource, contains('_syncFloatingBallNow'));
    expect(settingsSource, contains('WidgetsBindingObserver'));
    expect(settingsSource, contains('_setFloatingBallEnabled'));
    expect(settingsSource, contains('_syncFloatingBallAfterPermissionReturn'));
    expect(settingsSource, contains('syncFloatingBallVisibility()'));
    expect(settingsSource, contains('with WidgetsBindingObserver'));
    expect(settingsSource, isNot(contains("showFloatingBall('')")));
  });

  test('floating ball show waits for service addView result', () {
    final activitySource =
        File('android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt')
            .readAsStringSync();
    final serviceSource = File(
            'android/app/src/main/kotlin/com/daozhang/py/FloatingBallService.kt')
        .readAsStringSync();

    expect(activitySource, contains('ResultReceiver(mainHandler)'));
    expect(activitySource, contains('EXTRA_RESULT_RECEIVER'));
    expect(activitySource, contains('RESULT_SHOW_OK'));
    expect(activitySource, contains('postDelayed(timeoutRunnable!!, 2500L)'));
    expect(serviceSource, contains('const val EXTRA_RESULT_RECEIVER'));
    expect(serviceSource, contains('const val RESULT_SHOW_ERROR'));
    expect(serviceSource, contains('private fun reportShowResult'));
    expect(
        serviceSource,
        contains(
            'receiver?.send(if (success) RESULT_SHOW_OK else RESULT_SHOW_ERROR'));
    expect(serviceSource, contains('isAttachedToWindow'));
    expect(serviceSource, contains('windowManager?.addView(view, params)'));
    expect(serviceSource, contains('throw e'));
  });

  test('manual floating ball enable surfaces native failures', () {
    final providerSource =
        File('lib/providers/execution_provider.dart').readAsStringSync();
    final settingsActionsSource =
        File('lib/pages/settings_actions.dart').readAsStringSync();

    expect(providerSource,
        contains('syncFloatingBallVisibility({bool throwOnError = false})'));
    expect(providerSource, contains("source: 'FloatingBall'"));
    expect(settingsActionsSource,
        contains('syncFloatingBallVisibility(throwOnError: true)'));
    expect(settingsActionsSource,
        contains("prefs.setBool('floating_ball_enabled', false)"));
    expect(settingsActionsSource, contains('悬浮球显示失败：'));
  });

  test('home navigation uses ordinary tap switching only', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('NavigationBar('));
    expect(source, contains('onDestinationSelected: _selectTab'));
    expect(source, contains('Color.alphaBlend'));
    expect(
      source,
      isNot(contains('Timer(const Duration(milliseconds: 320)')),
    );
    expect(source, isNot(contains('_selectTabFromDrag')));
    expect(source, isNot(contains('_navigationDragActive')));
    expect(source, isNot(contains('AnimatedPositioned(')));
  });
  test('settings floating ball switch retries after overlay permission return',
      () {
    final settingsPageSource =
        File('lib/pages/settings_page.dart').readAsStringSync();
    final settingsActionsSource =
        File('lib/pages/settings_actions.dart').readAsStringSync();
    final settingsSectionsSource =
        File('lib/pages/settings_sections.dart').readAsStringSync();

    expect(settingsPageSource, contains('with WidgetsBindingObserver'));
    expect(settingsPageSource, contains('didChangeAppLifecycleState'));
    expect(settingsPageSource,
        contains('_syncFloatingBallAfterPermissionReturn()'));
    expect(settingsActionsSource, contains('_setFloatingBallEnabled'));
    expect(
        settingsActionsSource, contains('_waitingForFloatingBallPermission'));
    expect(settingsActionsSource, contains('_syncFloatingBallNow'));
    expect(settingsActionsSource,
        contains("prefs.setBool('floating_ball_enabled', false)"));
    expect(settingsActionsSource, contains('Duration(milliseconds: 350)'));
    expect(
        settingsSectionsSource, contains('onChanged: _setFloatingBallEnabled'));
  });

  test('app resume asks execution provider to restore the floating ball', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source,
        contains('void didChangeAppLifecycleState(AppLifecycleState state)'));
    expect(source, contains('AppLifecycleState.resumed'));
    expect(source, contains('syncFloatingBallVisibility()'));
  });

  test(
      'home page initial frame also asks execution provider to restore the floating ball',
      () {
    final source = File('lib/main.dart').readAsStringSync();
    final initStateBody = RegExp(
      r'class _HomePageState extends State<HomePage> \{([\s\S]*?)Future<void> _checkForUpdatesOnLaunch',
    ).firstMatch(source)!.group(1)!;

    expect(initStateBody, contains('syncFloatingBallVisibility()'));
  });
}

class _FloatingBallBridgeFake extends NativeBridge {
  final StreamController<Map<dynamic, dynamic>> _logController =
      StreamController<Map<dynamic, dynamic>>.broadcast();
  final Stream<Map<dynamic, dynamic>> _emptyStream =
      const Stream<Map<dynamic, dynamic>>.empty().asBroadcastStream();

  final List<String> pushedOutputs = <String>[];
  final List<String> shownScripts = <String>[];
  int hideCount = 0;

  @override
  Stream<Map<dynamic, dynamic>> get logStream => _logController.stream;

  @override
  Stream<Map<dynamic, dynamic>> get executionStatusStream => _emptyStream;

  @override
  Stream<Map<dynamic, dynamic>> get stdinRequestStream => _emptyStream;

  void emitLog(Map<dynamic, dynamic> data) {
    _logController.add(data);
  }

  @override
  Future<bool> checkOverlayPermission() async => true;

  @override
  Future<void> showFloatingBall(String scriptName) async {
    shownScripts.add(scriptName);
  }

  @override
  Future<void> pushFloatingBallOutput(String output) async {
    pushedOutputs.add(output);
  }

  @override
  Future<void> hideFloatingBall() async {
    hideCount++;
  }

  @override
  Future<String?> consumePendingRunScript() async => null;

  @override
  Future<void> executeScript(
    String name,
    String executionId, {
    String? workingDir,
    Map<String, String>? hookEnv,
    int? timeoutSeconds,
  }) async {}

  @override
  Future<void> stopExecution() async {}
}

class _FloatingBallBridgePendingRunFake extends _FloatingBallBridgeFake {
  bool _consumed = false;

  @override
  Future<String?> consumePendingRunScript() async {
    if (_consumed) return null;
    _consumed = true;
    return 'from_ball.py';
  }
}
