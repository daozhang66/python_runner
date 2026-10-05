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
  @override
  Future<List<ScriptProjectFile>> listProjectFiles(String key) async {
    loads++;
    return [
      ScriptProjectFile(
        path: 'main.py',
        name: 'main.py',
        isDirectory: false,
        size: 1,
        modifiedAt: DateTime.utc(2026),
      ),
    ];
  }

  @override
  Future<String> readProjectFile(String key, String path) async => content;
}

void main() {
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
