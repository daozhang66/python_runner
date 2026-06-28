import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/models/script_group.dart';
import 'package:python_runner/models/script_project_file.dart';
import 'package:python_runner/services/native_bridge.dart';
import 'package:python_runner/services/script_project_service.dart';

class FakeProjectBridge extends NativeBridge {
  FakeProjectBridge() : super.named();

  final files = <String, String>{};
  final createdProjects = <String>[];
  final deletedProjects = <String>[];

  @override
  Future<String> createScriptProject(String projectKey) async {
    createdProjects.add(projectKey);
    return '/files/script_projects/$projectKey';
  }

  @override
  Future<bool> deleteScriptProject(String projectKey) async {
    deletedProjects.add(projectKey);
    return true;
  }

  @override
  Future<List<ScriptProjectFile>> listProjectFiles(String projectKey) async {
    return files.keys
        .map((path) => ScriptProjectFile(
              path: path,
              name: path.split('/').last,
              isDirectory: false,
              size: files[path]!.length,
              modifiedAt: DateTime.fromMillisecondsSinceEpoch(1000),
            ))
        .toList();
  }

  @override
  Future<String> readProjectFile(String projectKey, String path) async {
    return files[path] ?? '';
  }

  @override
  Future<bool> saveProjectFile(
      String projectKey, String path, String content) async {
    files[path] = content;
    return true;
  }
}

void main() {
  test('project service creates default main file and validates project groups',
      () async {
    final bridge = FakeProjectBridge();
    final service = ScriptProjectService(bridge);

    final root = await service.createProject('project_1', 'Demo');
    expect(root, '/files/script_projects/project_1');
    expect(bridge.createdProjects, ['project_1']);
    expect(bridge.files['main.py'], contains('Hello from Demo'));

    final group = ScriptGroup(
      id: 1,
      name: 'Demo',
      sortOrder: 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(1000),
      isProject: true,
      projectKey: 'project_1',
      mainFilePath: 'main.py',
    );

    expect((await service.loadProjectFiles(group)).single.path, 'main.py');
    expect(await service.readProjectFile(group, 'main.py'),
        contains('Hello from Demo'));
    expect(
        await service.saveProjectFile(group, 'src/app.py', 'print(1)'), isTrue);
    expect(() => service.requireProjectKey(group.copyWith(isProject: false)),
        throwsStateError);
  });

  test('script provider keeps project metadata separate from project files',
      () {
    final providerSource =
        File('lib/providers/script_provider.dart').readAsStringSync();
    final dbSource =
        File('lib/services/database_service.dart').readAsStringSync();

    expect(providerSource, contains('Future<ScriptGroup?> createProjectGroup'));
    expect(providerSource, contains('Future<bool> updateProjectMainFile'));
    expect(dbSource, contains('Future<void> updateProjectMainFile'));
    expect(providerSource, isNot(contains('readProjectFile(')));
    expect(providerSource, isNot(contains('saveProjectFile(')));
  });

  test('project page exposes linux-like requirements install shortcut', () {
    final source =
        File('lib/pages/script_project_page.dart').readAsStringSync();

    expect(source, contains('_hasRootRequirements'));
    expect(source, contains("file.path == 'requirements.txt'"));
    expect(source, contains("value: 'install_requirements'"));
    expect(source, contains('installRequirementsFromProject'));
    expect(source, contains('_RequirementsInstallDialog'));
    expect(source, contains('_scheduleCloseOnSuccess'));
    expect(source, contains('安装完成，正在刷新库列表'));
    expect(source, contains('Duration(milliseconds: 900)'));
    expect(source, contains('仅 Linux-like 可用'));
  });

  test('project page intercepts back gesture to leave subdirectories first',
      () {
    final source =
        File('lib/pages/script_project_page.dart').readAsStringSync();

    expect(source, contains('PopScope'));
    expect(source, contains('canPop: _currentDirectory.isEmpty'));
    expect(source, contains('onPopInvokedWithResult'));
    expect(source, contains('_goUpDirectory();'));
  });

  test('project console rerun keeps project execution context', () {
    final consoleSource =
        File('lib/pages/run_console_page.dart').readAsStringSync();
    final projectPageSource =
        File('lib/pages/script_project_page.dart').readAsStringSync();
    final projectEditorSource =
        File('lib/pages/project_file_editor_page.dart').readAsStringSync();

    expect(consoleSource, contains('final ScriptGroup? projectGroup;'));
    expect(consoleSource,
        contains('await exec.executeScriptProject(projectGroup);'));
    expect(consoleSource,
        contains('await scriptProvider.markProjectGroupUsed(projectGroup);'));
    expect(consoleSource,
        contains('await exec.executeScript(widget.scriptName);'));
    expect(projectPageSource, contains('projectGroup: project.group'));
    expect(projectEditorSource, contains('projectGroup: widget.group'));
  });
}
