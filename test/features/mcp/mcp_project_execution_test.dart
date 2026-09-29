import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:python_runner/features/mcp/application/mcp_execution_service.dart';
import 'package:python_runner/features/mcp/domain/mcp_error_codes.dart';
import 'package:python_runner/features/mcp/domain/mcp_tool_definition.dart';
import 'package:python_runner/features/mcp/infrastructure/mcp_tool_registry.dart';
import 'package:python_runner/models/execution_state.dart';
import 'package:python_runner/models/script_group.dart';
import 'package:python_runner/providers/execution_provider.dart';
import 'package:python_runner/runtime/runtime_manager.dart';

import '../../support/mcp_test_helper.dart';
import '../../support/script_test_helper.dart';
import '../../support/script_workspace_harness.dart';

class ProjectBridge extends FakeScriptNativeBridge {
  final executions = <Map<String, dynamic>>[];

  @override
  Future<Map<String, String>> getLinuxLikeRuntimeInfo() async =>
      const {'available': 'true', 'installed': 'true'};

  @override
  Future<void> executeLinuxLikeScript(
    String name,
    String executionId, {
    String? workingDir,
    Map<String, String>? environment,
    int? timeoutSeconds,
    String? projectKey,
    String? projectMainFilePath,
  }) async {
    executions.add({
      'name': name,
      'execution_id': executionId,
      'project_key': projectKey,
      'main_file_path': projectMainFilePath,
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScriptGroup group;
  late FakeScriptRepository repository;
  late ProjectBridge bridge;
  late ExecutionProvider owner;
  late McpExecutionService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({'runtime_backend': 'linux_like'});
    final now = DateTime.fromMillisecondsSinceEpoch(1000);
    group = ScriptGroup(
      id: 7,
      name: 'Demo Project',
      sortOrder: 0,
      createdAt: now,
      modifiedAt: now,
      projectKey: 'demo_project',
      mainFilePath: 'src/main.py',
      isProject: true,
    );
    repository = FakeScriptRepository(groups: [group]);
    bridge = ProjectBridge();
    owner = ExecutionProvider(
      bridge,
      runtimeManager: RuntimeManager.linuxLike(bridge),
    );
    service = McpExecutionService(
      execution: () => owner,
      scripts: repository,
      recordRun: (_) async {},
      recordProjectRun: (used) => repository.touchGroup(used.id!),
    );
  });

  tearDown(() {
    owner.dispose();
    bridge.dispose();
  });

  test('runs a project group through the Linux-like project path', () async {
    final result = await service.runProject('demo_project');
    await Future<void>.delayed(Duration.zero);

    expect(result['project_key'], 'demo_project');
    expect(result['script_name'], 'Demo Project');
    expect(result['main_file_path'], 'src/main.py');
    expect(result['execution_id'], owner.state.executionId);
    expect(bridge.executions, hasLength(1));
    expect(bridge.executions.single['name'], 'Demo Project');
    expect(bridge.executions.single['project_key'], 'demo_project');
    expect(bridge.executions.single['main_file_path'], 'src/main.py');
    expect(repository.touchGroupCount, 1);
    expect(repository.lastTouchedGroupId, 7);
    expect(
        service.output(result['execution_id'] as String)['status'], 'running');

    bridge.emitState(ExecutionState(
      executionId: result['execution_id'] as String,
      status: ExecutionStatus.completed,
      exitCode: 0,
    ));
    await Future<void>.delayed(Duration.zero);
  });

  test('project run does not replace a currently running execution', () async {
    final first = await service.runProject('demo_project');
    await expectLater(
      service.runProject('demo_project'),
      throwsA(isA<McpToolException>()
          .having((e) => e.code, 'code', 'EXECUTION_BUSY')),
    );
    await Future<void>.delayed(Duration.zero);
    expect(bridge.executions, hasLength(1));

    bridge.emitState(ExecutionState(
      executionId: first['execution_id'] as String,
      status: ExecutionStatus.completed,
      exitCode: 0,
    ));
    await Future<void>.delayed(Duration.zero);
  });

  test('validates missing projects and projects without a main file', () async {
    await expectLater(
      service.runProject('missing'),
      throwsA(isA<McpToolException>()
          .having((e) => e.code, 'code', McpErrorCodes.projectNotFound)),
    );

    final emptyMain = group.copyWith(clearMainFilePath: true);
    final emptyRepository = FakeScriptRepository(groups: [emptyMain]);
    final emptyService = McpExecutionService(
      execution: () => owner,
      scripts: emptyRepository,
      recordRun: (_) async {},
    );
    await expectLater(
      emptyService.runProject('demo_project'),
      throwsA(isA<McpToolException>()
          .having((e) => e.code, 'code', McpErrorCodes.projectPathInvalid)),
    );
  });

  test('MCP exposes a dedicated project run tool', () async {
    final registry =
        McpToolRegistry(FakeMcpApplicationFacade(), execution: service);
    final tool = registry.find('pyrunner_project_run');
    expect(tool, isNotNull);
    expect(registry.definitions.map((definition) => definition.name),
        contains('pyrunner_project_run'));

    final result = await tool!.handler(
      const McpToolContext(
        sessionId: 'test',
        clientName: 'test',
        clientVersion: '1',
      ),
      {'project_key': 'demo_project'},
    );
    expect(result.isError, isFalse);
    await Future<void>.delayed(Duration.zero);

    bridge.emitState(ExecutionState(
      executionId: owner.state.executionId!,
      status: ExecutionStatus.completed,
      exitCode: 0,
    ));
    await Future<void>.delayed(Duration.zero);
  });
}
