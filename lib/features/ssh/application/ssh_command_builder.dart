/// Pure helpers that build the shell snippets used for remote runs.
library;

/// Quotes [value] for a POSIX shell.
String shQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";

/// Quotes a remote path. A leading `~` is expanded through `$HOME` so that it
/// still works inside quotes.
String shQuotePath(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty || trimmed == '~') return r'"$HOME"';
  if (trimmed.startsWith('~/')) {
    final rest = trimmed.substring(2);
    if (rest.isEmpty) return r'"$HOME"';
    return '"\$HOME"/${shQuote(rest)}';
  }
  return shQuote(trimmed);
}

/// Reduces [name] to a file name that is safe to use under the remote
/// directory (no directories, no control characters).
String safeRemoteFileName(String name) {
  var base = name.trim().replaceAll('\\', '/').split('/').last;
  base = base.replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), '_');
  if (base.isEmpty || base == '.' || base == '..') base = 'script.py';
  return base;
}

/// Command that reads the script from stdin and stores it on the remote host.
String buildUploadCommand({
  required String remoteDir,
  required String fileName,
}) {
  final dir = shQuotePath(remoteDir);
  return 'mkdir -p $dir && cat > $dir/${shQuote(fileName)}';
}

/// Command that runs the uploaded script and prints its exit code.
String buildRunCommand({
  required String remoteDir,
  required String fileName,
  String pythonCommand = 'python3',
}) {
  final dir = shQuotePath(remoteDir);
  final python = _cleanPythonCommand(pythonCommand);
  return 'cd $dir && PYTHONUNBUFFERED=1 $python ${shQuote(fileName)}; '
      r'''status=$?; printf '\n[exit code %s]\n' "$status"''';
}

String _cleanPythonCommand(String value) {
  final cleaned = value.replaceAll(RegExp(r'[\r\n]'), ' ').trim();
  return cleaned.isEmpty ? 'python3' : cleaned;
}
