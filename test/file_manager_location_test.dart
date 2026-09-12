import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/files/domain/file_manager_location.dart';

void main() {
  group('resolveWorkingDirectory', () {
    test('uses configured accessible working directory', () {
      final path = resolveWorkingDirectory(
        configuredPath: '/storage/emulated/0/Work',
        isAccessible: (value) => value == '/storage/emulated/0/Work',
      );
      expect(path, '/storage/emulated/0/Work');
    });

    test('trims configured path before checking accessibility', () {
      final path = resolveWorkingDirectory(
        configuredPath: '  /storage/emulated/0/Work  ',
        isAccessible: (value) => value == '/storage/emulated/0/Work',
      );
      expect(path, '/storage/emulated/0/Work');
    });

    test('falls back for null configuration', () {
      expect(
        resolveWorkingDirectory(
          configuredPath: null,
          isAccessible: (_) => true,
        ),
        defaultScriptWorkingDirectory,
      );
    });

    test('falls back for blank configuration', () {
      expect(
        resolveWorkingDirectory(
          configuredPath: '   ',
          isAccessible: (_) => true,
        ),
        defaultScriptWorkingDirectory,
      );
    });

    test('falls back for inaccessible configuration', () {
      expect(
        resolveWorkingDirectory(
          configuredPath: '/missing/directory',
          isAccessible: (_) => false,
        ),
        defaultScriptWorkingDirectory,
      );
    });

    test('falls back for relative configuration', () {
      expect(
        resolveWorkingDirectory(
          configuredPath: 'relative/path',
          isAccessible: (_) => true,
        ),
        defaultScriptWorkingDirectory,
      );
    });

    test('never falls back to filesystem root', () {
      expect(defaultScriptWorkingDirectory, isNot('/'));
    });
  });

  group('initialLocation', () {
    test('starts in working directory mode with configured path', () {
      final location = initialLocation(
        configuredPath: '/storage/emulated/0/Work',
        isAccessible: (_) => true,
      );
      expect(location.mode, FileManagerLocationMode.workingDirectory);
      expect(location.path, '/storage/emulated/0/Work');
      expect(location.isRoot, isFalse);
    });

    test('starts in working directory mode with fallback path', () {
      final location = initialLocation(
        configuredPath: null,
        isAccessible: (_) => false,
      );
      expect(location.mode, FileManagerLocationMode.workingDirectory);
      expect(location.path, defaultScriptWorkingDirectory);
    });
  });

  group('FileManagerLocation', () {
    test('root location is exactly slash', () {
      final root = FileManagerLocation.root;
      expect(root.path, '/');
      expect(root.mode, FileManagerLocationMode.root);
      expect(root.isRoot, isTrue);
    });

    test('working directory location keeps path and display name', () {
      final location = FileManagerLocation.workingDirectory(
        '/storage/emulated/0/Work',
      );
      expect(location.mode, FileManagerLocationMode.workingDirectory);
      expect(location.path, '/storage/emulated/0/Work');
      expect(location.isRoot, isFalse);
      expect(location.displayName, 'Work');
    });

    test('root display name is root marker', () {
      expect(FileManagerLocation.root.displayName, '/');
    });
  });
}
