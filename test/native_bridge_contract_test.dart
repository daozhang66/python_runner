import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/pigeon/native_runtime_api.g.dart' as pigeon;
import 'package:python_runner/services/native_bridge.dart';
import 'package:python_runner/services/native_bridge_contract.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const validSha256 =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  const runtimeInfoChannel = BasicMessageChannel<Object?>(
    'dev.flutter.pigeon.python_runner.RuntimeHostApi.getLinuxLikeRuntimeInfo',
    pigeon.RuntimeHostApi.pigeonChannelCodec,
  );
  const nativeMethodChannel = MethodChannel(NativeBridgeContract.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger.setMockDecodedMessageHandler<Object?>(runtimeInfoChannel, null);
    messenger.setMockMethodCallHandler(nativeMethodChannel, null);
  });

  tearDown(() {
    messenger.setMockDecodedMessageHandler<Object?>(runtimeInfoChannel, null);
    messenger.setMockMethodCallHandler(nativeMethodChannel, null);
  });

  test('Dart contract rejects missing required native bridge arguments', () {
    expect(
      () => NativeBridgeContract.validate('startApkDownload', {
        'url': 'https://example.invalid/app.apk',
      }),
      throwsA(isA<NativeBridgeContractException>()),
    );
  });

  test('Dart contract requires valid SHA-256 for APK downloads', () {
    expect(
      () => NativeBridgeContract.validate('startApkDownload', {
        'url': 'https://example.invalid/app.apk',
        'fileName': 'app.apk',
      }),
      throwsA(
        isA<NativeBridgeContractException>()
            .having((e) => e.message, 'message', contains('"sha256"')),
      ),
    );

    expect(
      () => NativeBridgeContract.validate('startApkDownload', {
        'url': 'https://example.invalid/app.apk',
        'fileName': 'app.apk',
        'sha256': 'not-a-checksum',
      }),
      throwsA(
        isA<NativeBridgeContractException>()
            .having((e) => e.message, 'message', contains('SHA-256')),
      ),
    );

    expect(
      () => NativeBridgeContract.validate('startApkDownload', {
        'url': 'https://example.invalid/app.apk',
        'fileName': 'app.apk',
        'sha256': validSha256,
      }),
      returnsNormally,
    );
  });

  test('Dart contract allows intentionally empty content fields', () {
    expect(
      () => NativeBridgeContract.validate('saveScript', {
        'name': 'demo.py',
        'content': '',
      }),
      returnsNormally,
    );
  });

  test('NativeBridge converts contract errors to stable exception code',
      () async {
    final bridge = NativeBridge();

    await expectLater(
      bridge.startApkDownload('', fileName: 'app.apk', sha256: validSha256),
      throwsA(
        isA<NativeBridgeException>()
            .having(
                (e) => e.code, 'code', NativeBridgeContract.contractErrorCode)
            .having(
              (e) => e.rawCode,
              'rawCode',
              NativeBridgeContract.contractErrorCode.toString(),
            )
            .having((e) => e.message, 'message', contains('startApkDownload')),
      ),
    );
  });

  test('NativeBridge reads linux-like runtime info through Pigeon', () async {
    final bridge = NativeBridge.named(
      runtimeHostApi: _FakeRuntimeHostApi(
        pigeon.LinuxLikeRuntimeInfo(
          available: true,
          installed: true,
          message: 'ready',
          pythonPath: '/rootfs/usr/bin/python3',
          pipPath: '/rootfs/usr/bin/pip3',
          rootfsDir: '/rootfs',
        ),
      ),
    );

    final info = await bridge.getLinuxLikeRuntimeInfo();

    expect(info['available'], 'true');
    expect(info['installed'], 'true');
    expect(info['message'], 'ready');
    expect(info['pythonPath'], '/rootfs/usr/bin/python3');
    expect(info['pipPath'], '/rootfs/usr/bin/pip3');
    expect(info['rootfsDir'], '/rootfs');
  });

  test('malformed Pigeon replies fall back to MethodChannel runtime info',
      () async {
    messenger.setMockMethodCallHandler(nativeMethodChannel, (call) async {
      expect(call.method, 'getLinuxLikeRuntimeInfo');
      return {
        'available': 'true',
        'installed': 'true',
        'message': 'legacy-ready',
        'pythonPath': '/python',
        'pipPath': '/pip',
        'rootfsDir': '/rootfs',
      };
    });

    final malformedPayloads = <Object?>[
      const <Object?>[],
      <Object?>[true, 'not-a-bool', 'ready', '/python', '/pip', '/rootfs'],
      <Object?>[null, true, 'ready', '/python', '/pip', '/rootfs'],
    ];
    final bridge = NativeBridge.named();
    for (final payload in malformedPayloads) {
      messenger.setMockDecodedMessageHandler<Object?>(
          runtimeInfoChannel, (_) async => <Object?>[payload]);
      final info = await bridge.getLinuxLikeRuntimeInfo();
      expect(info['message'], 'legacy-ready');
    }
  });

  test('Pigeon TypeError, RangeError, and StateError use legacy fallback',
      () async {
    final fallbackMethods = <String>[];
    messenger.setMockMethodCallHandler(nativeMethodChannel, (call) async {
      fallbackMethods.add(call.method);
      switch (call.method) {
        case 'getLinuxLikeRuntimeInfo':
          return {
            'available': 'true',
            'installed': 'true',
            'message': 'legacy',
            'pythonPath': '/python',
            'pipPath': '/pip',
            'rootfsDir': '/rootfs',
          };
        case 'getFilePickerRoots':
          return <Object?>[];
        case 'getAppInfo':
          return {
            'appName': 'Python Runner',
            'packageName': 'com.daozhang.py',
            'version': '1.0.0',
            'buildNumber': '1',
          };
      }
      fail('Unexpected fallback method: ${call.method}');
    });

    final runtimeBridge = NativeBridge.named(
      runtimeHostApi: _ThrowingRuntimeHostApi(TypeError()),
    );
    final fileBridge = NativeBridge.named(
      filePickerHostApi: _ThrowingFilePickerHostApi(RangeError.index(1, [])),
    );
    final appBridge = NativeBridge.named(
      appHostApi: _ThrowingAppHostApi(StateError('malformed reply')),
    );

    expect(
        (await runtimeBridge.getLinuxLikeRuntimeInfo())['message'], 'legacy');
    expect(await fileBridge.getFilePickerRoots(), isEmpty);
    expect((await appBridge.getAppInfo())['buildNumber'], '1');
    expect(
      fallbackMethods,
      containsAll(
          ['getLinuxLikeRuntimeInfo', 'getFilePickerRoots', 'getAppInfo']),
    );
  });

  test('business Pigeon PlatformException does not fall back', () async {
    var fallbackCalls = 0;
    messenger.setMockMethodCallHandler(nativeMethodChannel, (call) async {
      fallbackCalls++;
      return <String, String>{};
    });
    final bridge = NativeBridge.named(
      runtimeHostApi: _ThrowingRuntimeHostApi(
        PlatformException(code: '4321', message: 'native failed'),
      ),
    );

    await expectLater(
      bridge.getLinuxLikeRuntimeInfo(),
      throwsA(
        isA<NativeBridgeException>()
            .having((e) => e.code, 'code', 4321)
            .having((e) => e.rawCode, 'rawCode', '4321'),
      ),
    );
    expect(fallbackCalls, 0);
  });

  test('non-numeric native error codes retain their raw value', () async {
    final directBridge = NativeBridge.named();
    messenger.setMockMethodCallHandler(nativeMethodChannel, (call) async {
      expect(call.method, 'startApkDownload');
      throw PlatformException(
        code: 'native-download-failed',
        message: 'download service unavailable',
      );
    });

    await expectLater(
      directBridge.startApkDownload(
        'https://example.invalid/app.apk',
        fileName: 'app.apk',
        sha256: validSha256,
      ),
      throwsA(
        isA<NativeBridgeException>()
            .having((e) => e.code, 'code', 1000)
            .having(
              (e) => e.rawCode,
              'rawCode',
              'native-download-failed',
            )
            .having(
              (e) => e.toString(),
              'toString',
              contains('rawCode=native-download-failed'),
            ),
      ),
    );

    final pigeonBridge = NativeBridge.named(
      runtimeHostApi: _ThrowingRuntimeHostApi(
        PlatformException(
            code: 'native-runtime-failed', message: 'unavailable'),
      ),
    );
    await expectLater(
      pigeonBridge.getLinuxLikeRuntimeInfo(),
      throwsA(
        isA<NativeBridgeException>().having((e) => e.code, 'code', 1000).having(
              (e) => e.rawCode,
              'rawCode',
              'native-runtime-failed',
            ),
      ),
    );
  });

  test('recoverable Pigeon channel codes still use MethodChannel fallback',
      () async {
    final fallbackCalls = <String>[];
    messenger.setMockMethodCallHandler(nativeMethodChannel, (call) async {
      fallbackCalls.add(call.method);
      return {
        'available': 'true',
        'installed': 'true',
        'message': 'legacy-ready',
        'pythonPath': '/python',
        'pipPath': '/pip',
        'rootfsDir': '/rootfs',
      };
    });

    for (final code in ['channel-error', 'null-error']) {
      final bridge = NativeBridge.named(
        runtimeHostApi: _ThrowingRuntimeHostApi(
          PlatformException(code: code, message: 'pigeon unavailable'),
        ),
      );
      expect(
        (await bridge.getLinuxLikeRuntimeInfo())['message'],
        'legacy-ready',
      );
    }
    expect(fallbackCalls, [
      'getLinuxLikeRuntimeInfo',
      'getLinuxLikeRuntimeInfo',
    ]);
  });

  test('NativeBridge reads app state queries through Pigeon', () async {
    final bridge = NativeBridge.named(
      runtimeHostApi: _FakeRuntimeHostApi(
        pigeon.LinuxLikeRuntimeInfo(
          available: true,
          installed: true,
          message: 'ready',
          pythonPath: '/rootfs/usr/bin/python3',
          pipPath: '/rootfs/usr/bin/pip3',
          rootfsDir: '/rootfs',
        ),
        pythonInfo: pigeon.NativePythonInfo(
          pythonVersion: '3.11.0',
          sitePackages: '/site-packages',
          pythonPath: '/python',
          chaquopyPipDir: '/pip',
        ),
      ),
      appHostApi: _FakeAppHostApi(
        appInfo: pigeon.NativeAppInfo(
          appName: 'Python Runner',
          packageName: 'com.daozhang.py',
          version: '1.2.3',
          buildNumber: '45',
        ),
      ),
    );

    final pythonInfo = await bridge.getPythonInfo();
    final appInfo = await bridge.getAppInfo();

    expect(pythonInfo['pythonVersion'], '3.11.0');
    expect(pythonInfo['sitePackages'], '/site-packages');
    expect(pythonInfo['pythonPath'], '/python');
    expect(pythonInfo['chaquopyPipDir'], '/pip');
    expect(appInfo['appName'], 'Python Runner');
    expect(appInfo['packageName'], 'com.daozhang.py');
    expect(appInfo['version'], '1.2.3');
    expect(appInfo['buildNumber'], '45');
  });

  test('NativeBridge reads file picker data through Pigeon', () async {
    final bridge = NativeBridge.named(
      filePickerHostApi: _FakeFilePickerHostApi(
        roots: [
          pigeon.NativeAppFileEntry(
            path: '/downloads',
            name: '下载',
            isDirectory: true,
            size: 0,
            modifiedAtMillis: 123,
          ),
        ],
        directoryEntries: [
          pigeon.NativeAppFileEntry(
            path: '/downloads/demo.py',
            name: 'demo.py',
            isDirectory: false,
            size: 12,
            modifiedAtMillis: 456,
          ),
        ],
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
    );

    final roots = await bridge.getFilePickerRoots();
    final entries = await bridge.listFilePickerDirectory('/downloads');
    final bytes = await bridge.readFilePickerFile('/downloads/demo.py');

    expect(roots.single.path, '/downloads');
    expect(roots.single.name, '下载');
    expect(roots.single.isDirectory, isTrue);
    expect(roots.single.modifiedAt, DateTime.fromMillisecondsSinceEpoch(123));
    expect(entries.single.path, '/downloads/demo.py');
    expect(entries.single.size, 12);
    expect(bytes, [1, 2, 3]);
  });

  test('Kotlin native bridge contract mirrors critical method requirements',
      () {
    final source = File(
      'android/app/src/main/kotlin/com/daozhang/py/NativeBridgeContract.kt',
    ).readAsStringSync();

    for (final entry in NativeBridgeContract.requiredStringArguments.entries) {
      expect(source, contains('"${entry.key}"'));
      for (final argument in entry.value) {
        expect(source, contains('"$argument"'));
      }
    }
    expect(source, contains('ERROR_CODE = "1000"'));
    expect(source, isNot(contains('FloatingBall')));
    expect(source, contains('requires non-empty string argument'));
    expect(source, contains('valid SHA-256 checksum'));
  });

  test('Pigeon bridges are generated and registered on Android', () {
    final pigeonDart = File(
      'lib/pigeon/native_runtime_api.g.dart',
    ).readAsStringSync();
    final pigeonKotlin = File(
      'android/app/src/main/kotlin/com/daozhang/py/NativeRuntimeApi.g.kt',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt',
    ).readAsStringSync();
    final runtimeInfoController = File(
      'android/app/src/main/kotlin/com/daozhang/py/RuntimeInfoController.kt',
    ).readAsStringSync();
    final appUpdateController = File(
      'android/app/src/main/kotlin/com/daozhang/py/AppUpdateController.kt',
    ).readAsStringSync();

    expect(pigeonDart, contains('class RuntimeHostApi'));
    expect(pigeonDart, contains('Future<LinuxLikeRuntimeInfo>'));
    expect(pigeonDart, contains('Future<NativePythonInfo>'));
    expect(pigeonDart, contains('class FilePickerHostApi'));
    expect(pigeonDart, contains('Future<List<NativeAppFileEntry>>'));
    expect(pigeonDart, contains('Future<Uint8List>'));
    expect(pigeonDart, contains('class AppHostApi'));
    expect(pigeonDart, contains('Future<NativeAppInfo>'));
    expect(pigeonDart, isNot(contains('OverlayPermission')));
    expect(pigeonDart, isNot(contains('PendingRunScript')));
    expect(pigeonKotlin, contains('interface RuntimeHostApi'));
    expect(pigeonKotlin, contains('data class LinuxLikeRuntimeInfo'));
    expect(pigeonKotlin, contains('data class NativePythonInfo'));
    expect(pigeonKotlin, contains('interface FilePickerHostApi'));
    expect(pigeonKotlin, contains('data class NativeAppFileEntry'));
    expect(pigeonKotlin, contains('interface AppHostApi'));
    expect(pigeonKotlin, contains('data class NativeAppInfo'));
    expect(mainActivity, contains('RuntimeHostApi.setUp'));
    expect(mainActivity, contains('FilePickerHostApi.setUp'));
    expect(mainActivity, contains('AppHostApi.setUp'));
    expect(runtimeInfoController, contains('getLinuxLikeRuntimeInfoForPigeon'));
    expect(runtimeInfoController, contains('getPythonInfoForPigeon'));
    expect(appUpdateController, contains('getAppInfoForPigeon'));
  });
}

