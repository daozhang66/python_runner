import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart' as legacy;
import 'package:python_runner/features/packages/application/package_repository.dart';
import 'package:python_runner/features/scripts/presentation/pages/script_project_page.dart';
import 'package:python_runner/l10n/app_localizations.dart';
import 'package:python_runner/models/script_group.dart';
import 'package:python_runner/providers/script_project_provider.dart';
import 'package:python_runner/ui/app_liquid_host.dart';
import 'package:python_runner/ui/app_theme.dart';
import 'package:python_runner/ui/app_visual_style.dart';

import 'support/package_test_helper.dart';

Future<List<int>> backgroundPixels(
  WidgetTester tester,
  GlobalKey shot,
  List<Offset> points,
) async {
  final boundary =
      shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
  try {
    final data = await tester.runAsync(
      () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    return [
      for (final point in points)
        data!.getUint32(
          (point.dy.floor() * image!.width + point.dx.floor()) * 4,
        ),
    ];
  } finally {
    image!.dispose();
  }
}

void main() {
  const channel = MethodChannel('com.daozhang.py/native_bridge');
  for (final style in AppVisualStyle.values) {
    testWidgets(
      'new project file has no persistent ink rectangle while scrolling: ${style.name}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 700);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final files = {
          'main.py': 'print(1)',
          for (var i = 0; i < 30; i++) 'z_$i.py': '',
        };
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'listProjectFiles':
              return [
                for (final path in files.keys)
                  {
                    'path': path,
                    'name': path,
                    'isDirectory': false,
                    'size': files[path]!.length,
                    'modifiedAt': 1000,
                  },
              ];
            case 'readProjectFile':
              return files[call.arguments['path']] ?? '';
            case 'saveProjectFile':
              files[call.arguments['path'] as String] =
                  call.arguments['content'] as String;
              return true;
          }
          throw StateError('Unexpected method ${call.method}');
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        final shot = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              packageRepositoryProvider.overrideWithValue(
                FakePackageRepository(),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.build(
                ColorScheme.fromSeed(
                  seedColor: Colors.blue,
                  brightness: Brightness.dark,
                ),
                visualStyle: style,
              ),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (_, child) => RepaintBoundary(
                key: shot,
                child: AppLiquidHost(child: child!),
              ),
              home: ScriptProjectPage(
                group: ScriptGroup(
                  id: 1,
                  name: 'Test',
                  sortOrder: 0,
                  createdAt: DateTime(2026),
                  modifiedAt: DateTime(2026),
                  isProject: true,
                  projectKey: 'test',
                  mainFilePath: 'main.py',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final project = legacy.Provider.of<ScriptProjectProvider>(
          tester.element(find.text('main.py')),
          listen: false,
        );
        expect(await tester.runAsync(() => project.createFile('a.py')), true);
        await tester.pumpAndSettle();
        Future<void> checkBackground() async {
          final row = tester.getRect(
            find.ancestor(
              of: find.text('a.py'),
              matching: find.byType(ListTile),
            ),
          );
          final mainRow = tester.getRect(
            find.ancestor(
              of: find.text('main.py'),
              matching: find.byType(ListTile),
            ),
          );
          final pixels = await backgroundPixels(tester, shot, [
            Offset(8, row.center.dy),
            Offset(8, mainRow.center.dy),
          ]);
          expect(
            pixels[0],
            pixels[1],
            reason: 'Creating a file must not leave an editor-selection fill on the browser row',
          );
        }

        await checkBackground();
        await tester.drag(find.byType(ListView), const Offset(0, -300));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, 500));
        await tester.pumpAndSettle();
        await checkBackground();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
