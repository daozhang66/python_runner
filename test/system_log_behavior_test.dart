import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String settingsPageSource() => [
      'lib/pages/settings_page.dart',
      'lib/pages/settings_actions.dart',
      'lib/pages/settings_sections.dart',
      'lib/pages/settings_widgets.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');

void main() {
  test(
      'settings page views full exported diagnostics instead of memory-only logs',
      () {
    final source = settingsPageSource();
    final viewBody = RegExp(
      r'Future<void> _viewSystemLogs\(\) async \{([\s\S]*?)\r?\n  }\r?\n\r?\n  Future<void> _exportSystemLogs',
    ).firstMatch(source)!.group(1)!;

    expect(viewBody, contains('await AppLogger.instance.exportAll()'));
    expect(viewBody, isNot(contains('readRecentLogs')));
  });

  test(
      'system log export uses configured working directory and native fallback otherwise',
      () {
    final settingsSource = settingsPageSource();
    final bridgeSource =
        File('lib/services/native_bridge.dart').readAsStringSync();
    final activitySource =
        File('android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt')
            .readAsStringSync();

    expect(settingsSource, contains("prefs.getString('working_dir')"));
    expect(settingsSource, contains('destDir: logExportDir'));
    expect(bridgeSource, contains('String? destDir'));
    expect(bridgeSource, contains("'destDir': destDir"));
    expect(activitySource,
        contains('val destDir = call.argument<String>("destDir")'));
    expect(activitySource, contains('if (!destDir.isNullOrBlank())'));
    expect(activitySource, contains('Environment.DIRECTORY_DOWNLOADS'));
  });

  test(
      'app logger flushes before reading and exports rotated system logs with diagnostics',
      () {
    final source = File('lib/services/app_logger.dart').readAsStringSync();

    expect(source, contains('Future<void> flush()'));
    expect(source, contains('_systemLogSink?.flush()'));
    expect(source, contains(r'$_systemLogFile.old'));
    expect(source, contains('====== 诊断信息 ======'));
    expect(source, contains('Log directory:'));
  });

  test('app logger clearAll closes and reopens system log sink', () {
    final source = File('lib/services/app_logger.dart').readAsStringSync();
    final clearBody = RegExp(
      r'Future<void> clearAll\(\) async \{([\s\S]*?)\r?\n  }\r?\n\r?\n  /// Export all logs',
    ).firstMatch(source)!.group(1)!;

    expect(clearBody, contains('await flush()'));
    expect(clearBody, contains('await _systemLogSink?.close()'));
    expect(clearBody, contains('_systemLogSink = null'));
    expect(clearBody, contains('openWrite(mode: FileMode.append)'));
    expect(clearBody, contains('_systemLogSize = 0'));
  });

  test(
      'app logger writes dated category logs without automatic history snapshots',
      () {
    final loggerSource =
        File('lib/services/app_logger.dart').readAsStringSync();
    final mainSource = File('lib/main.dart').readAsStringSync();

    expect(loggerSource, contains('_appLogFileName'));
    expect(loggerSource, contains('_scriptLogFileName'));
    expect(loggerSource, contains('_crashLogFileName'));
    expect(loggerSource, contains(r'app-${_dateStamp'));
    expect(loggerSource, contains(r'script-${_dateStamp'));
    expect(loggerSource, contains(r'crash-${_dateStamp'));
    expect(loggerSource, isNot(contains('archiveToWorkingDirectory')));
    expect(loggerSource, isNot(contains('listArchivedDiagnostics')));
    expect(loggerSource, isNot(contains('readArchivedDiagnostic')));
    expect(loggerSource, isNot(contains('exportDiagnosticPackage')));
    expect(loggerSource, isNot(contains('PythonRunner/logs')));
    expect(mainSource, isNot(contains('archiveToWorkingDirectory')));
  });

  test(
      'settings page has one complete log export and no snapshot or package actions',
      () {
    final settingsSource = settingsPageSource();

    expect(settingsSource,
        contains("final timestamp = DateFormat('yyyyMMdd_HHmmss')"));
    expect(settingsSource,
        contains("fileName: 'python_runner_logs_\$timestamp.txt'"));
    expect(settingsSource, contains("title: const Text('导出完整日志')"));
    expect(settingsSource, isNot(contains("title: const Text('导出系统日志')")));
    expect(settingsSource, isNot(contains("title: const Text('导出诊断包')")));
    expect(settingsSource, isNot(contains("title: const Text('历史日志归档')")));
    expect(settingsSource, isNot(contains('Future<void> _viewArchivedLogs()')));
    expect(settingsSource,
        isNot(contains('Future<void> _exportDiagnosticPackage()')));
    expect(settingsSource, isNot(contains('class _ArchivedLogListPage')));
    expect(settingsSource,
        isNot(contains('python_runner_diagnostic_package.txt')));
  });

  test(
      'settings page exposes searchable log viewer with unified dropdown borders',
      () {
    final settingsSource = settingsPageSource();

    expect(settingsSource,
        contains('class _SystemLogViewPage extends StatefulWidget'));
    expect(settingsSource, contains('TextField('));
    final formFieldDropdowns = RegExp(r'DropdownButtonFormField<String>')
        .allMatches(settingsSource)
        .length;
    expect(formFieldDropdowns, greaterThanOrEqualTo(2));
    expect(settingsSource, isNot(contains('child: DropdownButton<String>(')));
    expect(settingsSource, contains('_filteredLogContent'));
  });
}
