import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/ssh/application/python_launch.dart';

void main() {
  group('shellSplit', () {
    test('splits on spaces and keeps quoted words together', () {
      expect(shellSplit('a  b "c d" \'e f\''), ['a', 'b', 'c d', 'e f']);
    });

    test('handles backslashes and empty quotes', () {
      expect(shellSplit(r'a\ b ""'), ['a b', '']);
    });

    test('rejects shell operators and unterminated quotes', () {
      expect(() => shellSplit('a | b'), throwsA(isA<PythonCommandException>()));
      expect(() => shellSplit('a && b'), throwsA(isA<PythonCommandException>()));
      expect(() => shellSplit('"abc'), throwsA(isA<PythonCommandException>()));
    });

    test('an operator inside quotes is just text', () {
      expect(shellSplit('echo "a | b"'), ['echo', 'a | b']);
    });
  });

  group('resolveShellPath', () {
    test('joins, normalizes and expands ~', () {
      expect(resolveShellPath('x.py', '/data/a'), '/data/a/x.py');
      expect(resolveShellPath('../x.py', '/data/a'), '/data/x.py');
      expect(resolveShellPath('./b/../c.py', '/d'), '/d/c.py');
      expect(resolveShellPath('/abs/x.py', '/d'), '/abs/x.py');
      expect(resolveShellPath('~/x.py', '/d', home: '/home'), '/home/x.py');
    });
  });

  group('parsePythonCommand', () {
    PythonLaunch? parse(String line) =>
        parsePythonCommand(line, cwd: '/work', home: '/home');

    test('ignores lines that are not python commands', () {
      expect(parse('ls -l'), isNull);
      expect(parse('pytest x'), isNull);
      expect(parse(''), isNull);
    });

    test('python with no arguments opens the console', () {
      expect(parse('python')!.mode, PythonLaunchMode.interactive);
      expect(parse('python3')!.mode, PythonLaunchMode.interactive);
      expect(parse('py')!.mode, PythonLaunchMode.interactive);
      expect(parse('python3.10')!.mode, PythonLaunchMode.interactive);
    });

    test('a script with arguments', () {
      final launch = parse('python3 -u demo.py a "b c"')!;
      expect(launch.mode, PythonLaunchMode.file);
      expect(launch.filePath, '/work/demo.py');
      expect(launch.displayName, 'demo.py');
      expect(launch.args, ['a', 'b c']);
      expect(launch.cwd, '/work');
    });

    test('-c and -m take everything after them as arguments', () {
      final code = parse('python -c "print(1)" x y')!;
      expect(code.mode, PythonLaunchMode.code);
      expect(code.code, 'print(1)');
      expect(code.args, ['x', 'y']);
      final module = parse('python -m http.server 8000')!;
      expect(module.mode, PythonLaunchMode.module);
      expect(module.module, 'http.server');
      expect(module.args, ['8000']);
    });

    test('--version and errors', () {
      expect(parse('python --version')!.mode, PythonLaunchMode.version);
      expect(() => parse('python -c'), throwsA(isA<PythonCommandException>()));
      expect(() => parse('python --bogus'), throwsA(isA<PythonCommandException>()));
      expect(() => parse('python x.py | cat'), throwsA(isA<PythonCommandException>()));
    });
  });

  group('buildLauncherSource', () {
    test('file launch embeds the script as base64 and sets argv', () {
      final source = buildLauncherSource(
        const PythonLaunch(
          mode: PythonLaunchMode.file,
          displayName: 'demo.py',
          filePath: '/work/demo.py',
          source: 'print("hi")\n',
          args: ['a', 'b c'],
          cwd: '/work',
        ),
      );
      expect(source, contains('_os.chdir("/work")'));
      expect(source, contains('_sys.argv = [_file or _name] + ["a","b c"]'));
      expect(source, contains('_file = "/work/demo.py"'));
      expect(source, contains('cHJpbnQoImhpIikK'));
      expect(source, isNot(contains('print("hi")')));
    });

    test('a file launch without a script text is an error', () {
      expect(
        () => buildLauncherSource(
          const PythonLaunch(mode: PythonLaunchMode.file, displayName: 'x.py'),
        ),
        throwsStateError,
      );
    });

    test('other modes', () {
      expect(
        buildLauncherSource(
          const PythonLaunch(mode: PythonLaunchMode.code, code: 'print(1)'),
        ),
        contains('exec(compile("print(1)", "<string>"'),
      );
      expect(
        buildLauncherSource(
          const PythonLaunch(
            mode: PythonLaunchMode.module,
            module: 'json.tool',
            args: ['x'],
          ),
        ),
        contains('_runpy.run_module("json.tool"'),
      );
      expect(
        buildLauncherSource(
          const PythonLaunch(mode: PythonLaunchMode.interactive),
        ),
        contains('InteractiveConsole'),
      );
      expect(
        buildLauncherSource(
          const PythonLaunch(mode: PythonLaunchMode.version),
        ),
        contains('print("Python "'),
      );
    });
  });
}
