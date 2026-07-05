import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:python_runner/models/app_file_entry.dart';
import 'package:python_runner/pages/app_file_picker_page.dart';
import 'package:python_runner/pigeon/native_runtime_api.g.dart' as pigeon;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const listDirectoryChannel = BasicMessageChannel<Object?>(
    'dev.flutter.pigeon.python_runner.FilePickerHostApi.listFilePickerDirectory',
    pigeon.FilePickerHostApi.pigeonChannelCodec,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(listDirectoryChannel, null);
  });

  void setListDirectoryHandler(
    List<Map<String, Object>> Function(String path) handler,
  ) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(listDirectoryChannel,
            (message) async {
      final path = ((message as List<Object?>).single) as String;
      return <Object?>[
        handler(path).map(_nativeAppFileEntryFromMap).toList(),
      ];
    });
  }

  testWidgets('app file picker filters files by extension', (tester) async {
    setListDirectoryHandler((path) {
      expect(path, '/storage/emulated/0');
      return [
        {
          'path': '/storage/emulated/0/demo.py',
          'name': 'demo.py',
          'isDirectory': false,
          'size': 12,
          'modifiedAt': 1000,
        },
        {
          'path': '/storage/emulated/0/readme.txt',
          'name': 'readme.txt',
          'isDirectory': false,
          'size': 20,
          'modifiedAt': 1000,
        },
        {
          'path': '/storage/emulated/0/src',
          'name': 'src',
          'isDirectory': true,
          'size': 0,
          'modifiedAt': 1000,
        },
      ];
    });

    AppFilePickResult? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                picked = await AppFilePickerPage.pickFile(
                  context,
                  title: '导入脚本',
                  allowedExtensions: const ['py'],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('demo.py'), findsOneWidget);
    expect(find.text('src'), findsOneWidget);
    expect(find.text('readme.txt'), findsNothing);

    await tester.tap(find.text('demo.py'));
    await tester.pumpAndSettle();
    expect(picked?.path, '/storage/emulated/0/demo.py');
    expect(picked?.name, 'demo.py');
  });

  testWidgets('app file picker navigates to parent directories',
      (tester) async {
    setListDirectoryHandler((path) {
      if (path == '/storage/emulated/0') {
        return [
          {
            'path': '/storage/emulated/0/src',
            'name': 'src',
            'isDirectory': true,
            'size': 0,
            'modifiedAt': 1000,
          }
        ];
      }
      if (path == '/storage/emulated/0/src') {
        return [
          {
            'path': '/storage/emulated/0/src/demo.py',
            'name': 'demo.py',
            'isDirectory': false,
            'size': 12,
            'modifiedAt': 1000,
          }
        ];
      }
      fail('Unexpected path: $path');
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () {
                AppFilePickerPage.pickFile(
                  context,
                  title: '导入脚本',
                  allowedExtensions: const ['py'],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('src'));
    await tester.pumpAndSettle();
    expect(find.text('demo.py'), findsOneWidget);

    await tester.tap(find.byTooltip('上一级'));
    await tester.pumpAndSettle();
    expect(find.text('src'), findsOneWidget);
    expect(find.text('demo.py'), findsNothing);
  });

  testWidgets('app file picker remembers last selected directory',
      (tester) async {
    var firstOpen = true;
    final listedPaths = <String>[];
    setListDirectoryHandler((path) {
      listedPaths.add(path);
      if (path == '/storage/emulated/0') {
        return [
          {
            'path': '/storage/emulated/0/Download',
            'name': 'Download',
            'isDirectory': true,
            'size': 0,
            'modifiedAt': 1000,
          }
        ];
      }
      if (path == '/storage/emulated/0/Download') {
        return [
          {
            'path': '/storage/emulated/0/Download/demo.py',
            'name': firstOpen ? 'demo.py' : 'second.py',
            'isDirectory': false,
            'size': 12,
            'modifiedAt': 1000,
          }
        ];
      }
      fail('Unexpected path: $path');
    });

    Future<void> openPicker() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  AppFilePickerPage.pickFile(
                    context,
                    title: '导入脚本',
                    allowedExtensions: const ['py'],
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    await openPicker();
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('demo.py'));
    await tester.pumpAndSettle();

    firstOpen = false;
    await openPicker();
    await tester.pumpAndSettle();
    expect(find.text('second.py'), findsOneWidget);
    expect(listedPaths.last, '/storage/emulated/0/Download');
  });
}

pigeon.NativeAppFileEntry _nativeAppFileEntryFromMap(
  Map<String, Object> map,
) {
  return pigeon.NativeAppFileEntry(
    path: map['path']! as String,
    name: map['name']! as String,
    isDirectory: map['isDirectory']! as bool,
    size: map['size']! as int,
    modifiedAtMillis: map['modifiedAt']! as int,
  );
}
