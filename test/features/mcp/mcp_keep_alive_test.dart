import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:python_runner/providers/theme_provider.dart';
import 'package:python_runner/features/mcp/application/mcp_server_controller.dart';
import 'package:python_runner/services/native_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('cold start ignores legacy enabled flag and never constructs a server',
      () async {
    for (final enabled in [null, true, false]) {
      SharedPreferences.setMockInitialValues({
        if (enabled != null) McpServerController.enabledPrefsKey: enabled,
        McpServerController.portPrefsKey: 39001,
        McpServerController.requireTokenPrefsKey: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        mcpServerAdapterProvider
            .overrideWith((ref) => throw StateError('must not start')),
      ]);
      final state = container.read(mcpServerControllerProvider);
      expect(state.status, McpServerStatus.stopped);
      expect(state.port, 39001);
      expect(state.requireToken, isTrue);
      await container
          .read(mcpServerControllerProvider.notifier)
          .setEnabled(false);
      expect(prefs.containsKey(McpServerController.enabledPrefsKey), isFalse);
      container.dispose();
    }
    expect(File('lib/main.dart').readAsStringSync(),
        isNot(contains('restoreIfEnabled')));
  });
  test('authentication defaults off but preserves explicit choice', () async {
    for (final saved in [null, true, false]) {
      SharedPreferences.setMockInitialValues({
        if (saved != null) McpServerController.requireTokenPrefsKey: saved,
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ]);
      expect(container.read(mcpServerControllerProvider).requireToken,
          saved ?? false);
      expect(container.read(mcpServerControllerProvider.notifier).requireToken,
          saved ?? false);
      container.dispose();
    }
  });

  test('keep-alive bridge forwards explicit permission request and stop',
      () async {
    const channel = MethodChannel('com.daozhang.py/native_bridge');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return false;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    expect(
        await NativeBridge()
            .startMcpKeepAlive(requestPermission: true, showOverlay: true),
        isFalse);
    await NativeBridge().startMcpKeepAlive();
    await NativeBridge().hideMcpOverlay();
    await NativeBridge().stopMcpKeepAlive();
    expect(
        calls[0].arguments, {'requestPermission': true, 'showOverlay': true});
    expect(
        calls[1].arguments, {'requestPermission': false, 'showOverlay': false});
    expect(calls.last.method, 'stopMcpKeepAlive');
    expect(calls[2].method, 'hideMcpOverlay');
  });

  test('native service lease and activity teardown release keep-alive', () {
    final source = File(
            'android/app/src/main/kotlin/com/daozhang/py/McpKeepAliveService.kt')
        .readAsStringSync();
    expect(source, contains('wakeLock?.acquire(LEASE_MS)'));
    expect(source, contains('if (it.isHeld) it.release()'));
    expect(source, contains('stopForeground(STOP_FOREGROUND_REMOVE)'));
    expect(source, contains('WindowManager.LayoutParams(dp(48), dp(48)'));
    expect(source, contains('shape = GradientDrawable.OVAL'));
    expect(source, contains('clipChildren = true'));
    expect(source, contains('McpOverlayGeometry.recessedTranslation'));
    expect(source, contains('ball.translationX = 0f'));
    expect(source, contains('!revealOnly'));
    expect(source, contains('alpha(0.65f)'));
    expect(source, contains('layout.performLongClick()'));
    expect(source, contains('override fun dispatchTouchEvent'));
    expect(
        source, contains('MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL'));
    expect(source, contains('snapToEdge()'));
    expect(source, contains('McpOverlayGeometry.nearestEdge'));
    expect(source, contains('ValueAnimator.ofInt(params.x, targetOffset)'));
    expect(source, contains('placeAtEdge(destination, generation)'));
    expect(source, contains('getLocationOnScreen(actualPosition)'));
    expect(source, contains('generation != dockGeneration'));
    expect(source, contains('snapAnimator?.cancel()'));
    expect(source, contains('wm.maximumWindowMetrics'));
    expect(source, contains('setFitInsetsTypes(0)'));
    expect(source, isNot(contains('getWindowVisibleDisplayFrame')));
    expect(source, contains('intent.getBooleanExtra(HIDE, false)'));
    expect(source, contains('else if (intent.getBooleanExtra(SHOW, false))'));
    expect(source, isNot(contains('resources.displayMetrics.widthPixels')));
    final activity =
        File('android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt')
            .readAsStringSync();
    expect(activity,
        contains('mcpKeepAliveWanted && mcpOverlayPermissionPending'));
    expect(activity,
        contains('stopService(Intent(this, McpKeepAliveService::class.java))'));
  });
}
