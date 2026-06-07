import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/models/script_group.dart';

void main() {
  test('script group supports ordinary and project metadata', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1000);
    final ordinary = ScriptGroup(
      id: 1,
      name: '普通分组',
      sortOrder: 2,
      createdAt: now,
      modifiedAt: now,
    );

    expect(ordinary.isProject, isFalse);
    expect(ordinary.projectKey, isNull);
    expect(ordinary.mainFilePath, isNull);
    expect(ordinary.toMap()['projectKey'], isNull);
    expect(ordinary.toMap()['mainFilePath'], isNull);
    expect(ordinary.toMap()['isProject'], 0);

    final project = ordinary.copyWith(
      projectKey: 'project_abc123',
      mainFilePath: 'src/main.py',
      isProject: true,
    );

    expect(project.isProject, isTrue);
    expect(project.projectKey, 'project_abc123');
    expect(project.mainFilePath, 'src/main.py');
    expect(project.toMap()['projectKey'], 'project_abc123');
    expect(project.toMap()['mainFilePath'], 'src/main.py');
    expect(project.toMap()['isProject'], 1);

    final clearedMain = project.copyWith(clearMainFilePath: true);
    expect(clearedMain.mainFilePath, isNull);
  });

  test('script group reads old database rows as ordinary groups', () {
    final group = ScriptGroup.fromMap({
      'id': 1,
      'name': '旧分组',
      'sortOrder': 0,
      'createdAt': 1000,
      'modifiedAt': 2000,
    });

    expect(group.isProject, isFalse);
    expect(group.projectKey, isNull);
    expect(group.mainFilePath, isNull);
  });
}
