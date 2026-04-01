import 'package:flutter/services.dart';
import 'dart:async';
import 'app_logger.dart';

class NativeBridge {
  static const _methodChannel = MethodChannel('com.daozhang.py/native_bridge');
  static const _logStreamChannel = EventChannel('com.daozhang.py/log_stream');
  static const _installProgressChannel = EventChannel('com.daozhang.py/install_progress');
  static const _executionStatusChannel = EventChannel('com.daozhang.py/execution_status');
  static const _stdinRequestChannel = EventChannel('com.daozhang.py/stdin_request');

  Stream<Map<dynamic, dynamic>>? _logStream;
  Stream<Map<dynamic, dynamic>>? _installProgressStream;
  Stream<Map<dynamic, dynamic>>? _executionStatusStream;
  Stream<Map<dynamic, dynamic>>? _stdinRequestStream;

  Stream<Map<dynamic, dynamic>> get logStream =>
      _logStream ??= _logStreamChannel.receiveBroadcastStream().map((e) => e as Map<dynamic, dynamic>).asBroadcastStream();

  Stream<Map<dynamic, dynamic>> get installProgressStream =>
      _installProgressStream ??= _installProgressChannel.receiveBroadcastStream().map((e) => e as Map<dynamic, dynamic>).asBroadcastStream();

  Stream<Map<dynamic, dynamic>> get executionStatusStream =>
      _executionStatusStream ??= _executionStatusChannel.receiveBroadcastStream().map((e) => e as Map<dynamic, dynamic>).asBroadcastStream();

  Stream<Map<dynamic, dynamic>> get stdinRequestStream =>
      _stdinRequestStream ??= _stdinRequestChannel.receiveBroadcastStream().map((e) => e as Map<dynamic, dynamic>).asBroadcastStream();

  Future<String> createScript(String name, {String content = ''}) async {
    final result = await _invoke('createScript', {'name': name, 'content': content});
    if (result is Map) {
      return result['path']?.toString() ?? name;
    }
    return result.toString();
  }

  Future<bool> deleteScript(String name) async {
    final result = await _invoke('deleteScript', {'name': name});
    return result as bool;
  }

  Future<bool> renameScript(String oldName, String newName) async {
    final result = await _invoke('renameScript', {'oldName': oldName, 'newName': newName});
    return result as bool;
  }

  Future<List<String>> listScripts() async {
    final result = await _invoke('listScripts', {});
    return (result as List).map((e) {
      if (e is Map) return e['name']?.toString() ?? '';
      return e.toString();
    }).where((n) => n.isNotEmpty).toList();
  }

  Future<String> readScript(String name) async {
    final result = await _invoke('readScript', {'name': name});
    return result as String;
  }

  Future<bool> saveScript(String name, String content) async {
    final result = await _invoke('saveScript', {'name': name, 'content': content});
    return result as bool;
  }

  Future<void> executeScript(String name, String executionId,
      {String? workingDir, Map<String, String>? hookEnv}) async {
    await _invoke('executeScript', {
      'name': name,
      'executionId': executionId,
      'workingDir': workingDir,
      'hookEnv': hookEnv,
    });
  }

  Future<void> stopExecution() async {
    await _invoke('stopExecution', {});
  }

  Future<void> sendStdin(String input) async {
    await _invoke('sendStdin', {'input': input});
  }

  Future<void> sendSceneTouch(String touchJson) async {
    await _invoke('sendSceneTouch', {'touchJson': touchJson});
  }

  Future<void> installPackage(String packageName, {String? version, String? indexUrl}) async {
    await _invoke('installPackage', {
      'packageName': packageName,
      'version': version,
      'indexUrl': indexUrl,
    });
  }

  Future<void> uninstallPackage(String packageName) async {
    await _invoke('uninstallPackage', {'packageName': packageName});
  }

  Future<List<Map<String, String>>> listInstalledPackages() async {
    final result = await _invoke('listInstalledPackages', {});
    return (result as List).map((e) {
      final map = e as Map;
      return map.map((k, v) => MapEntry(k.toString(), v.toString()));
    }).toList();
  }

  Future<String> importScriptFromUri(String uri, String name) async {
    final result = await _invoke('importScriptFromUri', {'uri': uri, 'name': name});
    return result as String;
  }

  Future<String> exportLog(String content, {String fileName = 'log.txt'}) async {
    final result = await _invoke('exportLog', {'content': content, 'fileName': fileName});
    return result as String;
  }

  Future<String> exportScript(String name, String destDir) async {
    final result = await _invoke('exportScript', {'name': name, 'destDir': destDir});
    return result as String;
  }

  Future<Map<String, String>> getPythonInfo() async {
    final result = await _invoke('getPythonInfo', {});
    final map = result as Map;
    return map.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  Future<dynamic> _invoke(String method, Map<String, dynamic> arguments) async {
    try {
      return await _methodChannel.invokeMethod(method, arguments);
    } on PlatformException catch (e) {
      AppLogger.instance.error(
        'NativeBridge调用失败: $method',
        source: 'NativeBridge',
        detail: 'code=${e.code}, message=${e.message}, args=$arguments',
      );
      throw NativeBridgeException(
        code: int.tryParse(e.code) ?? 1000,
        message: e.message ?? 'Unknown error',
      );
    }
  }
}

class NativeBridgeException implements Exception {
  final int code;
  final String message;
  NativeBridgeException({required this.code, required this.message});

  @override
  String toString() => 'NativeBridgeException($code): $message';
}
