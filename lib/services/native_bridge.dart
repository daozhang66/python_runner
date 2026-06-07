import 'package:flutter/services.dart';
import 'dart:async';
import 'app_logger.dart';
import '../models/script_project_file.dart';
import 'project_path_validator.dart';
import 'script_name_validator.dart';

class NativeBridge {
  static const _methodChannel = MethodChannel('com.daozhang.py/native_bridge');
  static const _logStreamChannel = EventChannel('com.daozhang.py/log_stream');
  static const _installProgressChannel =
      EventChannel('com.daozhang.py/install_progress');
  static const _downloadProgressChannel =
      EventChannel('com.daozhang.py/download_progress');
  static const _executionStatusChannel =
      EventChannel('com.daozhang.py/execution_status');
  static const _stdinRequestChannel =
      EventChannel('com.daozhang.py/stdin_request');

  Stream<Map<dynamic, dynamic>>? _logStream;
  Stream<Map<dynamic, dynamic>>? _installProgressStream;
  Stream<Map<dynamic, dynamic>>? _downloadProgressStream;
  Stream<Map<dynamic, dynamic>>? _executionStatusStream;
  Stream<Map<dynamic, dynamic>>? _stdinRequestStream;

  Stream<Map<dynamic, dynamic>> get logStream =>
      _logStream ??= _logStreamChannel
          .receiveBroadcastStream()
          .map((e) => e as Map<dynamic, dynamic>)
          .asBroadcastStream();

  Stream<Map<dynamic, dynamic>> get installProgressStream =>
      _installProgressStream ??= _installProgressChannel
          .receiveBroadcastStream()
          .map((e) => e as Map<dynamic, dynamic>)
          .asBroadcastStream();

  Stream<Map<dynamic, dynamic>> get downloadProgressStream =>
      _downloadProgressStream ??= _downloadProgressChannel
          .receiveBroadcastStream()
          .map((e) => e as Map<dynamic, dynamic>)
          .asBroadcastStream();

  Stream<Map<dynamic, dynamic>> get executionStatusStream =>
      _executionStatusStream ??= _executionStatusChannel
          .receiveBroadcastStream()
          .map((e) => e as Map<dynamic, dynamic>)
          .asBroadcastStream();

  Stream<Map<dynamic, dynamic>> get stdinRequestStream =>
      _stdinRequestStream ??= _stdinRequestChannel
          .receiveBroadcastStream()
          .map((e) => e as Map<dynamic, dynamic>)
          .asBroadcastStream();

  Future<String> createScript(String name, {String content = ''}) async {
    final safeName = ScriptNameValidator.normalize(name);
    final result =
        await _invoke('createScript', {'name': safeName, 'content': content});
    if (result is Map) {
      return result['path']?.toString() ?? safeName;
    }
    return result.toString();
  }

  Future<bool> deleteScript(String name) async {
    final safeName = ScriptNameValidator.normalize(name);
    final result = await _invoke('deleteScript', {'name': safeName});
    if (result is bool) return result;
    return result == true;
  }

  Future<bool> renameScript(String oldName, String newName) async {
    final safeOldName = ScriptNameValidator.normalize(oldName);
    final safeNewName = ScriptNameValidator.normalize(newName);
    final result = await _invoke(
        'renameScript', {'oldName': safeOldName, 'newName': safeNewName});
    if (result is bool) return result;
    return result == true;
  }

  Future<List<String>> listScripts() async {
    final result = await _invoke('listScripts', {});
    return (result as List)
        .map((e) {
          if (e is Map) return e['name']?.toString() ?? '';
          return e.toString();
        })
        .where((n) => n.isNotEmpty)
        .toList();
  }

  Future<String> readScript(String name) async {
    final safeName = ScriptNameValidator.normalize(name);
    final result = await _invoke('readScript', {'name': safeName});
    return result?.toString() ?? '';
  }

  Future<bool> saveScript(String name, String content) async {
    final safeName = ScriptNameValidator.normalize(name);
    final result =
        await _invoke('saveScript', {'name': safeName, 'content': content});
    if (result is bool) return result;
    return result == true;
  }

  Future<void> executeScript(String name, String executionId,
      {String? workingDir,
      Map<String, String>? hookEnv,
      int? timeoutSeconds}) async {
    final safeName = ScriptNameValidator.normalize(name);
    await _invoke('executeScript', {
      'name': safeName,
      'executionId': executionId,
      'workingDir': workingDir,
      'hookEnv': hookEnv,
      'timeoutSeconds': timeoutSeconds,
    });
  }

  Future<void> stopExecution() async {
    await _invoke('stopExecution', {});
  }

  Future<void> sendStdin(String input) async {
    await _invoke('sendStdin', {'input': input});
  }

  Future<void> installPackage(String packageName,
      {String? version, String? indexUrl}) async {
    await _invoke('installPackage', {
      'packageName': packageName,
      'version': version,
      'indexUrl': indexUrl,
    });
  }

  Future<Map<String, dynamic>> uninstallPackage(String packageName) async {
    final result =
        await _invoke('uninstallPackage', {'packageName': packageName});
    return _dynamicMap(result);
  }

