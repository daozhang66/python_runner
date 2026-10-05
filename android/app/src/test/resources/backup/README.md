# Future-version backup fixture

`future-version.zip` is a deterministic, uncompressed ZIP shared by JVM archive
tests and Flutter parser/controller/UI tests. It contains a version-2
`.python_runner_backup.json` marker followed by `scripts/hello.py` with the bytes
`print("future fixture")\n`. File size and SHA-256 are correct. The timestamps and
metadata are fixed; there are no credentials or external paths.

The native regression stages the actual ZIP and requires `UNSUPPORTED_VERSION`.
It then changes only the marker version to 1, rebuilds the ZIP and confirms full
staging and the script bytes, proving the fixture is otherwise valid. Invalid
format and malformed version variants remain invalid archives.

The Flutter test helper reads the first stored ZIP member from this known
fixture and supplies its metadata to the real native bridge result decoder,
Dart manifest validator, controller and localized UI. It never injects an error
code, and is not a production ZIP parser. No test executes the script.
