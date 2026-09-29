import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:python_runner/features/mcp/application/mcp_execution_service.dart';
import 'package:python_runner/features/mcp/domain/mcp_error_codes.dart';
import 'package:python_runner/features/mcp/domain/mcp_tool_definition.dart';
import 'package:python_runner/features/mcp/infrastructure/mcp_tool_registry.dart';
import 'package:python_runner/models/execution_state.dart';
import 'package:python_runner/providers/execution_provider.dart';
import 'package:python_runner/runtime/runtime_manager.dart';
import '../../support/mcp_test_helper.dart';
import '../../support/script_test_helper.dart';
import '../../support/script_workspace_harness.dart';

class MenuBridge extends FakeScriptNativeBridge {
  @override
  Future<Map<String, String>> getLinuxLikeRuntimeInfo() async =>
      {'available': 'true', 'installed': 'true'};

  @override
  Future<void> stopLinuxLikeExecution() async {}
  final inputs = <String>[];
  final backends = <String>[];
  Future<void> Function()? onInput;

  @override
  Future<void> executeLinuxLikeScript(String name, String executionId,
      {String? workingDir,
      Map<String, String>? environment,
      int? timeoutSeconds,
      String? projectKey,
      String? projectMainFilePath}) async {}

  Future<void> accept(String backend, String input) async {
    inputs.add(input);
    backends.add(backend);
    await onInput?.call();
  }

  @override
  Future<void> sendStdin(String input) => accept('chaquopy', input);
  @override
  Future<void> sendLinuxLikeStdin(String input) => accept('linux_like', input);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final backend in ['chaquopy', 'linux_like']) {
    test('$backend supports repeated menu input, blank input, races and errors',
        () async {
      SharedPreferences.setMockInitialValues({'runtime_backend': backend});
      final bridge = MenuBridge();
      final owner = ExecutionProvider(bridge,
          runtimeManager: backend == 'chaquopy'
              ? RuntimeManager.chaquopy(bridge)
              : RuntimeManager.linuxLike(bridge));
      addTearDown(() {
        owner.dispose();
        bridge.dispose();
      });
      final service = McpExecutionService(
          execution: () => owner,
          scripts: FakeScriptRepository(),
          recordRun: (_) async {});
      await owner.executeScript('menu.py');
      final id = owner.state.executionId!;
      bridge.emitStdin(executionId: id, prompt: '1.查询 2.退出\n请选择：');
      await Future<void>.delayed(Duration.zero);
      final first = service.output(id);
      expect(first['waiting_for_input'], isTrue);
      expect(first['input_prompt'], contains('请选择'));
      final requestId = first['input_request_id'] as int;
      bridge.onInput = () async {
        // Native code can report the next input before acknowledging this one.
        bridge.emitStdin(executionId: id, prompt: '按回车继续：');
        await Future<void>.delayed(Duration.zero);
      };
      final sent = await service.sendInput(id, '1', inputRequestId: requestId);
      expect(sent['input_sent'], isTrue);
      expect(sent['waiting_for_input'], isTrue);
      expect(sent['input_prompt'], '按回车继续：');
      expect(bridge.inputs, ['1']);
      expect(bridge.backends, [backend]);
      await expectLater(
          service.sendInput(id, '1', inputRequestId: requestId),
          throwsA(isA<McpToolException>()
              .having((e) => e.code, 'code', 'INPUT_REQUEST_STALE')));

      final secondId = sent['input_request_id'] as int;
      bridge.onInput = () async {
        throw StateError('broken pipe');
      };
      await expectLater(
          service.sendInput(id, '', inputRequestId: secondId),
          throwsA(isA<McpToolException>()
              .having((e) => e.code, 'code', 'STDIN_SEND_FAILED')));
      expect(service.output(id)['waiting_for_input'], isTrue);

      final gate = Completer<void>();
      bridge.onInput = () => gate.future;
      final inFlight = service.sendInput(id, '', inputRequestId: secondId);
      await expectLater(
          service.sendInput(id, 'duplicate', inputRequestId: secondId),
          throwsA(isA<McpToolException>()));
      gate.complete();
      expect((await inFlight)['waiting_for_input'], isFalse);
      expect(bridge.inputs, ['1', '', '']);

      bridge.emitState(ExecutionState(
          executionId: id, status: ExecutionStatus.completed, exitCode: 0));
      await Future<void>.delayed(Duration.zero);
      await owner.executeScript('other.py');
      bridge.emitStdin(executionId: owner.state.executionId, prompt: 'other');
      await Future<void>.delayed(Duration.zero);
      await expectLater(
          service.sendInput(id, 'wrong run', inputRequestId: secondId),
          throwsA(isA<McpToolException>()));
      expect(bridge.inputs, hasLength(3));

      // Tool accepts empty strings and passes the latest prompt identifier.
      bridge.onInput = null;
      final registry =
          McpToolRegistry(FakeMcpApplicationFacade(), execution: service);
      final result = await registry.find('pyrunner_execution_input')!.handler(
        const McpToolContext(
            sessionId: 'test', clientName: 'test', clientVersion: '1'),
        {
          'execution_id': owner.state.executionId,
          'input_request_id': owner.inputRequestRevision,
          'input': ''
        },
      );
      expect(result.isError, isFalse);
      expect(bridge.inputs.last, '');
      await expectLater(
          service.sendInput(owner.state.executionId!, 'a\nb',
              inputRequestId: 1),
          throwsA(isA<McpToolException>()));
    });
  }
}
