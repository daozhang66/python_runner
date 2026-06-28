import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:python_runner/services/app_update_manager.dart';
import 'package:python_runner/services/native_bridge.dart';
import 'package:python_runner/services/update_service.dart';

/// A valid 64-hex SHA-256 used to satisfy the manager's security precondition.
const _validSha256 =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

AppUpdateInfo _updateInfoFixture() {
  final asset = ReleaseAssetInfo(
    name: 'python_runner-v1.1.0.apk',
    downloadUrl: 'https://example.com/app.apk',
    size: 123,
    contentType: 'application/vnd.android.package-archive',
    sha256: _validSha256,
  );
  return AppUpdateInfo(
    currentVersion: '1.0.0',
    latestVersion: '1.1.0',
    tagName: 'v1.1.0',
    releaseName: '1.1.0',
    releaseNotes: 'notes',
    htmlUrl: 'https://example.com/release',
    publishedAt: null,
    apkAsset: asset,
  );
}

Map<dynamic, dynamic> _event(String status, {String error = ''}) {
  return {
    'taskId': 'task-1',
    'type': 'apk_update',
    'status': status,
    'downloadedBytes': status == 'completed' ? 123 : 50,
    'totalBytes': 123,
    'progress': status == 'completed' ? 100 : 40,
    'speedBytesPerSecond': 1000,
    'etaSeconds': 1,
    'retryCount': 0,
    'filePath': status == 'completed' ? '/tmp/app.apk' : '',
    'errorCode': error.isEmpty ? '' : 'DOWNLOAD_FAILED',
    'errorMessage': error,
  };
}

Future<void> _openUpdateAndTapInstall(
  WidgetTester tester,
  AppUpdateManager manager,
) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => manager.checkForUpdates(context, manual: true),
          child: const Text('go'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  // Update dialog is shown; tap the primary update button.
  await tester.tap(find.text('立即更新'));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  testWidgets('completed event installs via native installDownloadedApk',
      (tester) async {
    final bridge = _UpdateBridgeFake();
    final manager = AppUpdateManager(
      bridge: bridge,
      updateService: _UpdateServiceFake(),
    );

    await _openUpdateAndTapInstall(tester, manager);

    expect(bridge.startCalls, 1);
    expect(bridge.startSha, _validSha256);

    bridge.emit(_event('downloading'));
    await tester.pump();
    bridge.emit(_event('completed'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(bridge.installedTaskIds, ['task-1']);
    await tester.pumpAndSettle();
  });

  testWidgets('failed event surfaces an error and installs nothing',
      (tester) async {
    final bridge = _UpdateBridgeFake();
    final manager = AppUpdateManager(
      bridge: bridge,
      updateService: _UpdateServiceFake(),
    );

    await _openUpdateAndTapInstall(tester, manager);
    bridge.emit(_event('failed', error: '服务器响应错误：500'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(bridge.installedTaskIds, isEmpty);
    expect(find.textContaining('更新失败'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('cancel button routes to native cancelDownload',
      (tester) async {
    final bridge = _UpdateBridgeFake();
    final manager = AppUpdateManager(
      bridge: bridge,
      updateService: _UpdateServiceFake(),
    );

    await _openUpdateAndTapInstall(tester, manager);
    bridge.emit(_event('downloading'));
    await tester.pump();

    await tester.tap(find.text('取消'));
    await tester.pump();

    expect(bridge.cancelledTaskIds, ['task-1']);
    expect(bridge.installedTaskIds, isEmpty);
    await tester.pumpAndSettle();
  });

  testWidgets('startApkDownload failure (install permission) is reported',
      (tester) async {
    final bridge = _UpdateBridgeFake(throwOnStart: true);
    final manager = AppUpdateManager(
      bridge: bridge,
      updateService: _UpdateServiceFake(),
    );

    await _openUpdateAndTapInstall(tester, manager);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(bridge.installedTaskIds, isEmpty);
    expect(find.textContaining('更新失败'), findsOneWidget);
    await tester.pumpAndSettle();
  });
}

class _UpdateServiceFake extends UpdateService {
  @override
  Future<AppUpdateInfo> fetchLatestRelease({required String currentVersion}) {
    return Future.value(_updateInfoFixture());
  }
}

class _UpdateBridgeFake extends NativeBridge {
  _UpdateBridgeFake({this.throwOnStart = false}) : super.named();

  final bool throwOnStart;
  final _controller = StreamController<Map<dynamic, dynamic>>.broadcast();

  int startCalls = 0;
  String? startSha;
  final List<String> installedTaskIds = [];
  final List<String> cancelledTaskIds = [];

  void emit(Map<dynamic, dynamic> event) => _controller.add(event);

  @override
  Stream<Map<dynamic, dynamic>> get downloadProgressStream =>
      _controller.stream;

  @override
  Future<Map<String, String>> getAppInfo() async => {'version': '1.0.0'};

  @override
  Future<String> startApkDownload(
    String url, {
    required String fileName,
    String version = '',
    required String sha256,
  }) async {
    startCalls++;
    startSha = sha256;
    if (throwOnStart) {
      throw NativeBridgeException(
        code: 1011,
        message: '请先允许此应用安装APK，然后再重试更新',
      );
    }
    return 'task-1';
  }

  @override
  Future<bool> cancelDownload(String taskId) async {
    cancelledTaskIds.add(taskId);
    return true;
  }

  @override
  Future<String> installDownloadedApk(String taskId) async {
    installedTaskIds.add(taskId);
    return '/tmp/app.apk';
  }
}
