import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/files/application/file_manager_controller.dart';
import 'package:python_runner/features/files/domain/file_manager_location.dart';
import 'package:python_runner/models/app_file_entry.dart';

AppFileEntry _dir(String path) => AppFileEntry(
      path: path,
      name: path.split('/').last,
      isDirectory: true,
      size: 0,
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

AppFileEntry _namedDir(String path, String name) => AppFileEntry(
      path: path,
      name: name,
      isDirectory: true,
      size: 0,
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

AppFileEntry _file(String path, {int size = 10}) => AppFileEntry(
      path: path,
      name: path.split('/').last,
      isDirectory: false,
      size: size,
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

class _FakeBridge {
  final Map<String, List<AppFileEntry>> directories;
  Object? listError;
  Object? deleteError;
  final deleted = <String>[];
  final created = <String>[];
  final renamed = <String>[];
  final Map<String, List<int>> files;
  final Map<String, Completer<List<AppFileEntry>>> pendingList = {};

  _FakeBridge({
    Map<String, List<AppFileEntry>>? directories,
    this.files = const {},
  }) : directories = directories ?? {};

  Future<List<AppFileEntry>> list(String path) {
    final pending = pendingList.remove(path);
    if (pending != null) return pending.future;
    if (listError != null) throw listError!;
    return Future.value(directories[path] ?? const []);
  }

  Future<List<int>> readFile(String path) async {
    return files[path] ?? const [];
  }

  Future<void> createDirectory(String parent, String name) async {
    created.add('$parent/$name');
    final entries = [...directories[parent] ?? const <AppFileEntry>[]];
    entries.add(_dir('$parent/$name'));
    directories[parent] = entries;
  }

  Future<void> rename(String path, String newName) async {
    renamed.add('$path->$newName');
    final parent = path.substring(0, path.lastIndexOf('/'));
    final entries = [...directories[parent] ?? const <AppFileEntry>[]];
    final index = entries.indexWhere((e) => e.path == path);
    if (index >= 0) {
      final old = entries[index];
      entries[index] = AppFileEntry(
        path: '$parent/$newName',
        name: newName,
        isDirectory: old.isDirectory,
        size: old.size,
        modifiedAt: old.modifiedAt,
      );
      directories[parent] = entries;
    }
  }

  Future<void> delete(String path) async {
    if (deleteError != null) {
      throw deleteError!;
    }
    deleted.add(path);
    final parent = path.substring(0, path.lastIndexOf('/'));
    directories[parent] = (directories[parent] ?? const <AppFileEntry>[])
        .where((e) => e.path != path)
        .toList();
  }
}

FileManagerController _controller(
  _FakeBridge bridge, {
  String? configuredWorkingDir,
  bool workingDirAccessible = true,
  List<AppFileEntry> appDataRoots = const [],
}) {
  return FileManagerController(
    listDirectory: bridge.list,
    readFile: bridge.readFile,
    createDirectory: bridge.createDirectory,
    renameEntry: bridge.rename,
    deleteEntry: bridge.delete,
    workingDirectoryProvider: () async => configuredWorkingDir,
    isPathAccessible: (path) async => workingDirAccessible,
    appDataRootsProvider: () async => appDataRoots,
  );
}

void main() {
  test('loads configured working directory before any child path', () async {
    final bridge = _FakeBridge(directories: {
      '/work': [_dir('/work/src'), _file('/work/main.py')],
    });
    final controller = _controller(bridge, configuredWorkingDir: '/work');

    await controller.loadInitial();

    expect(controller.location.path, '/work');
    expect(controller.location.mode, FileManagerLocationMode.workingDirectory);
    expect(controller.state, FileManagerState.ready);
    expect(controller.visibleEntries.map((e) => e.name), ['src', 'main.py']);
  });

  test('falls back to default work directory when configured path missing',
      () async {
    final bridge = _FakeBridge(directories: {
      '/storage/emulated/0/Download/PythonRunner': [],
    });
    final controller = _controller(
      bridge,
      configuredWorkingDir: '/missing',
      workingDirAccessible: false,
    );

    await controller.loadInitial();

    expect(
      controller.location.path,
      '/storage/emulated/0/Download/PythonRunner',
    );
  });

  test('enter directory navigates and goUp returns to parent', () async {
    final bridge = _FakeBridge(directories: {
      '/work': [_dir('/work/src')],
      '/work/src': [_file('/work/src/a.py')],
    });
    final controller = _controller(bridge, configuredWorkingDir: '/work');

    await controller.loadInitial();
    await controller.enterDirectory(_dir('/work/src'));
    expect(controller.location.path, '/work/src');
    expect(controller.visibleEntries.single.name, 'a.py');

    await controller.goUp();
    expect(controller.location.path, '/work');
  });

  test('goUp at the working directory root does not escape the mode',
      () async {
    final bridge = _FakeBridge(directories: {
      '/work': [],
    });
    final controller = _controller(bridge, configuredWorkingDir: '/work');

    await controller.loadInitial();
    await controller.goUp();

    expect(controller.location.path, '/work');
  });

  test('switches from a work child to root and back to work root', () async {
    final bridge = _FakeBridge(directories: {
      '/work': [_dir('/work/src')],
      '/work/src': [],
      '/': [_dir('/system'), _dir('/storage')],
    });
    final controller = _controller(
      bridge,
      configuredWorkingDir: '/work',
      appDataRoots: [
        _namedDir('/data/user/0/com.daozhang.py', 'data'),
        _namedDir(
          '/storage/emulated/0/Android/data/com.daozhang.py',
          'android_data',
        ),
      ],
    );

    await controller.loadInitial();
    await controller.enterDirectory(_dir('/work/src'));

    await controller.switchMode(FileManagerLocationMode.root);
    expect(controller.location.path, '/');
    expect(controller.location.mode, FileManagerLocationMode.root);
    // App data entries are pinned to the top (alphabetical within the rank),
    // then filesystem directories.
    expect(controller.visibleEntries.map((e) => e.name), [
      'android_data',
      'data',
      'storage',
      'system',
    ]);

    await controller.switchMode(FileManagerLocationMode.workingDirectory);
    expect(controller.location.path, '/work');
    expect(controller.location.mode, FileManagerLocationMode.workingDirectory);
  });

  test('app data root entries are not mutable from the root listing',
      () async {
    final bridge = _FakeBridge(directories: {
      '/': [],
    });
    final controller = _controller(
      bridge,
      configuredWorkingDir: '/work',
      appDataRoots: [_namedDir('/data/user/0/com.daozhang.py', 'data')],
    );

    await controller.loadInitial();
    await controller.switchMode(FileManagerLocationMode.root);

    final appDataEntry = controller.visibleEntries.single;
    expect(appDataEntry.name, 'data');
    expect(controller.canMutate(appDataEntry), isFalse);
  });

  test('root mode with empty filesystem still shows app data entries',
      () async {
    final bridge = _FakeBridge(directories: {
      '/': [],
    });
    final controller = _controller(
      bridge,
      configuredWorkingDir: '/work',
      appDataRoots: [
        _namedDir('/data/user/0/com.daozhang.py', 'data'),
        _namedDir('/storage/emulated/0/Android/data/com.daozhang.py',
            'android_data'),
        _namedDir('/storage/emulated/0/Android/obb/com.daozhang.py',
            'android_obb'),
      ],
    );

    await controller.loadInitial();
    await controller.switchMode(FileManagerLocationMode.root);

    expect(controller.state, FileManagerState.ready);
    expect(controller.visibleEntries.map((e) => e.name), [
      'android_data',
      'android_obb',
      'data',
    ]);
  });

  test('navigating into app data keeps root mode and back returns to /',
      () async {
    final bridge = _FakeBridge(directories: {
      '/data/user/0/com.daozhang.py': [_dir('/data/user/0/com.daozhang.py/files')],
    });
    final controller = _controller(
      bridge,
      configuredWorkingDir: '/work',
      appDataRoots: [_namedDir('/data/user/0/com.daozhang.py', 'data')],
    );

    await controller.loadInitial();
    await controller.switchMode(FileManagerLocationMode.root);
    await controller.enterDirectory(controller.visibleEntries.single);

    expect(controller.location.mode, FileManagerLocationMode.root);
    expect(controller.location.path, '/data/user/0/com.daozhang.py');
    expect(controller.location.isRoot, isTrue);
    expect(controller.canGoUp, isTrue);

    await controller.goUp();
    expect(controller.location.path, '/data/user/0');
    expect(controller.location.mode, FileManagerLocationMode.root);

    // Walk back up to /; there goUp is a no-op and the back gesture exits.
    for (var i = 0; i < 5 && controller.canGoUp; i++) {
      await controller.goUp();
    }
    expect(controller.location.path, '/');
    expect(controller.canGoUp, isFalse);
  });

  test('app data entries dedupe against filesystem listing', () async {
    final bridge = _FakeBridge(directories: {
      '/': [_namedDir('/data/user/0/com.daozhang.py', 'data')],
    });
    final controller = _controller(
      bridge,
      configuredWorkingDir: '/work',
      appDataRoots: [_namedDir('/data/user/0/com.daozhang.py', 'data')],
    );

    await controller.loadInitial();
    await controller.switchMode(FileManagerLocationMode.root);

    expect(controller.visibleEntries, hasLength(1));
  });

  test('search filters visible entries by name only', () async {
    final bridge = _FakeBridge(directories: {
      '/work': [_file('/work/alpha.py'), _file('/work/beta.txt')],
    });
    final controller = _controller(bridge, configuredWorkingDir: '/work');

    await controller.loadInitial();
    controller.setSearchQuery('ALPHA');
    expect(controller.visibleEntries.single.name, 'alpha.py');
    controller.setSearchQuery('');
    expect(controller.visibleEntries, hasLength(2));
  });

  test('create directory refreshes the listing after success', () async {
    final bridge = _FakeBridge(directories: {
      '/work': [],
    });
    final controller = _controller(bridge, configuredWorkingDir: '/work');

    await controller.loadInitial();
    await controller.createDirectory('build');

    expect(bridge.created, ['/work/build']);
    expect(
      controller.visibleEntries.map((e) => e.name),
      contains('build'),
    );
  });

  test('keeps old entries when delete fails', () async {
    final bridge = _FakeBridge(directories: {
      '/work': [_file('/work/locked')],
    });
    bridge.deleteError = const FileManagerError(
      code: FileManagerErrorCode.notEmpty,
      message: '目录非空',
    );
    final controller = _controller(bridge, configuredWorkingDir: '/work');

    await controller.loadInitial();
    await expectLater(
      controller.deleteEntry(_file('/work/locked')),
      throwsA(isA<FileManagerError>()),
    );
    expect(controller.visibleEntries.any((e) => e.name == 'locked'), isTrue);
  });

  test('rename refreshes the listing after success', () async {
    final bridge = _FakeBridge(directories: {
      '/work': [_file('/work/old.py')],
    });
    final controller = _controller(bridge, configuredWorkingDir: '/work');

    await controller.loadInitial();
    await controller.renameEntry(_file('/work/old.py'), 'new.py');

    expect(bridge.renamed, ['/work/old.py->new.py']);
    expect(
      controller.visibleEntries.map((e) => e.name),
      contains('new.py'),
    );
  });

  test('list error surfaces retryable error state', () async {
    final bridge = _FakeBridge();
    bridge.listError = const FileManagerError(
      code: FileManagerErrorCode.permissionDenied,
      message: '无权限访问此目录',
    );
    final controller = _controller(bridge, configuredWorkingDir: '/work');

    await controller.loadInitial();
    expect(controller.state, FileManagerState.error);
    expect(controller.errorMessage, '无权限访问此目录');

    bridge.listError = null;
    bridge.directories['/work'] = [_file('/work/main.py')];
    await controller.retry();
    expect(controller.state, FileManagerState.ready);
    expect(controller.visibleEntries.single.name, 'main.py');
  });

  test('can still switch to root after working directory error', () async {
    final bridge = _FakeBridge(directories: {
      '/': [_dir('/storage')],
    });
    bridge.listError = const FileManagerError(
      code: FileManagerErrorCode.permissionDenied,
      message: '无权限访问此目录',
    );
    final controller = _controller(bridge, configuredWorkingDir: '/work');

    await controller.loadInitial();
    expect(controller.state, FileManagerState.error);

    bridge.listError = null;
    await controller.switchMode(FileManagerLocationMode.root);
    expect(controller.location.path, '/');
    expect(controller.state, FileManagerState.ready);
  });

  test('read text preview decodes bytes and rejects directories', () async {
    final bridge = _FakeBridge(
      directories: {
        '/work': [_dir('/work/sub'), _file('/work/main.py')],
      },
      files: {
        '/work/main.py': utf8.encode('print("你好")'),
      },
    );
    final controller = _controller(bridge, configuredWorkingDir: '/work');

    await controller.loadInitial();

    expect(
      await controller.readTextPreview(_file('/work/main.py')),
      'print("你好")',
    );
    expect(
      () => controller.readTextPreview(_dir('/work/sub')),
      throwsA(isA<FileManagerError>()),
    );
  });

  test('stale directory load results are ignored after navigation',
      () async {
    final bridge = _FakeBridge(directories: {
      '/work': [_dir('/work/a')],
      '/work/a': [_file('/work/a/1.py')],
      '/work/b': [_file('/work/b/2.py')],
    });
    final controller = _controller(bridge, configuredWorkingDir: '/work');
    await controller.loadInitial();

    // Hold /work/a in flight; the faster /work/b must win.
    final stale = Completer<List<AppFileEntry>>();
    bridge.pendingList['/work/a'] = stale;
    final slowEnter = controller.enterDirectory(_dir('/work/a'));
    await controller.enterDirectory(_dir('/work/b'));
    expect(controller.location.path, '/work/b');

    stale.complete([_file('/work/a/1.py')]);
    await slowEnter;
    await Future<void>.delayed(Duration.zero);

    expect(controller.location.path, '/work/b');
    expect(controller.visibleEntries.single.name, '2.py');
  });
}
