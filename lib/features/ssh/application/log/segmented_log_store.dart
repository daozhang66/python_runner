import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'log_record.dart';

/// One file of a [SegmentedLogStore].
class LogSegment {
  const LogSegment({
    required this.file,
    required this.startMicros,
    required this.endMicros,
    required this.bytes,
    required this.sealed,
  });

  final File file;
  final int startMicros;
  final int endMicros;
  final int bytes;

  /// Sealed segments are gzip-compressed and never written to again.
  final bool sealed;
}

class LogStats {
  const LogStats({
    required this.bytes,
    required this.segments,
    this.oldest,
    this.newest,
  });

  final int bytes;
  final int segments;
  final DateTime? oldest;
  final DateTime? newest;
}

/// Append-only log kept on disk as small segments.
///
/// New records go to `active.jsonl`. When it grows past [maxSegmentBytes] it is
/// compressed into `seg-<first>-<last>.jsonl.gz` and a new active file starts,
/// so reading or deleting never touches one huge file and old data costs a
/// fraction of its size. When the whole log passes [maxTotalBytes] the oldest
/// segments are dropped.
class SegmentedLogStore {
  SegmentedLogStore({
    required this.directory,
    this.maxSegmentBytes = 256 * 1024,
    this.maxTotalBytes = 24 * 1024 * 1024,
    this.flushDelay = const Duration(seconds: 2),
  });

  final Directory directory;
  final int maxSegmentBytes;
  final int maxTotalBytes;
  final Duration flushDelay;

  static final RegExp _sealedName = RegExp(r'^seg-(\d+)-(\d+)\.jsonl\.gz$');
  static const int _activeStart = 1 << 62;

  final List<String> _pending = <String>[];
  int _pendingBytes = 0;
  Timer? _timer;
  Future<void> _lock = Future<void>.value();
  bool _dirReady = false;

  File get _activeFile => File('${directory.path}/active.jsonl');

  Future<T> _locked<T>(Future<T> Function() action) {
    final run = _lock.then((_) => action());
    _lock = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  /// Queues [record]; it reaches the disk within [flushDelay].
  void append(LogRecord record) {
    final line = jsonEncode(record.toJson());
    _pending.add(line);
    _pendingBytes += line.length + 1;
    if (_pendingBytes >= 32 * 1024) {
      unawaited(flush().catchError((Object _) {}));
    } else {
      _timer ??= Timer(flushDelay, () {
        _timer = null;
        unawaited(flush().catchError((Object _) {}));
      });
    }
  }

  Future<void> flush() => _locked(_flushLocked);

  Future<void> _ensureDir() async {
    if (_dirReady) return;
    await directory.create(recursive: true);
    _dirReady = true;
  }

  Future<void> _flushLocked() async {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return;
    final text = '${_pending.join('\n')}\n';
    _pending.clear();
    _pendingBytes = 0;
    await _ensureDir();
    await _activeFile.writeAsString(text, mode: FileMode.append, flush: true);
    if (await _activeFile.length() >= maxSegmentBytes) {
      await _sealLocked();
    }
  }

  /// Compresses the active file into a sealed segment.
  Future<void> _sealLocked() async {
    final active = _activeFile;
    if (!await active.exists()) return;
    final text = await active.readAsString();
    if (text.trim().isEmpty) {
      await active.delete();
      return;
    }
    final lines = const LineSplitter().convert(text);
    final first = _timeOf(lines.first);
    final last = _timeOf(lines.last);
    final target = File('${directory.path}/seg-$first-$last.jsonl.gz');
    await target.writeAsBytes(gzip.encode(utf8.encode(text)), flush: true);
    await active.delete();
    await _enforceQuotaLocked();
  }

  int _timeOf(String line) {
    try {
      return ((jsonDecode(line) as Map<String, dynamic>)['t'] as num).toInt();
    } catch (_) {
      return DateTime.now().microsecondsSinceEpoch;
    }
  }

  Future<List<LogSegment>> _segments() async {
    if (!await directory.exists()) return <LogSegment>[];
    final result = <LogSegment>[];
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final bytes = await entity.length();
      if (name == 'active.jsonl') {
        result.add(
          LogSegment(
            file: entity,
            startMicros: _activeStart,
            endMicros: _activeStart,
            bytes: bytes,
            sealed: false,
          ),
        );
        continue;
      }
      final match = _sealedName.firstMatch(name);
      if (match == null) continue;
      result.add(
        LogSegment(
          file: entity,
          startMicros: int.parse(match.group(1)!),
          endMicros: int.parse(match.group(2)!),
          bytes: bytes,
          sealed: true,
        ),
      );
    }
    result.sort((a, b) => b.startMicros.compareTo(a.startMicros));
    return result;
  }

