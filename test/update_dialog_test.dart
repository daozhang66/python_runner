import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/l10n/app_localizations.dart';
import 'package:python_runner/services/update_service.dart';
import 'package:python_runner/ui/app_liquid_host.dart';
import 'package:python_runner/ui/app_materials.dart';
import 'package:python_runner/ui/app_theme.dart';
import 'package:python_runner/ui/app_visual_style.dart';
import 'package:python_runner/widgets/update_dialog.dart';

void main() {
  for (final visualStyle in AppVisualStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'update dialog shows content and usable actions: $visualStyle $brightness',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(420, 933);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          var updateCalls = 0;
          var ignoreCalls = 0;

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.build(
                ColorScheme.fromSeed(
                  seedColor: Colors.indigo,
                  brightness: brightness,
                ),
                visualStyle: visualStyle,
              ),
              locale: const Locale('zh'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (_, child) => AppLiquidHost(child: child!),
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (dialogContext) => UpdateDialog(
                          updateInfo: AppUpdateInfo(
                            currentVersion: '1.5.9',
                            latestVersion: '1.6.0',
                            tagName: 'v1.6.0',
                            releaseName: '1.6.0',
                            releaseNotes: '修复更新提示显示问题。',
                            htmlUrl: 'https://example.com/release',
                            publishedAt: DateTime(2026, 10, 1),
                            apkAsset: const ReleaseAssetInfo(
                              name: 'python_runner.apk',
                              downloadUrl: 'https://example.com/app.apk',
                              size: 10485760,
                              contentType:
                                  'application/vnd.android.package-archive',
                            ),
                          ),
                          onUpdate: () => updateCalls++,
                          onIgnore: () {
                            ignoreCalls++;
                            Navigator.pop(dialogContext);
                          },
                        ),
                      ),
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('v1.6.0'), findsOneWidget);
          expect(find.text('修复更新提示显示问题。'), findsOneWidget);
          final surface = find
              .descendant(
                of: find.byType(UpdateDialog),
                matching: find.byType(AppGlassSurface),
              )
              .first;
          final rect = tester.getRect(surface);
          expect(rect.width, lessThanOrEqualTo(400));
          expect(
            rect.height,
            lessThan(700),
            reason: 'Short release notes must not fill the screen',
          );
          expect(find.text('立即更新').hitTestable(), findsOneWidget);
          expect(find.text('不再提示').hitTestable(), findsOneWidget);

          await tester.tap(find.text('立即更新'));
          await tester.pumpAndSettle();
          expect(updateCalls, 1);
          await tester.tap(find.text('不再提示'));
          await tester.pumpAndSettle();
          expect(ignoreCalls, 1);
          expect(find.byType(UpdateDialog), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
