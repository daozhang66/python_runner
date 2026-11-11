import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ssh/application/log/log_record.dart';
import '../../ssh/application/log/terminal_logs.dart';
import '../../ssh/application/terminal/session_manager.dart';
import '../../ssh/application/terminal/terminal_locale.dart';
import '../../ssh/application/terminal/terminal_session.dart';
import '../domain/mcp_error_codes.dart';
import 'mcp_confirmation_service.dart';

/// One line of the conversation between the person and the AI.
class AiChatEntry {
  const AiChatEntry({
    required this.id,
    required this.fromAi,
    required this.text,
    required this.time,
    this.system = false,
  });

  /// Grows with every entry, from any side, so "after message N" means
  /// "said after the AI's message N".
  final int id;
  final bool fromAi;
  final String text;
  final DateTime time;

  /// A notice from the app itself (for example "a terminal asks for a
  /// password"), neither the AI nor the person talking.
  final bool system;

  bool get fromUser => !fromAi && !system;
}

/// Something the person has to do in the app: type into a terminal that asks
/// for a password, or answer a script's `input()`.
class AiAttention {
  AiAttention({required this.kind, required this.target, required this.text})
      : time = DateTime.now();

  /// `script` or `terminal`.
  final String kind;

  /// Script name or terminal session id.
  final String target;
  final String text;
  final DateTime time;

  /// Set once the app has taken the person there, so it does not do it twice.
  bool opened = false;
}

/// What an AI client may do with terminals, and the conversation it has with
/// the person while doing it.
///
/// The AI works with the very same sessions as the person. There is no popup
/// per command (an AI that may run scripts can reach the same things anyway);
/// the real controls are the `terminal` permission, the pause switch, the
/// optional "confirm each command" setting, and a complete log of everything
/// in the AI operations and conversation logs.
///
/// When a terminal asks for a password the AI must not guess it: the person
/// is told (chat notice, button badge, and the app opens the terminal when
/// they switch back to it) and the AI waits for the output to move on.
class McpTerminalService extends ChangeNotifier {
  McpTerminalService({
    required McpConfirmationService confirmations,
    TerminalSessionManager? sessions,
    TerminalLogs? logs,
  })  : _confirmations = confirmations,
        _sessions = sessions ?? TerminalSessionManager.instance,
        _logs = logs ?? TerminalLogs.instance;

  static const String confirmEachPrefsKey = 'mcp.terminal.confirm_each';
  static const int maxCommandChars = 4096;
  static const int maxThread = 200;

  /// Anything but a tab is refused: a command is exactly one line.
  static final RegExp _badChars = RegExp(r'[\x00-\x08\x0a-\x1f\x7f]');

  final McpConfirmationService _confirmations;
  final TerminalSessionManager _sessions;
  final TerminalLogs _logs;

  final List<AiChatEntry> _thread = <AiChatEntry>[];
  final Map<String, AiAttention> _attention = <String, AiAttention>{};
  final Set<String> _aiOpened = <String>{};
  int _seq = 0;
  int _seenUpTo = 0;
  bool _paused = false;
  bool _confirmEach = false;
  bool _settingsLoaded = false;

  // ── state shown in the chat sheet ──

  List<AiChatEntry> get thread => List<AiChatEntry>.unmodifiable(_thread);

  /// Messages and notices the person has not looked at yet.
  int get unreadCount =>
      _thread.where((e) => !e.fromUser && e.id > _seenUpTo).length;

  /// What waits for the person right now.
  List<AiAttention> get attention =>
      List<AiAttention>.unmodifiable(_attention.values);

  /// While paused every terminal tool is refused (the chat keeps working).
  bool get paused => _paused;

  /// Optional: ask the person before each command. Off by default.
  bool get confirmEach => _confirmEach;

