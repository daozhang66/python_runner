import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/mcp/application/mcp_confirmation_service.dart';
import 'package:python_runner/features/mcp/application/mcp_terminal_service.dart';
import 'package:python_runner/features/mcp/domain/mcp_error_codes.dart';
import 'package:python_runner/features/mcp/domain/mcp_permission.dart';
import 'package:python_runner/features/mcp/infrastructure/mcp_terminal_tools.dart';

import '../../support/mcp_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  McpTerminalService newService() =>
      McpTerminalService(confirmations: McpConfirmationService());

  test('the terminal permission is off by default and counts as a write scope',
      () {
    expect(McpPermission.defaults, isNot(contains(McpPermission.terminal)));
    expect(McpPermission.terminal.isWriteScope, isTrue);
  });

  test('terminal tools are listed next to the regular ones and need the permission',
      () {
    final registry = McpTerminalToolRegistry(
      FakeMcpApplicationFacade(),
      terminal: newService(),
    );
    final names = registry.definitions.map((d) => d.name).toSet();
    expect(
      names,
      containsAll(<String>[
        'pyrunner_terminal_list',
        'pyrunner_terminal_send',
        'pyrunner_terminal_read',
        'pyrunner_terminal_interrupt',
        'pyrunner_terminal_tell_user',
        'pyrunner_terminal_wait_reply',
        'pyrunner_script_list',
      ]),
    );
    final terminalTools =
        registry.definitions.where((d) => d.name.startsWith('pyrunner_terminal_'));
    expect(terminalTools, isNotEmpty);
    expect(
      terminalTools.every((d) => d.permission == McpPermission.terminal),
      isTrue,
    );
    expect(registry.find('pyrunner_terminal_send'), isNotNull);
    expect(registry.find('pyrunner_script_list'), isNotNull);
    expect(registry.find('pyrunner_nope'), isNull);
  });

  test('a command with more than one line is refused before anything is asked',
      () async {
    final service = newService();
    await expectLater(
      service.send(
        sessionId: 'local-1',
        command: 'ls\nrm -rf x',
        clientLabel: 'test',
      ),
      throwsA(isA<McpToolException>()),
    );
  });

  test('a note for the user can be answered and waited for', () async {
    final service = newService();
    final sent = service.tellUser('Shall I continue?', 'test');
    final id = sent['message_id'] as int;
    expect(service.openMessages, hasLength(1));

    final waiting = service.waitReply(messageId: id, timeoutSeconds: 5);
    service.reply(id, 'yes');
    final result = await waiting;

    expect(result['replied'], isTrue);
    expect(result['reply'], 'yes');
    expect(service.openMessages, isEmpty);
  });

  test('a dismissed note ends the wait without a reply', () async {
    final service = newService();
    final id = service.tellUser('Hello', 'test')['message_id'] as int;
    final waiting = service.waitReply(messageId: id, timeoutSeconds: 5);
    service.dismiss(id);
    final result = await waiting;
    expect(result['replied'], isFalse);
    expect(result['dismissed'], isTrue);
  });
}
