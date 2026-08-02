import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../pigeon/native_runtime_api.g.dart' as pigeon;
import 'app_logger.dart';
import 'native_bridge_contract.dart';
import '../models/app_file_entry.dart';
import '../models/script_project_file.dart';
import 'project_path_validator.dart';
import 'script_name_validator.dart';

/// Test-only source override for native event streams.
///
/// Production instances continue to receive events from the matching
/// [EventChannel]. Keeping this injectable lets stream reconnection behavior
/// be verified without an Android engine.
@visibleForTesting
typedef NativeBridgeEventStreamFactory = Stream<dynamic> Function(
  String channelName,
);

/// Dart facade for the Android `MethodChannel` and native event streams.
///
/// The bridge is intentionally a singleton for application code so event
/// streams are not recreated by each page. Tests can still subclass it through
/// [NativeBridge.named] to provide fakes without replacing [instance].
class NativeBridge {
  static final NativeBridge instance = NativeBridge.named();

  factory NativeBridge() => instance;

  static const _methodChannel = MethodChannel(NativeBridgeContract.channelName);
  static const _logStreamChannel = EventChannel('com.daozhang.py/log_stream');
  static const _installProgressChannel =
      EventChannel('com.daozhang.py/install_progress');
  static const _downloadProgressChannel =
      EventChannel('com.daozhang.py/download_progress');
  static const _executionStatusChannel =
      EventChannel('com.daozhang.py/execution_status');
  static const _stdinRequestChannel =
      EventChannel('com.daozhang.py/stdin_request');

  final pigeon.RuntimeHostApi _runtimeHostApi;
  final pigeon.FilePickerHostApi _filePickerHostApi;
  final pigeon.AppHostApi _appHostApi;
  final NativeBridgeEventStreamFactory _eventStreamFactory;

  NativeBridge.named({
    pigeon.RuntimeHostApi? runtimeHostApi,
    pigeon.FilePickerHostApi? filePickerHostApi,
    pigeon.AppHostApi? appHostApi,
    @visibleForTesting NativeBridgeEventStreamFactory? eventStreamFactory,
  })  : _runtimeHostApi = runtimeHostApi ?? pigeon.RuntimeHostApi(),
        _filePickerHostApi = filePickerHostApi ?? pigeon.FilePickerHostApi(),
        _appHostApi = appHostApi ?? pigeon.AppHostApi(),
        _eventStreamFactory = eventStreamFactory ?? _defaultEventStream;

  late final _ResettableEventStream<Map<dynamic, dynamic>> _logEvents =
      _eventStream('com.daozhang.py/log_stream');
  late final _ResettableEventStream<Map<dynamic, dynamic>>
      _installProgressEvents = _eventStream('com.daozhang.py/install_progress');
  late final _ResettableEventStream<Map<dynamic, dynamic>>
      _downloadProgressEvents =
      _eventStream('com.daozhang.py/download_progress');
  late final _ResettableEventStream<Map<dynamic, dynamic>>
      _executionStatusEvents = _eventStream('com.daozhang.py/execution_status');
  late final _ResettableEventStream<Map<dynamic, dynamic>> _stdinRequestEvents =
      _eventStream('com.daozhang.py/stdin_request');

  Stream<Map<dynamic, dynamic>> get logStream => _logEvents.stream;

  Stream<Map<dynamic, dynamic>> get installProgressStream =>
      _installProgressEvents.stream;

  Stream<Map<dynamic, dynamic>> get downloadProgressStream =>
      _downloadProgressEvents.stream;

  Stream<Map<dynamic, dynamic>> get executionStatusStream =>
      _executionStatusEvents.stream;

  Stream<Map<dynamic, dynamic>> get stdinRequestStream =>
      _stdinRequestEvents.stream;

  /// Rebinds native event sources without invalidating existing Dart listeners.
  ///
  /// This is a recovery hook for a controlled host after its native event
  /// sinks have been recreated. Call it only while script execution, package
  /// installation, and APK download work are all idle: an EventChannel event
  /// emitted during rebinding cannot be replayed.
  Future<void> resetEventStreams() {
    return Future.wait<void>([
      _logEvents.reset(),
      _installProgressEvents.reset(),
      _downloadProgressEvents.reset(),
      _executionStatusEvents.reset(),
      _stdinRequestEvents.reset(),
    ]);
  }

