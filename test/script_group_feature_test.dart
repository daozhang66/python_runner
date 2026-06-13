import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String scriptListSource() => [
      'lib/pages/script_list_page.dart',
      'lib/pages/script_list_actions.dart',
      'lib/pages/script_list_content.dart',
      'lib/pages/script_list_widgets.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');

void main() {
  test('script groups have persisted model and database support', () {
    final groupModel = File('lib/models/script_group.dart');
    final scriptModelSource =
        File('lib/models/script_file.dart').readAsStringSync();
    final dbSource =
        File('lib/services/database_service.dart').readAsStringSync();
    final providerSource =
        File('lib/providers/script_provider.dart').readAsStringSync();

    expect(groupModel.existsSync(), isTrue);
    final groupModelSource = groupModel.readAsStringSync();

    expect(groupModelSource, contains('class ScriptGroup'));
    expect(groupModelSource, contains('final int? id;'));
    expect(groupModelSource, contains('final String name;'));
    expect(groupModelSource, contains('final int sortOrder;'));
    expect(scriptModelSource, contains('final int? groupId;'));
    expect(scriptModelSource, contains("'groupId': groupId"));
    expect(dbSource, contains('schemaVersion = 5'));
    expect(dbSource, contains('CREATE TABLE script_groups'));
    expect(dbSource, contains('projectKey TEXT'));
    expect(dbSource, contains('mainFilePath TEXT'));
    expect(dbSource, contains('isProject INTEGER DEFAULT 0'));
    expect(
        dbSource, contains('ALTER TABLE scripts ADD COLUMN groupId INTEGER'));
    expect(dbSource, contains('Future<List<ScriptGroup>> getAllGroups'));
    expect(dbSource, contains('Future<int> createGroup'));
    expect(dbSource, contains('Future<void> moveScriptsToGroup'));
    expect(providerSource, contains('List<ScriptGroup> _groups'));
    expect(providerSource, contains('Future<bool> createGroup'));
    expect(providerSource, contains('Future<void> moveScriptsToGroup'));
    expect(providerSource, contains('List<ScriptFile> scriptsInGroup'));
    expect(providerSource, contains('List<ScriptFile> get ungroupedScripts'));
  });

  test(
      'script homepage shows folders and ungrouped scripts instead of an ungrouped folder',
      () {
    final source = scriptListSource();

    expect(source, contains("case 'add_group':"));
    expect(source, contains("const Text('添加分组')"));
    expect(source, contains('void _showCreateGroupDialog()'));
    expect(source, contains('Widget _buildFolderHome('));
    expect(source, contains('class _ScriptFolderCard'));
    expect(source, contains('final homeScripts = provider.ungroupedScripts'));
    expect(source, contains('script.groupId == null'));
    expect(source, contains('_openGroup('));
    expect(source, contains('移动到分组'));
    expect(source, contains('移出到首页'));
    expect(source, isNot(contains("const Text('未分组')")));
  });

  test(
      'group detail exposes multi-select and homepage ungrouped scripts stay reorderable',
      () {
    final source = scriptListSource();
    final mainSource = File('lib/main.dart').readAsStringSync();

    expect(source, contains('actions: _activeGroupId == null'));
    expect(source, contains('onPressed: _enterMultiSelect'));
    expect(source, contains('Widget _buildFolderHomeScriptListItem('));
    expect(source, contains('final pinnedScripts ='));
    expect(
        source, contains('visibleScripts.where((script) => script.isPinned)'));
    expect(source, contains('final regularScripts ='));
    expect(
        source, contains('visibleScripts.where((script) => !script.isPinned)'));
    expect(source, contains('final regularGroups ='));
    expect(source, contains('final projectGroups ='));
    expect(source, contains('final recentItems ='));
    expect(source, contains('..sort(_compareHomeRecentItems)'));
    expect(source, contains('final firstFolderIndex = pinnedScripts.length'));
    expect(source, contains('final firstRecentIndex ='));
    expect(source, contains('pinnedScripts.length + regularGroups.length'));
    expect(source, contains('Widget _buildListDragTarget('));
    expect(source, contains('Widget _buildListDragHandle('));
    expect(source, contains('void _commitListDragTarget('));
    expect(source, contains('swapScriptPositionsByName('));
    expect(source, contains('groupId: groupId'));
    expect(source, contains('Widget _buildFolderHomeGridScriptCard('));
    expect(source, contains('Draggable<String>('));
    expect(source, contains('DragTarget<String>('));
    expect(source, contains('class ScriptListPageController'));
    expect(source, contains('bool handleBack()'));
    expect(source, contains('bool _handleBackNavigation()'));
    expect(source, contains('_activeGroupId != null'));
    expect(source, contains('_closeGroup();'));
    expect(mainSource, contains('controller: _scriptListController'));
  });

  test('homepage groups support multi-select management', () {
    final source = scriptListSource();

    expect(source, contains('bool _groupSelectMode'));
    expect(source, contains('final Set<int> _selectedGroupIds'));
    expect(source, contains("value: 'select_groups'"));
    expect(source, contains("title: Text('分组多选')"));
    expect(source, contains('void _enterGroupSelect'));
    expect(source, contains('void _toggleGroupSelection'));
    expect(source, contains('Future<void> _deleteSelectedGroups'));
    expect(source, contains("title: '批量删除分组'"));
    expect(source, contains('selected: _groupSelectMode'));
    expect(source, contains('selected: selected == true'));
    expect(source, contains('Icons.library_add_check_outlined'));
  });

  test('move-to-group sheet is scrollable when there are many groups', () {
    final source = scriptListSource();

    expect(source, contains('isScrollControlled: true'));
    expect(source, contains('DraggableScrollableSheet('));
    expect(source, contains('builder: (context, scrollController)'));
    expect(source, contains('ListView('));
    expect(source, contains('controller: scrollController'));
  });

  test('running grouped scripts promotes them inside their own group', () {
    final providerSource =
        File('lib/providers/script_provider.dart').readAsStringSync();
    final dbSource =
        File('lib/services/database_service.dart').readAsStringSync();

    expect(providerSource, contains('_promoteScriptToFrontInGroup'));
    expect(providerSource, contains('script.groupId'));
    expect(
        providerSource, contains('await _db.batchUpdateSortOrders(updates)'));
    expect(dbSource,
        contains('UPDATE scripts SET runCount = runCount + 1, modifiedAt = ?'));
  });
}
