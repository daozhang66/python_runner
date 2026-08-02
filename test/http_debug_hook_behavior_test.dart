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

  test('HTTP hook captures requests made through a custom urllib opener',
      () async {
    final python = await _findPythonExecutable();
    if (python == null) {
      return;
    }

    const script = r'''
import importlib.util
import io
import json
import os
import pathlib
import sys
import threading
import urllib.request
from http.cookiejar import CookieJar
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, format, *args):
        pass


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
os.environ["PYRUNNER_HTTP_HOOK_CONFIG"] = json.dumps({"record_requests": True})

path = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("http_debug_hook_under_test", path)
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)

captured = io.StringIO()
original_stdout = sys.stdout
try:
    sys.stdout = captured
    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({}),
        urllib.request.HTTPCookieProcessor(CookieJar()),
    )
    url = f"http://127.0.0.1:{server.server_port}/song"
    request = urllib.request.Request(url, headers={"X-Test": "opener"})
    with opener.open(request, timeout=5) as response:
        assert response.read() == b"ok"
finally:
    sys.stdout = original_stdout
    server.shutdown()
    server.server_close()
    thread.join(timeout=5)

records = [
    json.loads(line[len("__HTTP_RECORD__"):])
    for line in captured.getvalue().splitlines()
    if line.startswith("__HTTP_RECORD__")
]
urllib_records = [record for record in records if record["library"] == "urllib"]
assert len(urllib_records) == 1, captured.getvalue()
record = urllib_records[0]
assert record["library"] == "urllib", record
assert record["method"] == "GET", record
assert record["url"] == url, record
assert record["status_code"] == 200, record
assert record["request_headers"]["X-test"] == "opener", record
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

  test('HTTP hook applies the first matching domain rule over global fields',
      () async {
    final python = await _findPythonExecutable();
    if (python == null) return;

    const script = r'''
import importlib.util
import json
import os
import pathlib
import sys

os.environ["PYRUNNER_HTTP_HOOK_CONFIG"] = json.dumps({
    "override_enabled": True,
    "global_user_agent": "global-agent",
    "global_cookie": "global=1",
    "global_headers": json.dumps({"X-Global": "1"}),
    "domain_rules": [
        {"domain": "*.example.com", "user_agent": "wildcard-agent",
         "headers": {"X-Rule": "first"}},
        {"domain": "api.example.com", "user_agent": "later-agent"}
    ]
})

path = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("http_debug_hook_under_test", path)
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)

headers = hook._apply_overrides_to_headers(
    {"X-Existing": "yes"}, "requests", "https://api.example.com/v1"
)
assert headers["User-Agent"] == "wildcard-agent", headers
assert headers["Cookie"] == "global=1", headers
assert headers["X-Global"] == "1", headers
assert headers["X-Rule"] == "first", headers
assert hook._match_domain_rule("https://api.example.com/v1")["user_agent"] == "wildcard-agent"
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
