import '../application/mcp_application_facade.dart';
import '../application/mcp_operation_registry.dart';
import '../application/mcp_execution_service.dart';
import '../domain/mcp_error_codes.dart';
import '../domain/mcp_facade_models.dart';
import '../domain/mcp_permission.dart';
import '../domain/mcp_tool_definition.dart';
import '../domain/mcp_tool_result.dart';

/// 工具处理器签名：只接收 [McpToolContext] 与已通过 Schema 的参数。
typedef McpToolHandler = Future<McpToolResult> Function(
  McpToolContext context,
  Map<String, dynamic> arguments,
);

/// 确认界面参数摘要生成器：只输出名称、大小等摘要，不输出完整正文。
typedef McpToolSummarizer = String Function(Map<String, dynamic> arguments);

/// 一个可调用的 MCP 工具：定义 + 处理器 + 超时 + 确认摘要。
class McpToolEntry {
  const McpToolEntry({
    required this.definition,
    required this.handler,
    this.timeout = const Duration(seconds: 120),
    this.summarize,
  });

  final McpToolDefinition definition;
  final McpToolHandler handler;
  final Duration timeout;
  final McpToolSummarizer? summarize;
}

/// MCP 工具注册表（计划 §6）：tools/list 与 tools/call 的唯一事实来源。
class McpToolRegistry {
  McpToolRegistry(this._facade,
      {McpOperationRegistry? operations, McpExecutionService? execution})
      : _operations = operations,
        _execution = execution {
    _entries = _buildEntries();
    final names = <String>{};
    for (final entry in _entries) {
      final name = entry.definition.name;
      if (!RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(name) ||
          !names.add(name)) {
        throw StateError('Invalid or duplicate MCP tool name: $name');
      }
    }
  }

  final McpApplicationFacade _facade;
  final McpOperationRegistry? _operations;
  final McpExecutionService? _execution;

  McpExecutionService get execution =>
      _execution ??
      (throw McpToolException(
          'EXECUTION_UNAVAILABLE', 'Execution service is not initialized'));
  late final List<McpToolEntry> _entries;

  List<McpToolDefinition> get definitions =>
      _entries.map((entry) => entry.definition).toList(growable: false);

  McpToolEntry? find(String name) {
    // Old clients may retain dotted names; aliases are never advertised.
    if (name.contains('.')) name = 'pyrunner_${name.replaceAll('.', '_')}';
    for (final entry in _entries) {
      if (entry.definition.name == name) return entry;
    }
    return null;
  }

  // ── 参数解析助手（Schema 之外的入口二次校验，计划 §9.1）──

  Never _invalid(String message) =>
      throw McpToolException(McpErrorCodes.invalidArgument, message);

  String requireString(Map<String, dynamic> args, String key,
      {int max = 1024, bool allowEmpty = false}) {
    final value = args[key];
    if (value is! String || (!allowEmpty && value.isEmpty)) {
      _invalid('Parameter $key must be a non-empty string');
    }
    if (value.length > max) _invalid('Parameter $key is too long');
    return value;
  }

  String? optionalString(Map<String, dynamic> args, String key,
      {int max = 1024}) {
    final value = args[key];
    if (value == null) return null;
    if (value is! String) _invalid('Parameter $key must be a string');
    if (value.length > max) _invalid('Parameter $key is too long');
    if (value.isEmpty) return null;
    return value;
  }

  int requireInt(Map<String, dynamic> args, String key) {
    final value = args[key];
    if (value is int) return value;
    if (value is num && value == value.toInt()) return value.toInt();
    _invalid('Parameter $key must be an integer');
  }

  int? optionalInt(Map<String, dynamic> args, String key) {
    final value = args[key];
    if (value == null) return null;
    if (value is int) return value;
    if (value is num && value == value.toInt()) return value.toInt();
    _invalid('Parameter $key must be an integer');
  }

  bool optionalBool(Map<String, dynamic> args, String key,
      {bool defaultValue = false}) {
    final value = args[key];
    if (value == null) return defaultValue;
    if (value is bool) return value;
    _invalid('Parameter $key must be a boolean');
  }

