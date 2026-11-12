import '../application/mcp_terminal_service.dart';
import '../domain/mcp_permission.dart';
import '../domain/mcp_tool_definition.dart';
import '../domain/mcp_tool_result.dart';
import 'mcp_tool_registry.dart';

/// The regular MCP tools plus the terminal tools.
///
/// All terminal tools need the `terminal` permission (off by default). The
/// person can pause them at any time from the AI chat button in the app.
class McpTerminalToolRegistry extends McpToolRegistry {
  McpTerminalToolRegistry(
    super.facade, {
    required McpTerminalService terminal,
    super.operations,
    super.execution,
  }) : _terminal = terminal {
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
              'List the open terminal sessions (local shells and SSH) with id, status, output_cursor and whether you opened them. A session with needs_user_input=true is waiting for the user to type a password. Use pyrunner_terminal_open for a new local shell.',
          permission: McpPermission.terminal,
          inputSchema: _obj(const <String, dynamic>{}),
        ),
        handler: (context, args) async =>
            McpToolResult.success(_terminal.listSessions()),
      ),
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_terminal_open',
          description:
              'Open a new local shell session (Android sh). It appears as a tab in the app so the user can watch and type into it too. The built-in commands python, run, scripts and pyhelp only work while the user has the Terminal page open in the app (their output shows in a run console); otherwise they answer with a message saying so. SSH sessions must be opened by the user.',
          permission: McpPermission.terminal,
          inputSchema: _obj(<String, dynamic>{
            'title': _str('Short name for the tab (optional)'),
          }),
        ),
        timeout: const Duration(seconds: 60),
        handler: (context, args) async =>
            McpToolResult.success(await _terminal.openLocal(
          title: optionalString(args, 'title', max: 80),
        )),
      ),
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_terminal_close',
          description:
              'Close a terminal session you opened with pyrunner_terminal_open. The user\'s own sessions cannot be closed by you.',
          permission: McpPermission.terminal,
          inputSchema: _obj(<String, dynamic>{
            'session_id': _str('Session id'),
          }, <String>[
            'session_id'
          ]),
        ),
        handler: (context, args) async => McpToolResult.success(
          await _terminal.close(requireString(args, 'session_id', max: 64)),
        ),
      ),
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_terminal_send',
          description:
              'Type one command line into a terminal session and press Enter, then wait up to wait_seconds for the output to settle and return it with next_cursor. You and the user share the same terminal: pyrunner_terminal_read also shows what the user typed. If the result has needs_user_input=true the terminal asks for a password: do NOT guess it; tell the user to switch to Python Runner (it opens the terminal for them), then call pyrunner_terminal_wait_output. A line typed at a password prompt is never recorded in the logs. (If the user turned on "confirm each command", they are asked first.)',
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
              'Read the plain-text output of a terminal session, including what the user typed there. Pass cursor (next_cursor of an earlier call) to get only what is new; without it the most recent output is returned. dropped=true means older output was already discarded. needs_user_input=true means the terminal waits for the user to type a password.',
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
          name: 'pyrunner_terminal_wait_output',
          description:
              'Wait until the terminal prints something new after cursor (for example once the user has typed the password it asked for), then return the output like pyrunner_terminal_read. Returns empty text when the time is up; call it again to keep waiting.',
          permission: McpPermission.terminal,
          inputSchema: _obj(<String, dynamic>{
            'session_id': _str('Session id'),
            'cursor': _int('next_cursor of your last call', minimum: 0),
            'timeout_seconds': _int('Seconds to wait; default 30, maximum 100',
                minimum: 1, maximum: 100),
          }, <String>[
            'session_id',
            'cursor'
          ]),
        ),
        timeout: const Duration(seconds: 110),
        handler: (context, args) async =>
            McpToolResult.success(await _terminal.waitOutput(
          requireString(args, 'session_id', max: 64),
          cursor: optionalInt(args, 'cursor') ?? 0,
          timeoutSeconds: optionalInt(args, 'timeout_seconds') ?? 30,
        )),
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
              'Say something to the user in the in-app AI chat (a small button in Python Runner). The app is usually in the background while the user talks to you in another app, so ask them in YOUR chat first; use this too when a password is needed (they must switch to Python Runner and type it in the terminal or the script console, which the app opens for them) or when the note should stay in the app log.',
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
              'Wait for the user to answer your message from pyrunner_terminal_tell_user (default: the newest one). Returns replied=false when the time is up; call it again to keep waiting.',
          permission: McpPermission.terminal,
          inputSchema: _obj(<String, dynamic>{
            'message_id': _int('message_id returned by tell_user', minimum: 1),
            'timeout_seconds': _int('Seconds to wait; default 30, maximum 100',
                minimum: 1, maximum: 100),
          }),
        ),
        timeout: const Duration(seconds: 110),
        handler: (context, args) async =>
            McpToolResult.success(await _terminal.waitReply(
          messageId: optionalInt(args, 'message_id'),
          timeoutSeconds: optionalInt(args, 'timeout_seconds') ?? 30,
        )),
      ),
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_terminal_inbox',
          description:
              'Read what the user wrote to you in the in-app AI chat, including unprompted messages. Pass next_after_id from the previous call to get only new ones; with wait_seconds it waits until something arrives.',
          permission: McpPermission.terminal,
          inputSchema: _obj(<String, dynamic>{
            'after_id': _int('Only messages after this id (default 0)',
                minimum: 0),
            'wait_seconds': _int('Seconds to wait if nothing is new; default 0, maximum 100',
                minimum: 0, maximum: 100),
          }),
        ),
        timeout: const Duration(seconds: 110),
        handler: (context, args) async =>
            McpToolResult.success(await _terminal.inbox(
          afterId: optionalInt(args, 'after_id') ?? 0,
          waitSeconds: optionalInt(args, 'wait_seconds') ?? 0,
        )),
      ),
    ];
  }
}