  _ResettableEventStream<Map<dynamic, dynamic>> _eventStream(
    String channelName,
  ) {
    return _ResettableEventStream<Map<dynamic, dynamic>>(
      () => _eventStreamFactory(channelName).map(_eventMap),
    );
  }

  static Stream<dynamic> _defaultEventStream(String channelName) {
    switch (channelName) {
      case 'com.daozhang.py/log_stream':
        return _logStreamChannel.receiveBroadcastStream();
      case 'com.daozhang.py/install_progress':
        return _installProgressChannel.receiveBroadcastStream();
      case 'com.daozhang.py/download_progress':
        return _downloadProgressChannel.receiveBroadcastStream();
      case 'com.daozhang.py/execution_status':
        return _executionStatusChannel.receiveBroadcastStream();
      case 'com.daozhang.py/stdin_request':
        return _stdinRequestChannel.receiveBroadcastStream();
      default:
        throw ArgumentError.value(
            channelName, 'channelName', 'Unknown channel');
    }
  }

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
    return _asBool(result);
  }

  Future<bool> renameScript(String oldName, String newName) async {
    final safeOldName = ScriptNameValidator.normalize(oldName);
    final safeNewName = ScriptNameValidator.normalize(newName);
    final result = await _invoke(
        'renameScript', {'oldName': safeOldName, 'newName': safeNewName});
    return _asBool(result);
  }

  Future<List<String>> listScripts() async {
    final result = await _invoke('listScripts', {});
    return _asList(result)
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
    return _asBool(result);
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
    return _asList(result).map((e) {
      final map = _asMap(e);
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

  Future<List<AppFileEntry>> getFilePickerRoots() async {
    return _withPigeonFallback(
      '文件根目录',
      () async {
        final entries = await _filePickerHostApi.getFilePickerRoots();
        return entries.map(_appFileEntryFromPigeon).toList();
      },
      () async {
        final result = await _invoke('getFilePickerRoots', {});
        return _asList(result)
            .map((item) => AppFileEntry.fromMap(_asMap(item)))
            .toList();
      },
    );
  }

  Future<List<AppFileEntry>> listFilePickerDirectory(String path) async {
    return _withPigeonFallback(
      '文件目录列表',
      () async {
        final entries = await _filePickerHostApi.listFilePickerDirectory(path);
        return entries.map(_appFileEntryFromPigeon).toList();
      },
      () async {
        final result = await _invoke('listFilePickerDirectory', {'path': path});
        return _asList(result)
            .map((item) => AppFileEntry.fromMap(_asMap(item)))
            .toList();
      },
    );
  }

  Future<AppFileEntry?> openFilePickerTree({String title = '选择目录'}) async {
    final result = await _invoke('openFilePickerTree', {'title': title});
    if (result == null) return null;
    return AppFileEntry.fromMap(_asMap(result));
  }

  Future<List<int>> readFilePickerFile(String path) async {
    return _withPigeonFallback(
      '文件读取',
      () => _filePickerHostApi.readFilePickerFile(path),
      () async {
        final result = await _invoke('readFilePickerFile', {'path': path});
        return _asList(result)
            .whereType<num>()
            .map((item) => item.toInt())
            .toList();
      },
    );
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
    return _asBool(result);
  }

  Future<List<ScriptProjectFile>> listProjectFiles(String projectKey) async {
    final safeKey = ProjectPathValidator.normalizeProjectKey(projectKey);
    final result = await _invoke('listProjectFiles', {'projectKey': safeKey});
    return _asList(result)
        .map((item) => ScriptProjectFile.fromMap(_asMap(item)))
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
    return _asBool(result);
  }

  Future<bool> createProjectDirectory(String projectKey, String path) async {
    final safeKey = ProjectPathValidator.normalizeProjectKey(projectKey);
    final safePath = ProjectPathValidator.normalizeRelativePath(path);
    final result = await _invoke(
      'createProjectDirectory',
      {'projectKey': safeKey, 'path': safePath},
    );
    return _asBool(result);
  }

  Future<bool> deleteProjectEntry(String projectKey, String path) async {
    final safeKey = ProjectPathValidator.normalizeProjectKey(projectKey);
    final safePath = ProjectPathValidator.normalizeRelativePath(path);
    final result = await _invoke(
      'deleteProjectEntry',
      {'projectKey': safeKey, 'path': safePath},
    );
    return _asBool(result);
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
    return _asBool(result);
  }

  Future<List<ScriptProjectFile>> importScriptProjectZip(
      String projectKey, String uri) async {
    final safeKey = ProjectPathValidator.normalizeProjectKey(projectKey);
    final result = await _invoke(
      'importScriptProjectZip',
      {'projectKey': safeKey, 'uri': uri},
    );
    return _asList(result)
        .map((item) => ScriptProjectFile.fromMap(_asMap(item)))
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
    return _withPigeonFallback(
      'Python信息',
      () async {
        final info = await _runtimeHostApi.getPythonInfo();
        return _pythonInfoFromPigeon(info);
      },
      () async {
        final result = await _invoke('getPythonInfo', {});
        return _stringMap(result);
      },
    );
  }

  Future<Map<String, String>> getAppInfo() async {
    return _withPigeonFallback(
      '应用信息',
      () async {
        final info = await _appHostApi.getAppInfo();
        return _appInfoFromPigeon(info);
      },
      () async {
        final result = await _invoke('getAppInfo', {});
        return _stringMap(result);
      },
    );
  }

  Future<Map<String, String>> getLinuxLikeRuntimeInfo() async {
    return _withPigeonFallback(
      '运行时信息',
      () async {
        final info = await _runtimeHostApi.getLinuxLikeRuntimeInfo();
        return {
          'available': info.available.toString(),
          'installed': info.installed.toString(),
          'message': info.message,
          'pythonPath': info.pythonPath,
          'pipPath': info.pipPath,
          'rootfsDir': info.rootfsDir,
        };
      },
      () async {
        final result = await _invoke('getLinuxLikeRuntimeInfo', {});
        return _stringMap(result);
      },
    );
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

  Future<void> repairLinuxLikePackage(String packageName,
      {String? version, String? indexUrl}) async {
    await _invoke('repairLinuxLikePackage', {
      'packageName': packageName,
      'version': version,
      'indexUrl': indexUrl,
    });
  }

  Future<void> installLinuxLikeRequirements({
    String? projectKey,
    String requirementsPath = 'requirements.txt',
    String? content,
    String displayName = 'requirements.txt',
    String? indexUrl,
  }) async {
    final safeProjectKey = projectKey == null || projectKey.trim().isEmpty
        ? null
        : ProjectPathValidator.normalizeProjectKey(projectKey);
    final safeRequirementsPath =
        ProjectPathValidator.normalizeRelativePath(requirementsPath);
    await _invoke('installLinuxLikeRequirements', {
      'projectKey': safeProjectKey,
      'requirementsPath': safeRequirementsPath,
      'content': content,
      'displayName': displayName,
      'indexUrl': indexUrl,
    });
  }

  Future<Map<String, dynamic>> uninstallLinuxLikePackage(
      String packageName) async {
    final result = await _invoke(
        'uninstallLinuxLikePackage', {'packageName': packageName});
    return _dynamicMap(result);
  }

  Future<List<Map<String, dynamic>>> listLinuxLikePackages() async {
    final result = await _invoke('listLinuxLikePackages', {});
    return _asList(result).map((e) {
      final map = _asMap(e);
      return map.map((k, v) => MapEntry(k.toString(), v));
    }).toList();
  }

  Future<void> openUrl(String url) async {
    await _invoke('openUrl', {'url': url});
  }

  Future<String> downloadAndInstallApk(
    String url, {
    required String fileName,
    required String sha256,
    String version = '',
  }) async {
    return startApkDownload(
      url,
      fileName: fileName,
      version: version,
      sha256: sha256,
    );
  }

  Future<String> startApkDownload(
    String url, {
    required String fileName,
    String version = '',
    required String sha256,
  }) async {
    final result = await _invoke('startApkDownload', {
      'url': url,
      'fileName': fileName,
      'version': version,
      'sha256': sha256,
    });
    return result?.toString() ?? '';
  }

  Future<bool> cancelDownload(String taskId) async {
    final result = await _invoke('cancelDownload', {'taskId': taskId});
    return _asBool(result);
  }

  Future<bool> retryDownload(String taskId) async {
    final result = await _invoke('retryDownload', {'taskId': taskId});
    return _asBool(result);
  }

  Future<String> installDownloadedApk(String taskId) async {
    final result = await _invoke('installDownloadedApk', {'taskId': taskId});
    return result?.toString() ?? '';
  }

  /// 直接安装指定路径的 APK 文件
  Future<void> installApkFile(String filePath) async {
    await _invoke('installApkFile', {'filePath': filePath});
  }

  Map<String, String> _stringMap(dynamic result) {
    final map = _asMap(result);
    return map.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  Map<String, dynamic> _dynamicMap(dynamic result) {
    final map = _asMap(result);
    return map.map((k, v) => MapEntry(k.toString(), v));
  }

  AppFileEntry _appFileEntryFromPigeon(pigeon.NativeAppFileEntry entry) {
    return AppFileEntry(
      path: entry.path,
      name: entry.name,
      isDirectory: entry.isDirectory,
      size: entry.size,
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(entry.modifiedAtMillis),
    );
  }

  Map<String, String> _pythonInfoFromPigeon(pigeon.NativePythonInfo info) {
    return {
      'pythonVersion': info.pythonVersion,
      'sitePackages': info.sitePackages,
      'pythonPath': info.pythonPath,
      'chaquopyPipDir': info.chaquopyPipDir,
    };
  }

  Map<String, String> _appInfoFromPigeon(pigeon.NativeAppInfo info) {
    return {
      'appName': info.appName,
      'packageName': info.packageName,
      'version': info.version,
      'buildNumber': info.buildNumber,
    };
  }

  Future<T> _withPigeonFallback<T>(
    String operation,
    Future<T> Function() pigeonCall,
    Future<T> Function() legacyFallback,
  ) async {
    try {
      return await pigeonCall();
    } on PlatformException catch (e) {
      if (!_isRecoverablePigeonPlatformException(e)) {
        _throwPigeonBridgeException(operation, e);
      }
      return _recoverPigeonResponse(operation, e, legacyFallback);
    } on TypeError catch (e) {
      return _recoverPigeonResponse(
        operation,
        _PigeonResponseFormatException(e),
        legacyFallback,
      );
    } on RangeError catch (e) {
      return _recoverPigeonResponse(
        operation,
        _PigeonResponseFormatException(e),
        legacyFallback,
      );
    } on StateError catch (e) {
      return _recoverPigeonResponse(
        operation,
        _PigeonResponseFormatException(e),
        legacyFallback,
      );
    } on ArgumentError catch (e) {
      return _recoverPigeonResponse(
        operation,
        _PigeonResponseFormatException(e),
        legacyFallback,
      );
    }
  }

  bool _isRecoverablePigeonPlatformException(PlatformException error) =>
      error.code == 'channel-error' || error.code == 'null-error';

  Future<T> _recoverPigeonResponse<T>(
    String operation,
    Object error,
    Future<T> Function() legacyFallback,
  ) async {
    AppLogger.instance.warn(
      'Pigeon$operation返回异常，回退MethodChannel',
      source: 'NativeBridge',
      detail: '${error.runtimeType}: $error',
    );
    return legacyFallback();
  }

  Never _throwPigeonBridgeException(String operation, PlatformException e) {
    AppLogger.instance.error(
      'Pigeon$operation调用失败',
      source: 'NativeBridge',
      detail: 'code=${e.code}, message=${e.message}',
    );
    throw _platformExceptionToNativeBridgeException(e);
  }

  NativeBridgeException _platformExceptionToNativeBridgeException(
    PlatformException error,
  ) {
    return NativeBridgeException(
      code: int.tryParse(error.code) ?? NativeBridgeContract.contractErrorCode,
      rawCode: error.code,
      message: error.message ?? 'Unknown error',
    );
  }

  static Map<dynamic, dynamic> _eventMap(dynamic event) {
    if (event is Map) return event;
    AppLogger.instance.warn(
      'Native event ignored because payload is not a map',
      source: 'NativeBridge',
      detail: 'payload=$event',
    );
    return <dynamic, dynamic>{};
  }

  bool _asBool(dynamic result) => result is bool ? result : result == true;

  List<dynamic> _asList(dynamic result) {
    if (result is List) return result;
    AppLogger.instance.warn(
      'NativeBridge returned non-list payload',
      source: 'NativeBridge',
      detail: 'payload=$result',
    );
    return const <dynamic>[];
  }

  Map<dynamic, dynamic> _asMap(dynamic result) {
    if (result is Map) return result;
    AppLogger.instance.warn(
      'NativeBridge returned non-map payload',
      source: 'NativeBridge',
      detail: 'payload=$result',
    );
    return const <dynamic, dynamic>{};
  }

  Future<dynamic> _invoke(String method, Map<String, dynamic> arguments) async {
    try {
      NativeBridgeContract.validate(method, arguments);
      return await _methodChannel.invokeMethod(method, arguments);
    } on NativeBridgeContractException catch (e) {
      AppLogger.instance.error(
        'NativeBridge参数校验失败: $method',
        source: 'NativeBridge',
        detail: e.message,
      );
      throw NativeBridgeException(
        code: NativeBridgeContract.contractErrorCode,
        rawCode: NativeBridgeContract.contractErrorCode.toString(),
        message: e.message,
      );
    } on PlatformException catch (e) {
      AppLogger.instance.error(
        'NativeBridge调用失败: $method',
        source: 'NativeBridge',
        detail: 'code=${e.code}, message=${e.message}, args=$arguments',
      );
      throw _platformExceptionToNativeBridgeException(e);
    }
  }
}

/// Keeps the public broadcast stream stable while its EventChannel source is
/// replaced. The source is subscribed only while at least one downstream
/// listener exists.
class _ResettableEventStream<T> {
  _ResettableEventStream(this._sourceFactory) {
    _controller = StreamController<T>.broadcast(
      onListen: _onListen,
      onCancel: _onCancel,
    );
  }

  final Stream<T> Function() _sourceFactory;
  late final StreamController<T> _controller;
  StreamSubscription<T>? _sourceSubscription;
  Future<void> _operation = Future<void>.value();
  int _generation = 0;
  bool _hasListeners = false;

  Stream<T> get stream => _controller.stream;

  Future<void> reset() => _scheduleRebind();

  void _onListen() {
    _hasListeners = true;
    unawaited(_scheduleRebind());
  }

  Future<void> _onCancel() {
    _hasListeners = false;
    return _scheduleRebind();
  }

  Future<void> _scheduleRebind() {
    final generation = ++_generation;
    final operation = _operation.then<void>((_) => _rebind(generation));
    // A failed cancellation must not leave the serial queue permanently
    // poisoned. The caller that initiated the reset still receives the error.
    _operation = operation.then<void>((_) {}, onError: (_, __) {});
    return operation;
  }

  Future<void> _rebind(int generation) async {
    final previous = _sourceSubscription;
    _sourceSubscription = null;
    await previous?.cancel();

    if (!_hasListeners || generation != _generation) return;

    var completed = false;
    StreamSubscription<T>? next;
    try {
      next = _sourceFactory().listen(
        (event) {
          if (_hasListeners && generation == _generation) {
            _controller.add(event);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (_hasListeners && generation == _generation) {
            _controller.addError(error, stackTrace);
          }
        },
        onDone: () {
          completed = true;
          if (identical(_sourceSubscription, next)) {
            _sourceSubscription = null;
          }
        },
      );
    } catch (error, stackTrace) {
      if (_hasListeners && generation == _generation) {
        _controller.addError(error, stackTrace);
      }
      return;
    }

    final nextSubscription = next;
    if (_hasListeners && generation == _generation && !completed) {
      _sourceSubscription = nextSubscription;
    } else {
      await nextSubscription.cancel();
    }
  }
}

class _PigeonResponseFormatException implements Exception {
  _PigeonResponseFormatException(this.cause);

  final Object cause;

  @override
  String toString() => 'Malformed Pigeon response: $cause';
}

class NativeBridgeException implements Exception {
  final int code;
  final String rawCode;
  final String message;
  NativeBridgeException({
    required this.code,
    required this.message,
    String? rawCode,
  }) : rawCode = rawCode ?? code.toString();

  @override
  String toString() {
    final codeDetail = rawCode == code.toString()
        ? code.toString()
        : '$code, rawCode=$rawCode';
    return 'NativeBridgeException($codeDetail): $message';
  }
}