  Future<List<LogRecord>> _readSegment(LogSegment segment) async {
    final String text;
    try {
      text = segment.sealed
          ? utf8.decode(gzip.decode(await segment.file.readAsBytes()))
          : await segment.file.readAsString();
    } catch (_) {
      return <LogRecord>[];
    }
    final records = <LogRecord>[];
    for (final line in const LineSplitter().convert(text)) {
      if (line.isEmpty) continue;
      try {
        records.add(LogRecord.fromJson(jsonDecode(line) as Map<String, dynamic>));
      } catch (_) {
        continue;
      }
    }
    return records;
  }

  Future<void> _enforceQuotaLocked() async {
    final segments = await _segments();
    var total = segments.fold<int>(0, (sum, s) => sum + s.bytes);
    for (final segment in segments.reversed) {
      if (total <= maxTotalBytes) break;
      if (!segment.sealed) continue;
      total -= segment.bytes;
      await segment.file.delete();
    }
  }

  /// Newest records first. [beforeMicros] continues after the last record of
  /// the previous page.
  Future<List<LogRecord>> readPage({
    int limit = 200,
    int? beforeMicros,
    String? sessionId,
    int maxImportance = 2,
  }) {
    return _locked(() async {
      await _flushLocked();
      final out = <LogRecord>[];
      for (final segment in await _segments()) {
        if (beforeMicros != null &&
            segment.sealed &&
            segment.startMicros >= beforeMicros) {
          continue;
        }
        final records = await _readSegment(segment);
        for (var i = records.length - 1; i >= 0; i--) {
          final record = records[i];
          if (beforeMicros != null && record.t >= beforeMicros) continue;
          if (record.i > maxImportance) continue;
          if (sessionId != null && record.sid != sessionId) continue;
          out.add(record);
          if (out.length >= limit) return out;
        }
      }
      return out;
    });
  }

  Future<LogStats> stats() {
    return _locked(() async {
      await _flushLocked();
      final segments = await _segments();
      var bytes = 0;
      DateTime? oldest;
      DateTime? newest;
      for (final segment in segments) {
        bytes += segment.bytes;
        if (!segment.sealed) {
          newest = DateTime.now();
          continue;
        }
        final start = DateTime.fromMicrosecondsSinceEpoch(segment.startMicros);
        final end = DateTime.fromMicrosecondsSinceEpoch(segment.endMicros);
        if (oldest == null || start.isBefore(oldest)) oldest = start;
        if (newest == null || end.isAfter(newest)) newest = end;
      }
      return LogStats(
        bytes: bytes,
        segments: segments.length,
        oldest: oldest,
        newest: newest,
      );
    });
  }

  /// Removes everything.
  Future<void> deleteAll() {
    return _locked(() async {
      _timer?.cancel();
      _timer = null;
      _pending.clear();
      _pendingBytes = 0;
      if (!await directory.exists()) return;
      await for (final entity in directory.list()) {
        await entity.delete(recursive: true);
      }
    });
  }

  /// Removes the records of one session. Returns how many were removed.
  Future<int> deleteSession(String sessionId) {
    return _locked(() async {
      await _flushLocked();
      var removed = 0;
      for (final segment in await _segments()) {
        final records = await _readSegment(segment);
        final kept =
            records.where((record) => record.sid != sessionId).toList();
        if (kept.length == records.length) continue;
        removed += records.length - kept.length;
        if (kept.isEmpty) {
          await segment.file.delete();
          continue;
        }
        final text =
            '${kept.map((record) => jsonEncode(record.toJson())).join('\n')}\n';
        if (segment.sealed) {
          await segment.file
              .writeAsBytes(gzip.encode(utf8.encode(text)), flush: true);
        } else {
          await segment.file.writeAsString(text, flush: true);
        }
      }
      return removed;
    });
  }

  /// Removes whole sealed segments that end before [cutoff]. Returns how many
  /// segments were removed.
  Future<int> deleteBefore(DateTime cutoff) {
    return _locked(() async {
      await _flushLocked();
      var removed = 0;
      for (final segment in await _segments()) {
        if (!segment.sealed) continue;
        if (segment.endMicros < cutoff.microsecondsSinceEpoch) {
          await segment.file.delete();
          removed++;
        }
      }
      return removed;
    });
  }

  /// Oldest-first text (or JSON lines) of the records that pass the filters.
  Future<String> exportText({
    int maxImportance = 2,
    String? sessionId,
    bool jsonl = false,
    int maxChars = 8 * 1024 * 1024,
  }) {
    return _locked(() async {
      await _flushLocked();
      final out = StringBuffer();
      final segments = (await _segments()).reversed.toList();
      for (final segment in segments) {
        for (final record in await _readSegment(segment)) {
          if (record.i > maxImportance) continue;
          if (sessionId != null && record.sid != sessionId) continue;
          out.writeln(
            jsonl
                ? jsonEncode(record.toJson())
                : formatLogRecord(record, maxImportance, withDate: true),
          );
          if (out.length > maxChars) {
            out.writeln('… (export cut at $maxChars characters)');
            return out.toString();
          }
        }
      }
      return out.toString();
    });
  }

  /// Writes pending records and stops the flush timer.
  Future<void> close() async {
    await flush();
  }
}
