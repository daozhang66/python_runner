import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/services/native_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.daozhang.py/native_bridge');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('native bridge exposes project file APIs with safe argument shape',
      () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'createScriptProject':
          return {'path': '/files/script_projects/project_1'};
        case 'listProjectFiles':
          return [
            {
              'path': 'main.py',
              'name': 'main.py',
              'isDirectory': false,
              'size': 12,
              'modifiedAt': 1000,
            }
          ];
        case 'readProjectFile':
          return 'print("ok")';
        case 'saveProjectFile':
        case 'createProjectDirectory':
        case 'deleteProjectEntry':
        case 'renameProjectEntry':
        case 'deleteScriptProject':
          return true;
      }
      throw PlatformException(code: 'missing', message: call.method);
    });

    final bridge = NativeBridge();

    expect(await bridge.createScriptProject('project_1'),
        '/files/script_projects/project_1');
    expect((await bridge.listProjectFiles('project_1')).single.path, 'main.py');
    expect(await bridge.readProjectFile('project_1', 'main.py'), 'print("ok")');
    expect(await bridge.saveProjectFile('project_1', 'main.py', 'x'), isTrue);
    expect(await bridge.createProjectDirectory('project_1', 'src'), isTrue);
    expect(await bridge.deleteProjectEntry('project_1', 'src/old.py'), isTrue);
    expect(
        await bridge.renameProjectEntry('project_1', 'a.py', 'b.py'), isTrue);
    expect(await bridge.deleteScriptProject('project_1'), isTrue);

    expect(calls.map((c) => c.method), [
      'createScriptProject',
      'listProjectFiles',
      'readProjectFile',
      'saveProjectFile',
      'createProjectDirectory',
      'deleteProjectEntry',
      'renameProjectEntry',
      'deleteScriptProject',
    ]);
    expect(calls.first.arguments, {'projectKey': 'project_1'});
  });
}
