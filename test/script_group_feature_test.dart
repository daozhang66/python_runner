import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
    expect(dbSource, contains('version: 4'));
    expect(dbSource, contains('CREATE TABLE script_groups'));
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
    final source = File('lib/pages/script_list_page.dart').readAsStringSync();

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
      'group detail hides menu and homepage ungrouped scripts stay reorderable',
      () {
    final source = File('lib/pages/script_list_page.dart').readAsStringSync();
    final mainSource = File('lib/main.dart').readAsStringSync();

    expect(source, contains('actions: _activeGroupId == null'));
    expect(source, contains('Widget _buildFolderHomeScriptListItem('));
    expect(source, contains('final pinnedScripts ='));
    expect(
        source, contains('visibleScripts.where((script) => script.isPinned)'));
    expect(source, contains('final regularScripts ='));
    expect(
        source, contains('visibleScripts.where((script) => !script.isPinned)'));
    expect(source, contains('final firstFolderIndex = pinnedScripts.length'));
    expect(source, contains('final firstRegularIndex ='));
    expect(source, contains('pinnedScripts.length + groups.length'));
    expect(source, contains('Widget _buildListDragTarget('));
    expect(source, contains('Widget _buildListDragHandle('));
    expect(source, contains('void _commitListDragTarget('));
    expect(
        source, contains('swapScriptPositionsByName(draggedName, targetName)'));
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

  test('move-to-group sheet is scrollable when there are many groups', () {
    final source = File('lib/pages/script_list_page.dart').readAsStringSync();

    expect(source, contains('isScrollControlled: true'));
    expect(source, contains('DraggableScrollableSheet('));
    expect(source, contains('builder: (context, scrollController)'));
    expect(source, contains('ListView('));
    expect(source, contains('controller: scrollController'));
  });
}
