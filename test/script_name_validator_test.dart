import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/services/script_name_validator.dart';

void main() {
  group('ScriptNameValidator', () {
    test('accepts normal script names including spaces and CJK text', () {
      expect(ScriptNameValidator.normalize('hello.py'), 'hello.py');
      expect(ScriptNameValidator.normalize(' 中文 脚本.py '), '中文 脚本.py');
    });

    test('rejects path traversal and path separators', () {
      const invalidNames = [
        '',
        '   ',
        '.',
        '..',
        '../evil.py',
        '..\\evil.py',
        'dir/evil.py',
        'dir\\evil.py',
        'bad:name.py',
        'bad*name.py',
        'bad?name.py',
        'bad"name.py',
        'bad<name.py',
        'bad>name.py',
        'bad|name.py',
        'trailing.',
        'CON',
        'prn.txt',
        'NUL.py',
        'COM1',
        'lpt9.log',
        'evil\u0000.py',
        'evil\n.py',
      ];

      for (final name in invalidNames) {
        expect(
          () => ScriptNameValidator.normalize(name),
          throwsA(isA<FormatException>()),
          reason: name,
        );
        expect(ScriptNameValidator.tryNormalize(name), isNull, reason: name);
      }
    });
  });
}
