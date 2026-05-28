import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('script page uses compact app bar actions without large toolbar or FAB',
      () {
    final source = File('lib/pages/script_list_page.dart').readAsStringSync();

    expect(
        source, contains('title: _buildScriptTitleBadge(allScripts.length)'));
    expect(source, contains('Widget _buildScriptTitleBadge(int count)'));
    expect(source, contains('count.toString()'));
    expect(source, contains('BorderRadius.circular(999)'));
    expect(source, contains('actions: [_buildScriptMenu()]'));
    expect(source, contains('PopupMenuButton<String>'));
    expect(source, contains("case 'add':"));
    expect(source, contains("case 'search':"));
    expect(source, contains("case 'toggle_view':"));
    expect(source, contains("case 'select':"));
    expect(source, contains('void _showAddScriptOptions()'));
    expect(source, contains('新建脚本'));
    expect(source, contains('导入脚本'));
    expect(source, contains('Widget _buildSearchResultBar('));
    expect(source, isNot(contains('Widget _buildScriptToolbar(')));
    expect(source, isNot(contains('FilledButton.tonalIcon')));
    expect(source, isNot(contains('SegmentedButton<bool>')));
    expect(
        source, isNot(contains('floatingActionButton: FloatingActionButton')));
    expect(source, isNot(contains('_searchVisible')));
  });

  test('scripts support pinning with persistent order and highlighted cards',
      () {
    final pageSource =
        File('lib/pages/script_list_page.dart').readAsStringSync();
    final providerSource =
        File('lib/providers/script_provider.dart').readAsStringSync();
    final modelSource = File('lib/models/script_file.dart').readAsStringSync();
    final dbSource =
        File('lib/services/database_service.dart').readAsStringSync();

    expect(modelSource, contains('final bool isPinned;'));
    expect(modelSource, contains('this.isPinned = false'));
    expect(modelSource, contains("'isPinned': isPinned ? 1 : 0"));
    expect(
        modelSource, contains("isPinned: (map['isPinned'] as int? ?? 0) == 1"));

    expect(dbSource, contains('version: 2'));
    expect(dbSource, contains('onUpgrade: _onUpgrade'));
    expect(dbSource, contains('isPinned INTEGER DEFAULT 0'));
    expect(dbSource, contains('ADD COLUMN isPinned INTEGER DEFAULT 0'));

    expect(providerSource, contains('Future<void> togglePinned'));
    expect(providerSource, contains('isPinned: !current.isPinned'));
    expect(providerSource, contains('b.isPinned ? 1 : 0'));

    expect(pageSource, contains('置顶'));
    expect(pageSource, contains('取消置顶'));
    expect(pageSource, contains('pinned: script.isPinned'));
    expect(pageSource, contains('class _PinnedBadge'));
    expect(pageSource, contains('primaryContainer.withValues(alpha: 0.72)'));
  });

  test('script cards use unified Material style with modest quick run button',
      () {
    final source = File('lib/pages/script_list_page.dart').readAsStringSync();

    expect(source, contains('class _ScriptIcon'));
    expect(source, contains('class _ScriptMetaChip'));
    expect(source, contains('class _QuickRunButton'));
    expect(source, contains('colors.outlineVariant.withValues(alpha: 0.7)'));
    expect(source, contains('SizedBox.square('));
    expect(source, contains('dimension: 34'));
    expect(source, contains('size: 20'));
    expect(source, contains('maxLines: 2'));
    expect(source, isNot(contains('dimension: 40')));
    expect(source, isNot(contains('width: 28')));
  });

  test('app theme supports optional Material You dynamic color', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final settingsSource =
        File('lib/pages/settings_page.dart').readAsStringSync();
    final pubspecSource = File('pubspec.yaml').readAsStringSync();

    expect(pubspecSource, contains('dynamic_color:'));
    expect(mainSource,
        contains("import 'package:dynamic_color/dynamic_color.dart';"));
    expect(mainSource, contains('DynamicColorBuilder'));
    expect(mainSource, contains('_materialYouEnabled'));
    expect(mainSource, contains("prefs.getBool('material_you_enabled')"));
    expect(mainSource, contains('onMaterialYouChanged'));
    expect(settingsSource, contains('Material You'));
    expect(settingsSource, contains('widget.currentMaterialYouEnabled'));
  });

  test(
      'graphics engine and scene support are fully removed from user-visible and runtime layers',
      () {
    final settingsSource =
        File('lib/pages/settings_page.dart').readAsStringSync();
    final executionSource =
        File('lib/providers/execution_provider.dart').readAsStringSync();
    final bridgeSource =
        File('lib/services/native_bridge.dart').readAsStringSync();
    final activitySource =
        File('android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt')
            .readAsStringSync();
    final runnerSource =
        File('android/app/src/main/python/script_runner.py').readAsStringSync();

    for (final source in [
      settingsSource,
      executionSource,
      bridgeSource,
      activitySource,
      runnerSource,
    ]) {
      expect(source, isNot(contains('graphics_engine_enabled')));
      expect(source, isNot(contains('sendSceneTouch')));
      expect(source, isNot(contains('__scene_')));
      expect(source, isNot(contains('provide_touch')));
      expect(source, isNot(contains('_touch_queue')));
    }

    expect(executionSource, isNot(contains('sceneActive')));
    expect(executionSource, isNot(contains('currentSceneFrame')));
  });
}
