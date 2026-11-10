import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/mcp/application/mcp_confirmation_service.dart';
import 'package:python_runner/features/mcp/application/mcp_terminal_service.dart';
import 'package:python_runner/features/mcp/domain/mcp_error_codes.dart';
import 'package:python_runner/features/mcp/domain/mcp_permission.dart';
import 'package:python_runner/features/mcp/infrastructure/mcp_terminal_tools.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        'pyrunner_terminal_open',
        'pyrunner_terminal_close',
        'pyrunner_terminal_send',
        'pyrunner_terminal_read',
        'pyrunner_terminal_interrupt',
        'pyrunner_terminal_tell_user',
        'pyrunner_terminal_wait_reply',
        'pyrunner_terminal_inbox',
        'pyrunner_script_list',
      ]),
    );
    final terminalTools = registry.definitions
        .where((d) => d.name.startsWith('pyrunner_terminal_'));
    expect(terminalTools, isNotEmpty);
    expect(
      terminalTools.every((d) => d.permission == McpPermission.terminal),
      isTrue,
    );
    expect(registry.find('pyrunner_terminal_send'), isNotNull);
    expect(registry.find('pyrunner_script_list'), isNotNull);
    expect(registry.find('pyrunner_nope'), isNull);
  });

  test('commands are not confirmed one by one unless the person turns it on',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final service = newService();
    await service.loadSettings();
    expect(service.confirmEach, isFalse);
  });

  test('a command with more than one line is refused before anything happens',
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

  test('a message for the user is unread until the chat is opened', () {
    final service = newService();
    service.tellUser('Done with the install', 'test');
    expect(service.unreadCount, 1);
    service.markSeen();
    expect(service.unreadCount, 0);
  });

  test('the AI can wait for the answer to its message', () async {
    final service = newService();
    final id = service.tellUser('Shall I continue?', 'test')['message_id'] as int;

    final waiting = service.waitReply(messageId: id, timeoutSeconds: 5);
    service.userSay('yes');
    final result = await waiting;

    expect(result['replied'], isTrue);
    expect(result['reply'], 'yes');
  });

  test('unprompted messages from the user are handed over once', () async {
    final service = newService();
    service.userSay('hello');
    final first = await service.inbox();
    expect(first['messages'] as List<dynamic>, hasLength(1));

    final next = await service.inbox(afterId: first['next_after_id'] as int);
    expect(next['messages'] as List<dynamic>, isEmpty);
  });

  test('while paused the terminal tools are refused but the chat keeps working',
      () async {
    final service = newService();
    service.setPaused(true);
    expect(service.listSessions, throwsA(isA<McpToolException>()));
    service.userSay('please continue');
    final inbox = await service.inbox();
    expect(inbox['messages'] as List<dynamic>, hasLength(1));
    expect(inbox['paused'], isTrue);
  });
}
