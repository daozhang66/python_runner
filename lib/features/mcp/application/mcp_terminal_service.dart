import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../ssh/application/log/log_record.dart';
import '../../ssh/application/log/terminal_logs.dart';
import '../../ssh/application/terminal/session_manager.dart';
import '../../ssh/application/terminal/terminal_session.dart';
import '../domain/mcp_error_codes.dart';
import 'mcp_confirmation_service.dart';

/// A note the AI left for the person, and the answer it may be waiting for.
class McpUserMessage {
  McpUserMessage({
    required this.id,
    required this.text,
    required this.clientLabel,
  }) : createdAt = DateTime.now();

  final int id;
  final String text;
  final String clientLabel;
  final DateTime createdAt;
  String? reply;
  bool dismissed = false;

  bool get isOpen => reply == null && !dismissed;
}

/// What an AI client may do with the terminals the person has open.
///
/// The AI works with the very same sessions as the person. Every command is
/// confirmed one by one, everything it does lands in the AI operations log,
/// and the notes exchanged with the person land in the conversation log.
class McpTerminalService extends ChangeNotifier {
  McpTerminalService({
    required McpConfirmationService confirmations,
    TerminalSessionManager? sessions,
    TerminalLogs? logs,
  })  : _confirmations = confirmations,
        _sessions = sessions ?? TerminalSessionManager.instance,
        _logs = logs ?? TerminalLogs.instance;

  static const int maxCommandChars = 4096;
  static const int maxOpenMessages = 20;

  /// Anything but a tab is refused: a command is exactly one line.
  static final RegExp _badChars = RegExp(r'[\x00-\x08\x0a-\x1f\x7f]');

  final McpConfirmationService _confirmations;
  final TerminalSessionManager _sessions;
  final TerminalLogs _logs;

  final List<McpUserMessage> _messages = <McpUserMessage>[];
  int _messageSeq = 0;

  /// Notes the person has not answered or dismissed yet.
  List<McpUserMessage> get openMessages =>
      _messages.where((m) => m.isOpen).toList(growable: false);

  // ── logging ──

  void _op(
    String kind,
    String summary, {
    String sid = '',
    int importance = 1,
    String? detail,
    Map<String, Object?>? extra,
  }) {
    _logs.add(
      LogChannel.operations,
      LogRecord.now(
        k: kind,
        s: summary,
        sid: sid,
        a: 'ai',
        i: importance,
        d: detail,
        x: extra,
      ),
    );
  }

  void _conversation(int id, String who, String text) {
    _logs.add(
      LogChannel.conversation,
      LogRecord.now(
        k: 'msg',
        s: text,
        sid: 'mcp-$id',
        a: who,
        i: 0,
        d: text.length > 300 ? text : null,
      ),
    );
  }

  static String _clip(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}…';

  // ── sessions ──

  TerminalSession _session(String id) {
    final session = _sessions.byId(id);
    if (session == null) {
      throw McpToolException(
        McpErrorCodes.invalidArgument,
        'Unknown terminal session: $id. Call pyrunner_terminal_list for the open sessions',
        false,
        {'session_id': id},
      );
    }
    return session;
  }

  void _requireAlive(TerminalSession session) {
    if (session.isAlive) return;
    throw McpToolException(
      'TERMINAL_NOT_RUNNING',
      'Terminal ${session.id} is ${session.status.name}; ask the user to restart it',
      false,
      {'session_id': session.id, 'status': session.status.name},
    );
  }

  Map<String, dynamic> listSessions() => <String, dynamic>{
        'sessions': [for (final s in _sessions.sessions) s.describe()],
      };

  /// Types [command] and Enter into a session after the person approved it.
  Future<Map<String, dynamic>> send({
    required String sessionId,
    required String command,
    required String clientLabel,
    int waitSeconds = 2,
  }) async {
    if (command.length > maxCommandChars || _badChars.hasMatch(command)) {
      throw McpToolException(
        McpErrorCodes.invalidArgument,
        'command must be one line of at most $maxCommandChars characters without control characters',
      );
    }
    final session = _session(sessionId);
    _requireAlive(session);
    // A line typed at a password prompt is never shown or recorded.
    session.logger.flushOutput();
    final hidden = session.logger.expectingSecret;
    final shown = hidden
        ? '<hidden input: the terminal is asking for a password>'
        : _clip(command.isEmpty ? '<Enter>' : command, 300);
    final decision = await _confirmations.request(
      toolName: 'pyrunner_terminal_send',
      summary: '${session.title} (${session.id})\n$shown',
      clientLabel: clientLabel,
      singleUse: true,
    );
    final denied = McpConfirmationService.toException(decision);
    if (denied != null) {
      _op(
        'denied',
        'Command refused: $shown',
        sid: session.id,
        importance: 0,
        extra: <String, Object?>{'decision': decision.name},
      );
      throw denied;
    }
    _requireAlive(session);
    final from = session.ring.end;
    _op(
      'cmd',
      shown,
      sid: session.id,
      importance: 0,
      detail: hidden || command.length <= 300 ? null : command,
      extra: const <String, Object?>{'approved': true},
    );
    session.sendText('$command\r', actor: 'ai');
    final output = await _settle(session, from, waitSeconds);
    return <String, dynamic>{'sent': true, ...output};
  }

