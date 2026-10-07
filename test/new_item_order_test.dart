import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/scripts/application/script_workspace_controller.dart';
import 'package:python_runner/models/script_file.dart';
import 'package:python_runner/models/script_group.dart';

import 'support/script_test_helper.dart';

void main() {
  for (final action in [
    'create',
    'import',
    'group',
    'project',
    'group-script',
  ]) {
    test('$action reports persisted creation when ordering fails', () async {
      final time = DateTime(2026);
      final repo = _FailingInsertionOrderRepository(
        scripts: [
          ScriptFile(
            name: 'existing.py',
            path: 'existing.py',
            createdAt: time,
            modifiedAt: time,
            sortOrder: 5,
          ),
        ],
        groups: [
          ScriptGroup(
            id: 1,
            name: 'Existing',
            sortOrder: 5,
            createdAt: time,
            modifiedAt: time,
          ),
        ],
      );
      final container = buildScriptContainer(repository: repo);
      addTearDown(container.dispose);
      final controller = container.read(
        scriptWorkspaceControllerProvider.notifier,
      );
      await controller.load();
      switch (action) {
        case 'create':
          expect(await controller.createScript('new.py'), isTrue);
        case 'import':
          expect(
            await controller.importScript('content://new', 'new.py'),
            isNotNull,
          );
        case 'group-script':
          expect(await controller.createScript('new.py', groupId: 1), isTrue);
        case 'group':
          expect(await controller.createGroup('New'), isTrue);
        case 'project':
          final created = await controller.createProjectGroup(
            'New',
            projectKey: 'new_project',
          );
          expect(
            created,
            isNotNull,
            reason: 'A null result makes the caller delete an already registered project directory',
          );
          expect(created!.projectKey, 'new_project');
      }
      final scripts = controller.scripts.map((s) => s.toMap()).toList();
      final groups = controller.groups.map((g) => g.toMap()).toList();
      expect((await repo.getScript('existing.py'))!.sortOrder, 5);
      expect((await repo.getAllGroups()).first.sortOrder, 5);
      await controller.load();
      expect(controller.scripts.map((s) => s.toMap()).toList(), scripts);
      expect(controller.groups.map((g) => g.toMap()).toList(), groups);
    });
  }
  for (final action in ['create', 'import', 'group', 'project', 'discover']) {
    for (final ordering in ['legacy', 'manual', 'mixed']) {
      test(
        '$action enters home first after pins, ordering=$ordering, survives reload',
        () async {
          final time = DateTime(2026);
          final repo = FakeScriptRepository(
            nextGroupId: 10,
            scripts: [
              for (final (name, order, pin) in [
                ('pin.py', 0, true),
                ('b.py', 1, false),
                ('a.py', 2, false),
              ])
                ScriptFile(
                  name: name,
                  path: name,
                  createdAt: time,
                  modifiedAt: time,
                  sortOrder: order,
                  isPinned: pin,
                  homeSortOrder:
                      ordering == 'manual' ||
                          (ordering == 'mixed' && name == 'b.py')
                      ? order
                      : null,
                ),
            ],
            groups: [
              ScriptGroup(
                id: 1,
                name: 'Folder',
                sortOrder: 0,
                homeSortOrder: ordering == 'manual' ? 3 : null,
                createdAt: time,
                modifiedAt: time,
              ),
              ScriptGroup(
                id: 2,
                name: 'Project',
                isProject: true,
                projectKey: 'old_project',
                sortOrder: 1,
                homeSortOrder: ordering != 'legacy' ? 0 : null,
                createdAt: time,
                modifiedAt: time,
              ),
            ],
          );
          final container = buildScriptContainer(repository: repo);
          addTearDown(container.dispose);
          final controller = container.read(
            scriptWorkspaceControllerProvider.notifier,
          );
          await controller.load();
          final previous = controller.homeItems.map((e) => e.key).toList();
          switch (action) {
            case 'create':
              expect(await controller.createScript('new.py'), isTrue);
            case 'import':
              expect(
                await controller.importScript('content://new', 'new.py'),
                isNotNull,
              );
            case 'group':
              expect(await controller.createGroup('New'), isTrue);
            case 'project':
              expect(await controller.createProjectGroup('New'), isNotNull);
            case 'discover':
              await repo.createScriptFile('new.py');
              await controller.load();
          }
          final newKey = ['group', 'project'].contains(action)
              ? 'group:10'
              : 'new.py';
          final expected = [previous.first, newKey, ...previous.skip(1)];
          expect(controller.homeItems.map((e) => e.key), expected);
          final reopened = buildScriptContainer(repository: repo);
          addTearDown(reopened.dispose);
          final reloaded = reopened.read(
            scriptWorkspaceControllerProvider.notifier,
          );
          await reloaded.load();
          expect(reloaded.homeItems.map((e) => e.key), expected);
          for (final script in await repo.getAllScripts()) {
            expect(script.sortOrder, greaterThanOrEqualTo(0));
            expect(script.homeSortOrder ?? 0, greaterThanOrEqualTo(0));
          }
          for (final group in await repo.getAllGroups()) {
            expect(group.sortOrder, greaterThanOrEqualTo(0));
            expect(group.homeSortOrder ?? 0, greaterThanOrEqualTo(0));
          }
        },
      );
    }
  }
  for (final importing in [false, true]) {
    test(
      'new group script follows pins and preserves manual order, import=$importing',
      () async {
        final time = DateTime(2026);
        final repo = FakeScriptRepository(
          scripts: [
            for (final (name, order, pin) in [
              ('pin.py', 0, true),
              ('b.py', 5, false),
              ('a.py', 9, false),
            ])
              ScriptFile(
                name: name,
                path: name,
                createdAt: time,
                modifiedAt: time,
                groupId: 1,
                sortOrder: order,
                isPinned: pin,
              ),
          ],
          groups: [
            ScriptGroup(
              id: 1,
              name: 'Folder',
              sortOrder: 0,
              createdAt: time,
              modifiedAt: time,
            ),
          ],
        );
        final container = buildScriptContainer(repository: repo);
        addTearDown(container.dispose);
        final controller = container.read(
          scriptWorkspaceControllerProvider.notifier,
        );
        await controller.load();
        if (importing) {
          expect(
            await controller.importScript(
              'content://new',
              'new.py',
              groupId: 1,
            ),
            isNotNull,
          );
        } else {
          expect(await controller.createScript('new.py', groupId: 1), isTrue);
        }
        expect(controller.scriptsInGroup(1).map((s) => s.name), [
          'pin.py',
          'new.py',
          'b.py',
          'a.py',
        ]);
        await controller.load();
        expect(controller.scriptsInGroup(1).map((s) => s.name), [
          'pin.py',
          'new.py',
          'b.py',
          'a.py',
        ]);
        expect(
          controller.scriptsInGroup(1).every((s) => s.sortOrder >= 0),
          isTrue,
        );
      },
    );
  }
}

class _FailingInsertionOrderRepository extends FakeScriptRepository {
  _FailingInsertionOrderRepository({super.scripts, super.groups})
    : super(nextGroupId: 10);

  @override
  Future<void> batchUpdateHomeSortOrders(
    List<ScriptFile> scripts,
    List<ScriptGroup> groups,
  ) async {
    throw StateError('insertion order write failed');
  }

  @override
  Future<void> batchUpdateSortOrders(List<ScriptFile> scripts) async {
    throw StateError('insertion order write failed');
  }
}
