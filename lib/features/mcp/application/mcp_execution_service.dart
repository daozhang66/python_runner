import 'dart:async';

import '../../../models/execution_state.dart';
import '../../../models/script_group.dart';
import '../../../providers/execution_provider.dart';
import '../../../services/project_path_validator.dart';
import '../../../services/script_name_validator.dart';
import '../../scripts/application/script_repository.dart';
import '../domain/mcp_error_codes.dart';

/// Shares the terminal's execution owner; never creates another runtime.
class McpExecutionService {
  McpExecutionService(
      {required this.execution,
      required this.scripts,
      required this.recordRun,
      this.recordProjectRun});

  final ExecutionProvider Function() execution;
  final ScriptRepository scripts;
  final Future<void> Function(String name) recordRun;
  final Future<void> Function(ScriptGroup group)? recordProjectRun;

  Future<Map<String, dynamic>> run(String name) async {
    final String safeName;
    try {
      safeName = ScriptNameValidator.normalize(name);
    } on FormatException {
      throw McpToolException(
          McpErrorCodes.invalidArgument, 'Invalid script name');
    }
    if (!(await scripts.listScriptFiles()).contains(safeName)) {
      throw McpToolException(
          McpErrorCodes.scriptNotFound, 'Script not found: $safeName');
    }
    final owner = execution();
    if (owner.isRunning) {
      throw McpToolException('EXECUTION_BUSY',
          'A script is already running; the current execution is not replaced');
    }
    // executeScript reserves executionId and running state before its first
    // await. Concurrent MCP calls therefore cannot replace this run.
    final starting = owner.executeScript(safeName);
    final id = owner.state.executionId;
    unawaited(starting.catchError((Object error, StackTrace stack) {
      // The provider records runtime start failures in its terminal history.
    }));
    if (id == null) {
      throw McpToolException(
          'EXECUTION_START_FAILED', 'Unable to create an execution session');
    }
    // Count accepted launches, like the home/editor actions, not output polls.
    // Reserve execution first so concurrent calls rejected as busy aren't counted.
    await recordRun(safeName);
    return {'execution_id': id, 'script_name': safeName, 'status': 'starting'};
  }

  Future<Map<String, dynamic>> runProject(String projectKey) async {
    final String safeKey;
    try {
      safeKey = ProjectPathValidator.normalizeProjectKey(projectKey);
    } on FormatException {
      throw McpToolException(
          McpErrorCodes.projectPathInvalid, 'Invalid project key: $projectKey');
    }

    final groups = await scripts.getAllGroups();
    ScriptGroup? group;
    for (final candidate in groups) {
      if (candidate.isProject && candidate.projectKey == safeKey) {
        group = candidate;
        break;
      }
    }
    if (group == null) {
      throw McpToolException(
        McpErrorCodes.projectNotFound,
        'Project not found: $safeKey',
        false,
        {'project_key': safeKey},
      );
    }
    if ((group.mainFilePath ?? '').trim().isEmpty) {
      throw McpToolException(
        McpErrorCodes.projectPathInvalid,
        'The project has no main program; select main.py on the project page first',
        false,
        {'project_key': safeKey},
      );
    }

    final owner = execution();
    if (owner.isRunning) {
      throw McpToolException('EXECUTION_BUSY',
          'A script is already running; the current execution is not replaced');
    }
    final starting = owner.executeScriptProject(group);
    final id = owner.state.executionId;
    unawaited(starting.catchError((Object error, StackTrace stack) {
      // executeScriptProject records launch failures in its terminal history.
    }));
    if (id == null || owner.state.status != ExecutionStatus.running) {
      throw McpToolException('EXECUTION_START_FAILED',
          'Unable to create a project execution session');
    }
    await (recordProjectRun?.call(group) ?? Future<void>.value());
    return {
      'execution_id': id,
      'script_name': group.name.trim().isEmpty ? safeKey : group.name.trim(),
      'project_key': safeKey,
      'main_file_path': group.mainFilePath,
      'status': 'starting',
    };
  }