  Future<List<Map<String, String>>> listInstalledPackages() async {
    final result = await _invoke('listInstalledPackages', {});
    return (result as List).map((e) {
      final map = e as Map;
      return map.map((k, v) => MapEntry(k.toString(), v.toString()));
    }).toList();
  }

  Future<String> importScriptFromUri(String uri, String name) async {
    final safeName = ScriptNameValidator.normalize(name);
    final result =
        await _invoke('importScriptFromUri', {'uri': uri, 'name': safeName});
    return result?.toString() ?? '';
  }

  Future<String> exportLog(String content,
      {String fileName = 'log.txt', String? destDir}) async {
    final result = await _invoke('exportLog', {
      'content': content,
      'fileName': fileName,
      'destDir': destDir,
    });
    return result?.toString() ?? '';
  }

  Future<String> exportScript(String name, String destDir) async {
    final safeName = ScriptNameValidator.normalize(name);
    final result =
        await _invoke('exportScript', {'name': safeName, 'destDir': destDir});
    return result?.toString() ?? '';
  }

  Future<String> createScriptProject(String projectKey) async {
    final safeKey = ProjectPathValidator.normalizeProjectKey(projectKey);
    final result =
        await _invoke('createScriptProject', {'projectKey': safeKey});
    if (result is Map) {
      return result['path']?.toString() ?? '';
    }
    return result?.toString() ?? '';
  }

  Future<bool> deleteScriptProject(String projectKey) async {
    final safeKey = ProjectPathValidator.normalizeProjectKey(projectKey);
    final result =
        await _invoke('deleteScriptProject', {'projectKey': safeKey});
    if (result is bool) return result;
    return result == true;
  }

  Future<List<ScriptProjectFile>> listProjectFiles(String projectKey) async {
    final safeKey = ProjectPathValidator.normalizeProjectKey(projectKey);
    final result = await _invoke('listProjectFiles', {'projectKey': safeKey});
    return (result as List)
        .map((item) => ScriptProjectFile.fromMap(item as Map))
        .toList();
  }

  Future<String> readProjectFile(String projectKey, String path) async {
    final safeKey = ProjectPathValidator.normalizeProjectKey(projectKey);
    final safePath = ProjectPathValidator.normalizeRelativePath(path);
    final result = await _invoke(
      'readProjectFile',
      {'projectKey': safeKey, 'path': safePath},
    );
    return result?.toString() ?? '';
  }

  Future<bool> saveProjectFile(
      String projectKey, String path, String content) async {
    final safeKey = ProjectPathValidator.normalizeProjectKey(projectKey);
    final safePath = ProjectPathValidator.normalizeRelativePath(path);
    final result = await _invoke(
      'saveProjectFile',
      {'projectKey': safeKey, 'path': safePath, 'content': content},
    );
    if (result is bool) return result;
    return result == true;
  }

  Future<bool> createProjectDirectory(String projectKey, String path) async {
    final safeKey = ProjectPathValidator.normalizeProjectKey(projectKey);
    final safePath = ProjectPathValidator.normalizeRelativePath(path);
    final result = await _invoke(
      'createProjectDirectory',
      {'projectKey': safeKey, 'path': safePath},
    );
    if (result is bool) return result;
    return result == true;
  }

  Future<bool> deleteProjectEntry(String projectKey, String path) async {
    final safeKey = ProjectPathValidator.normalizeProjectKey(projectKey);
    final safePath = ProjectPathValidator.normalizeRelativePath(path);
    final result = await _invoke(
      'deleteProjectEntry',
      {'projectKey': safeKey, 'path': safePath},
    );
    if (result is bool) return result;
    return result == true;
  }

  Future<bool> renameProjectEntry(
      String projectKey, String oldPath, String newPath) async {
    final safeKey = ProjectPathValidator.normalizeProjectKey(projectKey);
    final safeOldPath = ProjectPathValidator.normalizeRelativePath(oldPath);
    final safeNewPath = ProjectPathValidator.normalizeRelativePath(newPath);
    final result = await _invoke(
      'renameProjectEntry',
      {
        'projectKey': safeKey,
        'oldPath': safeOldPath,
        'newPath': safeNewPath,
      },
    );
    if (result is bool) return result;
    return result == true;
  }

  Future<List<ScriptProjectFile>> importScriptProjectZip(
      String projectKey, String uri) async {
    final safeKey = ProjectPathValidator.normalizeProjectKey(projectKey);
    final result = await _invoke(
      'importScriptProjectZip',
      {'projectKey': safeKey, 'uri': uri},
    );
    return (result as List)
        .map((item) => ScriptProjectFile.fromMap(item as Map))
        .toList();
  }

  Future<String> exportScriptProjectZip(String projectKey,
      {String? destDir}) async {
    final safeKey = ProjectPathValidator.normalizeProjectKey(projectKey);
    final result = await _invoke(
      'exportScriptProjectZip',
      {'projectKey': safeKey, 'destDir': destDir},
    );
    return result?.toString() ?? '';
  }

