class NativeBridgeContract {
  const NativeBridgeContract._();

  static const channelName = 'com.daozhang.py/native_bridge';
  static const contractErrorCode = 1000;

  static const Map<String, List<String>> requiredStringArguments = {
    'createScript': ['name'],
    'deleteScript': ['name'],
    'renameScript': ['oldName', 'newName'],
    'readScript': ['name'],
    'saveScript': ['name'],
    'executeScript': ['name', 'executionId'],
    'sendStdin': ['input'],
    'installPackage': ['packageName'],
    'uninstallPackage': ['packageName'],
    'importScriptFromUri': ['uri', 'name'],
    'exportLog': ['content', 'fileName'],
    'exportScript': ['name'],
    'listFilePickerDirectory': ['path'],
    'openFilePickerTree': ['title'],
    'readFilePickerFile': ['path'],
    'createScriptProject': ['projectKey'],
    'deleteScriptProject': ['projectKey'],
    'listProjectFiles': ['projectKey'],
    'readProjectFile': ['projectKey', 'path'],
    'saveProjectFile': ['projectKey', 'path', 'content'],
    'createProjectDirectory': ['projectKey', 'path'],
    'deleteProjectEntry': ['projectKey', 'path'],
    'renameProjectEntry': ['projectKey', 'oldPath', 'newPath'],
    'importScriptProjectZip': ['projectKey', 'uri'],
    'exportScriptProjectZip': ['projectKey'],
    'executeLinuxLikeScript': ['name', 'executionId'],
    'sendLinuxLikeStdin': ['input'],
    'installLinuxLikePackage': ['packageName'],
    'repairLinuxLikePackage': ['packageName'],
    'installLinuxLikeRequirements': ['requirementsPath', 'displayName'],
    'uninstallLinuxLikePackage': ['packageName'],
    'openUrl': ['url'],
    'showFloatingBall': ['scriptName'],
    'updateFloatingBallStatus': ['status'],
    'pushFloatingBallOutput': ['output'],
    'downloadAndInstallApk': ['url', 'fileName', 'sha256'],
    'startApkDownload': ['url', 'fileName', 'sha256'],
    'cancelDownload': ['taskId'],
    'retryDownload': ['taskId'],
    'installDownloadedApk': ['taskId'],
  };

  static const Map<String, List<String>> optionalStringArguments = {
    'exportLog': ['destDir'],
    'exportScriptProjectZip': ['destDir'],
    'executeScript': ['workingDir'],
    'installPackage': ['version', 'indexUrl'],
    'executeLinuxLikeScript': [
      'workingDir',
      'projectKey',
      'projectMainFilePath',
    ],
    'installLinuxLikePackage': ['version', 'indexUrl'],
    'repairLinuxLikePackage': ['version', 'indexUrl'],
    'installLinuxLikeRequirements': ['projectKey', 'content', 'indexUrl'],
    'downloadAndInstallApk': ['version'],
    'startApkDownload': ['version'],
  };

  static final RegExp _sha256Pattern = RegExp(r'^[a-fA-F0-9]{64}$');

  static const Set<String> sha256StringArguments = {
    'downloadAndInstallApk.sha256',
    'startApkDownload.sha256',
  };

  static const Set<String> allowEmptyRequiredStrings = {
    'createScript.content',
    'saveScript.content',
    'exportLog.content',
    'saveProjectFile.content',
    'sendStdin.input',
    'sendLinuxLikeStdin.input',
    'showFloatingBall.scriptName',
    'pushFloatingBallOutput.output',
  };

  static const Set<String> knownMethods = {
    'createScript',
    'deleteScript',
    'renameScript',
    'listScripts',
    'readScript',
    'saveScript',
    'createScriptProject',
    'deleteScriptProject',
    'listProjectFiles',
    'readProjectFile',
    'saveProjectFile',
    'createProjectDirectory',
    'deleteProjectEntry',
    'renameProjectEntry',
    'importScriptProjectZip',
    'exportScriptProjectZip',
    'executeScript',
    'stopExecution',
    'sendStdin',
    'installPackage',
    'uninstallPackage',
    'listInstalledPackages',
    'importScriptFromUri',
    'exportLog',
    'exportScript',
    'getFilePickerRoots',
    'listFilePickerDirectory',
    'openFilePickerTree',
    'readFilePickerFile',
    'openUrl',
    'downloadAndInstallApk',
    'startApkDownload',
    'cancelDownload',
    'retryDownload',
    'installDownloadedApk',
    'getAppInfo',
    'getPythonInfo',
    'getLinuxLikeRuntimeInfo',
    'prepareLinuxLikeRuntime',
    'installLinuxLikeRuntime',
    'executeLinuxLikeScript',
    'sendLinuxLikeStdin',
    'stopLinuxLikeExecution',
    'installLinuxLikePackage',
    'repairLinuxLikePackage',
    'installLinuxLikeRequirements',
    'uninstallLinuxLikePackage',
    'listLinuxLikePackages',
    'moveToBackground',
    'checkOverlayPermission',
    'requestOverlayPermission',
    'showFloatingBall',
    'hideFloatingBall',
    'updateFloatingBallStatus',
    'pushFloatingBallOutput',
    'consumePendingRunScript',
  };

  static void validate(String method, Map<String, dynamic> arguments) {
    if (!knownMethods.contains(method)) return;
    final required = requiredStringArguments[method] ?? const <String>[];
    for (final key in required) {
      if (!arguments.containsKey(key)) {
        throw NativeBridgeContractException(
          'Method $method requires string argument "$key"',
        );
      }
      final value = arguments[key];
      if (value is! String) {
        throw NativeBridgeContractException(
          'Method $method argument "$key" must be a string',
        );
      }
      if (!allowEmptyRequiredStrings.contains('$method.$key') &&
          value.trim().isEmpty) {
        throw NativeBridgeContractException(
          'Method $method requires non-empty string argument "$key"',
        );
      }
    }

    final optional = optionalStringArguments[method] ?? const <String>[];
    for (final key in [...required, ...optional]) {
      final value = arguments[key];
      if (value != null && value is! String) {
        throw NativeBridgeContractException(
          'Method $method argument "$key" must be a string when provided',
        );
      }
      if (value is String &&
          sha256StringArguments.contains('$method.$key') &&
          !_sha256Pattern.hasMatch(value.trim())) {
        throw NativeBridgeContractException(
          'Method $method argument "$key" must be a valid SHA-256 checksum',
        );
      }
    }
  }
}

class NativeBridgeContractException implements Exception {
  final String message;

  const NativeBridgeContractException(this.message);

  @override
  String toString() => message;
}
