import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('large Flutter pages are split into focused part files', () {
    final expectedLineCaps = {
      'lib/pages/network_inspector_page.dart': 500,
      'lib/features/scripts/presentation/pages/script_list_page.dart': 520,
      'lib/pages/settings_page.dart': 500,
    };

    for (final entry in expectedLineCaps.entries) {
      final lineCount = File(entry.key).readAsLinesSync().length;
      expect(lineCount, lessThanOrEqualTo(entry.value), reason: entry.key);
    }

    expect(
        File('lib/pages/network_inspector_detail.dart').existsSync(), isTrue);
    expect(
        File('lib/pages/network_inspector_widgets.dart').existsSync(), isTrue);
    expect(
        File('lib/features/scripts/presentation/pages/script_list_actions.dart')
            .existsSync(),
        isTrue);
    expect(
        File('lib/features/scripts/presentation/pages/script_list_content.dart')
            .existsSync(),
        isTrue);
    expect(
        File('lib/features/scripts/presentation/pages/script_list_widgets.dart')
            .existsSync(),
        isTrue);
    expect(File('lib/pages/settings_actions.dart').existsSync(), isTrue);
    expect(File('lib/pages/settings_sections.dart').existsSync(), isTrue);
    expect(File('lib/pages/settings_widgets.dart').existsSync(), isTrue);
  });

  test('MainActivity delegates native bridge policy and script files', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt',
    ).readAsStringSync();
    final scriptStore = File(
      'android/app/src/main/kotlin/com/daozhang/py/ScriptFileStore.kt',
    ).readAsStringSync();
    final projectStore = File(
      'android/app/src/main/kotlin/com/daozhang/py/ScriptProjectStore.kt',
    ).readAsStringSync();
    final nativeFileOperations = File(
      'android/app/src/main/kotlin/com/daozhang/py/NativeFileOperations.kt',
    ).readAsStringSync();
    final appUpdateController = File(
      'android/app/src/main/kotlin/com/daozhang/py/AppUpdateController.kt',
    ).readAsStringSync();
    final chaquopyPackageController = File(
      'android/app/src/main/kotlin/com/daozhang/py/ChaquopyPackageController.kt',
    ).readAsStringSync();
    final runtimeInfoController = File(
      'android/app/src/main/kotlin/com/daozhang/py/RuntimeInfoController.kt',
    ).readAsStringSync();
    final linuxLikePackageController = File(
      'android/app/src/main/kotlin/com/daozhang/py/LinuxLikePackageController.kt',
    ).readAsStringSync();
    final scriptExecutionController = File(
      'android/app/src/main/kotlin/com/daozhang/py/ScriptExecutionController.kt',
    ).readAsStringSync();

    expect(mainActivity, contains('NativeBridgeContract.validate'));
    expect(mainActivity, contains('ScriptFileStore(filesDir)'));
    expect(mainActivity, contains('ScriptProjectStore(this, filesDir)'));
    expect(mainActivity, contains('NativeFileOperations(filesDir'));
    expect(mainActivity, contains('ChaquopyPackageController(mainHandler'));
    expect(mainActivity, contains('AppUpdateController(this)'));
    expect(mainActivity, contains('RuntimeInfoController('));
    expect(mainActivity, contains('LinuxLikePackageController('));
    expect(mainActivity, contains('ScriptExecutionController('));
    expect(mainActivity, contains('scriptFileStore.createScript'));
    expect(mainActivity, contains('scriptFileStore.listScripts'));
    expect(mainActivity, contains('scriptProjectStore.createProject'));
    expect(mainActivity, contains('scriptProjectStore.importProjectZip'));
    expect(mainActivity, isNot(contains('ZipInputStream(buffered)')));
    expect(mainActivity, isNot(contains('appFileEntryMap(')));
    expect(mainActivity, isNot(contains('private fun handleStartApkDownload')));

    expect(scriptStore, contains('class ScriptFileStore'));
    expect(scriptStore, contains('fun safeScriptFile'));
    expect(scriptStore, contains('fun listScripts'));
    expect(projectStore, contains('class ScriptProjectStore'));
    expect(projectStore, contains('fun safeProjectFile'));
    expect(projectStore, contains('fun importProjectZip'));
    expect(
      File('android/app/src/main/kotlin/com/daozhang/py/FloatingBallController.kt')
          .existsSync(),
      isFalse,
    );
    expect(mainActivity, isNot(contains('FloatingBall')));
    expect(nativeFileOperations, contains('class NativeFileOperations'));
    expect(nativeFileOperations, contains('fun importScriptFromUri'));
    expect(nativeFileOperations, contains('fun getFilePickerRoots'));
    expect(appUpdateController, contains('class AppUpdateController'));
    expect(appUpdateController, contains('DownloadManager(context'));
    expect(appUpdateController, contains('ApkInstaller(context)'));
    expect(appUpdateController, contains('fun startApkDownload'));
    expect(
        chaquopyPackageController, contains('class ChaquopyPackageController'));
    expect(chaquopyPackageController, contains('val pipResult'));
    expect(chaquopyPackageController, contains('fun uninstallPackage'));
    expect(runtimeInfoController, contains('class RuntimeInfoController'));
    expect(runtimeInfoController, contains('fun getPythonInfo'));
    expect(runtimeInfoController, contains('fun installLinuxLikeRuntime'));
    expect(linuxLikePackageController,
        contains('class LinuxLikePackageController'));
    expect(linuxLikePackageController,
        contains('fun installLinuxLikeRequirements'));
    expect(linuxLikePackageController, contains('fun listLinuxLikePackages'));
    expect(
        scriptExecutionController, contains('class ScriptExecutionController'));
    expect(scriptExecutionController, contains('fun executeScript'));
    expect(scriptExecutionController, contains('fun executeLinuxLikeScript'));
    expect(mainActivity,
        isNot(contains('private data class LinuxLikeDistribution')));
    expect(mainActivity, isNot(contains('private fun executeLinuxLikeScript')));
  });
}
