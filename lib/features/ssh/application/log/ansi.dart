/// Removes terminal control sequences from [text] so it can be stored or
/// shown as plain text: colors and cursor moves, OSC titles, bells, and the
/// carriage-return rewrites that progress bars use.
library;

final RegExp _ansiPattern = RegExp(
  r'\x1B(?:\[[0-?]*[ -/]*[@-~]|\][^\x07\x1B]*(?:\x07|\x1B\\)|[@-Z\\-_])',
);

String stripAnsi(String text) {
  final cleaned = text
      .replaceAll(_ansiPattern, '')
      .replaceAll('\x07', '')
      .replaceAll('\r\n', '\n');
  if (!cleaned.contains('\r')) return cleaned;
  return cleaned.split('\n').map((line) {
    final index = line.lastIndexOf('\r');
    return index < 0 ? line : line.substring(index + 1);
  }).join('\n');
}
