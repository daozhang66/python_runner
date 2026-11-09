import '../application/mcp_application_facade.dart';
import '../application/mcp_execution_service.dart';
import '../application/mcp_operation_registry.dart';
import '../application/mcp_terminal_service.dart';
import '../domain/mcp_permission.dart';
import '../domain/mcp_tool_definition.dart';
import '../domain/mcp_tool_result.dart';
import 'mcp_tool_registry.dart';

/// The regular MCP tools plus the terminal tools.
///
/// All terminal tools need the `terminal` permission (off by default), and
/// every command sent through `pyrunner_terminal_send` is approved by the
/// person in a dialog of its own.
class McpTerminalToolRegistry extends McpToolRegistry {
  McpTerminalToolRegistry(
    McpApplicationFacade facade, {
    required McpTerminalService terminal,
    McpOperationRegistry? operations,
    McpExecutionService? execution,
  })  : _terminal = terminal,
        super(facade, operations: operations, execution: execution) {
    _terminalEntries = _buildTerminalEntries();
    final taken = super.definitions.map((d) => d.name).toSet();
    for (final entry in _terminalEntries) {
      if (!taken.add(entry.definition.name)) {
        throw StateError('Duplicate MCP tool name: ${entry.definition.name}');
      }
    }
  }

  final McpTerminalService _terminal;
  late final List<McpToolEntry> _terminalEntries;

  @override
  List<McpToolDefinition> get definitions => <McpToolDefinition>[
        ...super.definitions,
        for (final entry in _terminalEntries) entry.definition,
      ];

  @override
  McpToolEntry? find(String name) {
    for (final entry in _terminalEntries) {
      if (entry.definition.name == name) return entry;
    }
    return super.find(name);
  }

  static String _label(McpToolContext context) {
    final label = '${context.clientName} ${context.clientVersion}'.trim();
    return label.isEmpty ? 'MCP client' : label;
  }

  static Map<String, dynamic> _obj(
    Map<String, dynamic> properties, [
    List<String> required = const <String>[],
  ]) =>
      <String, dynamic>{
        'type': 'object',
        'properties': properties,
        if (required.isNotEmpty) 'required': required,
        'additionalProperties': false,
      };

  static Map<String, dynamic> _str(String description) =>
      <String, dynamic>{'type': 'string', 'description': description};

  static Map<String, dynamic> _int(
    String description, {
    int? minimum,
    int? maximum,
  }) =>
      <String, dynamic>{
        'type': 'integer',
        'description': description,
        if (minimum != null) 'minimum': minimum,
        if (maximum != null) 'maximum': maximum,
      };

  List<McpToolEntry> _buildTerminalEntries() {
    return <McpToolEntry>[
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_terminal_list',
          description:
              'List the terminal sessions the user has open (local shells and SSH) with id, status and output_cursor. The user opens sessions in the app; this tool cannot open new ones.',
          permission: McpPermission.terminal,
          inputSchema: _obj(const <String, dynamic>{}),
        ),
        handler: (context, args) async =>
            McpToolResult.success(_terminal.listSessions()),
      ),
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_terminal_send',
          description:
              'Type one command line into a terminal session and press Enter. The user approves EVERY command in a dialog (60 seconds, then it is refused). Waits up to wait_seconds for the output to settle and returns it with next_cursor; use pyrunner_terminal_read for more. A line typed at a password prompt is never recorded in the logs.',
          permission: McpPermission.terminal,
          inputSchema: _obj(<String, dynamic>{
            'session_id': _str('Session id from pyrunner_terminal_list'),
            'command': _str(
                'One line, at most 4096 characters, no control characters; empty means just Enter'),
            'wait_seconds': _int(
                'Seconds to wait for output (default 2, maximum 30)',
                minimum: 0,
                maximum: 30),
          }, <String>[
            'session_id',
            'command'
          ]),
        ),
        timeout: const Duration(seconds: 110),
        summarize: (args) {
          final command = args['command'];
          final length = command is String ? command.length : 0;
          return 'Terminal command for ${args['session_id']} ($length characters)';
        },
        handler: (context, args) async =>
            McpToolResult.success(await _terminal.send(
          sessionId: requireString(args, 'session_id', max: 64),
          command: requireString(args, 'command',
              max: McpTerminalService.maxCommandChars, allowEmpty: true),
          waitSeconds: optionalInt(args, 'wait_seconds') ?? 2,
          clientLabel: _label(context),
        )),
      ),
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_terminal_read',
          description:
              'Read the plain-text output of a terminal session. Pass cursor (next_cursor of an earlier call) to get only what is new; without it the most recent output is returned. dropped=true means older output was already discarded.',
          permission: McpPermission.terminal,
          inputSchema: _obj(<String, dynamic>{
            'session_id': _str('Session id'),
            'cursor': _int('Position to read from', minimum: 0),
            'max_chars': _int('Character budget; default 20000, maximum 64000',
                minimum: 1, maximum: 64000),
          }, <String>[
            'session_id'
          ]),
        ),
        handler: (context, args) async => McpToolResult.success(
          _terminal.read(
            requireString(args, 'session_id', max: 64),
            cursor: optionalInt(args, 'cursor'),
            maxChars: optionalInt(args, 'max_chars') ?? 20000,
          ),
        ),
      ),
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_terminal_interrupt',
          description:
              'Send Ctrl+C to a terminal session, for example to stop a command that does not end.',
          permission: McpPermission.terminal,
          inputSchema: _obj(<String, dynamic>{
            'session_id': _str('Session id'),
          }, <String>[
            'session_id'
          ]),
        ),
        handler: (context, args) async => McpToolResult.success(
          _terminal.interrupt(requireString(args, 'session_id', max: 64)),
        ),
      ),
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_terminal_tell_user',
          description:
              'Leave a message for the user; it opens as a dialog in the app where they can reply or dismiss it. Use it when you need a decision, a password you must not guess, or want to report something. Then call pyrunner_terminal_wait_reply.',
          permission: McpPermission.terminal,
          inputSchema: _obj(<String, dynamic>{
            'message': _str('What to tell or ask the user, at most 2000 characters'),
          }, <String>[
            'message'
          ]),
        ),
        handler: (context, args) async => McpToolResult.success(
          _terminal.tellUser(
            requireString(args, 'message', max: 2000),
            _label(context),
          ),
        ),
      ),
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_terminal_wait_reply',
          description:
              'Wait for the user to answer a message left with pyrunner_terminal_tell_user (default: the newest one). Returns replied=false when the time is up or the message was dismissed; you may call it again to keep waiting.',
          permission: McpPermission.terminal,
          inputSchema: _obj(<String, dynamic>{
            'message_id': _int('message_id returned by tell_user', minimum: 1),
            'timeout_seconds': _int('Seconds to wait; default 60, maximum 100',
                minimum: 1, maximum: 100),
          }),
        ),
        timeout: const Duration(seconds: 110),
        handler: (context, args) async =>
            McpToolResult.success(await _terminal.waitReply(
          messageId: optionalInt(args, 'message_id'),
          timeoutSeconds: optionalInt(args, 'timeout_seconds') ?? 60,
        )),
      ),
    ];
  }
}
