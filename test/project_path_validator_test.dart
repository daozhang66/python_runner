import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/services/project_path_validator.dart';

void main() {
  group('ProjectPathValidator', () {
    test('normalizes generated project keys', () {
      expect(ProjectPathValidator.normalizeProjectKey('project_18fabc'),
          'project_18fabc');
      expect(ProjectPathValidator.normalizeProjectKey('proj-123'), 'proj-123');
    });

    test('rejects unsafe project keys', () {
      for (final value in [
        '',
        ' project_1',
        'project 1',
        '../project',
        'a/b',
        r'a\b',
        '项目',
        'abc\u0000def',
      ]) {
        expect(() => ProjectPathValidator.normalizeProjectKey(value),
            throwsFormatException);
      }
    });

    test('normalizes project relative paths', () {
      expect(ProjectPathValidator.normalizeRelativePath('main.py'), 'main.py');
      expect(ProjectPathValidator.normalizeRelativePath('src/helper.py'),
          'src/helper.py');
      expect(ProjectPathValidator.normalizeRelativePath('scripts/tool.py'),
          'scripts/tool.py');
    });

    test('rejects unsafe project relative paths', () {
      for (final value in [
        '',
        '/main.py',
        '../main.py',
        'src/../main.py',
        'src//main.py',
        r'src\main.py',
        'src/\u0000/main.py',
      ]) {
        expect(() => ProjectPathValidator.normalizeRelativePath(value),
            throwsFormatException);
      }
    });

    test('validates main file paths as python files', () {
      expect(ProjectPathValidator.validateMainFilePath('main.py'), 'main.py');
      expect(ProjectPathValidator.validateMainFilePath('src/run.py'),
          'src/run.py');
      expect(() => ProjectPathValidator.validateMainFilePath('config.json'),
          throwsFormatException);
      expect(() => ProjectPathValidator.validateMainFilePath('src/'),
          throwsFormatException);
    });
  });
}
