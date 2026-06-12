import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android Gradle and Kotlin plugin versions are centralized and current',
      () {
    final gradleProperties =
        File('android/gradle.properties').readAsStringSync();
    final settingsGradle = File('android/settings.gradle').readAsStringSync();
    final rootBuildGradle = File('android/build.gradle').readAsStringSync();
    final appBuildGradle = File('android/app/build.gradle').readAsStringSync();
    final androidGradleFiles = [settingsGradle, rootBuildGradle].join('\n');

    expect(gradleProperties, contains('androidAgpVersion=8.11.1'));
    expect(gradleProperties, contains('kotlinGradlePluginVersion=2.2.20'));
    expect(gradleProperties, contains('kotlin.incremental=false'));
    expect(gradleProperties, contains('android.builtInKotlin=true'));
    expect(gradleProperties, contains('android.newDsl=true'));
    expect(settingsGradle, contains('androidAgpVersion'));
    expect(settingsGradle, contains('kotlinGradlePluginVersion'));
    expect(rootBuildGradle, contains(r'${androidAgpVersion}'));
    expect(rootBuildGradle, contains(r'${kotlinGradlePluginVersion}'));
    expect(appBuildGradle, isNot(contains('id "kotlin-android"')));

    expect(androidGradleFiles, isNot(contains('8.9.3')));
    expect(androidGradleFiles, isNot(contains('2.1.10')));
  });
}
