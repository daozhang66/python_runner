import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production sources contain no floating ball implementation', () {
    final root = Directory.current.path;
    final manifest = File('$root/android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final releaseManifest =
        File('$root/android/app/src/release/AndroidManifest.xml')
            .readAsStringSync();
    final mainActivity = File(
      '$root/android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt',
    ).readAsStringSync();
    final bridge =
        File('$root/lib/services/native_bridge.dart').readAsStringSync();
    final api =
        File('$root/pigeons/native_runtime_api.dart').readAsStringSync();

    for (final source in [
      manifest,
      releaseManifest,
      mainActivity,
      bridge,
      api
    ]) {
      final normalized = source.toLowerCase();
      expect(normalized, isNot(contains('floatingball')));
      expect(normalized, isNot(contains('floating_ball')));
      expect(normalized, isNot(contains('system_alert_window')));
      expect(normalized, isNot(contains('checkoverlaypermission')));
      expect(normalized, isNot(contains('consumependingrunscript')));
    }

    expect(
      File('$root/android/app/src/main/kotlin/com/daozhang/py/FloatingBallService.kt')
          .existsSync(),
      isFalse,
    );
    expect(
      File('$root/android/app/src/main/kotlin/com/daozhang/py/FloatingBallController.kt')
          .existsSync(),
      isFalse,
    );
  });

  test('about page uses localized sponsor content without a manual', () {
    final root = Directory.current.path;
    final source =
        File('$root/lib/pages/settings_widgets.dart').readAsStringSync();
    final settings =
        File('$root/lib/pages/settings_sections.dart').readAsStringSync();

    expect(source, contains('l10n.technicalArchitecture'));
    expect(source, contains('projectHomepage'));
    expect(source, contains('l10n.sponsorProject'));
    expect(source, contains('IMG_20260802_014149.png'));
    expect(source, isNot(contains('_UserManualPage')));
    expect(source, isNot(contains('openSourceLicense')));
    expect(settings, isNot(contains('RuntimeManagerPage')));
    expect(settings, contains('_buildRuntimeInstallPanel'));
    expect(settings, contains('_showRuntimeInstallDialog'));
    expect(source, contains('class _RuntimeInstallDialog'));
    expect(source, isNot(contains('FloatingBall')));
  });
}
