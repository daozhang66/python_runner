import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/backup/presentation/backup_preview_page.dart';
import 'package:python_runner/features/backup/presentation/backup_restore_page.dart';
import 'package:python_runner/providers/theme_provider.dart';

import 'backup_presentation_test.dart' show BackupUiFixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in {
      'MiSans': 'assets/fonts/MiSansVF.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final loader = FontLoader(font.key)..addFont(rootBundle.load(font.value));
      await loader.load();
    }
  });
  late BackupUiFixture f;
  setUp(() async {
    f = BackupUiFixture();
    await f.setUp();
  });
  tearDown(() async {
    await f.dispose();
  });
  for (final style in AppVisualStyle.values) {
    for (final brightness in Brightness.values) {
      for (final preview in [false, true]) {
        final name =
            'backup_${preview ? 'preview' : 'main'}_${style.name}_${brightness.name}';
        testWidgets(name, (tester) async {
          if (preview) await tester.runAsync(f.controller.pickAndStageLocal);
          await f.pump(
            tester,
            page: preview
                ? const BackupPreviewPage()
                : const BackupRestorePage(),
            style: style,
            brightness: brightness,
            locale: 'zh',
          );
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('../../goldens/$name.png'),
          );
          expect(tester.takeException(), isNull);
        }, tags: const ['golden']);
      }
    }
  }
  for (final locale in ['zh', 'en']) {
    for (final preview in [false, true]) {
      testWidgets('backup ${preview ? 'preview' : 'main'} 320 2x $locale', (
        tester,
      ) async {
        if (preview) await tester.runAsync(f.controller.pickAndStageLocal);
        await f.pump(
          tester,
          page: preview ? const BackupPreviewPage() : const BackupRestorePage(),
          width: 320,
          textScale: 2,
          locale: locale,
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../../goldens/backup_${preview ? 'preview' : 'main'}_320_2x_$locale.png',
          ),
        );
        expect(tester.takeException(), isNull);
      }, tags: const ['golden']);
    }
  }
}