  Map<String, dynamic> output(String id, {int maxChars = 32000}) {
    if (id.isEmpty || id.length > 128 || maxChars < 1 || maxChars > 64000) {
      throw McpToolException(
          McpErrorCodes.invalidArgument, 'Invalid execution ID or output size');
    }
    final owner = execution();
    final current = owner.state.executionId == id;
    final record =
        owner.logHistory.where((r) => r.executionId == id).firstOrNull;
    if (record == null && !current) {
      throw McpToolException(
          'EXECUTION_NOT_FOUND', 'Execution not found or history was cleared');
    }
    final status = current ? owner.state.status : record!.status;
    final logs = record?.logs ?? const [];
    var remaining = maxChars;
    final entries = <Map<String, dynamic>>[];
    var truncated = (record?.droppedLogCount ?? 0) > 0;
    for (var i = logs.length - 1; i >= 0; i--) {
      if (remaining == 0) {
        truncated = true;
        break;
      }
      final entry = logs[i];
      var text = entry.content;
      if (text.length > remaining) {
        var start = text.length - remaining;
        // Avoid splitting a UTF-16 surrogate pair at the retained boundary.
        if (start > 0 &&
            text.codeUnitAt(start) >= 0xdc00 &&
            text.codeUnitAt(start) <= 0xdfff) {
          start++;
        }
        text = text.substring(start);
        truncated = true;
      }
      remaining -= text.length;
      entries.add({
        'type': entry.type.name,
        'content': text,
        'timestamp': entry.timestamp.toUtc().toIso8601String()
      });
    }
    return {
      'execution_id': id,
      'script_name': record?.scriptName ?? owner.currentScriptName,
      'status': record == null ? 'starting' : status.name,
      'finished': status != ExecutionStatus.running &&
          status != ExecutionStatus.stopping,
      'exit_code': current ? owner.state.exitCode : record?.exitCode,
      'waiting_for_input': current && owner.waitingForInput,
      if (current && owner.waitingForInput) ...{
        'input_request_id': owner.inputRequestRevision,
        'input_prompt': owner.currentInputPrompt.length > maxChars
            ? owner.currentInputPrompt.substring(0, maxChars)
            : owner.currentInputPrompt,
        'input_prompt_truncated': owner.currentInputPrompt.length > maxChars,
      },
      'entries': entries.reversed.toList(),
      'truncated': truncated,
      'snapshot': true,
    };
  }

  Future<Map<String, dynamic>> sendInput(String id, String input,
      {required int inputRequestId}) async {
    if (input.length > 8192 ||
        input.contains('\n') ||
        input.contains('\r') ||
        input.contains('\u0000') ||
        inputRequestId < 1) {
      throw McpToolException(McpErrorCodes.invalidArgument,
          'input must be one line, may be empty, and contain at most 8192 characters; the input request ID must be valid');
    }
    final owner = execution();
    output(id, maxChars: 1);
    if (owner.state.executionId != id ||
        owner.state.status != ExecutionStatus.running ||
        !owner.waitingForInput ||
        owner.inputRequestRevision != inputRequestId) {
      throw McpToolException('INPUT_REQUEST_STALE',
          'The current execution is not waiting for this input; read pyrunner_execution_output again');
    }
    try {
      await owner.sendStdin(input,
          expectedExecutionId: id,
          expectedInputRevision: inputRequestId,
          propagateErrors: true);
    } catch (_) {
      throw McpToolException('STDIN_SEND_FAILED',
          'Failed to send input; check the latest run state before retrying');
    }
    return {'input_sent': true, ...output(id)};
  }

  Future<Map<String, dynamic>> stop(String id) async {
    final owner = execution();
    output(id, maxChars: 1); // Validate the ID without affecting another run.
    if (owner.state.executionId == id && owner.isRunning) {
      await owner.stopExecution();
    }
    return output(id);
  }
}
