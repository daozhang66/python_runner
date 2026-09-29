import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:python_runner/features/mcp/application/mcp_server_controller.dart';
import 'package:python_runner/features/mcp/domain/mcp_error_codes.dart';
import 'package:python_runner/features/scripts/application/script_repository.dart';
import 'package:python_runner/features/scripts/application/script_workspace_controller.dart';
import 'package:python_runner/models/script_file.dart';
import 'package:python_runner/models/execution_state.dart';
import 'package:python_runner/providers/execution_provider.dart';
import '../../support/script_test_helper.dart';
import '../../support/script_workspace_harness.dart';

// Mirrors DatabaseService.incrementRunCount's persisted timestamp update.
class RunRepository extends FakeScriptRepository {
  RunRepository(List<ScriptFile> scripts) : super(scripts: scripts);
  @override
  Future<void> incrementRunCount(String name) async {
    await super.incrementRunCount(name);
    final script = await getScript(name);
    if (script != null) {
      await upsertScript(script.copyWith(modifiedAt: DateTime.now()));
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('MCP updates home counts, timestamps and ordering exactly once per run',
      () async {
    SharedPreferences.setMockInitialValues({});
    final old = DateTime.fromMillisecondsSinceEpoch(1000);
    final repo = RunRepository([
      for (var i = 0; i < 2; i++)
        ScriptFile(
            name: '$i.py',
            path: '$i.py',
            createdAt: old,
            modifiedAt: old,
            sortOrder: i),
    ]);
    final bridge = FakeScriptNativeBridge(scriptNames: ['0.py', '1.py']);
    final owner = ExecutionProvider(bridge);
    final container = ProviderContainer(overrides: [
      scriptRepositoryProvider.overrideWithValue(repo),
      mcpExecutionOwnerProvider.overrideWithValue(owner),
    ]);
    addTearDown(() {
      container.dispose();
      owner.dispose();
      bridge.dispose();
    });
    final service = container.read(mcpExecutionServiceProvider);
    final run = await service.run('1.py');
    await Future<void>.delayed(Duration.zero);
    final workspace =
        container.read(scriptWorkspaceControllerProvider.notifier);
    expect(workspace.scripts.first.name, '1.py');
    expect(workspace.scripts.first.runCount, 1);
    expect(workspace.scripts.first.modifiedAt.isAfter(old), isTrue);
    expect((await repo.getScript('1.py'))!.runCount, 1);
    expect((await repo.getScript('1.py'))!.modifiedAt.isAfter(old), isTrue);
    service.output(run['execution_id'] as String);
    await expectLater(service.run('0.py'), throwsA(isA<McpToolException>()));
    await expectLater(
        service.run('missing.py'), throwsA(isA<McpToolException>()));
    expect(repo.incrementRunCountCount, 1);
    bridge.emitState(ExecutionState(
        executionId: run['execution_id'] as String,
        status: ExecutionStatus.completed,
        exitCode: 0));
    await Future<void>.delayed(Duration.zero);
    await service.run('1.py');
    expect(repo.incrementRunCountCount, 2);
    expect(workspace.scripts.first.runCount, 2);
    expect((await repo.getScript('0.py'))!.runCount, 0);
  });
}
