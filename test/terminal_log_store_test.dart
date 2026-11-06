import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/ssh/application/log/ansi.dart';
import 'package:python_runner/features/ssh/application/log/log_record.dart';
import 'package:python_runner/features/ssh/application/log/segmented_log_store.dart';
import 'package:python_runner/features/ssh/application/log/session_logger.dart';

LogRecord _rec(int t, {String sid = 's1', int i = 1, String? s}) => LogRecord(
      t: t,
      k: 'out',
      s: s ?? 'line ${t ~/ 1000}',
      sid: sid,
      i: i,
      d: 'detail ${t ~/ 1000}',
    );

void main() {
  group('SegmentedLogStore', () {
    late Directory dir;
    late SegmentedLogStore store;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('logstore');
      store = SegmentedLogStore(
        directory: dir,
        maxSegmentBytes: 400,
        flushDelay: const Duration(days: 1),
      );
    });

    tearDown(() {
      dir.deleteSync(recursive: true);
    });

    Future<void> fill() async {
      for (var n = 1; n <= 30; n++) {
        store.append(_rec(n * 1000, sid: n.isEven ? 's2' : 's1'));
        if (n % 5 == 0) await store.flush();
      }
      await store.flush();
    }

    test('rotates into gzip segments and pages newest first', () async {
      await fill();
      final names = dir.listSync().map((e) => e.uri.pathSegments.last).toList();
      expect(names.where((n) => n.endsWith('.jsonl.gz')), isNotEmpty);
      final first = await store.readPage(limit: 10);
      expect(first.length, 10);
      expect(first.first.s, 'line 30');
      final rest = await store.readPage(limit: 100, beforeMicros: first.last.t);
      expect(rest.length, 20);
      expect(rest.first.s, 'line 20');
      expect(rest.last.s, 'line 1');
    });

    test('filters by importance and session', () async {
      store.append(_rec(1000, i: 0, s: 'key'));
      store.append(_rec(2000, i: 2, s: 'verbose'));
      store.append(_rec(3000, sid: 'other', s: 'elsewhere'));
      await store.flush();
      final summary = await store.readPage(maxImportance: 0);
      expect(summary.map((r) => r.s), ['key']);
      final session = await store.readPage(sessionId: 'other');
      expect(session.map((r) => r.s), ['elsewhere']);
    });

    test('deleteSession removes only that session', () async {
      await fill();
      final removed = await store.deleteSession('s2');
      expect(removed, 15);
      final all = await store.readPage(limit: 100);
      expect(all.length, 15);
      expect(all.every((r) => r.sid == 's1'), isTrue);
    });

    test('deleteBefore drops old sealed segments', () async {
      await fill();
      final removed = await store.deleteBefore(
        DateTime.fromMicrosecondsSinceEpoch(20000),
      );
      expect(removed, greaterThan(0));
      final all = await store.readPage(limit: 100);
      expect(all.length, lessThan(30));
      expect(all.first.s, 'line 30');
    });

    test('exportText is oldest first and honours the detail level', () async {
      await fill();
      final detailed = await store.exportText(maxImportance: 2);
      expect(detailed.indexOf('line 3'), lessThan(detailed.indexOf('line 29')));
      expect(detailed, contains('detail 30'));
      final jsonl = await store.exportText(jsonl: true);
      expect(jsonl.trim().split('\n').length, 30);
    });

    test('the quota drops the oldest sealed segments', () async {
      final small = SegmentedLogStore(
        directory: Directory('${dir.path}/small'),
        maxSegmentBytes: 300,
        maxTotalBytes: 500,
        flushDelay: const Duration(days: 1),
      );
      for (var n = 1; n <= 40; n++) {
        small.append(_rec(n * 1000));
        if (n % 4 == 0) await small.flush();
      }
      await small.flush();
      final stats = await small.stats();
      expect(stats.bytes, lessThan(1500));
      final all = await small.readPage(limit: 100);
      expect(all.first.s, 'line 40');
      expect(all.length, lessThan(40));
    });

    test('deleteAll empties the log', () async {
      await fill();
      await store.deleteAll();
      expect(await store.readPage(), isEmpty);
    });
  });

  group('stripAnsi', () {
    test('removes colors, titles and carriage-return rewrites', () {
      expect(stripAnsi('\x1b[31mred\x1b[0m'), 'red');
      expect(stripAnsi('\x1b]0;title\x07text'), 'text');
      expect(stripAnsi('50%\r100%\n'), '100%\n');
      expect(stripAnsi('a\r\nb'), 'a\nb');
    });
  });

  group('SessionLogger', () {
    late List<LogRecord> records;
    late SessionLogger logger;

    setUp(() {
      records = <LogRecord>[];
      logger = SessionLogger(
        sessionId: 'local-1',
        sink: (channel, record) => records.add(record),
        flushDelay: const Duration(days: 1),
      );
    });

    test('collects output into plain text blocks', () {
      logger.output('\x1b[32mhello\x1b[0m\r\n');
      logger.output('world\r\n');
      logger.flushOutput();
      expect(records.length, 1);
      expect(records.single.k, 'out');
      expect(records.single.d, 'hello\nworld');
      expect(records.single.s, contains('+1 lines'));
    });

    test('commands are key records and keep their order', () {
      logger.input('ls');
      logger.output('a b\n');
      logger.input('pwd', actor: 'ai');
      logger.flushOutput();
      expect(records.map((r) => r.k), ['cmd', 'out', 'cmd']);
      expect(records.first.i, 0);
      expect(records.last.a, 'ai');
    });

    test('a line typed after a password prompt is not stored', () {
      logger.output('[sudo] password for me: ');
      logger.input('hunter2');
      expect(records.last.s, '<hidden input>');
      logger.input('whoami');
      expect(records.last.s, 'whoami');
    });

    test('raw keystrokes become command lines', () {
      logger.feedInput('ls -l');
      logger.feedInput('\x7fx\r');
      logger.feedInput('\x1b[A\r');
      expect(records.where((r) => r.k == 'cmd').map((r) => r.s), ['ls -x']);
    });
  });
}