class _FakeRuntimeHostApi extends pigeon.RuntimeHostApi {
  _FakeRuntimeHostApi(this.info, {this.pythonInfo});

  final pigeon.LinuxLikeRuntimeInfo info;
  final pigeon.NativePythonInfo? pythonInfo;

  @override
  Future<pigeon.LinuxLikeRuntimeInfo> getLinuxLikeRuntimeInfo() async => info;

  @override
  Future<pigeon.NativePythonInfo> getPythonInfo() async {
    final info = pythonInfo;
    if (info != null) return info;
    return super.getPythonInfo();
  }
}

class _FakeFilePickerHostApi extends pigeon.FilePickerHostApi {
  _FakeFilePickerHostApi({
    required this.roots,
    required this.directoryEntries,
    required this.bytes,
  });

  final List<pigeon.NativeAppFileEntry> roots;
  final List<pigeon.NativeAppFileEntry> directoryEntries;
  final Uint8List bytes;

  @override
  Future<List<pigeon.NativeAppFileEntry>> getFilePickerRoots() async => roots;

  @override
  Future<List<pigeon.NativeAppFileEntry>> listFilePickerDirectory(
    String path,
  ) async =>
      directoryEntries;

  @override
  Future<Uint8List> readFilePickerFile(String path) async => bytes;
}

class _FakeAppHostApi extends pigeon.AppHostApi {
  _FakeAppHostApi({
    required this.appInfo,
  });

  final pigeon.NativeAppInfo appInfo;

  @override
  Future<pigeon.NativeAppInfo> getAppInfo() async => appInfo;

}

class _ThrowingRuntimeHostApi extends pigeon.RuntimeHostApi {
  _ThrowingRuntimeHostApi(this.error);

  final Object error;

  @override
  Future<pigeon.LinuxLikeRuntimeInfo> getLinuxLikeRuntimeInfo() =>
      Future<pigeon.LinuxLikeRuntimeInfo>.error(error);
}

class _ThrowingFilePickerHostApi extends pigeon.FilePickerHostApi {
  _ThrowingFilePickerHostApi(this.error);

  final Object error;

  @override
  Future<List<pigeon.NativeAppFileEntry>> getFilePickerRoots() =>
      Future<List<pigeon.NativeAppFileEntry>>.error(error);
}

class _ThrowingAppHostApi extends pigeon.AppHostApi {
  _ThrowingAppHostApi(this.error);

  final Object error;

  @override
  Future<pigeon.NativeAppInfo> getAppInfo() =>
      Future<pigeon.NativeAppInfo>.error(error);
}
