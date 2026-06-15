import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('linux-like runtime uses bundled proot loader for guest ELF startup',
      () {
    final manager = File(
      'android/app/src/main/kotlin/com/daozhang/py/LinuxLikeRuntimeManager.kt',
    ).readAsStringSync();

    expect(manager, contains('/lib/ld-linux-aarch64.so.1'));
    expect(manager, contains('ensureGuestLoaderAliases'));
    expect(manager, contains('prootLoaderPath'));
    expect(manager, contains('PROOT_LOADER'));
    expect(manager, contains('prootRuntimeDir'));
    expect(manager, contains('proot_runtime/usr/libexec/proot/loader'));
    expect(manager, contains('legacyTermuxDir'));
    expect(manager, contains('add(pythonGuestPath)'));
    expect(manager, isNot(contains('add(nativeLinuxLikeLoaderGuestPath)')));
  });

  test('linux-like runtime removes downloaded archive after successful install',
      () {
    final manager = File(
      'android/app/src/main/kotlin/com/daozhang/py/LinuxLikeRuntimeManager.kt',
    ).readAsStringSync();

    expect(manager, contains('cleanupDownloadedArchive'));
    expect(manager, contains('archiveFile.delete()'));
    expect(manager, contains('downloadDir.delete()'));
    expect(
        manager, contains('"prootRuntimeDir" to prootRuntimeDir.absolutePath'));
  });

  test('linux-like manifest and archive downloads bypass stale HTTP caches',
      () {
    final manager = File(
      'android/app/src/main/kotlin/com/daozhang/py/LinuxLikeRuntimeManager.kt',
    ).readAsStringSync();

    expect(manager, contains('useCaches = false'));
    expect(manager, contains('"Cache-Control", "no-cache"'));
    expect(manager, contains('"Pragma", "no-cache"'));
  });

  test('linux-like runtime writes DNS resolver config before pip/network use',
      () {
    final manager = File(
      'android/app/src/main/kotlin/com/daozhang/py/LinuxLikeRuntimeManager.kt',
    ).readAsStringSync();
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(manager, contains('configureDnsResolver'));
    expect(manager, contains('readAndroidDnsServers'));
    expect(manager, contains('resolv.conf'));
    expect(manager, contains('nameserver'));
    expect(manager, contains('1.1.1.1'));
    expect(manifest, contains('android.permission.ACCESS_NETWORK_STATE'));
  });

  test('linux-like package list only exposes explicit user packages to the UI',
      () {
    final activity = File(
      'android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(activity, contains('resolveLinuxLikeExplicitPackages'));
    expect(activity, contains('REQUESTED'));
    expect(activity, contains('hostDistributions'));
    expect(activity, contains('queryLinuxLikeInstalledPackageVersions'));
    expect(activity, contains('installedPackageVersions'));
    expect(activity, contains('removeMissingLinuxLikeExplicitPackages'));
    expect(
        activity, contains('explicitPackages.contains(normalizedPackageName)'));
    expect(activity, contains('linux-like-package-list'));
    expect(
        activity,
        contains(
            '"source" to if (isExplicitUserPackage) "user" else "runtime"'));
  });

  test('linux-like package list migrates existing installs without metadata',
      () {
    final activity = File(
      'android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('resolveLinuxLikeExplicitPackages'));
    expect(activity, contains('readPythonPackageVersion'));
    expect(activity, contains('metadataOwnedTopLevels'));
    expect(activity, contains('requestedPackages'));
    expect(activity, contains('PYTHON_RUNNER_REQUESTED'));
    expect(activity, contains('markLinuxLikeExplicitDistributions'));
    expect(activity, contains('pruneLinuxLikeImplicitExplicitPackages'));
    expect(
        activity,
        contains(
            'explicitPackages.isEmpty() && topLevelPackages.isNotEmpty()'));
    expect(activity,
        isNot(contains('!linuxLikeImplicitDependencyPackages.contains(name)')));
    expect(activity, contains('saveLinuxLikeExplicitPackages(mergedPackages)'));
    expect(
        activity, contains('saveLinuxLikeExplicitPackages(resolvedPackages)'));
  });

  test('linux-like package install verifies pip actually installed package',
      () {
    final activity = File(
      'android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('verifyLinuxLikePackageInstalled'));
    expect(activity, contains('"show"'));
    expect(activity, contains('result.error("1019"'));
  });

  test('linux-like requirements install uses pip target and project guard', () {
    final activity = File(
      'android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('"installLinuxLikeRequirements"'));
    expect(activity, contains('handleInstallLinuxLikeRequirements'));
    expect(activity, contains('resolveLinuxLikeRequirementsTarget'));
    expect(activity,
        contains('safeProjectFile(projectKey, safeRequirementsPath)'));
    expect(activity,
        contains('linuxLikeRuntimeManager.userSitePackagesGuestPath'));
    expect(activity, contains('args.add("-r")'));
    expect(activity, contains('refreshLinuxLikeExplicitPackageMetadata'));
    expect(activity, contains('readLinuxLikeRequirementPackageNames'));
    expect(activity,
        contains('recordLinuxLikeExplicitPackages(requestedPackages)'));
    expect(activity, contains('result.error("1031"'));
  });

  test('linux-like uninstall records explicit packages and removes orphans',
      () {
    final activity = File(
      'android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final manager = File(
      'android/app/src/main/kotlin/com/daozhang/py/LinuxLikeRuntimeManager.kt',
    ).readAsStringSync();

    expect(activity, contains('recordLinuxLikeExplicitPackage'));
    expect(activity, contains('removeLinuxLikeExplicitPackage'));
    expect(activity, contains('cleanupLinuxLikeOrphanDependencies'));
    expect(activity, contains('removeLinuxLikePackagesFromOverlay'));
    expect(
        activity,
        contains(
            'resolveLinuxLikeExplicitPackages(\n                distributions,\n                emptyMap()'));
    expect(
        activity,
        isNot(contains(
            'resolveLinuxLikeExplicitPackages(\n                distributions,\n                queryLinuxLikeTopLevelPackages()')));
    expect(activity, contains('removedDependencies'));
    expect(manager, contains('explicit_user_packages.json'));
  });

  test('linux-like command temp directories are cleaned after each run', () {
    final activity = File(
      'android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt',
    ).readAsStringSync();
    final manager = File(
      'android/app/src/main/kotlin/com/daozhang/py/LinuxLikeRuntimeManager.kt',
    ).readAsStringSync();

    expect(activity, contains('cleanupExecutionTempDir'));
    expect(activity, contains('processBuilder.environment()["PROOT_TMP_DIR"]'));
    expect(manager, contains('fun cleanupExecutionTempDir('));
    expect(manager, contains('dir.deleteRecursively()'));
  });

  test(
      'linux-like scripts default to Download/PythonRunner and create cwd bind',
      () {
    final manager = File(
      'android/app/src/main/kotlin/com/daozhang/py/LinuxLikeRuntimeManager.kt',
    ).readAsStringSync();

    expect(
      manager,
      contains(
          'const val defaultScriptWorkingDir = "/storage/emulated/0/Download/PythonRunner"'),
    );
    expect(manager, contains('fun resolveScriptWorkingDir('));
    expect(manager, contains('ensureWorkingDirExists = true'));
    expect(manager, contains('hostWorkingDir.mkdirs()'));
    expect(manager, contains('addBind(command, hostWorkingDir.absolutePath)'));
  });

  test('linux-like user packages install into dedicated app-owned overlay path',
      () {
    final manager = File(
      'android/app/src/main/kotlin/com/daozhang/py/LinuxLikeRuntimeManager.kt',
    ).readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt',
    ).readAsStringSync();

    expect(manager, contains('userSitePackagesDir'));
    expect(manager, contains('userSitePackagesGuestPath'));
    expect(manager, contains('target["PYTHONPATH"]'));
    expect(manager,
        contains('"userSitePackagesDir" to userSitePackagesDir.absolutePath'));
    expect(activity, contains('"--target"'));
    expect(activity,
        contains('linuxLikeRuntimeManager.userSitePackagesGuestPath'));
  });

  test('linux-like process environment is stable across Android versions', () {
    final manager = File(
      'android/app/src/main/kotlin/com/daozhang/py/LinuxLikeRuntimeManager.kt',
    ).readAsStringSync();

    expect(manager, contains('target["HOME"] = "/root"'));
    expect(manager, contains('target["PATH"] ='));
    expect(manager, contains('target["TERM"] = "xterm-256color"'));
    expect(manager, contains('target["PIP_NO_INPUT"] = "1"'));
    expect(manager, contains('target["PYTHONDONTWRITEBYTECODE"] = "1"'));
    expect(manager, contains('target["PYTHONPYCACHEPREFIX"]'));
    expect(manager, contains('File(executionTempDir, "pycache")'));
    expect(
        manager,
        isNot(contains(
            'target["PYRUNNER_HTTP_HOOK_CONFIG"] = "{\\"record_requests\\": true}"')));
  });

  test('script execution environment sets TERM for terminal utilities', () {
    final provider = File(
      'lib/providers/execution_provider.dart',
    ).readAsStringSync();

    expect(provider, contains("'TERM': 'xterm-256color'"));
  });

  test('linux-like script execution HOME follows resolved working directory',
      () {
    final activity = File(
      'android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('resolveScriptWorkingDir(workingDir)'));
    expect(activity,
        contains('executionEnvironment["HOME"] = resolvedWorkingDir'));
    expect(activity, contains('processBuilder.environment(),'));
    expect(activity, contains('executionEnvironment'));
  });

  test('linux-like script launcher exposes cwd script path to user code', () {
    final manager = File(
      'android/app/src/main/kotlin/com/daozhang/py/LinuxLikeRuntimeManager.kt',
    ).readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt',
    ).readAsStringSync();

    expect(manager, contains('toPythonStringLiteral'));
    expect(manager, contains('add("-B")'));
    expect(manager, contains('sys.dont_write_bytecode = True'));
    expect(manager, contains('execution_file_path'));
    expect(manager, contains("'__file__': execution_file_path"));
    expect(manager,
        contains("sys.argv[0] = os.path.abspath(execution_file_path)"));
    expect(manager, contains("compile(_source, execution_file_path, 'exec')"));
    expect(activity, contains('executionFilePath = File('));
    expect(
        activity,
        contains(
            'linuxLikeRuntimeManager.resolveScriptWorkingDir(workingDir)'));
    expect(manager, isNot(contains('JSONObject.quote(scriptPath)')));
    expect(manager, isNot(contains(r"exec(open('$scriptPath').read())")));
    expect(manager, isNot(contains('runpy.run_path')));
  });

  test('linux-like script execution prevents and cleans pycache directories',
      () {
    final activity = File(
      'android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('deletePythonCacheDirectories'));
    expect(activity, contains('deletePythonCacheDirectory'));
    expect(activity, contains('isBroadPythonCacheCleanupRoot'));
    expect(activity, contains('file.name == "__pycache__"'));
    expect(activity, contains('pycacheCleanupRoots = listOf(projectRoot)'));
    expect(activity, contains('File(resolvedScriptWorkingDir)'));
    expect(activity, contains('projectRoot = projectRoot'));
    expect(activity, contains('executionTarget.pycacheCleanupRoots.forEach'));
  });

  test('linux-like launcher emits stdin request sentinel for interactive input',
      () {
    final manager = File(
      'android/app/src/main/kotlin/com/daozhang/py/LinuxLikeRuntimeManager.kt',
    ).readAsStringSync();

    expect(manager, contains('stdinRequestSentinel'));
    expect(manager, contains('_emit_stdin_request'));
    expect(manager, contains('sys.__stdout__.write'));
    expect(manager,
        isNot(contains('sys.__stderr__.write(stdin_request_sentinel')));
    expect(manager, contains('class _PythonRunnerStdin'));
    expect(manager, contains('builtins.input = _patched_input'));
    expect(manager, contains("return sys.stdin.readline().rstrip('\\\\n')"));
  });

  test('android bridge converts linux-like stdin sentinel into prompt events',
      () {
    final activity = File(
      'android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('emitStdinRequest('));
    expect(activity, contains('parseLinuxLikePrompt'));
    expect(
      activity,
      contains('line.startsWith(LinuxLikeRuntimeManager.stdinRequestSentinel)'),
    );
    expect(activity, isNot(contains('type == "stderr" &&')));
    expect(activity, contains('"prompt" to prompt'));
  });

  test('android script file operations use canonical safe script file guard',
      () {
    final activity = File(
      'android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt',
    ).readAsStringSync();
    final scriptStore = File(
      'android/app/src/main/kotlin/com/daozhang/py/ScriptFileStore.kt',
    ).readAsStringSync();

    expect(activity, contains('private fun normalizeScriptName('));
    expect(activity, contains('private fun safeScriptFile('));
    expect(activity, contains('scriptFileStore.safeScriptFile(name)'));
    expect(scriptStore, contains('canonicalFile'));
    expect(scriptStore, contains('startsWith(scriptsRoot.toPath())'));
    expect(activity, isNot(contains('File(scriptsDir(), name)')));
    expect(activity, isNot(contains('File(scriptsDir(), oldName)')));
    expect(activity, isNot(contains('File(scriptsDir(), newName)')));
  });

  test(
      'execution provider only enters waiting-input state for active execution',
      () {
    final provider = File(
      'lib/providers/execution_provider.dart',
    ).readAsStringSync();

    expect(provider, contains('final activeExecutionId = _state.executionId;'));
    expect(
      provider,
      contains('request.executionId != activeExecutionId'),
    );
    expect(provider, contains('_currentInputPrompt = request.prompt;'));
    expect(provider, contains("_updateFloatingBallStatus('waiting_input');"));
  });

  test('execution provider merges prompt-only stdin requests with user input',
      () {
    final provider = File(
      'lib/providers/execution_provider.dart',
    ).readAsStringSync();

    expect(provider, contains('_currentInputPrompt = request.prompt;'));
    expect(provider, contains("content: _currentInputPrompt,"));
    expect(
        provider,
        contains(
            "final echoedInput = prompt.isNotEmpty ? '\$prompt\$input' : '> \$input';"));
    expect(provider, contains('final mergedPromptLine ='));
    expect(provider, contains('prompt.isNotEmpty && _logs.isNotEmpty'));
    expect(provider, contains('_logs[_logs.length - 1] = entry;'));
  });

  test(
      'release build does not hardcode local signing passwords or apksigner path',
      () {
    final gradle = File('android/app/build.gradle').readAsStringSync();

    expect(gradle, isNot(contains('storePassword "daozhang123"')));
    expect(gradle, isNot(contains('keyPassword "daozhang123"')));
    expect(gradle, isNot(contains('D:/Android/Sdk/build-tools')));
    expect(gradle, contains('key.properties'));
  });

  test('code editor dependency uses local Flutter-compatible re_editor patch',
      () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final patchedInput = File(
      'third_party/re_editor/lib/src/_code_input.dart',
    ).readAsStringSync();

    expect(pubspec, contains('path: third_party/re_editor'));
    expect(pubspec, isNot(contains('re_editor: ^0.8.0')));
    expect(patchedInput, contains('bool onFocusReceived() => false;'));
  });

  test('code editor syntax highlighter ignores stale async results', () {
    final highlighter = File(
      'third_party/re_editor/lib/src/_code_highlight.dart',
    ).readAsStringSync();

    expect(highlighter, contains('int _highlightRevision = 0;'));
    expect(
      highlighter,
      contains('_controller.codeLines.equals(_controller.preValue?.codeLines)'),
    );
    expect(highlighter, contains('final int revision = ++_highlightRevision;'));
    expect(highlighter, contains('if (revision != _highlightRevision)'));
  });
}
