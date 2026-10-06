import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/services/workspace_access.dart';

void main() {
  test(
    'exclusive reserves immediately and drains accepted reentrant writes',
    () async {
      final gate = WorkspaceAccess();
      final finish = Completer<void>();
      final calls = <String>[];
      final write = gate.runMutation(() async {
        calls.add('write');
        await finish.future;
        await gate.runMutation(() async => calls.add('nested'));
      });
      final snapshot = gate.runExclusive(() async {
        calls.add('exclusive');
        await gate.runMutation(() async => calls.add('owner'));
      });
      expect(gate.isBusy, isTrue);
      await expectLater(
        gate.runMutation(() async {}),
        throwsA(isA<WorkspaceBusyException>()),
      );
      expect(calls, ['write']);
      finish.complete();
      await Future.wait([write, snapshot]);
      expect(calls, ['write', 'nested', 'exclusive', 'owner']);
      expect(gate.revision, 1);
      expect(gate.isBusy, isFalse);
    },
  );

  test('failed writes advance revision and recovery block survives exclusive failure', () async {
    final gate = WorkspaceAccess();
    await expectLater(
      gate.runMutation(() async => throw StateError('partial')),
      throwsStateError,
    );
    expect(gate.revision, 1);
    gate.blockForRecovery();
    await expectLater(
      gate.runMutation(() async {}),
      throwsA(isA<WorkspaceRecoveryRequired>()),
    );
    await gate.runExclusive(() async {
      gate.completeRecovery();
    }, recovery: true);
    await gate.runMutation(() async {});
    expect(gate.revision, 2);
  });

  test(
    'finished mutation zone cannot bypass a later exclusive reservation',
    () async {
      final gate = WorkspaceAccess();
      final later = Completer<void>();
      late Future<void> detached;
      await gate.runMutation(() async {
        detached = later.future.then((_) => gate.runMutation(() async {}));
      });
      final hold = Completer<void>();
      final exclusive = gate.runExclusive(() => hold.future);
      final assertion = expectLater(
        detached,
        throwsA(isA<WorkspaceBusyException>()),
      );
      later.complete();
      await assertion;
      hold.complete();
      await exclusive;
    },
  );
  test(
    'accepted nested writes are drained even if their caller finishes first',
    () async {
      final gate = WorkspaceAccess();
      final finish = Completer<void>();
      late Future<void> nested;
      await gate.runMutation(() async {
        nested = gate.runMutation(() async {
          await finish.future;
        });
      });
      var tookSnapshot = false;
      final snapshot = gate.runExclusive(() async {
        tookSnapshot = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(tookSnapshot, false);
      finish.complete();
      await nested;
      await snapshot;
      expect(tookSnapshot, true);
      expect(gate.revision, 1);
    },
  );
}