  DateTime? optionalIsoDate(Map<String, dynamic> args, String key) {
    final value = args[key];
    if (value == null) return null;
    if (value is! String) _invalid('Parameter $key must be an ISO8601 string');
    final parsed = DateTime.tryParse(value);
    if (parsed == null) _invalid('Parameter $key is not a valid ISO8601 time');
    return parsed.toUtc();
  }

  Map<String, dynamic> _objectSchema(
    Map<String, dynamic> properties, [
    List<String> required = const [],
  ]) {
    return {
      'type': 'object',
      'properties': properties,
      if (required.isNotEmpty) 'required': required,
      'additionalProperties': false,
    };
  }

  Map<String, dynamic> _stringProp(String description,
          {bool nullable = false}) =>
      {
        'type': nullable ? ['string', 'null'] : 'string',
        'description': description
      };

  Map<String, dynamic> _intProp(String description,
          {int? minimum, int? maximum, bool nullable = false}) =>
      {
        'type': nullable ? ['integer', 'null'] : 'integer',
        'description': description,
        if (minimum != null) 'minimum': minimum,
        if (maximum != null) 'maximum': maximum,
      };

  Map<String, dynamic> _boolProp(String description) =>
      {'type': 'boolean', 'description': description};

  // ── 工具目录 ──

