import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/services/native_bridge.dart';

void main() {
  const channels = <String>[
    'com.daozhang.py/log_stream',
    'com.daozhang.py/install_progress',
    'com.daozhang.py/download_progress',
    'com.daozhang.py/execution_status',
    'com.daozhang.py/stdin_request',
  ];

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('reset reconnects every event stream without replacing listeners',
      () async {
    final first = _EventSources(channels);
    final second = _EventSources(channels);
    var useSecond = false;
    final bridge = NativeBridge.named(
      eventStreamFactory: (channelName) =>
          (useSecond ? second : first).streamFor(channelName),
    );
    final received = <String, List<String>>{
      for (final channel in channels) channel: <String>[],
    };
    final subscriptions = <StreamSubscription<Map<dynamic, dynamic>>>[
      bridge.logStream.listen((event) => received[channels[0]]!.add(
            event['value'].toString(),
          )),
      bridge.installProgressStream.listen(
          (event) => received[channels[1]]!.add(event['value'].toString())),
      bridge.downloadProgressStream.listen(
          (event) => received[channels[2]]!.add(event['value'].toString())),
      bridge.executionStatusStream.listen(
          (event) => received[channels[3]]!.add(event['value'].toString())),
      bridge.stdinRequestStream.listen(
          (event) => received[channels[4]]!.add(event['value'].toString())),
    ];

    await settle();
    for (final channel in channels) {
      first.add(channel, {'value': 'first'});
    }
    await settle();

    useSecond = true;
    await bridge.resetEventStreams();
    for (final channel in channels) {
      first.add(channel, {'value': 'stale'});
      second.add(channel, {'value': 'second'});
    }
    await settle();

    for (final channel in channels) {
      expect(received[channel], ['first', 'second']);
      expect(first.listenCount(channel), 1);
      expect(second.listenCount(channel), 1);
    }

    await Future.wait(
        subscriptions.map((subscription) => subscription.cancel()));
    await first.close();
    await second.close();
  });

  test('reset is idle without listeners and binds only on first listen',
      () async {
    final sources = _EventSources(channels);
    final bridge = NativeBridge.named(
      eventStreamFactory: sources.streamFor,
    );

    await bridge.resetEventStreams();
    for (final channel in channels) {
      expect(sources.listenCount(channel), 0);
    }

    final received = <String>[];
    final subscription = bridge.logStream.listen(
      (event) => received.add(event['value'].toString()),
    );
    await settle();
    expect(sources.listenCount(channels[0]), 1);
    sources.add(channels[0], {'value': 'connected'});
    await settle();
    expect(received, ['connected']);

    await subscription.cancel();
    await sources.close();
  });

  test('a completed source stays recoverable and errors remain observable',
      () async {
    final first = _EventSources(channels);
    final second = _EventSources(channels);
    var useSecond = false;
    final bridge = NativeBridge.named(
      eventStreamFactory: (channelName) =>
          (useSecond ? second : first).streamFor(channelName),
    );
    final values = <String>[];
    final errors = <Object>[];
    final subscription = bridge.logStream.listen(
      (event) => values.add(event['value'].toString()),
      onError: errors.add,
    );

    await settle();
    final expectedError = StateError('native stream unavailable');
    first.addError(channels[0], expectedError);
    await first.closeChannel(channels[0]);
    await settle();
    expect(errors, [expectedError]);

    useSecond = true;
    await bridge.resetEventStreams();
    second.add(channels[0], {'value': 'recovered'});
    await settle();
    expect(values, ['recovered']);

    await subscription.cancel();
    await first.close();
    await second.close();
  });

  test('overlapping reset and cancellation leave no stale source active',
      () async {
    final first = _EventSources(channels);
    final second = _EventSources(channels);
    var useSecond = false;
    final bridge = NativeBridge.named(
      eventStreamFactory: (channelName) =>
          (useSecond ? second : first).streamFor(channelName),
    );
    final subscription = bridge.executionStatusStream.listen((_) {});
    await settle();

    useSecond = true;
    final firstReset = bridge.resetEventStreams();
    final secondReset = bridge.resetEventStreams();
    await subscription.cancel();
    await Future.wait([firstReset, secondReset]);
    await settle();
    expect(second.listenCount(channels[3]), 0);

    final received = <String>[];
    final replacement = bridge.executionStatusStream.listen(
      (event) => received.add(event['value'].toString()),
    );
    await settle();
    second.add(channels[3], {'value': 'fresh'});
    await settle();
    expect(received, ['fresh']);

    await replacement.cancel();
    await first.close();
    await second.close();
  });
}

class _EventSources {
  _EventSources(Iterable<String> channels)
      : _controllers = {
          for (final channel in channels)
            channel: StreamController<dynamic>.broadcast(
              onListen: () {},
            ),
        };

  final Map<String, StreamController<dynamic>> _controllers;
  final Map<String, int> _listenCounts = <String, int>{};

  Stream<dynamic> streamFor(String channelName) {
    final controller = _controllers[channelName]!;
    final stream = controller.stream;
    return Stream<dynamic>.multi(
      (multi) {
        _listenCounts[channelName] = listenCount(channelName) + 1;
        final subscription = stream.listen(
          multi.add,
          onError: multi.addError,
          onDone: multi.close,
        );
        multi.onCancel = subscription.cancel;
      },
      isBroadcast: true,
    );
  }

  int listenCount(String channelName) => _listenCounts[channelName] ?? 0;

  void add(String channelName, Map<String, String> event) {
    _controllers[channelName]!.add(event);
  }

  void addError(String channelName, Object error) {
    _controllers[channelName]!.addError(error);
  }

  Future<void> closeChannel(String channelName) =>
      _controllers[channelName]!.close();

  Future<void> close() =>
      Future.wait(_controllers.values.map((controller) => controller.close()));
}
