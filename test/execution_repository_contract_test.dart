import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/console/application/execution_repository.dart';
import 'package:python_runner/models/execution_state.dart';
import 'package:python_runner/runtime/runtime_output.dart';
import 'package:python_runner/runtime/runtime_request.dart';
import 'package:python_runner/runtime/runtime_stdin_request.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/execution_test_helper.dart';

/// FakeExecutionRepository 契约测试：验证流推送与命令计数符合
/// [ExecutionRepository] 契约，保证 Level 3 Controller 单测可信赖本 fake。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('FakeExecutionRepository streams', () {
    test('output stream relays emitted events', () async {
      final repo = FakeExecutionRepository();
      final outputs = <String>[];
      final sub = repo.outputStream.listen((o) => outputs.add(o.content));
      addTearDown(sub.cancel);
      addTearDown(repo.dispose);

      // 用最小可观测的 RuntimeOutput（content 字段）。
      repo.emitOutput(RuntimeOutput(
        type: RuntimeOutputType.stdout,
        content: 'hello',
        timestamp: DateTime(2026, 1, 1),
      ));
      await Future<void>.delayed(Duration.zero);

      expect(outputs, ['hello']);
    });

    test('state stream relays execution state', () async {
      final repo = FakeExecutionRepository();
      final states = <ExecutionStatus>[];
      final sub = repo.stateStream
          .listen((s) => states.add(s.status));
      addTearDown(sub.cancel);
      addTearDown(repo.dispose);

      repo.emitState(const ExecutionState(status: ExecutionStatus.running));
      repo.emitState(const ExecutionState(status: ExecutionStatus.completed));
      await Future<void>.delayed(Duration.zero);

      expect(
        states,
        [ExecutionStatus.running, ExecutionStatus.completed],
      );
    });

    test('stdin request stream relays prompts', () async {
      final repo = FakeExecutionRepository();
      final prompts = <String>[];
      final sub = repo.stdinRequestStream
          .listen((r) => prompts.add(r.prompt));
      addTearDown(sub.cancel);
      addTearDown(repo.dispose);

      repo.emitStdinRequest(const RuntimeStdinRequest(prompt: 'name: '));
      await Future<void>.delayed(Duration.zero);

      expect(prompts, ['name: ']);
    });
  });

  group('FakeExecutionRepository commands', () {
    test('startScript records request and increments counter', () async {
      final repo = FakeExecutionRepository();
      addTearDown(repo.dispose);
      final request = RuntimeRequest(
        scriptName: 'demo.py',
        executionId: 'exec-1',
      );
      await repo.startScript(request);
      expect(repo.startScriptCount, 1);
      expect(repo.lastStartRequest?.scriptName, 'demo.py');
      expect(repo.lastStartRequest?.executionId, 'exec-1');
    });

    test('sendStdin and stopExecution track calls', () async {
      final repo = FakeExecutionRepository();
      addTearDown(repo.dispose);
      await repo.sendStdin('42');
      await repo.stopExecution();
      expect(repo.sendStdinCount, 1);
      expect(repo.lastStdinInput, '42');
      expect(repo.stopExecutionCount, 1);
    });

    test('loadExecutionPreferences returns configured snapshot', () async {
      final repo = FakeExecutionRepository(
        preferences: const ExecutionPreferences(
          workingDir: '/w',
          timeoutSeconds: 30,
          preferredRuntimeBackendId: 'linux_like',
        ),
      );
      addTearDown(repo.dispose);
      final prefs = await repo.loadExecutionPreferences();
      expect(prefs.workingDir, '/w');
      expect(prefs.timeoutSeconds, 30);
      expect(prefs.preferredRuntimeBackendId, 'linux_like');
      expect(repo.loadPreferencesCount, 1);
    });
  });

  group('FakeExecutionRepository preferences', () {
    test('loadExecutionPreferences omits working dir for projects', () async {
      final repo = FakeExecutionRepository(
        preferences: const ExecutionPreferences(
          workingDir: '/persisted',
          timeoutSeconds: null,
          preferredRuntimeBackendId: 'chaquopy',
        ),
      );
      addTearDown(repo.dispose);
      final forScript = await repo.loadExecutionPreferences();
      final forProject = await repo.loadExecutionPreferences(
        includeWorkingDir: false,
      );
      expect(forScript.workingDir, '/persisted');
      expect(forProject.workingDir, isNull,
          reason: '项目执行路径应忽略持久化的 working_dir');
    });

    test('startScript returns a runtime session', () async {
      final repo = FakeExecutionRepository();
      addTearDown(repo.dispose);
      final request = RuntimeRequest(scriptName: 'demo.py', executionId: 'e1');
      final session = await repo.startScript(request);
      expect(session, isNotNull);
      expect(session.request.scriptName, 'demo.py');
    });
  });
}
