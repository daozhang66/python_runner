/// Pure helpers for running Python from a terminal-like prompt: splitting a
/// shell line, understanding `python ...` commands and generating the small
/// launcher script that runs them inside the embedded interpreter.
library;

import 'dart:convert';

enum PythonLaunchMode { file, code, module, interactive, version }

class PythonCommandException implements Exception {
  const PythonCommandException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What to run in the embedded Python.
class PythonLaunch {
  const PythonLaunch({
    required this.mode,
    this.displayName = '',
    this.filePath,
    this.source,
    this.code,
    this.module,
    this.args = const <String>[],
    this.cwd,
  });

  final PythonLaunchMode mode;

  /// Name shown in tracebacks and dialogs (file mode).
  final String displayName;

  /// Real path of the script, when it comes from the file system.
  final String? filePath;

  /// Script text (file mode). Filled in after reading [filePath].
  final String? source;
  final String? code;
  final String? module;
  final List<String> args;
  final String? cwd;

  PythonLaunch withSource(String value) => PythonLaunch(
        mode: mode,
        displayName: displayName,
        filePath: filePath,
        source: value,
        code: code,
        module: module,
        args: args,
        cwd: cwd,
      );

  String get label => switch (mode) {
        PythonLaunchMode.file =>
          displayName.isNotEmpty ? displayName : (filePath ?? 'script.py'),
        PythonLaunchMode.code => 'python -c',
        PythonLaunchMode.module => 'python -m $module',
        PythonLaunchMode.interactive => 'Python console',
        PythonLaunchMode.version => 'python --version',
      };
}

/// Splits a shell line into words, understanding quotes and backslashes.
/// Shell operators (pipes, redirects, `&&`, `;`, ...) are not supported and
/// raise a [PythonCommandException].
List<String> shellSplit(String line) {
  final tokens = <String>[];
  final current = StringBuffer();
  var inToken = false;
  String? quote;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (quote != null) {
      if (c == quote) {
        quote = null;
        continue;
      }
      if (quote == '"' &&
          c == r'\' &&
          i + 1 < line.length &&
          '"\\\$`'.contains(line[i + 1])) {
        current.write(line[i + 1]);
        i++;
        continue;
      }
      current.write(c);
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
      inToken = true;
      continue;
    }
    if (c == r'\') {
      if (i + 1 < line.length) {
        current.write(line[i + 1]);
        i++;
        inToken = true;
      }
      continue;
    }
    if (c == ' ' || c == '\t') {
      if (inToken) {
        tokens.add(current.toString());
        current.clear();
        inToken = false;
      }
      continue;
    }
    if ('|&;<>()`'.contains(c)) {
      throw const PythonCommandException(
        'pipes, redirects, && and ; are not supported here',
      );
    }
    current.write(c);
    inToken = true;
  }
  if (quote != null) {
    throw const PythonCommandException('unterminated quote');
  }
  if (inToken) tokens.add(current.toString());
  return tokens;
}

final RegExp _pythonWord = RegExp(r'^(python|py)(\d+(\.\d+)*)?$');
final RegExp _ignoredFlags = RegExp(r'^-[uBOsSEIqbdvxi]+$');

bool isPythonCommandName(String word) => _pythonWord.hasMatch(word);

/// Resolves [path] against [cwd]; `~` expands to [home] (or [cwd]).
String resolveShellPath(String path, String cwd, {String? home}) {
  var value = path;
  if (value == '~' || value.startsWith('~/')) {
    value = (home ?? cwd) + value.substring(1);
  }
  if (!value.startsWith('/')) value = '$cwd/$value';
  final parts = <String>[];
  for (final segment in value.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else {
      parts.add(segment);
    }
  }
  return '/${parts.join('/')}';
}

