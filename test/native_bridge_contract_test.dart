import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
    expect(source, contains('requires non-empty string argument'));
    expect(source, contains('valid SHA-256 checksum'));
  });
}
