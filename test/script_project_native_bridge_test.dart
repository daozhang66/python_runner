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

  test('native bridge exposes linux-like requirements install arguments',
      () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'installLinuxLikeRequirements') {
        return true;
      }
      throw PlatformException(code: 'missing', message: call.method);
    });

    final bridge = NativeBridge();
    await bridge.installLinuxLikeRequirements(
      projectKey: 'project_1',
      requirementsPath: 'requirements.txt',
      content: 'requests==2.32.0',
      displayName: 'requirements.txt',
      indexUrl: 'https://example.invalid/simple',
    );

    expect(calls.single.method, 'installLinuxLikeRequirements');
    expect(calls.single.arguments, {
      'projectKey': 'project_1',
      'requirementsPath': 'requirements.txt',
      'content': 'requests==2.32.0',
      'displayName': 'requirements.txt',
      'indexUrl': 'https://example.invalid/simple',
    });
  });

  test('native bridge exposes app file picker directory APIs', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getFilePickerRoots':
          return [
            {
              'path': '/downloads',
              'name': '下载',
              'isDirectory': true,
              'size': 0,
              'modifiedAt': 1000,
            }
          ];
        case 'listFilePickerDirectory':
          return [
            {
              'path': '/downloads/demo.py',
              'name': 'demo.py',
              'isDirectory': false,
              'size': 12,
              'modifiedAt': 1000,
            }
          ];
        case 'openFilePickerTree':
          return {
            'path': 'content://tree/downloads',
            'name': '授权目录',
            'isDirectory': true,
            'size': 0,
            'modifiedAt': 1000,
          };
        case 'readFilePickerFile':
          return Uint8List.fromList([112, 114, 105, 110, 116]);
      }
      throw PlatformException(code: 'missing', message: call.method);
    });

    final bridge = NativeBridge();
    expect((await bridge.getFilePickerRoots()).single.name, '下载');
    expect(
      (await bridge.listFilePickerDirectory('/downloads')).single.path,
      '/downloads/demo.py',
    );
    expect(
        (await bridge.openFilePickerTree())?.path, 'content://tree/downloads');
    expect(
        await bridge.readFilePickerFile('content://file/demo.py'), isNotEmpty);

    expect(calls.map((call) => call.method), [
      'getFilePickerRoots',
      'listFilePickerDirectory',
      'openFilePickerTree',
      'readFilePickerFile',
    ]);
    expect(calls[1].arguments, {'path': '/downloads'});
    expect(calls[2].arguments, {'title': '选择目录'});
    expect(calls[3].arguments, {'path': 'content://file/demo.py'});
  });
}
