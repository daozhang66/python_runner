"""Reject generated files and failed binary downloads in the source tree."""

import argparse
from pathlib import PurePosixPath
import subprocess
import sys


GENERATED_DIRECTORIES = {
    '__pycache__', '.pytest_cache', '.mypy_cache', '.ruff_cache',
    '.dart_tool', '.gradle', '.tooling', '.idea', '.vscode',
    'node_modules', 'build', 'dist', 'coverage', 'failures',
}
GENERATED_SUFFIXES = {'.pyc', '.pyo', '.class', '.apk', '.aab', '.log', '.tmp', '.bak', '.orig', '.rej'}
LOCAL_FILES = {'.DS_Store', 'Thumbs.db', 'local.properties', 'key.properties'}
ERROR_PAGES = {b'404: Not Found', b'404 Not Found', b'Not Found', b'403 Forbidden', b'Bad Gateway'}
SIGNATURES = {
    '.ttf': (b'\x00\x01\x00\x00', b'ttcf', b'OTTO'),
    '.otf': (b'OTTO',),
    '.woff': (b'wOFF',),
    '.woff2': (b'wOF2',),
    '.png': (b'\x89PNG\r\n\x1a\n',),
    '.jpg': (b'\xff\xd8\xff',),
    '.jpeg': (b'\xff\xd8\xff',),
    '.so': (b'\x7fELF',),
}


def inspect_file(path, content):
    name = PurePosixPath(path)
    errors = []
    if (set(name.parts[:-1]) & GENERATED_DIRECTORIES or
            name.suffix.lower() in GENERATED_SUFFIXES or name.name in LOCAL_FILES):
        errors.append('generated output, cache, or local configuration is tracked')
    if content.strip() in ERROR_PAGES:
        errors.append('file contains a download error response')
    signatures = SIGNATURES.get(name.suffix.lower())
    if signatures and not content.startswith(signatures):
        errors.append('file contents do not match the declared binary format')
    return errors


def tracked_contents(ref=None):
    if ref:
        records = subprocess.check_output(['git', 'ls-tree', '-r', '-z', ref]).split(b'\0')
        entries = []
        for record in records:
            if record:
                metadata, path = record.split(b'\t', 1)
                _, kind, oid = metadata.split()
                if kind == b'blob':
                    entries.append((path.decode('utf-8'), oid))
    else:
        records = subprocess.check_output(['git', 'ls-files', '--stage', '-z']).split(b'\0')
        entries = []
        for record in records:
            if record:
                metadata, path = record.split(b'\t', 1)
                mode, oid, stage = metadata.split()
                if stage != b'0':
                    raise ValueError('Resolve index conflicts before checking repository hygiene')
                if mode != b'160000':
                    entries.append((path.decode('utf-8'), oid))
    # Read Git blobs, not ignored files or unstaged contents. This also checks
    # deletions staged with git rm without mistaking them for missing files.
    with subprocess.Popen(['git', 'cat-file', '--batch'], stdin=subprocess.PIPE,
                          stdout=subprocess.PIPE) as process:
        try:
            for path, oid in entries:
                process.stdin.write(oid + b'\n')
                process.stdin.flush()
                header = process.stdout.readline().split()
                content = process.stdout.read(int(header[2]))
                process.stdout.read(1)
                yield path, content
        finally:
            process.stdin.close()
            process.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ref', help='Check a commit/tree instead of the staged index')
    args = parser.parse_args()
    count = failures = 0
    for path, content in tracked_contents(args.ref):
        count += 1
        for error in inspect_file(path, content):
            print(f'{path}: {error}', file=sys.stderr)
            failures += 1
    print(f'Checked {count} tracked files; {failures} hygiene issue(s).')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
