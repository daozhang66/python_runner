import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('script page uses compact app bar actions without large toolbar or FAB',
      () {
    final source = File('lib/pages/script_list_page.dart').readAsStringSync();

    expect(source, contains('_buildScriptTitleBadge(allScripts.length)'));
    expect(source, contains('Widget _buildScriptTitleBadge(int count)'));
    expect(source, contains("const Text('Python'"));
    expect(source, contains('count.toString()'));
    expect(source, contains('BorderRadius.circular(999)'));
    expect(source, contains('_buildScriptMenu()'));
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

  test('script page can mask script names from a small eye button', () {
    final source = File('lib/pages/script_list_page.dart').readAsStringSync();

    expect(source, contains('_maskScriptNames = false'));
    expect(source, contains('_loadScriptNameMaskPreference'));
    expect(source, contains('_toggleScriptNameMask'));
    expect(source, contains('_buildScriptNameVisibilityButton()'));
    expect(source, contains('script_name_mask_enabled'));
    expect(source, contains('Icons.visibility_outlined'));
    expect(source, contains('Icons.visibility_off_outlined'));
    expect(source, contains("'隐藏脚本名'"));
    expect(source, contains("'显示脚本名'"));
    expect(source, contains('_displayScriptName('));
    expect(source, contains("'脚本 '"));
    expect(source, contains('_buildScriptNameVisibilityButton(),'));
    expect(source.indexOf('_buildScriptNameVisibilityButton(),'),
        lessThan(source.indexOf('Icons.settings_outlined')));
  });

  test(
      'app uses edge-to-edge transparent system bars to avoid Android 16 top black strip',
      () {
    final source = File('lib/main.dart').readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/daozhang/py/MainActivity.kt',
    ).readAsStringSync();
    final styles = File(
      'android/app/src/main/res/values/styles.xml',
    ).readAsStringSync();
    final nightStyles = File(
      'android/app/src/main/res/values-night/styles.xml',
    ).readAsStringSync();

    expect(
        source,
        contains(
            'SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)'));
    expect(source, contains('AnnotatedRegion<SystemUiOverlayStyle>'));
    expect(source, contains('statusBarColor: Colors.transparent'));
    expect(source, contains('systemNavigationBarColor: Colors.transparent'));
    expect(activity,
        contains('WindowCompat.setDecorFitsSystemWindows(window, false)'));
    expect(
        styles,
        contains(
            '<item name="android:statusBarColor">@android:color/transparent</item>'));
    expect(
        styles,
        contains(
            '<item name="android:navigationBarColor">@android:color/transparent</item>'));
    expect(
        styles,
        contains(
            '<item name="android:windowDrawsSystemBarBackgrounds">true</item>'));
    expect(
        nightStyles,
        contains(
            '<item name="android:statusBarColor">@android:color/transparent</item>'));
    expect(
        nightStyles,
        contains(
            '<item name="android:navigationBarColor">@android:color/transparent</item>'));
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

    expect(dbSource, contains('version: 4'));
    expect(dbSource, contains('onUpgrade: _onUpgrade'));
    expect(dbSource, contains('isPinned INTEGER DEFAULT 0'));
    expect(dbSource, contains('sortOrder INTEGER DEFAULT 0'));
    expect(dbSource, contains('groupId INTEGER'));
    expect(dbSource, contains('CREATE TABLE script_groups'));
    expect(dbSource, contains('ADD COLUMN isPinned INTEGER DEFAULT 0'));
    expect(dbSource, contains('ADD COLUMN sortOrder INTEGER DEFAULT 0'));
    expect(dbSource, contains('ADD COLUMN groupId INTEGER'));

    expect(providerSource, contains('Future<void> togglePinned'));
    expect(providerSource, contains('isPinned: !current.isPinned'));
    expect(providerSource, contains('b.isPinned ? 1 : 0'));

    expect(pageSource, contains('置顶'));
    expect(pageSource, contains('取消置顶'));
    expect(pageSource, contains('pinned: script.isPinned'));
    expect(pageSource, contains('class _PinnedBadge'));
    expect(pageSource, contains('primaryContainer.withValues(alpha: 0.72)'));
  });

  test('script reordering starts only from handles and never from pinned cards',
      () {
    final pageSource =
        File('lib/pages/script_list_page.dart').readAsStringSync();
    final providerSource =
        File('lib/providers/script_provider.dart').readAsStringSync();

    expect(pageSource, contains('buildDefaultDragHandles: false'));
    expect(pageSource,
        contains('final canDragScript = canDrag && !script.isPinned'));
    expect(pageSource, contains('Draggable<String>'));
    expect(
        pageSource, contains('dragAnchorStrategy: pointerDragAnchorStrategy'));
    expect(pageSource, contains('feedbackOffset: const Offset(90, 62.5)'));
    expect(pageSource, contains('DragTarget<String>'));
    expect(pageSource, contains('onMove: (details)'));
    expect(pageSource, contains('ReorderableBuilder('));
    expect(pageSource, contains('enableDraggable: false'));
    expect(pageSource,
        contains('swapScriptPositionsByName(draggedName, targetName)'));
    expect(pageSource, isNot(contains('longPressDelay: Duration.zero')));

    expect(providerSource, contains('if (isPinned) return;'));
    expect(providerSource, contains('Future<void> swapScriptPositions'));
    expect(providerSource, contains('Future<void> swapScriptPositionsByName'));
    expect(
        providerSource,
        contains(
            'if (_scripts[oldIndex].isPinned || _scripts[newIndex].isPinned) return;'));
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

  test('animation iteration uses centralized transitions and smooth status',
      () {
    final transitions =
        File('lib/utils/app_page_transitions.dart').readAsStringSync();
    final listPage = File('lib/pages/script_list_page.dart').readAsStringSync();
    final editorPage =
        File('lib/pages/script_editor_page.dart').readAsStringSync();
    final consolePage =
        File('lib/pages/run_console_page.dart').readAsStringSync();
    final terminalView =
        File('lib/widgets/terminal_view.dart').readAsStringSync();
    final mainSource = File('lib/main.dart').readAsStringSync();

    expect(transitions, contains('class AppPageTransitions'));
    expect(transitions, contains('fadeThrough'));
    expect(transitions, contains('sharedAxisLeftRight'));
    expect(transitions, contains('scaleIn'));

    expect(listPage, contains('AppPageTransitions.sharedAxisLeftRight'));
    expect(listPage, contains('AppPageTransitions.fadeThrough'));
    expect(editorPage, contains('AppPageTransitions.scaleIn'));
    expect(consolePage, contains('AnimatedSwitcher'));
    expect(terminalView, contains('_scrollController.animateTo'));
    expect(mainSource, isNot(contains('_fadeOut')));
    expect(mainSource, contains("ValueKey('splash')"));
    expect(mainSource, contains("ValueKey('home')"));
  });

  test('splash page shows Python tagline with a polished background', () {
    final mainSource = File('lib/main.dart').readAsStringSync();

    expect(mainSource, contains("'人生苦短，我用 Python'"));
    expect(mainSource, contains('LinearGradient('));
    expect(mainSource, contains('_buildSplashContent'));
    expect(mainSource, contains('_buildSplashText'));
    expect(mainSource, contains('onSurfaceVariant'));
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
