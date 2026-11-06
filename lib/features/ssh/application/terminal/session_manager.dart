import 'package:flutter/foundation.dart';

import '../../domain/ssh_profile.dart';
import 'local_shell_session.dart';
import 'ssh_session.dart';
import 'terminal_session.dart';

/// All open terminal sessions. They keep running while no terminal page is
/// shown, and the AI works with the very same objects.
class TerminalSessionManager extends ChangeNotifier {
  TerminalSessionManager._();

  static final TerminalSessionManager instance = TerminalSessionManager._();

  static const int maxSessions = 8;

  final List<TerminalSession> _sessions = <TerminalSession>[];
  int _counter = 0;

  List<TerminalSession> get sessions =>
      List<TerminalSession>.unmodifiable(_sessions);

  TerminalSession? byId(String id) {
    for (final session in _sessions) {
      if (session.id == id) return session;
    }
    return null;
  }

  void _makeRoom() {
    if (_sessions.length < maxSessions) return;
    final index = _sessions.indexWhere((s) => !s.isAlive);
    if (index < 0) {
      throw StateError('At most $maxSessions terminals can be open at once');
    }
    final old = _sessions.removeAt(index);
    old.removeListener(notifyListeners);
    old.dispose();
  }

  T _add<T extends TerminalSession>(T session) {
    session.addListener(notifyListeners);
    _sessions.add(session);
    notifyListeners();
    return session;
  }

  LocalShellSession createLocal() {
    _makeRoom();
    final n = ++_counter;
    return _add(LocalShellSession(id: 'local-$n', title: 'Shell $n'));
  }

  SshSession createSsh(SshProfile profile, {SshRemoteTask? task}) {
    _makeRoom();
    final n = ++_counter;
    return _add(SshSession(id: 'ssh-$n', profile: profile, task: task));
  }

  Future<void> remove(String id) async {
    final session = byId(id);
    if (session == null) return;
    _sessions.remove(session);
    session.removeListener(notifyListeners);
    await session.close();
    session.dispose();
    notifyListeners();
  }
}
