import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class MemoryTokenStorage extends FlutterSecureStorage {
  MemoryTokenStorage({this.value});

  String? value;
  bool failReads = false;
  bool failWrites = false;
  int reads = 0;
  int writes = 0;
  Completer<void>? readGate;
  Completer<void>? writeGate;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    reads++;
    await readGate?.future;
    if (failReads) throw StateError('Storage unavailable');
    return value;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    writes++;
    await writeGate?.future;
    if (failWrites) throw StateError('Write failed');
    this.value = value;
  }
}