/// Understands `python [options] [file | -c code | -m module] [args]`.
/// Returns null when [line] is not a python command. For file launches the
/// script text is not loaded yet (see [PythonLaunch.withSource]).
PythonLaunch? parsePythonCommand(
  String line, {
  required String cwd,
  String? home,
}) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return null;
  final firstSpace = trimmed.indexOf(RegExp(r'\s'));
  final firstWord =
      firstSpace < 0 ? trimmed : trimmed.substring(0, firstSpace);
  if (!isPythonCommandName(firstWord)) return null;

  final tokens = shellSplit(trimmed);
  var i = 1;
  while (i < tokens.length) {
    final token = tokens[i];
    if (token == '--version' || token == '-V') {
      return PythonLaunch(mode: PythonLaunchMode.version, cwd: cwd);
    }
    if (token == '-c') {
      if (i + 1 >= tokens.length) {
        throw const PythonCommandException(
          'Argument expected for the -c option',
        );
      }
      return PythonLaunch(
        mode: PythonLaunchMode.code,
        code: tokens[i + 1],
        args: tokens.sublist(i + 2),
        cwd: cwd,
      );
    }
    if (token == '-m') {
      if (i + 1 >= tokens.length) {
        throw const PythonCommandException(
          'Argument expected for the -m option',
        );
      }
      return PythonLaunch(
        mode: PythonLaunchMode.module,
        module: tokens[i + 1],
        args: tokens.sublist(i + 2),
        cwd: cwd,
      );
    }
    if (_ignoredFlags.hasMatch(token)) {
      i++;
      continue;
    }
    if (token == '-W' || token == '-X' || token == '-Q') {
      i += 2;
      continue;
    }
    if (token == '-') {
      throw const PythonCommandException(
        'reading the program from stdin is not supported',
      );
    }
    if (token.startsWith('-')) {
      throw PythonCommandException('Unknown option: $token');
    }
    return PythonLaunch(
      mode: PythonLaunchMode.file,
      displayName: token.split('/').last,
      filePath: resolveShellPath(token, cwd, home: home),
      args: tokens.sublist(i + 1),
      cwd: cwd,
    );
  }
  return PythonLaunch(mode: PythonLaunchMode.interactive, cwd: cwd);
}

/// The text of the script that runs [launch] inside the embedded Python.
///
/// The user's script is passed base64-encoded so no quoting can break it, and
/// every other value is written as a JSON string (a valid Python literal).
String buildLauncherSource(PythonLaunch launch) {
  final out = StringBuffer()
    ..writeln('# Generated by Python Runner for terminal commands.')
    ..writeln('# It is rewritten every time a command is started.')
    ..writeln('import os as _os')
    ..writeln('import sys as _sys')
    ..writeln();
  final cwd = launch.cwd;
  if (cwd != null && cwd.isNotEmpty) {
    out.writeln('_os.chdir(${jsonEncode(cwd)})');
  }
  switch (launch.mode) {
    case PythonLaunchMode.file:
      final source = launch.source;
      if (source == null) {
        throw StateError('A file launch needs the script text');
      }
      final name =
          launch.displayName.isEmpty ? 'script.py' : launch.displayName;
      final file = launch.filePath;
      final encoded = base64.encode(utf8.encode(source));
      out
        ..writeln('import base64 as _b64')
        ..writeln('_name = ${jsonEncode(name)}')
        ..writeln('_file = ${file == null ? 'None' : jsonEncode(file)}')
        ..writeln(
          '_sys.argv = [_file or _name] + ${jsonEncode(launch.args)}',
        )
        ..writeln('if _file:')
        ..writeln('    _dir = _os.path.dirname(_file)')
        ..writeln('    if _dir and _dir not in _sys.path:')
        ..writeln('        _sys.path.insert(0, _dir)')
        ..writeln(
          '_src = _b64.b64decode(${jsonEncode(encoded)}).decode("utf-8")',
        )
        ..writeln(
          'exec(compile(_src, _file or _name, "exec"), '
          '{"__name__": "__main__", "__file__": _file or _name})',
        );
    case PythonLaunchMode.code:
      out
        ..writeln('_sys.argv = ["-c"] + ${jsonEncode(launch.args)}')
        ..writeln(
          'exec(compile(${jsonEncode(launch.code ?? '')}, "<string>", '
          '"exec"), {"__name__": "__main__"})',
        );
    case PythonLaunchMode.module:
      final module = launch.module ?? '';
      out
        ..writeln('import runpy as _runpy')
        ..writeln(
          '_sys.argv = [${jsonEncode(module)}] + ${jsonEncode(launch.args)}',
        )
        ..writeln(
          '_runpy.run_module(${jsonEncode(module)}, '
          'run_name="__main__", alter_sys=True)',
        );
    case PythonLaunchMode.interactive:
      out
        ..writeln('import code as _code')
        ..writeln('_sys.argv = [""] + ${jsonEncode(launch.args)}')
        ..writeln(
          '_code.InteractiveConsole({"__name__": "__console__"}).interact('
          'banner="Python " + _sys.version.split()[0] + '
          '"  (exit() to quit)", exitmsg="")',
        );
    case PythonLaunchMode.version:
      out.writeln('print("Python " + _sys.version.split()[0])');
  }
  return out.toString();
}
