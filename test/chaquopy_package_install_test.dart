import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chaquopy package install fails when pip or import verification fails', () {
    final activity = File(
      'android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt',
    ).readAsStringSync();
    final runner = File(
      'android/app/src/main/python/script_runner.py',
    ).readAsStringSync();

    expect(activity, contains('val pipResult'));
    expect(activity, contains('if (pipResult != 0)'));
    expect(activity, contains('result.error("1004"'));
    expect(activity, contains('sendInstallProgress(packageName, "error"'));
    expect(
      activity,
      isNot(contains(
        r'sendInstallProgress(packageName, "success", "$packageName 瀹夎瀹屾垚',
      )),
    );

    expect(runner, contains('if pip_result != 0:'));
    expect(runner, contains('return pip_result'));
    expect(runner, contains('if pkg_name and pip_result == 0'));
  });

  test('chaquopy uninstall reports and cleans orphan dependencies', () {
    final activity = File(
      'android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt',
    ).readAsStringSync();
    final runner = File(
      'android/app/src/main/python/script_runner.py',
    ).readAsStringSync();

    expect(activity, contains('removedDependencies'));
    expect(activity, contains('runner.callAttr("uninstall_package", packageName)'));
    expect(runner, contains('def uninstall_package(package_name):'));
    expect(runner, contains('removed_dependencies'));
    expect(runner, contains('return {'));
    expect(runner, contains('_cleanup_orphan_dependencies'));
  });
}
