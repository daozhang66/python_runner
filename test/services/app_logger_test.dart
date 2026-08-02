import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/services/app_logger.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('python_runner_app_logger_');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('restores structured app logs after a new logger instance starts',
      () async {
    final first = AppLogger.forTesting(root);
    await first.init();
    first.info('first launch', source: 'Test');
    first.warn('saved warning', source: 'Test', detail: 'details');
    await first.flush();

    final second = AppLogger.forTesting(root);
    await second.init();
    await second.flush();

    final restored = second.recentLogs;
    expect(restored.any((entry) => entry.message == 'first launch'), isTrue);
    expect(restored.any((entry) => entry.message == 'saved warning'), isTrue);
    expect(
      restored.where((entry) => entry.message == 'saved warning').single.detail,
      'details',
    );
  });

  test('compacts persisted history to the most recent 500 records', () async {
    final logger = AppLogger.forTesting(root);
    await logger.init();
    for (var index = 0; index < 520; index++) {
      logger.info('entry-$index', source: 'Test');
    }
    await logger.flush();

    final history = File('${root.path}/app_history.jsonl');
    expect(await history.readAsLines(), hasLength(500));

    final restored = AppLogger.forTesting(root);
    await restored.init();
    await restored.flush();
    expect(restored.recentLogs, hasLength(500));
    expect(restored.recentLogs.any((entry) => entry.message == 'entry-519'),
        isTrue);
    expect(restored.recentLogs.any((entry) => entry.message == 'entry-0'),
        isFalse);
  });

  test('ignores a malformed JSONL tail during restoration', () async {
    final first = AppLogger.forTesting(root);
    await first.init();
    first.error('keep this entry', source: 'Test');
    await first.flush();
    await File('${root.path}/app_history.jsonl').writeAsString(
      '{"level":"info"',
      mode: FileMode.append,
    );

    final restored = AppLogger.forTesting(root);
    await restored.init();
    await restored.flush();
    expect(
      restored.recentLogs.any((entry) => entry.message == 'keep this entry'),
      isTrue,
    );
  });

  test('migrates recognizable legacy system logs when history is absent',
      () async {
    await root.create(recursive: true);
    await File('${root.path}/system.log').writeAsString(
      '[2026-08-02 10:00:00.000] INFO  [Legacy] migrated\n'
      '[2026-08-02 10:00:01.000] ERROR [Legacy] failed\n'
      '  Detail: original stack trace\n',
    );

    final logger = AppLogger.forTesting(root);
    await logger.init();
    await logger.flush();

    expect(logger.recentLogs.any((entry) => entry.message == 'migrated'), isTrue);
    final failed =
        logger.recentLogs.where((entry) => entry.message == 'failed').single;
    expect(failed.detail, 'original stack trace');
    expect(await File('${root.path}/app_history.jsonl').exists(), isTrue);
  });

  test('clearAll removes structured history and restored app logs', () async {
    final first = AppLogger.forTesting(root);
    await first.init();
    first.info('remove me', source: 'Test');
    await first.flush();
    await first.clearAll();

    final restored = AppLogger.forTesting(root);
    await restored.init();
    await restored.flush();
    expect(restored.recentLogs.any((entry) => entry.message == 'remove me'),
        isFalse);
  });
}
