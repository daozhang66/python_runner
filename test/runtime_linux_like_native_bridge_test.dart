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
    final packageController = File(
      'android/app/src/main/kotlin/com/daozhang/py/LinuxLikePackageController.kt',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(packageController, contains('resolveLinuxLikeExplicitPackages'));
    expect(packageController, contains('REQUESTED'));
    expect(packageController, contains('hostDistributions'));
    expect(
        packageController, contains('queryLinuxLikeInstalledPackageVersions'));
    expect(packageController, contains('installedPackageVersions'));
    expect(
        packageController, contains('removeMissingLinuxLikeExplicitPackages'));
    expect(packageController,
        contains('explicitPackages.contains(normalizedPackageName)'));
    expect(packageController, contains('linux-like-package-list'));
    expect(
        packageController,
        contains(
            '"source" to if (isExplicitUserPackage) "user" else "runtime"'));
  });

  test('linux-like package list migrates existing installs without metadata',
      () {
    final packageController = File(
      'android/app/src/main/kotlin/com/daozhang/py/LinuxLikePackageController.kt',
    ).readAsStringSync();

    expect(packageController, contains('resolveLinuxLikeExplicitPackages'));
    expect(packageController, contains('readPythonPackageVersion'));
    expect(packageController, contains('metadataOwnedTopLevels'));
    expect(packageController, contains('requestedPackages'));
    expect(packageController, contains('PYTHON_RUNNER_REQUESTED'));
    expect(packageController, contains('markLinuxLikeExplicitDistributions'));
    expect(
        packageController, contains('pruneLinuxLikeImplicitExplicitPackages'));
    expect(
        packageController,
        contains(
            'explicitPackages.isEmpty() && topLevelPackages.isNotEmpty()'));
    expect(packageController,
        isNot(contains('!linuxLikeImplicitDependencyPackages.contains(name)')));
    expect(packageController,
        contains('saveLinuxLikeExplicitPackages(mergedPackages)'));
    expect(packageController,
        contains('saveLinuxLikeExplicitPackages(resolvedPackages)'));
  });

  test('linux-like package install verifies pip actually installed package',
      () {
    final packageController = File(
      'android/app/src/main/kotlin/com/daozhang/py/LinuxLikePackageController.kt',
    ).readAsStringSync();

    expect(packageController, contains('verifyLinuxLikePackageInstalled'));
    expect(packageController, contains('"show"'));
    expect(packageController, contains('result.error("1019"'));
  });

  test('linux-like package list exposes structure integrity fields', () {
    final packageController = File(
      'android/app/src/main/kotlin/com/daozhang/py/LinuxLikePackageController.kt',
    ).readAsStringSync();

    expect(packageController, contains('resolveLinuxLikeIntegrity'));
    expect(packageController, contains('inferLinuxLikeImportRoots'));
    expect(packageController, contains('top_level.txt'));
    expect(packageController, contains('RECORD'));
    expect(packageController, contains('"integrityStatus"'));
    expect(packageController, contains('"integrityMessage"'));
    expect(packageController, contains('"missingImports"'));
    expect(packageController, contains('"broken"'));
    expect(packageController, contains('"unknown"'));
    expect(packageController, contains(r'缺少 ${missingImports.joinToString'));
    expect(packageController, contains('linuxLikeImportRootExists'));
    expect(packageController, isNot(contains('importlib.import_module')));
  });

  test('linux-like package repair uses force reinstall into target overlay',
      () {
    final activity = File(
      'android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt',
    ).readAsStringSync();
    final contract = File(
      'android/app/src/main/kotlin/com/daozhang/py/NativeBridgeContract.kt',
    ).readAsStringSync();
    final packageController = File(
      'android/app/src/main/kotlin/com/daozhang/py/LinuxLikePackageController.kt',
    ).readAsStringSync();

    expect(activity, contains('"repairLinuxLikePackage"'));
    expect(activity,
        contains('linuxLikePackageController.repairLinuxLikePackage'));
    expect(contract,
        contains('"repairLinuxLikePackage" to listOf("packageName")'));
    expect(packageController, contains('fun repairLinuxLikePackage'));
    expect(packageController, contains('"--target"'));
    expect(packageController,
        contains('linuxLikeRuntimeManager.userSitePackagesGuestPath'));
    expect(packageController, contains('"--upgrade"'));
    expect(packageController, contains('"--force-reinstall"'));
    expect(packageController, contains('linux-like-pip-repair'));
    expect(
        packageController, contains('refreshLinuxLikeExplicitPackageMetadata'));
  });

  test('linux-like requirements install uses pip target and project guard', () {
    final activity = File(
      'android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt',
    ).readAsStringSync();
    final packageController = File(
      'android/app/src/main/kotlin/com/daozhang/py/LinuxLikePackageController.kt',
    ).readAsStringSync();

    expect(activity, contains('"installLinuxLikeRequirements"'));
    expect(activity,
        contains('linuxLikePackageController.installLinuxLikeRequirements'));
    expect(packageController, contains('fun installLinuxLikeRequirements'));
    expect(packageController, contains('resolveLinuxLikeRequirementsTarget'));
    expect(
        packageController,
        contains(
            'scriptProjectStore.safeProjectFile(projectKey, safeRequirementsPath)'));
    expect(packageController,
        contains('linuxLikeRuntimeManager.userSitePackagesGuestPath'));
    expect(packageController, contains('args.add("-r")'));
    expect(
        packageController, contains('refreshLinuxLikeExplicitPackageMetadata'));
    expect(packageController, contains('readLinuxLikeRequirementPackageNames'));
    expect(packageController,
        contains('recordLinuxLikeExplicitPackages(requestedPackages)'));
    expect(packageController, contains('result.error("1031"'));
  });

  test('linux-like uninstall records explicit packages and removes orphans',
      () {
    final packageController = File(
      'android/app/src/main/kotlin/com/daozhang/py/LinuxLikePackageController.kt',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final manager = File(
      'android/app/src/main/kotlin/com/daozhang/py/LinuxLikeRuntimeManager.kt',
    ).readAsStringSync();

    expect(packageController, contains('recordLinuxLikeExplicitPackage'));
    expect(packageController, contains('removeLinuxLikeExplicitPackage'));
    expect(packageController, contains('cleanupLinuxLikeOrphanDependencies'));
    expect(packageController, contains('removeLinuxLikePackagesFromOverlay'));
    expect(
        packageController,
        contains(
            'resolveLinuxLikeExplicitPackages(\n                distributions,\n                emptyMap()'));
    expect(
        packageController,
        isNot(contains(
            'resolveLinuxLikeExplicitPackages(\n                distributions,\n                queryLinuxLikeTopLevelPackages()')));
    expect(packageController, contains('removedDependencies'));
    expect(manager, contains('explicit_user_packages.json'));
  });

  test('linux-like command temp directories are cleaned after each run', () {
    final executionController = File(
      'android/app/src/main/kotlin/com/daozhang/py/ScriptExecutionController.kt',
    ).readAsStringSync();
    final manager = File(
      'android/app/src/main/kotlin/com/daozhang/py/LinuxLikeRuntimeManager.kt',
    ).readAsStringSync();

    expect(executionController, contains('cleanupExecutionTempDir'));
    expect(executionController,
        contains('processBuilder.environment()["PROOT_TMP_DIR"]'));
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
    final packageController = File(
      'android/app/src/main/kotlin/com/daozhang/py/LinuxLikePackageController.kt',
    ).readAsStringSync();

    expect(manager, contains('userSitePackagesDir'));
    expect(manager, contains('userSitePackagesGuestPath'));
    expect(manager, contains('userSitePackageGuestPaths'));
    expect(manager, contains('target["PYTHONPATH"]'));
    expect(manager,
        contains('"userSitePackagesDir" to userSitePackagesDir.absolutePath'));
    expect(manager, contains('"userSitePackageGuestPaths"'));
    expect(packageController, contains('"--target"'));
    expect(packageController,
        contains('linuxLikeRuntimeManager.userSitePackagesGuestPath'));
  });

  test('linux-like runtime migrates legacy user packages into overlay', () {
    final manager = File(
      'android/app/src/main/kotlin/com/daozhang/py/LinuxLikeRuntimeManager.kt',
    ).readAsStringSync();

    expect(manager, contains('legacyUserSitePackagesDirs'));
    expect(manager, contains('migrateLegacyUserSitePackages'));
    expect(manager, contains('mergeLegacyUserSiteEntry'));
    expect(manager, contains('rootfsFile(userSitePackagesGuestPath)'));
    expect(
      manager,
      contains(
          r'rootfsFile("${context.filesDir.absolutePath}/linux_like/user_site_packages")'),
    );
    expect(
      manager,
      contains(
          r'rootfsFile("/data/data/${context.packageName}/files/linux_like/user_site_packages")'),
    );
    expect(manager, contains('source.copyTo(target, overwrite = false)'));
  });

  test('linux-like runtime keeps legacy python package paths importable', () {
    final manager = File(
      'android/app/src/main/kotlin/com/daozhang/py/LinuxLikeRuntimeManager.kt',
    ).readAsStringSync();

    expect(manager, contains('legacyPythonPackageGuestPaths'));
    expect(manager, contains('"/root/.local/lib"'));
    expect(manager, contains('"/usr/local/lib"'));
    expect(manager, contains('"/usr/lib"'));
    expect(manager, contains('"site-packages"'));
    expect(manager, contains('"dist-packages"'));
    expect(manager,
        contains(').plus(legacyPythonPackageGuestPaths()).distinct()'));
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
    final executionController = File(
      'android/app/src/main/kotlin/com/daozhang/py/ScriptExecutionController.kt',
    ).readAsStringSync();

    expect(
        executionController, contains('resolveScriptWorkingDir(workingDir)'));
    expect(executionController,
        contains('executionEnvironment["HOME"] = resolvedWorkingDir'));
    expect(executionController, contains('processBuilder.environment(),'));
    expect(executionController, contains('executionEnvironment'));
  });

  test('linux-like script launcher exposes cwd script path to user code', () {
    final manager = File(
      'android/app/src/main/kotlin/com/daozhang/py/LinuxLikeRuntimeManager.kt',
    ).readAsStringSync();
    final executionController = File(
      'android/app/src/main/kotlin/com/daozhang/py/ScriptExecutionController.kt',
    ).readAsStringSync();

    expect(manager, contains('toPythonStringLiteral'));
    expect(manager, contains('add("-B")'));
    expect(manager, contains('sys.dont_write_bytecode = True'));
    expect(manager, contains('userSitePathListLiteral'));
    expect(
        manager,
        contains(
            r'for _python_runner_site in reversed($userSitePathListLiteral):'));
    expect(manager, contains('sys.path.insert(0, _python_runner_site)'));
    expect(manager, contains('execution_file_path'));
    expect(manager, contains("'__file__': execution_file_path"));
    expect(manager,
        contains("sys.argv[0] = os.path.abspath(execution_file_path)"));
    expect(manager, contains("compile(_source, execution_file_path, 'exec')"));
    expect(executionController, contains('executionFilePath = File('));
    expect(
        executionController,
        contains(
            'linuxLikeRuntimeManager.resolveScriptWorkingDir(workingDir)'));
    expect(manager, isNot(contains('JSONObject.quote(scriptPath)')));
    expect(manager, isNot(contains(r"exec(open('$scriptPath').read())")));
    expect(manager, isNot(contains('runpy.run_path')));
  });

  test('linux-like script execution prevents and cleans pycache directories',
      () {
    final mainActivity = File(
      'android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt',
    ).readAsStringSync();
    final executionController = File(
      'android/app/src/main/kotlin/com/daozhang/py/ScriptExecutionController.kt',
    ).readAsStringSync();

    expect(mainActivity, contains('deletePythonCacheDirectories'));
    expect(mainActivity, contains('deletePythonCacheDirectory'));
    expect(mainActivity, contains('isBroadPythonCacheCleanupRoot'));
    expect(mainActivity, contains('file.name == "__pycache__"'));
    expect(executionController,
        contains('pycacheCleanupRoots = listOf(projectRoot)'));
    expect(executionController, contains('File(resolvedScriptWorkingDir)'));
    expect(executionController, contains('projectRoot = projectRoot'));
    expect(executionController,
        contains('executionTarget.pycacheCleanupRoots.forEach'));
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
    final executionController = File(
      'android/app/src/main/kotlin/com/daozhang/py/ScriptExecutionController.kt',
    ).readAsStringSync();

    expect(executionController, contains('emitStdinRequest('));
    expect(executionController, contains('parseLinuxLikePrompt'));
    expect(
      executionController,
      contains('line.startsWith(LinuxLikeRuntimeManager.stdinRequestSentinel)'),
    );
    expect(executionController, isNot(contains('type == "stderr" &&')));
    expect(executionController,
        contains('emitStdinRequestEvent(executionId, prompt)'));
  });

  test('linux-like stop escalates quickly and terminates process tree', () {
    final executionController = File(
      'android/app/src/main/kotlin/com/daozhang/py/ScriptExecutionController.kt',
    ).readAsStringSync();

    expect(executionController, contains('LINUX_LIKE_GRACEFUL_STOP_MS = 300L'));
    expect(executionController, contains('private fun stopProcessTree('));
    expect(executionController, contains('private fun processPid('));
    expect(executionController, contains('private fun killProcessTree('));
    expect(executionController, contains('private fun collectDescendantPids('));
    expect(executionController, contains('android.os.Process.sendSignal'));
    expect(executionController, contains('android.os.Process.killProcess'));
    expect(executionController, contains(r'File("/proc/$pid/task")'));
    expect(executionController, isNot(contains('Thread.sleep(1000)')));
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
    final patchNotes =
        File('third_party/re_editor/PATCHES.md').readAsStringSync();
    final patchedInput = File(
      'third_party/re_editor/lib/src/_code_input.dart',
    ).readAsStringSync();

    expect(pubspec, contains('path: third_party/re_editor'));
    expect(pubspec, isNot(contains('re_editor: ^0.8.0')));
    expect(pubspec, contains('re_highlight: ^0.0.3'));
    expect(pubspec, isNot(contains('\n  highlight:')));
    expect(patchedInput, contains('bool onFocusReceived() => false;'));
    expect(patchNotes, contains('third_party/re_editor'));
    expect(patchNotes, contains('re_highlight'));
    expect(patchNotes, contains('should not depend directly on'));
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