  /// Waits until the output stops growing (or the time is up), then reads it.
  Future<Map<String, dynamic>> _settle(
    TerminalSession session,
    int from,
    int waitSeconds,
  ) async {
    final limit = DateTime.now().add(
      Duration(seconds: waitSeconds.clamp(0, 30).toInt()),
    );
    var last = session.ring.end;
    var quietSince = DateTime.now();
    while (DateTime.now().isBefore(limit)) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final now = session.ring.end;
      if (now != last) {
        last = now;
        quietSince = DateTime.now();
      } else if (now > from &&
          DateTime.now().difference(quietSince) >
              const Duration(milliseconds: 500)) {
        break;
      }
    }
    return read(session.id, cursor: from);
  }

  /// Plain-text output of a session. Without [cursor] the most recent output.
  Map<String, dynamic> read(
    String sessionId, {
    int? cursor,
    int maxChars = 20000,
  }) {
    if (maxChars < 1 || maxChars > 64000 || (cursor != null && cursor < 0)) {
      throw McpToolException(
        McpErrorCodes.invalidArgument,
        'cursor must be 0 or more and max_chars between 1 and 64000',
      );
    }
    final session = _session(sessionId);
    final end = session.ring.end;
    final from = cursor ?? (end - maxChars < 0 ? 0 : end - maxChars);
    final slice = session.ring.read(from, maxChars: maxChars);
    _op(
      'read',
      'Read ${slice.text.length} characters',
      sid: session.id,
      importance: 2,
      detail: slice.text.isEmpty ? null : slice.text,
    );
    return <String, dynamic>{
      'session_id': session.id,
      'status': session.status.name,
      'text': slice.text,
      'next_cursor': slice.next,
      'dropped': slice.dropped,
      'has_more': slice.next < end,
    };
  }

  /// Ctrl+C. Harmless, so it needs no approval.
  Map<String, dynamic> interrupt(String sessionId) {
    final session = _session(sessionId);
    _requireAlive(session);
    _op('cmd', '^C', sid: session.id, importance: 0);
    session.sendText('\x03', actor: 'ai');
    return <String, dynamic>{'interrupted': true, 'session_id': session.id};
  }

  // ── notes between the AI and the person ──

  McpUserMessage? _find(int id) {
    for (final message in _messages) {
      if (message.id == id) return message;
    }
    return null;
  }

  /// Leaves a note that is shown to the person right away.
  Map<String, dynamic> tellUser(String text, String clientLabel) {
    if (openMessages.length >= maxOpenMessages) {
      throw McpToolException(
        'TOO_MANY_MESSAGES',
        'The user has $maxOpenMessages unanswered messages; wait for a reply first',
        true,
      );
    }
    final message = McpUserMessage(
      id: ++_messageSeq,
      text: text,
      clientLabel: clientLabel,
    );
    _messages.add(message);
    while (_messages.length > 50) {
      final index = _messages.indexWhere((m) => !m.isOpen);
      if (index < 0) break;
      _messages.removeAt(index);
    }
    _conversation(message.id, 'ai', text);
    _op(
      'message',
      _clip(text, 120),
      importance: 0,
      detail: text.length > 120 ? text : null,
    );
    notifyListeners();
    return <String, dynamic>{
      'message_id': message.id,
      'delivered': true,
      'hint': 'Call pyrunner_terminal_wait_reply to wait for the answer',
    };
  }

  /// The person's answer (from the dialog).
  void reply(int id, String text) {
    final message = _find(id);
    if (message == null || !message.isOpen) return;
    message.reply = text;
    _conversation(id, 'human', text);
    notifyListeners();
  }

  /// The person closed the note without answering.
  void dismiss(int id) {
    final message = _find(id);
    if (message == null || !message.isOpen) return;
    message.dismissed = true;
    _conversation(id, 'human', '(dismissed)');
    notifyListeners();
  }

  /// Waits for the person's answer to [messageId] (default: the newest note).
  Future<Map<String, dynamic>> waitReply({
    int? messageId,
    int timeoutSeconds = 60,
  }) async {
    final message = messageId == null
        ? (_messages.isEmpty ? null : _messages.last)
        : _find(messageId);
    if (message == null) {
      throw McpToolException(
        McpErrorCodes.invalidArgument,
        'No such message; send one with pyrunner_terminal_tell_user first',
      );
    }
    final limit = DateTime.now().add(
      Duration(seconds: timeoutSeconds.clamp(1, 100).toInt()),
    );
    while (message.isOpen && DateTime.now().isBefore(limit)) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    final answer = message.reply;
    _op(
      'reply',
      answer != null
          ? 'The user replied'
          : message.dismissed
              ? 'The user dismissed the message'
              : 'No reply yet',
      importance: 1,
      detail: answer,
    );
    return <String, dynamic>{
      'message_id': message.id,
      'replied': answer != null,
      if (answer != null) 'reply': answer,
      'dismissed': message.dismissed,
      'waiting': message.isOpen,
    };
  }

  /// The service stopped: notes nobody answered are closed.
  void reset() {
    var changed = false;
    for (final message in _messages) {
      if (message.isOpen) {
        message.dismissed = true;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }
}