  Future<Map<String, String>> getPythonInfo() async {
    final result = await _invoke('getPythonInfo', {});
    return _stringMap(result);
  }

  Future<Map<String, String>> getAppInfo() async {
    final result = await _invoke('getAppInfo', {});
    return _stringMap(result);
  }

  Future<Map<String, String>> getLinuxLikeRuntimeInfo() async {
    final result = await _invoke('getLinuxLikeRuntimeInfo', {});
    return _stringMap(result);
  }

  Future<Map<String, String>> prepareLinuxLikeRuntime() async {
    final result = await _invoke('prepareLinuxLikeRuntime', {});
    return _stringMap(result);
  }

  Future<Map<String, String>> installLinuxLikeRuntime({
    String? manifestUrl,
  }) async {
    final result = await _invoke('installLinuxLikeRuntime', {
      'manifestUrl': manifestUrl,
    });
    return _stringMap(result);
  }

  Future<void> executeLinuxLikeScript(String name, String executionId,
      {String? workingDir,
      Map<String, String>? environment,
      int? timeoutSeconds,
      String? projectKey,
      String? projectMainFilePath}) async {
    final safeName =
        projectKey == null ? ScriptNameValidator.normalize(name) : name.trim();
    final safeProjectKey = projectKey == null
        ? null
        : ProjectPathValidator.normalizeProjectKey(projectKey);
    final safeProjectMainFilePath = projectMainFilePath == null
        ? null
        : ProjectPathValidator.validateMainFilePath(projectMainFilePath);
    await _invoke('executeLinuxLikeScript', {
      'name': safeName,
      'executionId': executionId,
      'workingDir': workingDir,
      'environment': environment,
      'timeoutSeconds': timeoutSeconds,
      'projectKey': safeProjectKey,
      'projectMainFilePath': safeProjectMainFilePath,
    });
  }

  Future<void> sendLinuxLikeStdin(String input) async {
    await _invoke('sendLinuxLikeStdin', {'input': input});
  }

  Future<void> stopLinuxLikeExecution() async {
    await _invoke('stopLinuxLikeExecution', {});
  }

  Future<void> installLinuxLikePackage(String packageName,
      {String? version, String? indexUrl}) async {
    await _invoke('installLinuxLikePackage', {
      'packageName': packageName,
      'version': version,
      'indexUrl': indexUrl,
    });
  }

  Future<Map<String, dynamic>> uninstallLinuxLikePackage(
      String packageName) async {
    final result = await _invoke(
        'uninstallLinuxLikePackage', {'packageName': packageName});
    return _dynamicMap(result);
  }

  Future<List<Map<String, String>>> listLinuxLikePackages() async {
    final result = await _invoke('listLinuxLikePackages', {});
    return (result as List).map((e) {
      final map = e as Map;
      return map.map((k, v) => MapEntry(k.toString(), v.toString()));
    }).toList();
  }

  Future<void> openUrl(String url) async {
    await _invoke('openUrl', {'url': url});
  }

  Future<bool> checkOverlayPermission() async {
    final result = await _invoke('checkOverlayPermission', {});
    if (result is bool) return result;
    return result == true;
  }

  Future<void> requestOverlayPermission() async {
    await _invoke('requestOverlayPermission', {});
  }

  Future<void> showFloatingBall(String scriptName) async {
    await _invoke('showFloatingBall', {'scriptName': scriptName});
  }

  Future<void> hideFloatingBall() async {
    await _invoke('hideFloatingBall', {});
  }

  Future<void> updateFloatingBallStatus(String status) async {
    await _invoke('updateFloatingBallStatus', {'status': status});
  }

  Future<void> pushFloatingBallOutput(String output) async {
    await _invoke('pushFloatingBallOutput', {'output': output});
  }

  Future<String?> consumePendingRunScript() async {
    final result = await _invoke('consumePendingRunScript', {});
    if (result == null) return null;
    return result.toString();
  }

  Future<String> downloadAndInstallApk(String url,
      {required String fileName}) async {
    return startApkDownload(url, fileName: fileName);
  }

  Future<String> startApkDownload(
    String url, {
    required String fileName,
    String version = '',
    String? sha256,
  }) async {
    final result = await _invoke('startApkDownload', {
      'url': url,
      'fileName': fileName,
      'version': version,
      'sha256': sha256 ?? '',
    });
    return result?.toString() ?? '';
  }

  Future<bool> cancelDownload(String taskId) async {
    final result = await _invoke('cancelDownload', {'taskId': taskId});
    if (result is bool) return result;
    return result == true;
  }

  Future<bool> retryDownload(String taskId) async {
    final result = await _invoke('retryDownload', {'taskId': taskId});
    if (result is bool) return result;
    return result == true;
  }

  Future<String> installDownloadedApk(String taskId) async {
    final result = await _invoke('installDownloadedApk', {'taskId': taskId});
    return result?.toString() ?? '';
  }

  Map<String, String> _stringMap(dynamic result) {
    final map = result as Map;
    return map.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  Map<String, dynamic> _dynamicMap(dynamic result) {
    final map = result as Map;
    return map.map((k, v) => MapEntry(k.toString(), v));
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
