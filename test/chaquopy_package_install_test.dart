import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chaquopy package install fails when pip or import verification fails',
      () {
    final controller = File(
      'android/app/src/main/kotlin/com/daozhang/py/ChaquopyPackageController.kt',
    ).readAsStringSync();
    final runner = File(
      'android/app/src/main/python/script_runner.py',
    ).readAsStringSync();

    expect(controller, contains('val pipResult'));
    expect(controller, contains('if (pipResult != 0)'));
    expect(controller, contains('result.error("1004"'));
    expect(controller, contains('sendInstallProgress(packageName, "error"'));
    expect(
      controller,
      isNot(contains(
        r'sendInstallProgress(packageName, "success", "$packageName 瀹夎瀹屾垚',
      )),
    );

    expect(runner, contains('if pip_result != 0:'));
    expect(runner, contains('return pip_result'));
    expect(runner, contains('if pkg_name and pip_result == 0'));
  });

  test('chaquopy uninstall reports and cleans orphan dependencies', () {
    final controller = File(
      'android/app/src/main/kotlin/com/daozhang/py/ChaquopyPackageController.kt',
    ).readAsStringSync();
    final runner = File(
      'android/app/src/main/python/script_runner.py',
    ).readAsStringSync();

    expect(controller, contains('removedDependencies'));
    expect(controller,
        contains('runner.callAttr("uninstall_package", packageName)'));
    expect(runner, contains('def uninstall_package(package_name):'));
    expect(runner, contains('removed_dependencies'));
    expect(runner, contains('return {'));
    expect(runner, contains('_cleanup_orphan_dependencies'));
  });

  test('chaquopy script execution disables bytecode cache writes', () {
    final runner = File(
      'android/app/src/main/python/script_runner.py',
    ).readAsStringSync();

    expect(runner, contains('sys.dont_write_bytecode = True'));
    expect(runner, contains('PYTHONDONTWRITEBYTECODE'));
    expect(runner, contains('_original_dont_write_bytecode'));
  });
}
