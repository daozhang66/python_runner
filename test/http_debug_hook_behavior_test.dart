import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HTTP hook caps image previews and preserves text body limit', () async {
    final python = await _findPythonExecutable();
    if (python == null) {
      return;
    }

    const script = r'''
import importlib.util
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("http_debug_hook_under_test", path)
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)

image_headers = {"content-type": "image/png"}
small_image = b"x" * (3 * 1024 * 1024)
small_preview = hook._safe_body_preview(small_image, image_headers)
assert small_preview.startswith("data:image/png;base64,"), small_preview[:40]
assert hook._is_preview_truncated(small_image, image_headers) is False

large_size = 30 * 1024 * 1024 + 1
large_image = b"x" * large_size
large_preview = hook._safe_body_preview(large_image, image_headers)
expected = f'media:{{"type":"image/png","size":{large_size},"truncated":true}}'
assert large_preview == expected, large_preview
assert hook._is_preview_truncated(large_image, image_headers) is True

text_body = b"x" * (10 * 1024 * 1024 + 1)
text_preview = hook._safe_body_preview(text_body, {"content-type": "text/plain"})
assert text_preview.endswith("... (truncated)"), text_preview[-20:]
assert hook._is_preview_truncated(text_body, {"content-type": "text/plain"}) is True
''';

    for (final path in [
      'assets/python_hooks/http_debug_hook.py',
      'android/app/src/main/python/http_debug_hook.py',
      'android/app/src/main/assets/python_hooks/http_debug_hook.py',
    ]) {
      final result = await Process.run(
        python,
        ['-c', script, path],
        workingDirectory: Directory.current.path,
      );
      expect(
        result.exitCode,
        0,
        reason: '$path\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );
    }
  });
}

Future<String?> _findPythonExecutable() async {
  for (final candidate in ['python3', 'python']) {
    try {
      final result = await Process.run(candidate, ['--version']);
      if (result.exitCode == 0) return candidate;
    } on ProcessException {
      continue;
    }
  }
  return null;
}
