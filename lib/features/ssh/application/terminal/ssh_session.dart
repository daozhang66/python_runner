import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart' show SSHSession;

import '../../domain/ssh_profile.dart';
import '../ssh_command_builder.dart';
import '../ssh_connection.dart';
import '../ssh_profile_store.dart';
import 'terminal_session.dart';

/// A script that is uploaded and run instead of opening a login shell.
class SshRemoteTask {
  const SshRemoteTask({required this.fileName, required this.content});

  final String fileName;
  final String content;
}

/// A shell (or a remote script run) on an SSH host.
class SshSession extends TerminalSession {
  SshSession({required super.id, required this.profile, this.task})
      : super(
          kind: 'ssh',
          title: task == null
              ? profile.name
              : '${profile.name} · ${task.fileName}',
        );

  final SshProfile profile;
  final SshRemoteTask? task;

  SshConnection? _connection;
  SSHSession? _session;
  StreamSubscription<String>? _outSub;
  StreamSubscription<String>? _errSub;
  int _generation = 0;

  Future<void> _teardown() async {
    terminal.onOutput = null;
    terminal.onResize = null;
    final out = _outSub;
    final err = _errSub;
    _outSub = null;
    _errSub = null;
    await out?.cancel();
    await err?.cancel();
    _session?.close();
    _session = null;
    _connection?.close();
    _connection = null;
  }

  @override
  Future<void> start() async {
    final generation = ++_generation;
    setStatus(TerminalSessionStatus.connecting);
    await _teardown();
    if (generation != _generation) return;

    info('Connecting to ${profile.endpoint} …');
    final connection = SshConnection(profile);
    try {
      final secrets = await SshProfileStore.instance.loadSecrets(profile.id);
      _connection = connection;
      await connection.connect(
        secrets: secrets,
        askPassword: () async => host?.askSecret('Password'),
        askPassphrase: () async => host?.askSecret('Key passphrase'),
        confirmHostKey: (prompt) async =>
            await host?.confirmHostKey(prompt) ?? false,
      );
      if (generation != _generation) {
        connection.close();
        return;
      }

      final cols = terminal.viewWidth;
      final rows = terminal.viewHeight;
      final task = this.task;
      final SSHSession session;
      if (task == null) {
        session = await connection.openShell(cols, rows);
      } else {
        final fileName = safeRemoteFileName(task.fileName);
        info('Uploading $fileName …');
        await connection.uploadText(
          buildUploadCommand(
            remoteDir: profile.remoteDir,
            fileName: fileName,
          ),
          task.content,
        );
        if (generation != _generation) {
          connection.close();
          return;
        }
        session = await connection.execPty(
          buildRunCommand(
            remoteDir: profile.remoteDir,
            fileName: fileName,
            pythonCommand: profile.pythonCommand,
          ),
          cols,
          rows,
        );
      }
      if (generation != _generation) {
        session.close();
        connection.close();
        return;
      }
      unawaited(SshProfileStore.instance.setLastProfileId(profile.id));
      _attach(session, generation);
    } on SshCancelled {
      connection.close();
      if (generation == _generation) {
        info('Cancelled');
        logger.event('session', 'connection cancelled');
        setStatus(TerminalSessionStatus.failed, 'cancelled');
      }
    } catch (e) {
      connection.close();
      if (generation == _generation) {
        final message = _describe(e);
        error(message);
        logger.event('session', 'connection failed', detail: message);
        setStatus(TerminalSessionStatus.failed, message);
      }
    }
  }

  /// Needs no screen, so it lives here rather than with the UI strings.
  String _describe(Object error) {
    if (error is SshFailure) {
      return switch (error.kind) {
        SshFailureKind.noPrivateKey => 'No private key is saved for this host.',
        SshFailureKind.badKey => 'Cannot read the private key: ${error.detail}',
        SshFailureKind.uploadFailed =>
          'Uploading the script failed: ${error.detail}',
      };
    }
    return '$error';
  }

  void _attach(SSHSession session, int generation) {
    _session = session;
    _outSub = session.stdout
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(emit);
    _errSub = session.stderr
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(emit);
    terminal.onOutput = (data) => _write(filter.apply(data), 'human');
    terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      session.resizeTerminal(width, height, pixelWidth, pixelHeight);
    };
    logger.event(
      'session',
      task == null
          ? 'connected to ${profile.endpoint}'
          : 'running ${task!.fileName} on ${profile.endpoint}',
    );
    setStatus(TerminalSessionStatus.running);
    unawaited(_watch(session, generation));
  }

  Future<void> _watch(SSHSession session, int generation) async {
    try {
      await session.done;
    } catch (_) {
      // The connection dropped; handled below like a normal exit.
    }
    if (generation != _generation) return;
    info('[Session ended]');
    logger.event('session', 'ended');
    setStatus(TerminalSessionStatus.closed, 'ended');
  }

  void _write(String data, String actor) {
    final session = _session;
    if (session == null) return;
    logger.feedInput(data, actor: actor);
    session.write(utf8.encoder.convert(data));
  }

  @override
  void sendText(String text, {String actor = 'human'}) => _write(text, actor);

  @override
  void interrupt() => _write('\x03', 'human');

  @override
  Future<void> close() async {
    final wasAlive = isAlive;
    _generation++;
    await _teardown();
    if (wasAlive) logger.event('session', 'closed');
    setStatus(TerminalSessionStatus.closed);
  }
}
