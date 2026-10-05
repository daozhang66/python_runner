import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/scripts/application/script_workspace_controller.dart';
import 'package:python_runner/providers/execution_provider.dart';
import 'package:python_runner/services/database_service.dart';
import 'package:python_runner/services/native_bridge.dart';
import 'package:python_runner/services/native_bridge_contract.dart';
import 'package:python_runner/services/workspace_access.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'restore_planner_test.dart' show localScript;
import '../../support/script_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  test('workspace queued admission blocks mutations and load without changing loading state', () async {
    final gate = WorkspaceAccess();
    final repository = FakeScriptRepository();
    final container = buildScriptContainer(
      repository: repository,
      overrides: [workspaceAccessProvider.overrideWithValue(gate)],
    );
    addTearDown(container.dispose);
    final workspace = container.read(
      scriptWorkspaceControllerProvider.notifier,
    );
    await gate.runExclusive(() async {
      // A different zone is needed: owner calls are deliberately reentrant.
    });
    final wait = Completer<void>();
    final exclusive = gate.runExclusive(() => wait.future);
    await expectLater(workspace.load(), throwsA(isA<WorkspaceBusyException>()));
    expect(workspace.loading, false);
    expect(repository.listScriptFilesCount, 0);
    wait.complete();
    await exclusive;
  });
  test('execution admission rejects before changing state or stopping an existing task', () async {
    final gate = WorkspaceAccess();
    final bridge = NativeBridge.named(
      workspaceAccess: gate,
      eventStreamFactory: (_) => const Stream.empty(),
    );
    final execution = ExecutionProvider(bridge, workspaceAccess: gate);
    addTearDown(execution.dispose);
    final wait = Completer<void>();
    final exclusive = gate.runExclusive(() => wait.future);
    await expectLater(
      execution.executeScript('script.py'),
      throwsA(isA<WorkspaceBusyException>()),
    );
    expect(execution.isRunning, false);
    wait.complete();
    await exclusive;
  });
  test(
    'database writes and direct native project edits obey the same gate',
    () async {
      final gate = WorkspaceAccess();
      final dir = await Directory.systemTemp.createTemp('gate_db_');
      final db = DatabaseService(
        databasePath: '${dir.path}/test.db',
        workspaceAccess: gate,
      );
      final bridge = NativeBridge.named(workspaceAccess: gate);
      final nativeCalls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(NativeBridgeContract.channelName),
            (call) async {
              nativeCalls.add(call.method);
              return true;
            },
          );
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(NativeBridgeContract.channelName),
              null,
            );
        await db.closeForTest();
        await dir.delete(recursive: true);
      });
      await db.upsertScript(localScript('test.py'));
      final revision = gate.revision;
      await bridge.saveProjectFile('project', 'main.py', 'changed');
      expect(gate.revision, revision + 1);
      final hold = Completer<void>();
      final exclusive = gate.runExclusive(() => hold.future);
      await expectLater(
        db.upsertScript(localScript('blocked.py')),
        throwsA(isA<WorkspaceBusyException>()),
      );
      await expectLater(
        bridge.saveProjectFile('project', 'main.py', 'blocked'),
        throwsA(isA<WorkspaceBusyException>()),
      );
      await expectLater(
        bridge.executeScript('test.py', 'id'),
        throwsA(isA<WorkspaceBusyException>()),
      );
      expect(nativeCalls, ['saveProjectFile']);
      hold.complete();
      await exclusive;
      expect(await db.getScript('blocked.py'), isNull);
    },
  );
  test('pending recovery preserves corrupt DB and never rebuilds away commit proof', () async {
    final dir = await Directory.systemTemp.createTemp('recovery_corrupt_');
    final path = '${dir.path}/test.db';
    await File(path).writeAsString('corrupt but preserve me');
    final db = DatabaseService(databasePath: path)
      ..preserveRestoreEvidence = true;
    addTearDown(() async {
      await db.closeForTest();
      await dir.delete(recursive: true);
    });
    await expectLater(
      db.committedRestoreIds(),
      throwsA(isA<DatabaseOpenException>()),
    );
    expect(await File(path).readAsString(), 'corrupt but preserve me');
    expect(
      (await dir.list().toList()).any((f) => f.path.contains('backup.corrupt')),
      isFalse,
    );
  });
}