  Future<void> loadSettings() async {
    if (_settingsLoaded) return;
    _settingsLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getBool(confirmEachPrefsKey) ?? false;
      if (value != _confirmEach) {
        _confirmEach = value;
        notifyListeners();
      }
    } catch (_) {
      // Keep the default (off).
    }
  }

  Future<void> setConfirmEach(bool value) async {
    _settingsLoaded = true;
    _confirmEach = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(confirmEachPrefsKey, value);
    } catch (_) {
      // The choice still holds until the app is closed.
    }
  }

  void setPaused(bool value) {
    if (_paused == value) return;
    _paused = value;
    _op(
      'control',
      value ? 'The user paused AI terminal access' : 'The user resumed AI terminal access',
      importance: 0,
    );
    notifyListeners();
  }

  void markSeen() {
    if (_seenUpTo >= _seq) return;
    _seenUpTo = _seq;
    notifyListeners();
  }

  void clearThread() {
    _thread.clear();
    notifyListeners();
  }

  /// The service stopped. The chat and the sessions stay as they are.
  void reset() {}

  // ── things the person has to do ──

  /// Something waits for the person (once per [kind] and [target]); they get a
  /// notice in the chat and the app takes them there when they come back.
  void raiseAttention(String kind, String target, String text) {
    final key = '$kind:$target';
    if (_attention.containsKey(key)) return;
    _attention[key] = AiAttention(kind: kind, target: target, text: text);
    _op('attention', text, sid: kind == 'terminal' ? target : '', importance: 0);
    _add(false, text, system: true);
  }

  void clearAttention(String kind, String target) {
    if (_attention.remove('$kind:$target') != null) notifyListeners();
  }

  void clearAttentionKind(String kind) {
    final before = _attention.length;
    _attention.removeWhere((_, item) => item.kind == kind);
    if (_attention.length != before) notifyListeners();
  }

  // ── logging ──

  void _op(
    String kind,
    String summary, {
    String sid = '',
    int importance = 1,
    String? detail,
    Map<String, Object?>? extra,
    String actor = 'ai',
  }) {
    _logs.add(
      LogChannel.operations,
      LogRecord.now(
        k: kind,
        s: summary,
        sid: sid,
        a: actor,
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
        sid: 'chat',
        a: who,
        i: 0,
        d: text.length > 300 ? text : null,
        x: <String, Object?>{'id': id},
      ),
    );
  }

  static String _clip(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}…';

  // ── sessions ──

  void _guard() {
    if (!_paused) return;
    throw McpToolException(
      'TERMINAL_PAUSED',
      'The user paused AI terminal access. Tell them in the chat (pyrunner_terminal_tell_user) or ask them to resume it from the AI chat button in the app',
      true,
    );
  }

  TerminalSession _session(String id) {
    final session = _sessions.byId(id);
    if (session == null) {
      throw McpToolException(
        McpErrorCodes.invalidArgument,
        'Unknown terminal session: $id. Call pyrunner_terminal_list for the open sessions, or pyrunner_terminal_open to open one',
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
      'Terminal ${session.id} is ${session.status.name}; open a new one with pyrunner_terminal_open',
      false,
      {'session_id': session.id, 'status': session.status.name},
    );
  }

  /// Tells whether the terminal waits for the person to type a password, and
  /// makes sure the person finds out. Empty when it does not.
  Map<String, dynamic> _inputHints(TerminalSession session) {
    session.logger.flushOutput();
    if (session.isAlive && session.logger.expectingSecret) {
      raiseAttention(
        'terminal',
        session.id,
        tr(
          '终端「${session.title}」在等你输入密码，点开它直接输入',
          'Terminal "${session.title}" is waiting for your password; open it and type',
        ),
      );
      return <String, dynamic>{
        'needs_user_input': true,
        'input_kind': 'password',
        'hint':
            'The terminal is asking for a password. Do not guess or type one. Tell the user, in your own chat and with pyrunner_terminal_tell_user, to switch to Python Runner and type it (the app opens this terminal for them). Then call pyrunner_terminal_wait_output with your last next_cursor.',
      };
    }
    clearAttention('terminal', session.id);
    return const <String, dynamic>{};
  }

  Map<String, dynamic> listSessions() {
    _guard();
    return <String, dynamic>{
      'sessions': [
        for (final s in _sessions.sessions)
          <String, Object?>{
            ...s.describe(),
            'opened_by_ai': _aiOpened.contains(s.id),
            ..._inputHints(s),
          },
      ],
    };
  }

  /// Opens a local shell. It shows up as a tab for the person, too.
  Future<Map<String, dynamic>> openLocal({String? title}) async {
    _guard();
    final TerminalSession session;
    try {
      session = _sessions.createLocal();
    } on StateError catch (error) {
      throw McpToolException('TOO_MANY_TERMINALS', error.message, false);
    }
    _aiOpened.add(session.id);
    final name = title?.trim() ?? '';
    session.title = name.isEmpty ? 'AI · ${session.title}' : 'AI · ${_clip(name, 40)}';
    _op('open', 'Opened ${session.id} (${session.title})',
        sid: session.id, importance: 0);
    await session.start();
    return <String, dynamic>{'opened': true, ...session.describe()};
  }

  /// Closes a session the AI opened itself; the person's sessions are theirs.
  Future<Map<String, dynamic>> close(String sessionId) async {
    _guard();
    final session = _session(sessionId);
    if (!_aiOpened.contains(session.id)) {
      throw McpToolException(
        McpErrorCodes.mcpForbidden,
        'Only terminals opened with pyrunner_terminal_open can be closed by the AI',
        false,
        {'session_id': session.id},
      );
    }
    _op('close', 'Closed ${session.id}', sid: session.id, importance: 0);
    _aiOpened.remove(session.id);
    clearAttention('terminal', session.id);
    await _sessions.remove(session.id);
    return <String, dynamic>{'closed': true, 'session_id': sessionId};
  }

  /// Types [command] and Enter into a session.
  Future<Map<String, dynamic>> send({
    required String sessionId,
    required String command,
    required String clientLabel,
    int waitSeconds = 2,
  }) async {
    _guard();
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
    await loadSettings();
    if (_confirmEach) {
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
      _guard();
      _requireAlive(session);
    }
    final from = session.ring.end;
    _op(
      'cmd',
      shown,
      sid: session.id,
      importance: 0,
      detail: hidden || command.length <= 300 ? null : command,
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

  /// Waits for new output after [cursor] (for example once the person has
  /// typed the password the terminal asked for), then reads it.
  Future<Map<String, dynamic>> waitOutput(
    String sessionId, {
    required int cursor,
    int timeoutSeconds = 30,
  }) async {
    _guard();
    final session = _session(sessionId);
    final limit = DateTime.now().add(
      Duration(seconds: timeoutSeconds.clamp(1, 100).toInt()),
    );
    while (session.ring.end <= cursor && DateTime.now().isBefore(limit)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return _settle(session, cursor, 1);
  }

  /// Plain-text output of a session (what the person typed and saw, too).
  /// Without [cursor] the most recent output.
  Map<String, dynamic> read(
    String sessionId, {
    int? cursor,
    int maxChars = 20000,
  }) {
    _guard();
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
      ..._inputHints(session),
    };
  }

  /// Ctrl+C.
  Map<String, dynamic> interrupt(String sessionId) {
    _guard();
    final session = _session(sessionId);
    _requireAlive(session);
    _op('cmd', '^C', sid: session.id, importance: 0);
    session.sendText('\x03', actor: 'ai');
    return <String, dynamic>{'interrupted': true, 'session_id': session.id};
  }

  // ── the conversation ──

  AiChatEntry _add(bool fromAi, String text, {bool system = false}) {
    final entry = AiChatEntry(
      id: ++_seq,
      fromAi: fromAi,
      text: text,
      time: DateTime.now(),
      system: system,
    );
    _thread.add(entry);
    if (_thread.length > maxThread) {
      _thread.removeRange(0, _thread.length - maxThread);
    }
    _conversation(
      entry.id,
      system ? 'system' : (fromAi ? 'ai' : 'human'),
      text,
    );
    notifyListeners();
    return entry;
  }

  /// The AI says something to the person (shown in the chat sheet).
  Map<String, dynamic> tellUser(String text, String clientLabel) {
    final entry = _add(true, text);
    _op(
      'message',
      _clip(text, 120),
      importance: 0,
      detail: text.length > 120 ? text : null,
    );
    return <String, dynamic>{
      'message_id': entry.id,
      'delivered': true,
      'hint':
          'The user may be in another app. Their answer arrives through pyrunner_terminal_wait_reply or pyrunner_terminal_inbox',
    };
  }

  /// The person says something to the AI.
  void userSay(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return;
    _add(false, clean);
  }

  /// What the person wrote after [afterId]. With [waitSeconds] it waits for
  /// something to arrive.
  Future<Map<String, dynamic>> inbox({
    int afterId = 0,
    int waitSeconds = 0,
  }) async {
    List<AiChatEntry> fresh() =>
        _thread.where((e) => e.fromUser && e.id > afterId).toList();
    final limit = DateTime.now().add(
      Duration(seconds: waitSeconds.clamp(0, 100).toInt()),
    );
    while (fresh().isEmpty && DateTime.now().isBefore(limit)) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    final list = fresh();
    _op(
      'inbox',
      list.isEmpty
          ? 'No new message from the user'
          : 'Read ${list.length} message(s) from the user',
      importance: 1,
      detail: list.isEmpty ? null : list.map((e) => e.text).join('\n---\n'),
    );
    return <String, dynamic>{
      'messages': [
        for (final e in list)
          <String, dynamic>{
            'id': e.id,
            'text': e.text,
            'at': e.time.toUtc().toIso8601String(),
          },
      ],
      'next_after_id': list.isEmpty ? afterId : list.last.id,
      'paused': _paused,
    };
  }

  /// Waits for the person's answer to the AI's message [messageId] (default:
  /// the newest one).
  Future<Map<String, dynamic>> waitReply({
    int? messageId,
    int timeoutSeconds = 60,
  }) async {
    var afterId = messageId ?? 0;
    if (messageId == null) {
      for (final entry in _thread) {
        if (entry.fromAi) afterId = entry.id;
      }
    }
    final result = await inbox(afterId: afterId, waitSeconds: timeoutSeconds);
    final messages = result['messages'] as List<dynamic>;
    return <String, dynamic>{
      ...result,
      'replied': messages.isNotEmpty,
      if (messages.isNotEmpty)
        'reply': messages
            .map((m) => (m as Map<String, dynamic>)['text'])
            .join('\n'),
    };
  }
}
