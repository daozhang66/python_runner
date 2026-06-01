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
    ).readAsStringSync();

    expect(activity, contains('resolveLinuxLikeExplicitPackages'));
    expect(activity, contains('queryLinuxLikeTopLevelPackages'));
    expect(activity, contains('REQUESTED'));
    expect(activity, contains('hostDistributions'));
    expect(activity, contains('removeMissingLinuxLikeExplicitPackages'));
    expect(activity, contains('explicitPackages.contains(normalizedPackageName)'));
    expect(activity, contains('pipListedPackages'));
    expect(activity,
        contains('"source" to if (isExplicitUserPackage) "user" else "runtime"'));
  });

  test('linux-like package list migrates existing installs without metadata',
      () {
    final activity = File(
      'android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('resolveLinuxLikeExplicitPackages'));
    expect(activity, contains('readPythonPackageVersion'));
    expect(activity, contains('"--not-required"'));
    expect(activity, contains('metadataOwnedTopLevels'));
    expect(activity, contains('requestedPackages'));
    expect(activity, contains('topLevelPackages'));
    expect(activity, isNot(contains('!linuxLikeImplicitDependencyPackages.contains(name)')));
    expect(activity, contains('saveLinuxLikeExplicitPackages(requestedPackages)'));
    expect(activity, contains('saveLinuxLikeExplicitPackages(resolvedPackages)'));
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

  test('linux-like uninstall records explicit packages and removes orphans', () {
    final activity = File(
      'android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt',
    ).readAsStringSync();
    final manager = File(
      'android/app/src/main/kotlin/com/daozhang/py/LinuxLikeRuntimeManager.kt',
    ).readAsStringSync();

    expect(activity, contains('recordLinuxLikeExplicitPackage'));
    expect(activity, contains('removeLinuxLikeExplicitPackage'));
    expect(activity, contains('cleanupLinuxLikeOrphanDependencies'));
    expect(activity, contains('removeLinuxLikePackagesFromOverlay'));
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
    expect(
        manager,
        contains(
            '"userSitePackagesDir" to userSitePackagesDir.absolutePath'));
    expect(activity, contains('"--target"'));
    expect(
        activity,
        contains('linuxLikeRuntimeManager.userSitePackagesGuestPath'));
  });

  test('linux-like process environment is stable across Android versions', () {
    final manager = File(
      'android/app/src/main/kotlin/com/daozhang/py/LinuxLikeRuntimeManager.kt',
    ).readAsStringSync();

    expect(manager, contains('target["HOME"] = "/root"'));
    expect(manager, contains('target["PATH"] ='));
    expect(manager, contains('target["PIP_NO_INPUT"] = "1"'));
    expect(
        manager,
        isNot(contains(
            'target["PYRUNNER_HTTP_HOOK_CONFIG"] = "{\\"record_requests\\": true}"')));
  });

  test('linux-like script launcher preserves script semantics with runpy', () {
    final manager = File(
      'android/app/src/main/kotlin/com/daozhang/py/LinuxLikeRuntimeManager.kt',
    ).readAsStringSync();

    expect(manager, contains('runpy.run_path'));
    expect(manager, contains('toPythonStringLiteral'));
    expect(manager, isNot(contains('JSONObject.quote(scriptPath)')));
    expect(manager, isNot(contains(r"exec(open('$scriptPath').read())")));
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
}
