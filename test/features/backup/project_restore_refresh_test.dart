import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/models/script_project_file.dart';
import 'package:python_runner/providers/script_project_provider.dart';
import 'package:python_runner/services/native_bridge.dart';
import 'package:python_runner/services/script_project_service.dart';

import 'restore_planner_test.dart' show localGroup;

class ProjectFiles extends NativeBridge {
  ProjectFiles() : super.named();
  String content = 'before';
  int loads = 0;
  int reads = 0;
  Completer<String>? nextRead;
  final paths = ['main.py'];
  final contents = <String, String>{};
  @override
  Future<List<ScriptProjectFile>> listProjectFiles(String key) async {
    loads++;
    return [
      for (final path in paths)
        ScriptProjectFile(
          path: path,
          name: path,
          isDirectory: false,
          size: 1,
          modifiedAt: DateTime.utc(2026),
        ),
    ];
  }

  @override
  Future<String> readProjectFile(String key, String path) async {
    reads++;
    final delayed = nextRead;
    nextRead = null;
    return delayed == null ? contents[path] ?? content : await delayed.future;
  }
}

void main() {
  test(
    'unrelated dirty project keeps its buffer, selection and error state',
    () async {
      final bridge = ProjectFiles();
      final group = localGroup(7, 'Unrelated', project: true, key: 'unrelated');
      final project = ScriptProjectProvider(
        group: group,
        service: ScriptProjectService(bridge),
      );
      addTearDown(project.dispose);
      await project.load();
      await project.selectFile('main.py');
      project.updateContent('unsaved unrelated');
      await project.selectFile('missing.py');
      final error = project.error;
      await ScriptProjectProvider.refreshAfterRestore([
        localGroup(8, 'Replaced', project: true, key: 'replaced'),
      ]);
      expect(project.content, 'unsaved unrelated');
      expect(project.dirty, true);
      expect(project.selectedPath, 'main.py');
      expect(project.error, error);
      expect(bridge.loads, 1);
    },
  );
  for (final changeSelection in [false, true]) {
    test(
      'delayed restore refresh preserves intervening ${changeSelection ? 'selection' : 'edit'}',
      () async {
        final bridge = ProjectFiles()..paths.add('other.py');
        bridge.contents['other.py'] = 'other file';
        final group = localGroup(7, 'Project', project: true, key: 'local');
        final project = ScriptProjectProvider(
          group: group,
          service: ScriptProjectService(bridge),
        );
        addTearDown(project.dispose);
        await project.load();
        await project.selectFile('main.py');
        final read = Completer<String>();
        bridge.nextRead = read;
        final refresh = ScriptProjectProvider.refreshAfterRestore([
          group.copyWith(mainFilePath: 'main.py'),
        ]);
        while (bridge.reads < 2) {
          await Future<void>.delayed(Duration.zero);
        }
        if (changeSelection) {
          await project.selectFile('other.py');
        } else {
          project.updateContent('new edit');
        }
        read.complete('restored on disk');
        await refresh;
        expect(project.selectedPath, changeSelection ? 'other.py' : 'main.py');
        expect(project.content, changeSelection ? 'other file' : 'new edit');
        expect(project.dirty, !changeSelection);
      },
    );
  }
  test(
    'successful restore reloads open project metadata and selected file',
    () async {
      final bridge = ProjectFiles();
      final group = localGroup(7, 'Project', project: true, key: 'local');
      final project = ScriptProjectProvider(
        group: group,
        service: ScriptProjectService(bridge),
      );
      addTearDown(project.dispose);
      await project.load();
      await project.selectFile('main.py');
      expect(project.content, 'before');
      bridge.content = 'after';
      final restored = group.copyWith(mainFilePath: 'main.py');
      await ScriptProjectProvider.refreshAfterRestore([restored]);
      expect(project.group.mainFilePath, 'main.py');
      expect(project.content, 'after');
      expect(bridge.loads, 2);
    },
  );
}
