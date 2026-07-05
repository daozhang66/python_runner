import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/pigeon/native_runtime_api.g.dart' as pigeon;
import 'package:python_runner/services/native_bridge.dart';
import 'package:python_runner/services/native_bridge_contract.dart';

void main() {
  const validSha256 =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

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

  test('Dart contract allows idle floating ball without script name', () {
    expect(
      () => NativeBridgeContract.validate('showFloatingBall', {
        'scriptName': '',
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
    expect(source, contains('"showFloatingBall.scriptName"'));
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

    expect(pigeonDart, contains('class RuntimeHostApi'));
    expect(pigeonDart, contains('Future<LinuxLikeRuntimeInfo>'));
    expect(pigeonDart, contains('class FilePickerHostApi'));
    expect(pigeonDart, contains('Future<List<NativeAppFileEntry>>'));
    expect(pigeonDart, contains('Future<Uint8List>'));
    expect(pigeonKotlin, contains('interface RuntimeHostApi'));
    expect(pigeonKotlin, contains('data class LinuxLikeRuntimeInfo'));
    expect(pigeonKotlin, contains('interface FilePickerHostApi'));
    expect(pigeonKotlin, contains('data class NativeAppFileEntry'));
    expect(mainActivity, contains('RuntimeHostApi.setUp'));
    expect(mainActivity, contains('FilePickerHostApi.setUp'));
    expect(runtimeInfoController, contains('getLinuxLikeRuntimeInfoForPigeon'));
  });
}

class _FakeRuntimeHostApi extends pigeon.RuntimeHostApi {
  _FakeRuntimeHostApi(this.info);

  final pigeon.LinuxLikeRuntimeInfo info;

  @override
  Future<pigeon.LinuxLikeRuntimeInfo> getLinuxLikeRuntimeInfo() async => info;
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