  List<McpToolEntry> _buildEntries() {
    return [
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_fs_create_directory',
          description:
              'Create a directory named name under the writable absolute path path. Existing entries are not overwritten.',
          permission: McpPermission.writeFilesystem,
          inputSchema: _objectSchema({
            'path': _stringProp('Parent directory absolute path'),
            'name': _stringProp('Single directory name')
          }, [
            'path',
            'name'
          ]),
        ),
        handler: (_, args) async {
          await _facade.createDirectory(requireString(args, 'path'),
              requireString(args, 'name', max: 255));
          return McpToolResult.success({'success': true});
        },
      ),
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_fs_rename_entry',
          description:
              'Rename a file or directory. new_name is only a name; cross-directory moves and overwrites are not supported.',
          permission: McpPermission.writeFilesystem,
          inputSchema: _objectSchema({
            'path': _stringProp('Entry absolute path'),
            'new_name': _stringProp('New name')
          }, [
            'path',
            'new_name'
          ]),
        ),
        handler: (_, args) async {
          await _facade.renameFileEntry(requireString(args, 'path'),
              requireString(args, 'new_name', max: 255));
          return McpToolResult.success({'success': true});
        },
      ),
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_fs_delete_entry',
          description:
              'Delete a file or empty directory. Recursive deletion is unsupported and deletion is irreversible.',
          permission: McpPermission.deleteFilesystem,
          inputSchema: _objectSchema(
              {'path': _stringProp('Entry absolute path')}, ['path']),
        ),
        handler: (_, args) async {
          await _facade.deleteFileEntry(requireString(args, 'path'));
          return McpToolResult.success({'success': true});
        },
      ),
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_fs_write_file',
          description:
              'Fully overwrite an existing plain-text file as UTF-8; content may be empty and no new file is created. Prefer dedicated script and project tools so metadata stays synchronized.',
          permission: McpPermission.writeFilesystem,
          inputSchema: _objectSchema({
            'path': _stringProp('File absolute path'),
            'content': _stringProp('Complete new content')
          }, [
            'path',
            'content'
          ]),
        ),
        handler: (_, args) async {
          await _facade.writeTextFile(
              requireString(args, 'path'),
              requireString(args, 'content',
                  max: 2 * 1024 * 1024, allowEmpty: true));
          return McpToolResult.success({'success': true});
        },
      ),
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_script_run',
          description:
              'Run a saved regular Python script and return an execution_id immediately. Busy runs are rejected. Poll pyrunner_execution_output; when a menu script waits for input(), reply with pyrunner_execution_input and poll again. Do not rerun. The app execution timeout applies.',
          permission: McpPermission.runScripts,
          inputSchema: _objectSchema(
              {'name': _stringProp('Saved script name, such as main.py')},
              ['name']),
        ),
        handler: (_, args) async => McpToolResult.success(
            await execution.run(requireString(args, 'name', max: 120))),
      ),
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_project_run',
          description:
              'Run the main program of a project group and return an execution_id immediately. Projects require the Debian runtime; install it and make it active first. Busy runs are rejected. Use pyrunner_execution_output and pyrunner_execution_input for output and interaction.',
          permission: McpPermission.runScripts,
          inputSchema: _objectSchema({
            'project_key': _stringProp('Project key; see pyrunner_group_list')
          }, [
            'project_key'
          ]),
        ),
        handler: (_, args) async => McpToolResult.success(
            await execution.runProject(requireString(args, 'project_key'))),
      ),
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_execution_output',
          description:
              'Read the latest output snapshot, status, and exit code for an execution_id. When waiting_for_input is true, use input_prompt and input_request_id with pyrunner_execution_input. History is bounded and repeated calls return snapshots, not deltas.',
          permission: McpPermission.runScripts,
          inputSchema: _objectSchema({
            'execution_id': _stringProp('execution_id returned by a run tool'),
            'max_chars': _intProp(
                'Output character budget; default 32000, maximum 64000',
                minimum: 1,
                maximum: 64000),
          }, [
            'execution_id'
          ]),
        ),
        handler: (_, args) async => McpToolResult.success(execution.output(
            requireString(args, 'execution_id', max: 128),
            maxChars: optionalInt(args, 'max_chars') ?? 32000)),
      ),
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_execution_input',
          description:
              'Reply to an interactive script or menu waiting for input(). Pass execution_id, the latest input_request_id, and one-line input; an empty string means Enter and no newline is needed. Each request ID may be used once, then poll output for the next prompt.',
          permission: McpPermission.runScripts,
          inputSchema: _objectSchema({
            'execution_id': _stringProp('Execution ID'),
            'input_request_id':
                _intProp('Input request ID from the latest output', minimum: 1),
            'input': _stringProp(
                'Menu choice or reply; one line, may be empty, maximum 8192 characters'),
          }, [
            'execution_id',
            'input_request_id',
            'input'
          ]),
        ),
        handler: (_, args) async =>
            McpToolResult.success(await execution.sendInput(
          requireString(args, 'execution_id', max: 128),
          requireString(args, 'input', max: 8192, allowEmpty: true),
          inputRequestId: requireInt(args, 'input_request_id'),
        )),
      ),
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_execution_stop',
          description:
              'Stop an execution_id only while it is the current run. Other runs are not stopped.',
          permission: McpPermission.runScripts,
          inputSchema: _objectSchema(
              {'execution_id': _stringProp('Execution ID')}, ['execution_id']),
        ),
        handler: (_, args) async => McpToolResult.success(await execution
            .stop(requireString(args, 'execution_id', max: 128))),
      ),
      // ── 6.1 基础查询 ──
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_app_get_status',
          description:
              'Get app status: version, active Python runtime (chaquopy or linux_like), Debian installation state, and MCP service information.',
          permission: McpPermission.readScripts,
          inputSchema: _objectSchema(const {}),
        ),
        handler: (context, args) async {
          final status = await _facade.getAppStatus();
          return McpToolResult.success({
            ...status.toMap(),
            'session': {
              'id': context.sessionId,
              'client': '${context.clientName} ${context.clientVersion}'.trim(),
            },
          });
        },
      ),
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_script_list',
          description:
              "List the app's Python scripts. Regular scripts are included; project files are not.",
          permission: McpPermission.readScripts,
          inputSchema: _objectSchema({
            'query':
                _stringProp('Filter by name, case-insensitive', nullable: true),
            'group_id': _intProp('Filter by group ID', nullable: true),
            'limit': _intProp('Page size; default 100, maximum 500',
                minimum: 1, maximum: 500),
            'cursor': _stringProp('next_cursor returned by the previous page',
                nullable: true),
          }),
        ),
        handler: (context, args) async {
          final page = await _facade.listScripts(
            query: optionalString(args, 'query', max: 200),
            groupId: optionalInt(args, 'group_id'),
            limit: optionalInt(args, 'limit') ?? 100,
            cursor: optionalString(args, 'cursor', max: 256),
          );
          return McpToolResult.success(page.toMap());
        },
      ),
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_script_read',
          description:
              'Read the text content of a regular script. Content above the limit returns FILE_TOO_LARGE.',
          permission: McpPermission.readScripts,
          inputSchema: _objectSchema({
            'name': _stringProp('Script name, such as hello.py'),
            'max_chars': _intProp('Maximum characters per call; default 200000',
                minimum: 1, maximum: 200000),
          }, [
            'name'
          ]),
        ),
        handler: (context, args) async {
          final content = await _facade.readScript(
            requireString(args, 'name', max: 120),
            maxChars: optionalInt(args, 'max_chars') ?? 200000,
          );
          return McpToolResult.success(content.toMap());
        },
      ),
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_group_list',
          description:
              'List regular groups and project groups, including ID, name, project flag, project_key, and main file path.',
          permission: McpPermission.readScripts,
          inputSchema: _objectSchema(const {}),
        ),
        handler: (context, args) async {
          final groups = await _facade.listGroups();
          return McpToolResult.success({
            'groups': groups.map((group) => group.toMap()).toList(),
          });
        },
      ),

      // ── 6.2 脚本和项目（读）──
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_project_list_files',
          description: 'List files and directories in a project.',
          permission: McpPermission.readProjects,
          inputSchema: _objectSchema({
            'project_key': _stringProp('Project key (see pyrunner_group_list)'),
            'limit': _intProp('Page size; default 200, maximum 500',
                minimum: 1, maximum: 500),
            'cursor': _stringProp('next_cursor returned by the previous page',
                nullable: true),
          }, [
            'project_key'
          ]),
        ),
        handler: (context, args) async {
          final page = await _facade.listProjectFiles(
            requireString(args, 'project_key', max: 100),
            limit: optionalInt(args, 'limit') ?? 200,
            cursor: optionalString(args, 'cursor', max: 256),
          );
          return McpToolResult.success(page.toMap());
        },
      ),
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_project_read_file',
          description:
              'Read a project file using a relative path. Absolute paths and .. are rejected.',
          permission: McpPermission.readProjects,
          inputSchema: _objectSchema({
            'project_key': _stringProp('Project key'),
            'path': _stringProp(
                'Project-relative path, such as main.py or lib/client.py'),
            'max_chars': _intProp('Maximum characters per call; default 200000',
                minimum: 1, maximum: 200000),
          }, [
            'project_key',
            'path'
          ]),
        ),
        handler: (context, args) async {
          final content = await _facade.readProjectFile(
            requireString(args, 'project_key', max: 100),
            requireString(args, 'path', max: 1024),
            maxChars: optionalInt(args, 'max_chars') ?? 200000,
          );
          return McpToolResult.success(content.toMap());
        },
      ),

      // ── 6.3 网络调试数据 ──
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_network_list_records',
          description:
              "Query captured network request summaries. Headers, cookies, authorization data, and request/response bodies are omitted by default.",
          permission: McpPermission.readNetwork,
          inputSchema: _objectSchema({
            'domain': _stringProp('Filter by domain', nullable: true),
            'method': _stringProp('Filter by HTTP method, such as GET',
                nullable: true),
            'status_class': {
              'type': 'string',
              'description':
                  'Filter by status class: 1xx/2xx/3xx/4xx/5xx/error',
              'enum': ['1xx', '2xx', '3xx', '4xx', '5xx', 'error'],
            },
            'since': _stringProp('Start time (ISO8601)', nullable: true),
            'until': _stringProp('End time (ISO8601)', nullable: true),
            'limit': _intProp('Page size; default 50, maximum 500',
                minimum: 1, maximum: 500),
            'cursor': _stringProp('next_cursor returned by the previous page',
                nullable: true),
          }),
        ),
        handler: (context, args) async {
          final page = await _facade.listNetworkRecords(
            McpNetworkQuery(
              domain: optionalString(args, 'domain', max: 200),
              method: optionalString(args, 'method', max: 16),
              statusClass: optionalString(args, 'status_class', max: 8),
              since: optionalIsoDate(args, 'since'),
              until: optionalIsoDate(args, 'until'),
            ),
            limit: optionalInt(args, 'limit') ?? 50,
            cursor: optionalString(args, 'cursor', max: 256),
          );
          return McpToolResult.success(page.toMap());
        },
      ),
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_network_get_record',
          description:
              'Read one network record in detail. Sensitive headers are redacted; include_body=true returns bodies within the size budget when available.',
          permission: McpPermission.readNetwork,
          inputSchema: _objectSchema({
            'id': _stringProp('Record ID (see pyrunner_network_list_records)'),
            'include_body':
                _boolProp('Include request/response bodies (default false)'),
          }, [
            'id'
          ]),
        ),
        handler: (context, args) async {
          final record = await _facade.getNetworkRecord(
            requireString(args, 'id', max: 128),
            includeBody: optionalBool(args, 'include_body'),
          );
          return McpToolResult.success(record.toDetailMap());
        },
      ),

      // ── 6.4 Python 库 ──
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_package_list',
          description:
              "List Python packages installed in the current runtime. backend must be active or match the app's current runtime; MCP never switches runtimes.",
          permission: McpPermission.readPackages,
          inputSchema: _objectSchema({
            'backend': {
              'type': 'string',
              'description': 'active / chaquopy / linux_like',
              'enum': ['active', 'chaquopy', 'linux_like'],
            },
            'query': _stringProp('Filter by package name', nullable: true),
            'limit': _intProp('Page size; default 100, maximum 500',
                minimum: 1, maximum: 500),
            'cursor': _stringProp('next_cursor returned by the previous page',
                nullable: true),
          }),
        ),
        handler: (context, args) async {
          final page = await _facade.listPackages(
            backend: optionalString(args, 'backend', max: 20),
            query: optionalString(args, 'query', max: 200),
            limit: optionalInt(args, 'limit') ?? 100,
            cursor: optionalString(args, 'cursor', max: 256),
          );
          return McpToolResult.success(page.toMap());
        },
      ),

      // ── 6.5 可访问文件系统（只读）──
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_fs_list_directory',
          description:
              'List an absolute directory currently accessible to the app, including / where Android sandbox rules permit. Read-only.',
          permission: McpPermission.readFilesystem,
          inputSchema: _objectSchema({
            'path': _stringProp(
                'Absolute path, such as / or /storage/emulated/0/Download'),
            'limit': _intProp('Page size; default 100, maximum 500',
                minimum: 1, maximum: 500),
            'cursor': _stringProp('next_cursor returned by the previous page',
                nullable: true),
            'include_hidden': _boolProp('Include hidden files (default false)'),
          }, [
            'path'
          ]),
        ),
        handler: (context, args) async {
          final path = requireString(args, 'path', max: 1024);
          final listing = await _facade.listAccessibleDirectory(
            path: path,
            limit: optionalInt(args, 'limit') ?? 100,
            cursor: optionalString(args, 'cursor', max: 256),
            includeHidden: optionalBool(args, 'include_hidden'),
          );
          return McpToolResult.success({
            'directory': path,
            // 权限受限由 Facade 显式判定；空目录/末页不为受限（P2 评审修正）。
            'permission_limited': !listing.accessible,
            ...listing.page.toMap(),
          });
        },
      ),
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_fs_read_file',
          description:
              'Read a file at an app-accessible path. Text is decoded as UTF-8, one call returns at most 256 KiB, and binary files return a metadata-only error.',
          permission: McpPermission.readFilesystem,
          inputSchema: _objectSchema({
            'path': _stringProp('Absolute path; content:// is unsupported'),
            'max_bytes': _intProp('Maximum bytes per call; default 262144',
                minimum: 1, maximum: 262144),
          }, [
            'path'
          ]),
        ),
        handler: (context, args) async {
          final path = requireString(args, 'path', max: 1024);
          final content = await _facade.readAccessibleFile(
            path: path,
            maxBytes: optionalInt(args, 'max_bytes') ?? 256 * 1024,
          );
          if (content.isBinary) {
            throw McpToolException(
              McpErrorCodes.binaryFileUnsupported,
              'Binary file content is unsupported; only metadata is returned',
              false,
              {'path': path, 'size': content.size},
            );
          }
          return McpToolResult.success({
            'path': path,
            ...content.toMap(),
          });
        },
      ),

      // ── 写操作（授权后直接执行）──
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_script_create',
          description:
              'Create a regular Python script, optionally in a group. Existing scripts fail without overwrite. Requires write_scripts permission and runs directly after authorization.',
          permission: McpPermission.writeScripts,
          inputSchema: _objectSchema({
            'name': _stringProp('Script name, such as hello.py'),
            'content':
                _stringProp('Initial content (default empty)', nullable: true),
            'group_id':
                _intProp('Destination group ID (optional)', nullable: true),
          }, [
            'name'
          ]),
        ),
        summarize: (args) {
          final content = (args['content'] as String?) ?? '';
          final group = args['group_id'];
          return 'Create script ${args['name']} (${content.length} characters'
              '${group == null ? '' : ', group $group'})';
        },
        handler: (context, args) async {
          final summary = await _facade.createScript(
            name: requireString(args, 'name', max: 120),
            content:
                optionalString(args, 'content', max: 2 * 1024 * 1024) ?? '',
            groupId: optionalInt(args, 'group_id'),
          );
          return McpToolResult.success(summary.toMap());
        },
      ),
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_script_save',
          description:
              'Fully overwrite a regular script. Pass modified_at from a read as expected_modified_at to avoid overwriting newer user changes. Requires write_scripts permission and runs directly after authorization.',
          permission: McpPermission.writeScripts,
          inputSchema: _objectSchema({
            'name': _stringProp('Script name'),
            'content': _stringProp('Complete new content'),
            'expected_modified_at': _intProp(
                'modified_at in milliseconds from the read; mismatched values are rejected',
                nullable: true),
          }, [
            'name',
            'content'
          ]),
        ),
        summarize: (args) {
          final content = args['content'] as String? ?? '';
          return 'Overwrite script ${args['name']} (${content.length} characters)';
        },
        handler: (context, args) async {
          final summary = await _facade.saveScript(
            name: requireString(args, 'name', max: 120),
            content: requireString(args, 'content',
                max: 2 * 1024 * 1024, allowEmpty: true),
            expectedModifiedAt: optionalInt(args, 'expected_modified_at'),
          );
          return McpToolResult.success(summary.toMap());
        },
      ),
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_project_group_create',
          description:
              'Create a project group with its project directory, main program, and group record; failures roll back automatically. Requires write_projects permission and runs directly after authorization.',
          permission: McpPermission.writeProjects,
          inputSchema: _objectSchema({
            'name': _stringProp('Group display name'),
            'project_key': _stringProp(
                'Project key; generated when empty, letters/digits/-/_',
                nullable: true),
            'main_file_path': _stringProp(
                'Main program relative path; default main.py, must end with .py',
                nullable: true),
            'main_file_content':
                _stringProp('Initial main program content', nullable: true),
          }, [
            'name'
          ]),
        ),
        summarize: (args) {
          final main = (args['main_file_path'] as String?) ?? 'main.py';
          final content = args['main_file_content'] as String?;
          return 'Create project group ${args['name']} (main program $main'
              '${content == null ? '' : ', ${content.length} characters'})';
        },
        handler: (context, args) async {
          final summary = await _facade.createProjectGroup(
            name: requireString(args, 'name', max: 100),
            projectKey: optionalString(args, 'project_key', max: 100),
            mainFilePath: optionalString(args, 'main_file_path', max: 1024),
            mainFileContent:
                optionalString(args, 'main_file_content', max: 2 * 1024 * 1024),
          );
          return McpToolResult.success(summary.toMap());
        },
      ),
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_project_save_file',
          description:
              'Save a project file using a project-root-relative path; parent directories may be created. Prefer expected_modified_at to detect conflicts. Requires write_projects permission and runs directly after authorization.',
          permission: McpPermission.writeProjects,
          inputSchema: _objectSchema({
            'project_key': _stringProp('Project key'),
            'path': _stringProp('Project-relative path, such as lib/client.py'),
            'content': _stringProp('Complete new content'),
            'expected_modified_at': _intProp(
                'modified_at in milliseconds from the read; mismatched values are rejected',
                nullable: true),
          }, [
            'project_key',
            'path',
            'content'
          ]),
        ),
        summarize: (args) {
          final content = args['content'] as String? ?? '';
          return 'Write project file ${args['project_key']}/${args['path']}'
              ' (${content.length} characters)';
        },
        handler: (context, args) async {
          final summary = await _facade.saveProjectFile(
            projectKey: requireString(args, 'project_key', max: 100),
            path: requireString(args, 'path', max: 1024),
            content: requireString(args, 'content',
                max: 2 * 1024 * 1024, allowEmpty: true),
            expectedModifiedAt: optionalInt(args, 'expected_modified_at'),
          );
          return McpToolResult.success(summary.toMap());
        },
      ),
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_package_install',
          description:
              "Install or upgrade a Python package using the app's current runtime and default PyPI source. One installation may run at a time. Requires install_packages permission, runs directly after authorization, returns operation_id immediately, and success is not implied; poll pyrunner_operation_get_status.",
          permission: McpPermission.installPackages,
          inputSchema: _objectSchema({
            'package_name': _stringProp('Package name, such as requests'),
            'version': _stringProp('Version, optional, such as 2.32.3',
                nullable: true),
            'index_url': _stringProp(
                'Custom PyPI index, http/https, for this installation only',
                nullable: true),
            'backend': {
              'type': 'string',
              'description': 'active / chaquopy / linux_like',
              'enum': ['active', 'chaquopy', 'linux_like'],
            },
          }, [
            'package_name'
          ]),
        ),
        timeout: const Duration(seconds: 30),
        summarize: (args) {
          final version = args['version'] as String?;
          final index = args['index_url'] as String?;
          // 确认摘要与审计只显示源的域名，不携带完整地址（P1 评审修正）。
          final host = index == null ? null : Uri.tryParse(index)?.host;
          return 'Install Python package ${args['package_name']}'
              '${version == null ? '' : '@$version'}'
              '${host == null ? '' : ' (index: $host)'}';
        },
        handler: (context, args) async {
          final result = await _facade.installPackage(
            packageName: requireString(args, 'package_name', max: 100),
            version: optionalString(args, 'version', max: 64),
            indexUrl: optionalString(args, 'index_url', max: 2048),
            backend: optionalString(args, 'backend', max: 20),
          );
          return McpToolResult.success(result.toMap());
        },
      ),

      // ── 长任务状态（计划 §10.2：SDK 不支持 progress 通知时的替代方案）──
      McpToolEntry(
        definition: McpToolDefinition(
          name: 'pyrunner_operation_get_status',
          description:
              'Query the status and latest progress of long-running tasks such as pyrunner_package_install using the returned operation_id.',
          permission: McpPermission.readPackages,
          inputSchema: _objectSchema({
            'id': _stringProp(
                'Operation ID returned by pyrunner_package_install'),
          }, [
            'id'
          ]),
        ),
        handler: (context, args) async {
          final id = requireString(args, 'id', max: 64);
          final operation = _operations?.find(id);
          if (operation == null) {
            throw McpToolException(
              McpErrorCodes.invalidArgument,
              'Operation does not exist or has expired: $id',
              false,
              {'id': id},
            );
          }
          return McpToolResult.success(operation.toMap());
        },
      ),
    ];
  }
}
